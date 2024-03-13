defmodule LCRDT.Counter do
  @moduledoc """
  This represents a simple increasing CRDT counter.
  """

  use LCRDT.CRDT

  @doc """
  Increments the counter for the current node.
  """
  def inc(pid) do
    call_blocking(pid, :inc)
  end

  @doc """
  Decrements the counter for the current node.
  """
  def dec(pid) do
    call_blocking(pid, :dec)
  end

  @doc """
  Estimates the sum of the counter.
  """
  def sum(pid) do
    call_blocking(pid, :sum)
  end

  def can_deallocate?(state, amount, process) do
    current_leases = Map.get(state.leases, process, 0)
    current_leases - get_counter(state, process) - amount >= 0
  end

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
  def handle_operation(:inc, state) do
    if get_leases(state) - get_counter(state, state.name) <= 0 do
      # TODO: Request more leases or/and return error
      {:lease_violation, state}
    else
      {:inc, %{state | up: Map.update(state.up, state.name, 1, &(&1 + 1))}}
    end
  end

  @doc """
  Decrements the counter.
  """
  def handle_operation(:dec, state) do
    if sum_counter(state) <= 0 do
      # TODO: return error, can't dec anymore
      {:lease_violation, state}
    else
      {:dec, %{state | down: Map.update(state.down, state.name, 1, &(&1 + 1))}}
    end
  end

  @doc """
  Estimates the current count.
  """
  def handle_operation(:sum, state) do
    {sum_counter(state), state}
  end

  # @impl true
  # def handle_cast(:inc, state) do
  #   if get_leases(state) - get_counter(state, state.name) <= 0 do
  #     # TODO: Request more leases or/and return error
  #     IO.puts("Lease violation: #{inspect(state)}")
  #     {:noreply, state}
  #   else
  #     {:noreply, %{state | up: Map.update(state.up, state.name, 1, &(&1 + 1))}}
  #   end
  # end

  # @doc """
  # Decrements the counter.
  # """
  # @impl true
  # def handle_cast(:dec, state) do
  #   if sum_counter(state) <= 0 do
  #     # TODO: return error, can't dec anymore
  #     IO.puts("Decrement violation: #{inspect(state)}")
  #     {:noreply, state}
  #   else
  #     {:noreply, %{state | down: Map.update(state.down, state.name, 1, &(&1 + 1))}}
  #   end
  # end

  # @doc """
  # Estimates the current count.
  # """
  # @impl true
  # def handle_call(:sum, _from, state) do
  #   {:reply, sum_counter(state), state}
  # end

  defp sum_counter(state), do: Enum.sum(Map.values(state.up)) - Enum.sum(Map.values(state.down))

  defp get_counter(state, process), do: Map.get(state.up, process, 0) - Map.get(state.down, process, 0)
end
