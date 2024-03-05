defmodule LCRDT.Counter do
  @moduledoc """
  This represents a simple increasing CRDT counter.
  """
  use LCRDT.CRDT

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

  def initial_state(name) do
    {name, Map.new(), Map.new()}
  end

  def merge_state({_name, other_up, other_down}, {name, up, down}) do
    merge_state_counters = fn left, right -> Map.merge(left, right, fn(_k, v1, v2) -> max(v1, v2) end) end
    {name, merge_state_counters.(other_up, up), merge_state_counters.(other_down, down)}
  end

  def name_from_state(state) do
    Kernel.elem(state, 0)
  end

  @impl true
  def handle_cast(:inc, {name, up, down}) do
    {:noreply, {name, Map.update(up, name, 1, &(&1 + 1)), down}}
  end

  @impl true
  def handle_cast(:dec, {name, up, down}) do
    {:noreply, {name, up, Map.update(down, name, 1, &(&1 + 1))}}
  end

  @impl true
  def handle_call(:sum, _from, {_name, up, down} = state) do
    {:reply, Enum.sum(Map.values(up)) - Enum.sum(Map.values(down)), state}
  end
end
