defmodule LCRDT.CounterTest do
  use ExUnit.Case
  alias LCRDT.Counter
  doctest LCRDT.Counter

  @delay 100
  @foo :foo_crdt
  @bar :bar_crdt
  @baz :baz_crdt

  setup do
    LCRDT.Environment.set_auto_allocation(-1)
    LCRDT.Environment.use_crdt(Counter)
    {:ok, _} = Application.ensure_all_started(:lcrdt)
    on_exit(fn ->
      Application.stop(:lcrdt)
      LCRDT.Environment.set_auto_allocation(-1)
    end)
  end

  test "we cant increment without a lease" do
    assert Counter.inc(@foo) == :lease_violation
    assert Counter.sum(@foo) == 0
  end

  test "we cant increment more than the stock" do
    # This will run in the background.
    Counter.request_leases(@foo, LCRDT.Environment.get_stock() + 1)
    # This will block until the above call is done:
    assert Counter.inc(@foo) == :lease_violation
    assert Counter.sum(@foo) == 0
  end

  test "we cant decrement below zero" do
    # Decrement twice
    assert Counter.dec(@bar) == :lease_violation
    assert Counter.dec(@bar) == :lease_violation
    assert Counter.sum(@bar) == 0
  end

  test "we can increment once per every lease" do
    Counter.request_leases(@foo, 1)
    # Increment twice.
    assert Counter.inc(@foo) == :inc
    assert Counter.inc(@foo) == :lease_violation
    assert Counter.sum(@foo) == 1
  end

  test "decrement reclaims a lease" do
    Counter.request_leases(@foo, 1)
    assert Counter.inc(@foo) == :inc
    assert Counter.sum(@foo) == 1

    assert Counter.dec(@foo) == :dec
    assert Counter.sum(@foo) == 0

    assert Counter.inc(@foo) == :inc
    assert Counter.sum(@foo) == 1
  end

  test "we can increment and decrement" do
    Counter.request_leases(@foo, 5)
    assert Counter.inc(@foo) == :inc
    assert Counter.inc(@foo) == :inc
    assert Counter.dec(@foo) == :dec
    assert Counter.sum(@foo) == 1
  end

  test "we can estimate the sum of other counters" do
    Counter.request_leases(@foo, 1)
    Counter.request_leases(@bar, 5)
    assert Counter.inc(@foo) == :inc
    assert Counter.inc(@bar) == :inc
    Counter.sync(@bar)
    :timer.sleep(@delay)
    assert Counter.inc(@bar) == :inc
    assert Counter.inc(@bar) == :inc
    assert Counter.sum(@foo) == 2
  end

  test "we can sync with other counters" do
    LCRDT.Participant.allocate(@foo, 1)
    assert Counter.inc(@foo) == :inc
    Counter.sync(@foo)
    :timer.sleep(@delay)
    assert Counter.sum(@bar) == 1
    assert Counter.sum(@baz) == 1
  end

  test "we can automatically allocate to a single node" do
    # We will allocate 5 leases every time we run out.
    LCRDT.Environment.set_auto_allocation(5)
    Counter.request_leases(@foo, 1)
    assert Counter.inc(@foo) == :inc
    # At this point, auto-allocation should occur in the background.
    assert Counter.sum(@foo) == 1
    # And we're good to increment another few!
    assert Counter.inc(@foo) == :inc
    assert Counter.inc(@foo) == :inc
    assert Counter.sum(@foo) == 3
  end

  test "we can automatically allocate to multiple nodes" do
    LCRDT.Environment.set_auto_allocation(5)
    Counter.request_leases(@foo, 1)
    Counter.request_leases(@bar, 1)
    assert Counter.inc(@foo) == :inc
    assert Counter.inc(@bar) == :inc
    # Auto-allocation should kick in.
    assert Counter.inc(@foo) == :inc
    assert Counter.inc(@bar) == :inc
    # They'll be 2 each since they have not synced.
    assert Counter.sum(@foo) == 2
    assert Counter.sum(@bar) == 2
  end
end
