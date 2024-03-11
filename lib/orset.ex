defmodule LCRDT.OrSet do
  @moduledoc """
  This represents an OR-Set CRDT.
  """

  use LCRDT.CRDT

  @doc """
  Whether the set contains an element.
  """
  def contains(pid, unique_id, item) do
    GenServer.call(pid, {:contains, unique_id, item})
  end

@doc """
  Adds an element to the set if enough leases are available.
  """
  def add(pid, unique_id, item) do
    GenServer.cast(pid, {:add, unique_id, item})
  end

  @doc """
  Removes an element from the set.
  """
  def remove(pid, unique_id, item) do
    GenServer.cast(pid, {:remove, unique_id, item})
  end

  @doc """
  Deallocates leases for an element in the set.
  """
  def deallocate_lease(pid, key, amount) do
    GenServer.cast(pid, {:deallocate_lease, key, amount})
  end

  def can_deallocate?(state, amount, _process) do
    get_leases(state) - most_used_item_count(state) - amount >= 0
  end

  @doc """
  The total number of stock.
  This is the max. leases we can allocate across all nodes.
  """
  def total_stock(), do: 100

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

  @impl true
  def handle_cast({:add, unique_id, item}, state) do
    if sum_item(state, item) >= get_leases(state) do
      # TODO: Request more leases or/and return error
      IO.puts("Lease violation: #{inspect(state)}")
      {:noreply, state}
    else
      key = {unique_id, item}
      map2 = insert(state.data, key)
      {add, remove} = Map.fetch!(map2, key)
      map3 = Map.put(map2, key, {MapSet.put(add, :erlang.make_ref()), remove})
      {:noreply, %{state | data: map3}}
    end
  end

  @impl true
  def handle_cast({:remove, unique_id, item}, state) do
    key = {unique_id, item}
    map2 = insert(state.data, key)
    {add, remove} = Map.fetch!(map2, key)
    map3 = Map.put(map2, key, {add, MapSet.union(add, remove)})
    {:noreply, %{state | data: map3}}
  end

  @impl true
  def handle_call({:contains, unique_id, item}, _from, state) do
    {exists?, state2} = exists?(state, unique_id, item)
    {:reply, exists?, state2}
  end

  defp insert(map, object), do: Map.put_new(map, object, {MapSet.new(), MapSet.new()})

  defp merge_sets(left, right), do: Map.merge(left, right, fn(_k, v1, v2) -> merge_tuples(v1, v2) end)

  defp merge_tuples({p1, p2}, {q1, q2}), do: {MapSet.union(p1, q1), MapSet.union(p2, q2)}

  # Number of occurrences in baskets of an item
  defp sum_item(state, item) do
    counter = state.data |> Map.keys() |> Enum.filter(fn {_, i} -> i == item end)
    |> Enum.map(fn {unique_id, _} -> exists?(state, unique_id, item) end)
    |> Enum.count(fn {exists?, _e} -> exists? end)
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
    {MapSet.size(MapSet.difference(add, remove)) > 0, %{state | data: map2}}
  end
end
