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
  Decrements the counter for the current node.
  """
  def dec(pid) do
    GenServer.cast(pid, :dec)
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
    :timer.send_interval(10000, :autosync)
    {:ok, {name, Map.new(), Map.new()}}
  end

  def handle_cast(:inc, {name, up, down}) do
    {:noreply, {name, Map.update(up, name, 1, &(&1 + 1)), down}}
  end

  def handle_cast(:dec, {name, up, down}) do
    {:noreply, {name, up, Map.update(down, name, 1, &(&1 + 1))}}
  end

  def handle_cast(:sync, {_name, up, down} = state) do
    Enum.each(LCRDT.Network.all_nodes(), &(GenServer.cast(&1, {:sync, up, down})))
    {:noreply, state}
  end

  def handle_cast({:sync, other_up, other_down}, {name, up, down}) do
    {:noreply, {name, merge_counters(other_up, up), merge_counters(other_down, down)}}
  end

  def handle_call(:sum, _from, {_name, up, down} = state) do
    {:reply, Enum.sum(Map.values(up)) - Enum.sum(Map.values(down)), state}
  end

  def handle_call(:dump, _from, {_name, up, down} = state) do
    {:reply, {up, down}, state}
  end

  def handle_info(:autosync, {name, _up, _down} = state) do
    IO.puts("#{name}: Performing periodic sync.")
    sync(name)
    {:noreply, state}
  end

  defp merge_counters(left, right), do: Map.merge(left, right, fn(_k, v1, v2) -> max(v1, v2) end)
end
