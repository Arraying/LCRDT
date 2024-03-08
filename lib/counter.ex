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

  @doc """
  The total number of stock.
  This is the max. leases we can allocate across all nodes.
  """
  def total_stock(), do: 100

  @doc """
  The initial state. Two empty counters.
  """
  def initial_state() do
    %{
      up: Map.new(),
      down: Map.new()
    }
  end

  @doc """
  Merges the two counters by taking the max element-wise.
  """
  def merge_state(other_state, state) do
    fun = fn left, right -> Map.merge(left, right, fn(_k, v1, v2) -> max(v1, v2) end) end
    %{state | up: fun.(other_state.up, state.up), down: fun.(other_state.down, state.down)}
  end

  @doc """
  Increments the counter.
  """
  @impl true
  def handle_cast(:inc, state) do
    if (get_leases(state) < 1) do
      # Not sure how to handle violations
      IO.puts("Lease violation: #{inspect(state)}")
      {:noreply, state}
    else
      # TODO: Store lease change persistently
      {:noreply, %{state | up: Map.update(state.up, state.name, 1, &(&1 + 1)), leases: Map.update(state.leases, get_tpc_name(state.name), 1, &(&1 - 1))}}
    end
  end

  @doc """
  Decrements the counter.
  """
  @impl true
  def handle_cast(:dec, state) do
    # Do I use the :sum call instead?
    if (Enum.sum(Map.values(state.up)) - Enum.sum(Map.values(state.down)) < 1) do
      # Not sure how to handle violations
      IO.puts("Decrement violation: #{inspect(state)}")
      {:noreply, state}
    else
      # TODO: Do we regain the lease? If so, store persistently.
      {:noreply, %{state | down: Map.update(state.down, state.name, 1, &(&1 + 1))}}
    end
  end

  @doc """
  Estimates the current count.
  """
  @impl true
  def handle_call(:sum, _from, state) do
    {:reply, Enum.sum(Map.values(state.up)) - Enum.sum(Map.values(state.down)), state}
  end
end
