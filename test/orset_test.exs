defmodule LCRDT.OrSetTest do
  use ExUnit.Case
  alias LCRDT.OrSet
  doctest LCRDT.OrSet

  @delay 100
  @foo :foo_crdt
  @bar :bar_crdt
  @baz :baz_crdt
  @id 5
  @item_name :apple

  setup do
    LCRDT.Environment.set_sync_interval(1_000_000_000)
    LCRDT.Environment.set_sync_interval(1_000_000_000)
    LCRDT.Environment.set_auto_allocation(-1)
    LCRDT.Environment.use_crdt(OrSet)
    {:ok, _} = Application.ensure_all_started(:lcrdt)
    on_exit(fn ->
      Application.stop(:lcrdt)
      LCRDT.Environment.set_auto_allocation(-1)
    end)
  end

  test "we cant increment without a lease" do
    assert OrSet.add(@foo, @id, @item_name) == :lease_violation
    assert OrSet.contains(@foo, @id, @item_name) == false
  end

  test "we cant increment more than the stock" do
    OrSet.request_leases(@foo, LCRDT.Environment.get_stock() + 1)
    assert OrSet.add(@foo, @id, @item_name) == :lease_violation
    assert OrSet.contains(@foo, @id, @item_name) == false
  end

  test "we can add multiple items with multiple ids" do
    id2 = 6
    id3 = 7
    item_name2 = :banana
    item_name3 = :carrot
    OrSet.request_leases(@foo, 2)

    assert OrSet.add(@foo, @id, @item_name) == :ok
    assert OrSet.add(@foo, id2, item_name2) == :ok
    assert OrSet.add(@foo, id3, item_name3) == :ok
    :timer.sleep(@delay)
    assert OrSet.contains(@foo, @id, @item_name) == true
    assert OrSet.contains(@foo, id2, item_name2) == true
    assert OrSet.contains(@foo, id3, item_name3) == true
  end

  test "increment successfully an already added product with the last lease (and a new id)" do
    id_2 = 6
    OrSet.request_leases(@baz, LCRDT.Environment.get_stock() - 2)
    OrSet.request_leases(@foo, 1)
    OrSet.request_leases(@bar, 1)

    assert OrSet.add(@foo, @id, @item_name) == :ok
    assert OrSet.contains(@foo, @id, @item_name) == true

    OrSet.sync(@foo)
    :timer.sleep(@delay)

    assert OrSet.add(@bar, id_2, @item_name) == :ok
    assert OrSet.contains(@bar, id_2, @item_name) == true
  end

  test "removing from nothing does nothing" do
    assert OrSet.remove(@bar, @id, @item_name) == :ok
    assert OrSet.contains(@bar, @id, @item_name) == false
  end

  test "we can increment once per every lease" do
    OrSet.request_leases(@foo, 1)

    # Even though we try adding twice, only the first one should be added.
    assert OrSet.add(@foo, @id, @item_name) == :ok
    assert OrSet.add(@foo, @id, @item_name) == :ok
    # Removing once to prove we only added once.
    assert OrSet.remove(@foo, @id, @item_name) == :ok

    assert OrSet.contains(@foo, @id, @item_name) == false
  end

  test "decrement reclaims a lease" do
    OrSet.request_leases(@foo, 1)
    assert OrSet.add(@foo, @id, @item_name) == :ok
    assert OrSet.contains(@foo, @id, @item_name) == true

    assert OrSet.remove(@foo, @id, @item_name) == :ok
    assert OrSet.contains(@foo, @id, @item_name) == false

    assert OrSet.add(@foo, @id, @item_name) == :ok
    assert OrSet.contains(@foo, @id, @item_name) == true
  end

  test "we can sync with other orsets" do
    OrSet.request_leases(@foo, 1)
    assert OrSet.add(@foo, @id, @item_name) == :ok
    assert OrSet.contains(@foo, @id, @item_name) == true
    assert OrSet.contains(@bar, @id, @item_name) == false
    assert OrSet.contains(@baz, @id, @item_name) == false

    OrSet.sync(@foo)
    :timer.sleep(@delay)
    assert OrSet.contains(@foo, @id, @item_name) == true
    assert OrSet.contains(@bar, @id, @item_name) == true
    assert OrSet.contains(@baz, @id, @item_name) == true
  end

  test "we can add and remove, using sync" do
    OrSet.request_leases(@foo, 1)
    assert OrSet.add(@foo, @id, @item_name) == :ok
    assert OrSet.contains(@foo, @id, @item_name) == true

    OrSet.sync(@foo)
    :timer.sleep(@delay)
    assert OrSet.contains(@bar, @id, @item_name) == true

    assert OrSet.remove(@bar, @id, @item_name) == :ok
    assert OrSet.contains(@foo, @id, @item_name) == true

    OrSet.sync(@bar)
    :timer.sleep(@delay)
    assert OrSet.contains(@foo, @id, @item_name) == false
  end

  test "we cant remove an item that was added but not synced yet" do
    OrSet.request_leases(@foo, 1)

    assert OrSet.add(@foo, @id, @item_name) == :ok
    assert OrSet.contains(@foo, @id, @item_name) == true
    assert OrSet.contains(@bar, @id, @item_name) == false

    # We remove from bar, but bar doesn't have the item yet.
    assert OrSet.remove(@bar, @id, @item_name) == :ok
    assert OrSet.contains(@foo, @id, @item_name) == true
    assert OrSet.contains(@bar, @id, @item_name) == false

    # Thus, on sync we should still have the item.
    OrSet.sync(@foo)
    :timer.sleep(@delay)
    assert OrSet.contains(@foo, @id, @item_name) == true
    assert OrSet.contains(@bar, @id, @item_name) == true
  end

  test "we can automatically allocate to a single node" do
    # We will allocate 5 leases every time we run out.
    LCRDT.Environment.set_auto_allocation(5)
    OrSet.request_leases(@foo, 1)
    assert OrSet.add(@foo, @id, @item_name) == :ok
    # At this point, auto-allocation should occur in the background.
    assert OrSet.contains(@foo, @id, @item_name) == true
    # And we're good to increment another few!
    assert OrSet.add(@foo, 19, @item_name) == :ok
    assert OrSet.add(@foo, 21, @item_name) == :ok
    assert OrSet.contains(@foo, 19, @item_name) == true
  end

  test "we can automatically allocate to multiple nodes" do
    LCRDT.Environment.set_auto_allocation(5)
    OrSet.request_leases(@foo, 1)
    OrSet.request_leases(@bar, 1)
    item1 = :salt_and_vinegar
    item2 = :cheese_and_onion
    assert OrSet.add(@foo, @id, item1) == :ok
    assert OrSet.add(@bar, @id, item2) == :ok
    # Auto-allocation should kick in.
    assert OrSet.add(@foo, 19, item1) == :ok
    assert OrSet.add(@bar, 19, item2) == :ok
    assert OrSet.contains(@foo, 19, item1) == true
    assert OrSet.contains(@bar, 19, item2) == true
  end

end
