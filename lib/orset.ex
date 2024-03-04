defmodule LCRDT.OrSet do
  @moduledoc """
  This represents an OR-Set CRDT.
  """
  use LCRDT.CRDT

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

  def initial_state(name) do
    {name, Map.new()}
  end

  def merge_state({_name, other_map}, {name, map}) do
    {name, merge_sets(other_map, map)}
  end

  def name_from_state(state) do
    Kernel.elem(state, 0)
  end

  @impl true
  def handle_cast({:add, key}, {name, map1}) do
    map2 = insert(map1, key)
    {add, remove} = Map.fetch!(map2, key)
    map3 = Map.put(map2, key, {MapSet.put(add, :erlang.make_ref()), remove})
    {:noreply, {name, map3}}
  end

  @impl true
  def handle_cast({:remove, key}, {name, map1}) do
    map2 = insert(map1, key)
    {add, remove} = Map.fetch!(map2, key)
    map3 = Map.put(map2, key, {add, MapSet.union(add, remove)})
    {:noreply, {name, map3}}
  end

  @impl true
  def handle_call({:contains, key}, _from, {name, map1}) do
    map2 = insert(map1, key)
    {add, remove} = Map.fetch!(map2, key)
    {:reply, MapSet.size(MapSet.difference(add, remove)) > 0, {name, map2}}
  end

  defp insert(map, object), do: Map.put_new(map, object, {MapSet.new(), MapSet.new()})

  defp merge_sets(left, right), do: Map.merge(left, right, fn(_k, v1, v2) -> merge_tuples(v1, v2) end)

  defp merge_tuples({p1, p2}, {q1, q2}), do: {MapSet.union(p1, q1), MapSet.union(p2, q2)}
end
