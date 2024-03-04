defmodule LCRDT.OrSet do
  @moduledoc """
  This represents an OR-Set CRDT.
  """
  use GenServer

  def start_link(name) do
    IO.puts("OrSet #{name} starting")
    GenServer.start_link(__MODULE__, name, name: name);
  end

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

  @doc """
  Broadcasts its state to all nodes.
  """
  def sync(pid) do
    GenServer.cast(pid, :sync)
  end

  @doc """
  Debug functionality to see the state of the node.
  """
  def dump(pid) do
    GenServer.call(pid, :dump)
  end

  @doc """
  Initializes the set to be empty.
  """
  @impl true
  def init(name) do
    :timer.send_interval(10000, :autosync)
    {:ok, {name, Map.new()}}
  end

  @impl true
  def handle_cast(:sync, {_name, map1} = state) do
    Enum.each(LCRDT.Network.all_nodes(), &(GenServer.cast(&1, {:sync, map1})))
    {:noreply, state}
  end

  @impl true
  def handle_cast({:sync, map0}, {name, map1}) do
    map2 = merge_sets(map0, map1)
    {:noreply, {name, map2}}
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

  @impl true
  def handle_call(:dump, _from, {_name, map} = state) do
    {:reply, map, state}
  end

  @impl true
  def handle_info(:autosync, {name, _map} = state) do
    IO.puts("#{name}: Performing periodic sync.")
    sync(name)
    {:noreply, state}
  end

  defp insert(map, object), do: Map.put_new(map, object, {MapSet.new(), MapSet.new()})

  defp merge_sets(left, right), do: Map.merge(left, right, fn(_k, v1, v2) -> merge_tuples(v1, v2) end)

  defp merge_tuples({p1, p2}, {q1, q2}), do: {MapSet.union(p1, q1), MapSet.union(p2, q2)}
end
