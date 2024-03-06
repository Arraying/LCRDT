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

  test "we can increment and decrement" do
    Counter.inc(@foo)
    Counter.inc(@foo)
    Counter.dec(@foo)
    :timer.sleep(@delay)
    assert Counter.sum(@foo) == 1
  end

  test "we can estimate the sum of other counters" do
    Counter.inc(@foo)
    Counter.inc(@bar)
    Counter.sync(@bar)
    :timer.sleep(@delay)
    Counter.inc(@bar)
    Counter.inc(@bar)
    assert Counter.sum(@foo) == 2
  end

  test "we can sync with other counters" do
    Counter.inc(@foo)
    Counter.sync(@foo)
    :timer.sleep(@delay)
    assert Counter.sum(@bar) == 1
    assert Counter.sum(@baz) == 1
  end
end
