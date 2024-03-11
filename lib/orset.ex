defmodule LCRDT.OrSet do
  @moduledoc """
  This represents an OR-Set CRDT.
  """

  use LCRDT.CRDT

  # TODO: Implement all kinds of leases.

  @doc """
  Whether the set contains an element.
  """
  def contains(pid, key) do
    GenServer.call(pid, {:contains, key})
  end

@doc """
  Adds an element to the set if enough leases are available.
  """
  def add(pid, key) do
    if available_leases(pid) > 0 do
      GenServer.cast(pid, {:add, key})
    else
      {:error, "Not enough leases available for adding element"}
    end
  end

  @doc """
  Removes an element from the set.
  """
  def remove(pid, key) do
    GenServer.cast(pid, {:remove, key})
  end

  @doc """
  Deallocates leases for an element in the set.
  """
  def deallocate_lease(pid, key, amount) do
    GenServer.cast(pid, {:deallocate_lease, key, amount})
  end

  @doc """
  Retrieves the leases for a given process identifier (pid).
  """
  def leases(pid) do
    GenServer.call(pid, :get_leases)
  end

  def can_deallocate?(state, amount, _process) do
    total = Enum.sum(Map.values(state.leases))
    total - amount >= 0
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
    %{
      data: Map.new(),
      leases: Map.new()
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
  def handle_cast({:add, key}, state) do
    map2 = insert(state.data, key)
    {add, remove} = Map.fetch!(map2, key)
    map3 = Map.put(map2, key, {MapSet.put(add, :erlang.make_ref()), remove})
    {:noreply, %{data: map3}}
  end

  @impl true
  def handle_cast({:remove, key}, state) do
    map2 = insert(state.data, key)
    {add, remove} = Map.fetch!(map2, key)
    map3 = Map.put(map2, key, {add, MapSet.union(add, remove)})
    {:noreply, %{data: map3}}
  end

  @impl true
  def handle_call({:contains, key}, _from, state) do
    map2 = insert(state.data, key)
    {add, remove} = Map.fetch!(map2, key)
    {:reply, MapSet.size(MapSet.difference(add, remove)) > 0, %{state | data: map2}}
  end

  defp insert(map, object), do: Map.put_new(map, object, {MapSet.new(), MapSet.new()})

  defp merge_sets(left, right), do: Map.merge(left, right, fn(_k, v1, v2) -> merge_tuples(v1, v2) end)

  defp merge_tuples({p1, p2}, {q1, q2}), do: {MapSet.union(p1, q1), MapSet.union(p2, q2)}

  defp available_leases(pid) do
    total_stock() - (Map.values(leases(pid)) |> Enum.sum())
  end
end
