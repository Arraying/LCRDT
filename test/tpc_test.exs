defmodule LCRDT.CounterTest do
  use ExUnit.Case
  alias LCRDT.Counter
  alias LCRDT.Participant
  import LCRDT.Injections
  import LCRDT.Injections.Crash
  doctest LCRDT.Participant

  @delay 500
  @foo :foo_crdt
  @bar :bar_crdt
  @baz :baz_crdt
  @faulty :bar_tpc

  setup do
    {:ok, _} = Application.ensure_all_started(:lcrdt)
    on_exit(fn -> Application.stop(:lcrdt) end)
  end

  test "commit, no crashes" do
    Participant.allocate(@foo, 1)
    :timer.sleep(@delay)
    assert foo_leases(@baz) == 1
  end

  test "abort, no crashes" do
    Participant.allocate(@foo, 1000000000000000)
    :timer.sleep(@delay)
    assert foo_leases(@baz) == 0
  end

  test "abort, follower crashes before prepare" do
    inject(@faulty, before_prepare(), neutral())
    Participant.allocate(@foo, 1)
    :timer.sleep(@delay)
    # In this scenario, we don't know if we committed or aborted, so we should abort.
    assert foo_leases(@baz) == 0
  end

  test "commit, follower crashes before sending vote" do
    inject(@faulty, during_prepare(), neutral())
    Participant.allocate(@foo, 1)
    :timer.sleep(@delay)
    # In this scenario, we should commit.
    assert foo_leases(@baz) == 1
  end

  test "commit, follower crashes after sending vote" do
    inject(@faulty, after_prepare(), neutral())
    Participant.allocate(@foo, 1)
    :timer.sleep(@delay)
    # In this scenario, we should commit.
    # Bar was offline so they need to be replayed the commit.
    # Checking for both bar and baz ensures this replay was successful.
    # This also works for aborts, it will get set to 0 (but is harder to test).
    assert foo_leases(@bar) == 1
    assert foo_leases(@baz) == 1
  end

  # We get this from baz to ensure the changes propagated to a non-coordinator non-faulty node.
  defp foo_leases(from), do: Map.get(elem(Counter.dump(from), 1), @foo, 0)

end
