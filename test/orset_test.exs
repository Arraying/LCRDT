defmodule LCRDT.OrSetTest do
  use ExUnit.Case
  alias LCRDT.OrSet
  doctest LCRDT.OrSet

  @delay 100
  @foo :foo_crdt
  @bar :bar_crdt
  @baz :baz_crdt

  setup do
    System.put_env("CRDT", "orset")
    {:ok, _} = Application.ensure_all_started(:lcrdt)
    on_exit(fn -> Application.stop(:lcrdt) end)
  end

  test "we cant increment without a lease" do
    id = 5
    item_name = :apple
    OrSet.add(@foo, id, item_name)
    :timer.sleep(@delay)

    assert OrSet.contains(@foo, id, item_name) == false
  end

  test "we cant increment more than the stock" do
    id = 5
    item_name = :apple
    LCRDT.Participant.allocate(@foo, OrSet.total_stock() + 1)
    :timer.sleep(@delay)

    OrSet.add(@foo, id, item_name)
    assert OrSet.contains(@foo, id, item_name) == false
  end

  test "we cant increment on merge leading to surpassing the the stock" do
    id = 5
    id_2 = 6
    item_name = :apple
    LCRDT.Participant.allocate(@baz, OrSet.total_stock() - 2)
    :timer.sleep(@delay)
    LCRDT.Participant.allocate(@foo, 1)
    :timer.sleep(@delay)
    LCRDT.Participant.allocate(@bar, 1)
    :timer.sleep(@delay)

    OrSet.add(@foo, id, item_name)
    :timer.sleep(@delay)
    assert OrSet.contains(@foo, id, item_name) == true

    # We can't add the item to other processes, because we don't have enough stock.
    OrSet.sync(@foo)
    :timer.sleep(@delay)

    OrSet.add(@bar, id_2, item_name)
    :timer.sleep(@delay)
    assert OrSet.contains(@bar, id_2, item_name) == true

    LCRDT.Participant.deallocate(@baz, OrSet.total_stock() - 1)
    :timer.sleep(@delay)
  end

  test "we cant decrement below zero" do
    id = 5
    item_name = :apple
    OrSet.remove(@bar, id, item_name)
    :timer.sleep(@delay)
    assert OrSet.contains(@bar, id, item_name) == false
  end

  test "we can increment once per every lease" do
    id = 5
    item_name = :apple
    LCRDT.Participant.allocate(@foo, 1)
    :timer.sleep(@delay)

    # Even though we try adding twice, only the first one should be added.
    OrSet.add(@foo, id, item_name)
    :timer.sleep(@delay)
    OrSet.add(@foo, id, item_name)
    :timer.sleep(@delay)
    # Removing once to prove we only added once.
    OrSet.remove(@foo, id, item_name)
    :timer.sleep(@delay)

    assert OrSet.contains(@foo, id, item_name) == false
  end

  test "decrement reclaims a lease" do
    id = 5
    item_name = :apple
    LCRDT.Participant.allocate(@foo, 1)
    :timer.sleep(@delay)

    OrSet.add(@foo, id, item_name)
    :timer.sleep(@delay)
    assert OrSet.contains(@foo, id, item_name) == true

    OrSet.remove(@foo, id, item_name)
    :timer.sleep(@delay)
    assert OrSet.contains(@foo, id, item_name) == false

    OrSet.add(@foo, id, item_name)
    :timer.sleep(@delay)
    assert OrSet.contains(@foo, id, item_name) == true
  end

  test "we can add multiple items with multiple ids" do
    id1 = 5
    id2 = 6
    item_name1 = :apple
    item_name2 = :banana
    LCRDT.Participant.allocate(@foo, 2)
    :timer.sleep(@delay)

    OrSet.add(@foo, id1, item_name1)
    OrSet.add(@foo, id2, item_name2)
    :timer.sleep(@delay)
    assert OrSet.contains(@foo, id1, item_name1) == true
    assert OrSet.contains(@foo, id2, item_name2) == true
  end

  test "we can sync with other orsets" do
    id = 5
    item_name = :apple
    LCRDT.Participant.allocate(@foo, 1)
    :timer.sleep(@delay)

    OrSet.add(@foo, id, item_name)
    :timer.sleep(@delay)
    assert OrSet.contains(@foo, id, item_name) == true
    assert OrSet.contains(@bar, id, item_name) == false
    assert OrSet.contains(@baz, id, item_name) == false

    OrSet.sync(@foo)
    :timer.sleep(@delay)
    assert OrSet.contains(@foo, id, item_name) == true
    assert OrSet.contains(@bar, id, item_name) == true
    assert OrSet.contains(@baz, id, item_name) == true
  end

  test "we can add and remove, using sync" do
    id = 5
    item_name = :apple
    LCRDT.Participant.allocate(@foo, 1)
    :timer.sleep(@delay)

    OrSet.add(@foo, id, item_name)
    :timer.sleep(@delay)
    assert OrSet.contains(@foo, id, item_name) == true

    OrSet.sync(@foo)
    :timer.sleep(@delay)
    assert OrSet.contains(@bar, id, item_name) == true

    OrSet.remove(@bar, id, item_name)
    :timer.sleep(@delay)
    assert OrSet.contains(@foo, id, item_name) == true

    OrSet.sync(@bar)
    :timer.sleep(@delay)
    assert OrSet.contains(@foo, id, item_name) == false
  end

  test "we cant remove an item that was added but not synced yet" do
    id = 5
    item_name = :apple
    LCRDT.Participant.allocate(@foo, 1)
    :timer.sleep(@delay)

    OrSet.add(@foo, id, item_name)
    :timer.sleep(@delay)
    assert OrSet.contains(@foo, id, item_name) == true
    assert OrSet.contains(@bar, id, item_name) == false

    # We remove from bar, but bar doesn't have the item yet.
    OrSet.remove(@bar, id, item_name)
    :timer.sleep(@delay)
    assert OrSet.contains(@foo, id, item_name) == true
    assert OrSet.contains(@bar, id, item_name) == false

    # Thus, on sync we should still have the item.
    OrSet.sync(@foo)
    :timer.sleep(@delay)
    assert OrSet.contains(@foo, id, item_name) == true
    assert OrSet.contains(@bar, id, item_name) == true
  end

end
