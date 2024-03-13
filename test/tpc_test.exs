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
  @coordinator :coordinator
  @faulty :bar_tpc

  setup do
    LCRDT.Environment.set_auto_allocation(-1)
    LCRDT.Environment.use_crdt(Counter)
    {:ok, _} = Application.ensure_all_started(:lcrdt)
    on_exit(fn -> Application.stop(:lcrdt) end)
  end

  test "commit, no crashes" do
    Counter.request_leases(@foo, 1)
    assert foo_leases(@baz) == 1
  end

  test "abort, no crashes" do
    Counter.request_leases(@foo, 1000000000000000)
    assert foo_leases(@baz) == 0
  end

  test "abort, follower crashes before prepare" do
    inject(@faulty, before_prepare(), neutral())
    Counter.request_leases(@foo, 1)
    # We have to wait here otherwise baz doesn't know it's pending (yet).
    # We need to keep the test alive long enough to pick this up.
    :timer.sleep(@delay)
    # In this scenario, we don't know if we committed or aborted, so we should abort.
    assert foo_leases(@baz) == 0
  end

  test "commit, follower crashes before sending vote" do
    inject(@faulty, during_prepare(), neutral())
    Counter.request_leases(@foo, 1)
    # In this scenario, we should commit.
    assert foo_leases(@baz) == 1
  end

  test "commit, follower crashes after sending vote" do
    inject(@faulty, after_prepare(), neutral())
    Counter.request_leases(@foo, 1)
    # In this scenario, we should commit.
    # Bar was offline so they need to be replayed the commit.
    # Checking for both bar and baz ensures this replay was successful.
    # This also works for aborts, it will get set to 0 (but is harder to test).
    # Give it some time for bar to recover.
    :timer.sleep(@delay)
    assert foo_leases(@bar) == 1
    assert foo_leases(@baz) == 1
  end

  test "commit, follower crashes after sending vote and another transaction started" do
    Counter.request_leases(@foo, 1)
    # Block until done, so we can read the logs.
    # We can't use Counter.sum for this as the 2PC logs take a bit longer to save.
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
    # Again keep the test alive.
    :timer.sleep(@delay)
    # We should now be able to see both.
    assert foo_leases(@bar) == 3
  end

  test "deallocate, no crashes" do
    Counter.revoke_leases(@foo, 1)
    assert foo_leases(@foo) == 0
  end

  test "deallocate, follower crashes before prepare" do
    inject(@faulty, before_prepare(), neutral())
    Counter.revoke_leases(@foo, 1)
    assert foo_leases(@foo) == 0
  end

  test "deallocate, follower crashes before sending vote" do
    inject(@faulty, during_prepare(), neutral())
    Counter.revoke_leases(@foo, 1)
    assert foo_leases(@foo) == 0
  end

  test "deallocate, follower crashes after sending vote" do
    inject(@faulty, after_prepare(), neutral())
    Counter.revoke_leases(@foo, 1)
    assert foo_leases(@foo) == 0
  end

  test "deallocate, follower crashes after sending vote and another transaction started" do
    # Initial allocation
    Counter.request_leases(@foo, 2)
    # Before prepare, we start another transaction
    inject(@faulty, before_prepare(), neutral())
    # Here we just go to the participant directly as we would otherwise block.
    # We want this to happen asynchronously!
    Participant.deallocate(@foo, 1)
    assert foo_leases(@foo) == 2
  end

  test "commit, coordinator crashes after start" do
    inject(@coordinator, before_prepare_request(), neutral())
    # Since starting happens sync (we need to know when to re-schedule starts)
    # when we raise this will fail the call. To get around this we just spawn the
    # transaction in a temporary process that is meant to fail!
    spawn(fn -> Counter.request_leases(@foo, 1) end)
    :timer.sleep(@delay)
    assert foo_leases(@baz) == 1
  end

  test "abort, coordinator crashes after sending prepare requests (never receives)" do
    inject(@coordinator, after_prepare_request(), neutral())
    # Same logic here, we need a new process to start it.
    spawn(fn ->  Counter.request_leases(@foo, 1) end)
    :timer.sleep(@delay)
    # At this point, it has not received its own prepare.
    # The log cannot show a commit so we are cautious and abort.
    assert foo_leases(@baz) == 0
  end

  test "commit, coordinator crashes after sending prepare requests (receives)" do
    inject(@coordinator, after_prepare(), neutral())
    Counter.request_leases(@foo, 1)
    # At this point we know that we OK'd, so when we recover we should hopefully be able to commit.
    assert foo_leases(@baz) == 1
  end

  test "commit, coordinator crashes before sending out finalize" do
    inject(@coordinator, before_finalize(), neutral())
    Counter.request_leases(@foo, 1)
    assert foo_leases(@foo) == 1
    assert foo_leases(@bar) == 1
    assert foo_leases(@baz) == 1
  end

  test "abort, coordinator crashes before sending out finalize" do
    inject(@coordinator, before_finalize(), neutral())
    Counter.request_leases(@foo, 123456)
    assert foo_leases(@foo) == 0
    assert foo_leases(@bar) == 0
    assert foo_leases(@baz) == 0
  end

  # We get this from baz to ensure the changes propagated to a non-coordinator non-faulty node.
  defp foo_leases(from), do: Map.get(Counter.dump(from).leases, @foo, 0)

end
