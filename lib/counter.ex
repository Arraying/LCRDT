defmodule LCRDT.Counter do
  @moduledoc """
  This represents a simple increasing CRDT counter.
  """
  @total_stock 100

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
    {name, Map.new(), Map.new(), Map.new()}
  end

  def merge_state({_name, _leases, other_up, other_down}, {name, __leases, up, down}) do
    merge_state_counters = fn left, right -> Map.merge(left, right, fn(_k, v1, v2) -> max(v1, v2) end) end
    {name, merge_state_counters.(other_up, up), merge_state_counters.(other_down, down)}
  end

  def name_from_state(state) do
    Kernel.elem(state, 0)
  end

  def prepare({:allocate, amount, _process}, {_name, leases, _up, _down} = state) do
    if Enum.sum(Map.values(leases)) + amount > @total_stock do
      {:abort, state}
    else
      {:ok, state}
    end
  end

  def commit(body, state1) do
    IO.inspect(body)
    state1
  end

  def abort(body, state1) do
    IO.inspect(body)
    state1
  end

  @impl true
  def handle_cast(:inc, {name, _leases, up, down}) do
    {:noreply, {name, Map.update(up, name, 1, &(&1 + 1)), down}}
  end

  @impl true
  def handle_cast(:dec, {name, _leases, up, down}) do
    {:noreply, {name, up, Map.update(down, name, 1, &(&1 + 1))}}
  end

  @impl true
  def handle_call(:sum, _from, {_name, _leases, up, down} = state) do
    {:reply, Enum.sum(Map.values(up)) - Enum.sum(Map.values(down)), state}
  end
end
