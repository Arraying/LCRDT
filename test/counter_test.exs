defmodule LCRDT.CounterTest do
  use ExUnit.Case
  alias LCRDT.Counter
  doctest LCRDT.Counter

  @delay 100
  @foo :foo_crdt
  @bar :bar_crdt
  @baz :baz_crdt

  setup do
    {:ok, _} = Application.ensure_all_started(:lcrdt)
    on_exit(fn -> Application.stop(:lcrdt) end)
  end

  test "we cant increment without a lease" do
    Counter.inc(@foo)
    :timer.sleep(@delay)
    assert Counter.sum(@foo) == 0
  end

  test "we cant increment more than the stock" do
    LCRDT.Participant.allocate(@foo, Counter.total_stock() + 1)
    :timer.sleep(@delay)

    Counter.inc(@foo)
    assert Counter.sum(@foo) == 0
  end

  test "we cant decrement below zero" do
    # Decrement twice
    Counter.dec(@bar)
    Counter.dec(@bar)
    :timer.sleep(@delay)
    assert Counter.sum(@bar) == 0
  end

  test "we can increment once per every lease" do
    LCRDT.Participant.allocate(@foo, 1)
    :timer.sleep(@delay)

    # Increment twice
    Counter.inc(@foo)
    Counter.inc(@foo)
    :timer.sleep(@delay)
    assert Counter.sum(@foo) == 1
  end

  test "decrement reclaims a lease" do
    LCRDT.Participant.allocate(@foo, 1)
    :timer.sleep(@delay)

    Counter.inc(@foo)
    :timer.sleep(@delay)
    assert Counter.sum(@foo) == 1

    Counter.dec(@foo)
    :timer.sleep(@delay)
    assert Counter.sum(@foo) == 0

    Counter.inc(@foo)
    :timer.sleep(@delay)
    assert Counter.sum(@foo) == 1
  end

  test "we can increment and decrement" do
    LCRDT.Participant.allocate(@foo, 5)
    :timer.sleep(@delay)

    Counter.inc(@foo)
    Counter.inc(@foo)
    Counter.dec(@foo)
    :timer.sleep(@delay)
    assert Counter.sum(@foo) == 1
  end

  test "we can estimate the sum of other counters" do
    LCRDT.Participant.allocate(@foo, 1)
    :timer.sleep(@delay)
    LCRDT.Participant.allocate(@bar, 5)
    :timer.sleep(@delay)

    Counter.inc(@foo)
    Counter.inc(@bar)
    Counter.sync(@bar)
    :timer.sleep(@delay)
    Counter.inc(@bar)
    Counter.inc(@bar)
    assert Counter.sum(@foo) == 2
  end

  test "we can sync with other counters" do
    LCRDT.Participant.allocate(@foo, 1)
    :timer.sleep(@delay)

    Counter.inc(@foo)
    Counter.sync(@foo)
    :timer.sleep(@delay)
    assert Counter.sum(@bar) == 1
    assert Counter.sum(@baz) == 1
  end
end
