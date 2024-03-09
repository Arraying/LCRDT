defmodule LCRDT.TPCTest do
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

  test "commit, follower crashes after sending vote and another transaction started" do
    Participant.allocate(@foo, 1)
    :timer.sleep(@delay)
    # There's no good way of doing this, so we manually prune the log.
    [{:finalize, :commit, _} | rest] = LCRDT.Logging.read(@faulty)
    LCRDT.Logging.write(@faulty, rest)
    # We undo the lease manually, so it's reflected in-memory at the application layer as well.
    # The in-memory log of the TPC node will still be incorrect.
    # That's fine though, because it's getting killed next :D
    bar_state_old = Counter.dump(@bar)
    bar_state_new = %{bar_state_old | leases: Map.new()}
    GenServer.call(@bar, {:test_override_state, bar_state_new}, :infinity)
    assert foo_leases(@bar) == 0
    # If we now crash before preparing it's going to get us into the state we want.
    inject(@faulty, before_prepare(), neutral())
    # It's time to kill it with another transaction.
    Participant.allocate(@foo, 2)
    :timer.sleep(@delay)
    # We should now be able to see both.
    assert foo_leases(@bar) == 3
  end

  test "deallocate, no crashes" do
    Participant.deallocate(@foo, 1)
    :timer.sleep(@delay)
    assert foo_leases(@baz) == 0
  end

  test "deallocate, follower crashes before prepare" do
    inject(@faulty, before_prepare(), neutral())
    Participant.deallocate(@foo, 1)
    :timer.sleep(@delay)
    assert foo_leases(@baz) == 0
  end

  test "deallocate, follower crashes before sending vote" do
    inject(@faulty, during_prepare(), neutral())
    Participant.deallocate(@foo, 1)
    :timer.sleep(@delay)
    assert foo_leases(@baz) == 0
  end

  test "deallocate, follower crashes after sending vote" do
    inject(@faulty, after_prepare(), neutral())
    Participant.deallocate(@foo, 1)
    :timer.sleep(@delay)
    assert foo_leases(@bar) == 0
    assert foo_leases(@baz) == 0
  end

  test "deallocate, follower crashes after sending vote and another transaction started" do
    # Initial allocation
    Participant.allocate(@foo, 2)
    :timer.sleep(@delay)

    # Before prepare, we start another transaction
    inject(@faulty, before_prepare(), neutral())
    Participant.deallocate(@foo, 1)
    :timer.sleep(@delay)
  end

  # We get this from baz to ensure the changes propagated to a non-coordinator non-faulty node.
  defp foo_leases(from), do: Map.get(Counter.dump(from).leases, @foo, 0)

end
