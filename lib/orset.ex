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
  Adds an element to the set.
  """
  def add(pid, key) do
    GenServer.cast(pid, {:add, key})
  end

  @doc """
  Removes an element from the set.
  """
  def remove(pid, key) do
    GenServer.cast(pid, {:remove, key})
  end

  def leases(pid) do
    GenServer.call(pid, :get_leases)
  end

  @doc """
  Allocate leases for an element in the set.
  """
  def allocate_lease(pid, key, amount) do
    GenServer.cast(pid, {:allocate_lease, key, amount})
  end

  @doc """
  Deallocate leases for an element in the set.
  """
  def deallocate_lease(pid, key, amount) do
    GenServer.cast(pid, {:deallocate_lease, key, amount})
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
    leases = merge_sets(other_state.leases, state.leases)
    %{state | data: data, leases: leases}
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
  def handle_cast({:allocate_lease, key, amount}, state) do
    leases = Map.update(state.leases, key, amount, &(&1 + amount))
    {:noreply, %{state | leases: leases}}
  end

  @impl true
  def handle_cast({:deallocate_lease, key, amount}, state) do
    current_leases = Map.get(state.leases, key, 0)
    new_leases = max(current_leases - amount, 0)
    leases = Map.put(state.leases, key, new_leases)
    {:noreply, %{state | leases: leases}}
  end

  @impl true
  def handle_call({:contains, key}, _from, state) do
    map2 = insert(state.data, key)
    {add, remove} = Map.fetch!(map2, key)
    {:reply, MapSet.size(MapSet.difference(add, remove)) > 0, %{state | data: map2}}
  end

  @impl true
  def handle_call(:get_leases, _from, state) do
    {:reply, state.leases, state}
  end

  defp insert(map, object), do: Map.put_new(map, object, {MapSet.new(), MapSet.new()})

  defp merge_sets(left, right), do: Map.merge(left, right, fn(_k, v1, v2) -> merge_tuples(v1, v2) end)

  defp merge_tuples({p1, p2}, {q1, q2}), do: {MapSet.union(p1, q1), MapSet.union(p2, q2)}
end
