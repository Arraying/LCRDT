defmodule LCRDT.CRDT do
  @moduledoc """
  A common abstraction for CvCRDTs.
  This implements state synchronization and syncing.
  """


  @callback initial_state() :: term
  @callback merge_state(other_state :: term, state :: term) :: term
  @callback can_deallocate?(state :: term, amount :: term, process :: term) :: term
  @callback handle_operation(operation :: term, state :: term) :: term

  defmacro __using__(_opts) do
    quote do
      use GenServer

      # This will start the GenServer with the correct module and register it.
      def start_link(name) do
        IO.puts("#{__MODULE__}/#{name}: Starting")
        GenServer.start_link(__MODULE__, name, name: name);
      end

      def request_leases(pid, amount) do
        GenServer.cast(pid, {:request_leases, amount})
      end

      def deallocate_leases(pid, amount) do
        GenServer.cast(pid, {:deallocate_leases, amount})
      end

      # Manually start a sync.
      def sync(pid) do
        GenServer.cast(pid, :sync)
      end

      # Debug functionality.
      def dump(pid) do
        GenServer.call(pid, :dump)
      end

      defp run_operation_blocking(pid, operation, requester_pid) do
        # We run an operation until we receive a response.
        # This will internally be a call.
        GenServer.call(pid, {:operation, operation, requester_pid}, :infinity)
      end

      # This will initialize the state and start auto-syncing.
      @impl true
      def init(name) do
        :timer.send_interval(10_000_000, :autosync)

        # State priority
        # 1. crdt
        # 2. recovered_state
        # 3. initial_state
        domain = initial_state()
        recovered_state = LCRDT.Store.read(name)
        crdt = %{
          name: name,
          leases: Map.new(),
          uncommitted_changes: false,
          waiting: false,
          queue: []
        }

        # CRDT state takes priority in terms of conflicts.
        {:ok, Map.merge(Map.merge(domain, recovered_state), crdt)}
      end

      @impl true
      def handle_cast({:request_leases, amount}, state) do
        LCRDT.Participant.allocate(state.name, amount)
        {:noreply, state}
      end

      @impl true
      def handle_cast({:deallocate_leases, amount}, state) do
        LCRDT.Participant.deallocate(state.name, amount)
        {:noreply, state}
      end

      # Broadcasts its entire state.
      @impl true
      def handle_cast(:sync, state) do
        Enum.each(LCRDT.Network.all_nodes() |> Enum.map(&(LCRDT.Network.node_to_crdt(&1))), &(GenServer.cast(&1, {:sync, state})))
        {:noreply, state}
      end

      @impl true
      def handle_cast({:sync, other_state}, state) do
        merged_state = merge_state(other_state, state)
        save_state(merged_state)
        {:noreply, merged_state}
      end

      # <-- CRDT communication -->
      @impl true
      def handle_cast({:commit, _body}, state1) do
        # We don't actually care what the body is.
        # Since this is 2PC, everyone needs to have prepared so we have nothing to do here.
        state2 = %{state1 | uncommitted_changes: false, waiting: false}
        save_state(state2)
        {:noreply, state2}
      end

      @impl true
      def handle_cast({:abort, {:allocate, amount, process}}, state1) do
        state2 =
          if state1.uncommitted_changes do
            leases =
              if Map.has_key?(state1.leases, process) do
                Map.update!(state1.leases, process, fn x -> x - amount end)
              else
                state1.leases
              end
            %{state1 | leases: leases, uncommitted_changes: false, waiting: false}
          else
            # We were (one of) the one(s) who aborted.
            # It's not in our state so we don't need to undo it.
            %{state1 | waiting: false}
          end
        save_state(state2)
        {:noreply, state2}
      end

      @impl true
      def handle_call({:prepare, {:allocate, amount, process} = body}, _from, state1) do
        out(state1, "Got asked to prepare #{inspect(body)}")
        {res, state2} =
          if Enum.sum(Map.values(state1.leases)) + amount > LCRDT.Environment.get_stock() do
            {:abort, state1}
          else
            {:ok, %{state1 | leases: add_leases(state1.leases, amount, process), uncommitted_changes: true}}
          end
        state3 = %{state2 | waiting: true}
        save_state(state3)
        {:reply, res, state3}
      end

      @impl true
      def handle_call({:replay, {:allocate, amount, process} = body}, _from, state) do
        out(state, "Replaying #{inspect(body)}")
        {:reply, :ok, %{state | leases: add_leases(state.leases, amount, process)}}
      end

      @impl true
      def handle_cast({:abort, {:deallocate, amount, process}}, state) do
        if state.uncommitted_changes do
          leases =
            if Map.has_key?(state.leases, process) do
              Map.update!(state.leases, process, fn x -> x + amount end)
            else
              Map.put(state.leases, process, amount)
            end
          {:noreply, %{state | leases: leases, uncommitted_changes: false}}
        else
          # We were (one of) the one(s) who aborted.
          # It's not in our state so we don't need to undo it.
          {:noreply, state}
        end
      end

      @impl true
      def handle_call({:prepare, {:deallocate, amount, process} = body}, _from, state) do
        out(state, "Preparing to deallocate #{inspect(body)}")
        if can_deallocate?(state, amount, process) do
          {:reply, :ok, %{state | leases: remove_leases(state.leases, amount, process), uncommitted_changes: true}}
        else
          {:reply, :abort, state}
        end
      end

      @impl true
      def handle_call({:replay, {:deallocate, amount, process} = body}, _from, state) do
        out(state, "Replaying deallocation #{inspect(body)}")
        {:reply, :ok, %{state | leases: remove_leases(state.leases, amount, process)}}
      end
      # <-- /CRDT communication -->

      # Just returns the state.
      @impl true
      def handle_call(:dump, _from, state) do
        {:reply, state, state}
      end

      # This should only ever be used for testing.
      @impl true
      def handle_call({:test_override_state, state}, _from, _state) do
        {:reply, :ok, state}
      end

      # This will receive the sync signal and perform synchronization.
      @impl true
      def handle_info(:autosync, state) do
        out(state, "Performing periodic sync")
        sync(state.name)
        {:noreply, state}
      end

      defp get_leases(state), do: Map.get(state.leases, state.name, 0)

      defp add_leases(leases, amount, process) do
        Map.update(leases, process, amount, fn x -> x + amount end)
      end

      defp remove_leases(leases, amount, process) do
        case Map.get(leases, process) do
          nil -> leases
          current_amount ->
            new_amount = current_amount - amount
            Map.update(leases, process, new_amount, fn x -> x - amount end)
        end
      end

      defp save_state(state) do
        # We do not save leases as these are recovered separately.
        # We save if we are waiting and the queue such that we can:
        # 1. Continue to wait until our recovery is successful
        # 2. Respond to the queue of requests.
        LCRDT.Store.write(state.name, %{state | leases: Map.new()})
      end

      defp out(state, message), do: IO.puts("#{__MODULE__}/#{state.name}: #{message}")

    end
  end
end
