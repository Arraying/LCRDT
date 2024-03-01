defmodule LCRDT.Counter do
  @moduledoc """
  This represents a simple increasing CRDT counter.
  """
  use GenServer

  def start_link(name) do
    IO.puts("Counter #{name} starting")
    GenServer.start_link(__MODULE__, name, name: name);
  end

  @doc """
  Increments the counter for the current node.
  """
  def inc(pid) do
    GenServer.cast(pid, :inc)
  end

  @doc """
  Estimates the sum of the counter.
  """
  def sum(pid) do
    GenServer.call(pid, :sum)
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
  Initializes the counter to be empty.
  """
  def init(name) do
    {:ok, {name, Map.new()}}
  end

  def handle_cast(:inc, {name, counters}) do
    {:noreply, {name, Map.update(counters, name, 1, &(&1 + 1))}}
  end

  def handle_cast(:sync, {name, counters}) do
    Enum.each(LCRDT.Network.all_nodes(), &(GenServer.cast(&1, {:sync, counters})))
    {:noreply, {name, counters}}
  end

  def handle_cast({:sync, other_counters}, {name, counters}) do
    {:noreply, {name, Map.merge(other_counters, counters, fn(_k, v1, v2) -> max(v1, v2) end)}}
  end

  def handle_call(:sum, _from, {name, counters}) do
    {:reply, Enum.sum(Map.values(counters)), {name, counters}}
  end

  def handle_call(:dump, _from, {name, counters}) do
    {:reply, counters, {name, counters}}
  end
end
