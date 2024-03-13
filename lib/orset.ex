defmodule LCRDT.OrSet do
  @moduledoc """
  This represents an OR-Set CRDT.
  """

  use LCRDT.CRDT

  @doc """
  Whether the set contains an element.
  """
  def contains(pid, unique_id, item) do
    call_blocking(pid, {:contains, unique_id, item})
  end

@doc """
  Adds an element to the set if enough leases are available.
  """
  def add(pid, unique_id, item) do
    call_blocking(pid, {:add, unique_id, item})
  end

  @doc """
  Removes an element from the set.
  """
  def remove(pid, unique_id, item) do
    call_blocking(pid, {:remove, unique_id, item})
  end

  def can_deallocate?(state, amount, _process) do
    get_leases(state) - most_used_item_count(state) - amount >= 0
  end

  @doc """
  The initial state. An empty map.
  """
  def initial_state() do
    # key - tuple of (unique_id, item_id)
    # value - tuple of (add, remove), each is a set of unique references
    %{
      data: Map.new(),
      # TODO: optimize by keeping track of sums of every unique item
      # (each item is unique)
      # item_sums: Map.new()
    }
  end

  @doc """
  Merges the two sets by taking unions.
  """
  def merge_state(other_state, state) do
    data = merge_sets(other_state.data, state.data)
    %{state | data: data}
  end

  def handle_operation({:add, unique_id, item}, state1) do
    {exists?, _, state2} = exists?(state1, unique_id, item)
    cond do
      # If it exists, we don't do anything.
      exists? ->
        {:ok, state2}
      # If it doesn't exist but we hit maximing leases, we throw an issue.
      sum_item(state2, item) >= get_leases(state2) ->
        {:lease_violation, state2}
      # We add it.
      true ->
        key = {unique_id, item}
        map2 = insert(state2.data, key)
        {add, remove} = Map.fetch!(map2, key)
        map3 = Map.put(map2, key, {MapSet.put(add, {state2.name, :erlang.make_ref()}), remove})
        {:ok, %{state2 | data: map3}}
    end
  end

  def handle_operation({:remove, unique_id, item}, state) do
    key = {unique_id, item}
    map2 = insert(state.data, key)
    {add, remove} = Map.fetch!(map2, key)
    map3 = Map.put(map2, key, {add, MapSet.union(add, remove)})
    {:ok, %{state | data: map3}}
  end

  def handle_operation({:contains, unique_id, item}, state) do
    {exists?, _, state2} = exists?(state, unique_id, item)
    {exists?, state2}
  end

  defp insert(map, object), do: Map.put_new(map, object, {MapSet.new(), MapSet.new()})

  defp merge_sets(left, right), do: Map.merge(left, right, fn(_k, v1, v2) -> merge_tuples(v1, v2) end)

  defp merge_tuples({p1, p2}, {q1, q2}), do: {MapSet.union(p1, q1), MapSet.union(p2, q2)}

  # Number of occurrences in baskets of an item
  defp sum_item(state, item) do
    counter = state.data
    |> Map.keys()
    |> Enum.filter(fn {_, i} -> i == item end)
    |> Enum.map(fn {unique_id, _} ->
      {exists?, owners, _} = exists?(state, unique_id, item)
      if exists? do
        Enum.count(owners, fn owner -> owner == state.name end)
      else
        0
      end
    end)
    # Changes to state from exists are ignored
    |> Enum.sum()
    counter
  end

  defp most_used_item_count(state) do
    # Get all unique items
    set = state.data |> Map.keys() |> Enum.map(fn {_, item} -> item end) |> Enum.uniq()
    # Get the item with the max. occurrences
    max = Enum.map(set, fn item -> sum_item(state, item) end) |> Enum.max()
    max
  end

  defp exists?(state, unique_id, item) do
    key = {unique_id, item}
    map2 = insert(state.data, key)
    {add, remove} = Map.fetch!(map2, key)
    difference_set = MapSet.difference(add, remove)
    difference_list = MapSet.to_list(difference_set)
    owners = Enum.map(difference_list, &(Kernel.elem(&1, 0)))
    # Without the owners when we sync:
    # foo: (:a, [123], [])
    # bar: (:a, [345], [])
    # res: (:a, [123, 345], [])
    # We need to keep track of the owners so we can see if we
    # can account for it when seeing if we have leases:
    # foo: (:a, [(foo, 123)], [])
    # bar: (:a, [(bar, 345)], [])
    # res: (:a, [(foo, 123), (bar, 345)], [])
    {MapSet.size(difference_set) > 0, owners, %{state | data: map2}}
  end
end
