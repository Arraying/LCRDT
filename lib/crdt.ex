defmodule LCRDT.CRDT do
  @moduledoc """
  A common abstraction for CvCRDTs.
  This implements state synchronization and syncing.
  """
alias LCRDT.Environment


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
        LCRDT.Network.reliable_call(pid, {:queue, :allocate, amount})
      end

      def revoke_leases(pid, amount) do
        LCRDT.Network.reliable_call(pid, {:queue, :deallocate, amount})
      end

      # Manually start a sync.
      def sync(pid) do
        GenServer.cast(pid, :sync)
      end

      # Debug functionality.
      def dump(pid) do
        LCRDT.Network.reliable_call(pid, :dump)
      end

      defp call_blocking(pid, operation) do
        # We run an operation until we receive a response.
        # This will internally be a call.
        LCRDT.Network.reliable_call(pid, {:queue, :operation, operation})
      end

      # This will initialize the state and start auto-syncing.
      @impl true
      def init(name) do
        :timer.send_interval(LCRDT.Environment.get_sync_interval(), :autosync)

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
      def handle_cast({:commit, {_, _, process}}, state1) do
        # We don't actually care what the body is.
        # Since this is 2PC, everyone needs to have prepared so we have nothing to do here.
        state2 = %{state1 | uncommitted_changes: false, waiting: should_we_wait(state1, process)}
        state3 = run_queue(state2)
        save_state(state3)
        {:noreply, state3}
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
            %{state1 | leases: leases, uncommitted_changes: false}
          else
            # We were (one of) the one(s) who aborted.
            # It's not in our state so we don't need to undo it.
            state1
          end
        state3 = run_queue(%{state2 | waiting: should_we_wait(state1, process)})
        save_state(state3)
        {:noreply, state3}
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
        save_state(state2)
        {:reply, res, state2}
      end

      @impl true
      def handle_call({:replay, {:allocate, amount, process} = body}, _from, state) do
        out(state, "Replaying #{inspect(body)}")
        {:reply, :ok, %{state | leases: add_leases(state.leases, amount, process)}}
      end

      @impl true
      def handle_cast({:abort, {:deallocate, amount, process}}, state1) do
        state2 =
          if state1.uncommitted_changes do
            leases =
              if Map.has_key?(state1.leases, process) do
                Map.update!(state1.leases, process, fn x -> x + amount end)
              else
                Map.put(state1.leases, process, amount)
              end
            %{state1 | leases: leases, uncommitted_changes: false}
          else
            # We were (one of) the one(s) who aborted.
            # It's not in our state so we don't need to undo it.
            state1
          end
        state3 = run_queue(%{state2 | waiting: should_we_wait(state1, process)})
        save_state(state3)
        {:noreply, state3}
      end

      @impl true
      def handle_call({:prepare, {:deallocate, amount, process} = body}, _from, state) do
        out(state, "Preparing to deallocate #{inspect(body)}")
        if can_deallocate?(state, amount, process) do
          state2 = %{state | leases: remove_leases(state.leases, amount, process), uncommitted_changes: true}
          save_state(state2)
          {:reply, :ok, state2}
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

      @impl true
      def handle_call({:queue, opcode, op}, sender, state1) do
        # Can we handle this operation right now?
        if state1.waiting do
          state2 = %{state1 | queue: state1.queue ++ [{opcode, op, sender}]}
          {:noreply, state2}
        else
          # If we're not waiting, we can handle it all the same.
          # We can reply immediately.
          {res, state2} = run_operation(opcode, op, sender, state1, false)
          {:reply, res, state2}
        end
      end

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

      defp potentially_request_more_leases(state, used_function) do
        amount = Environment.get_auto_allocation()
        cond do
          # We don't auto allocate
          amount == -1 ->
            state
          # We have none left, we need to get more.
          used_function.() >= get_leases(state) ->
            LCRDT.Participant.allocate(state.name, amount)
            state2 = %{state | waiting: true}
            save_state(state2)
            state2
          # We're good here, nothing left to do.
          true ->
            state
        end
      end

      defp add_leases(leases, amount, process) do
        Map.update(leases, process, amount, fn x -> x + amount end)
      end

      defp run_operation(opcode, op, sender, state1, notify) do
        {response, _} = res = case opcode do
          :operation ->
            handle_operation(op, state1)
            # If we notify, we just return the new state.
            # This is used in the fold function to continue.
          lease ->
            # Op here is an integer for the amount.
            handle_lease(lease, op, state1.name, sender, state1)
        end
        # If we notify, we just return the new state.
        # This is used in the fold function to continue.
        if notify and sender != :nil do
          # Only ever used in fold, here we just want the new state.
          GenServer.reply(sender, response)
        end
        res
      end

      defp handle_lease(opcode, amount, target, sender, state1) do
        res = case opcode do
          :allocate ->
            LCRDT.Participant.allocate(target, amount)
          :deallocate ->
            LCRDT.Participant.deallocate(target, amount)
        end
        state2 = %{state1 | waiting: true}
        save_state(state2)
        {:ok, state2}
      end

      defp run_queue(state1) do
        # If we're still waiting, we do not yet run the queue.
        unless state1.waiting do
          run_queue_worker(state1)
        else
          # We're still waiting, we don't do anything.
          state1
        end

      end

      defp run_queue_worker(state1) do
        case state1.queue do
          # Base case, we return.
          [] ->
            state1
          # If we're waiting we also return.
          _ when state1.waiting ->
            state1
          # Otherwise we work the queue until we have to wait.
          [{code, op, sender} | next] ->
            {_, state2} = run_operation(code, op, sender, state1, true)
            state3 = %{state2 | queue: next}
            run_queue_worker(state3)
        end
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

      defp should_we_wait(state, process_for) do
        res = if state.waiting do
          # If we are currently waiting, then we divide into two cases:
          # 1: We are waiting for us, in which case we can stop waiting.
          # 2: We are not waiting for us, in which case we retain our
          if process_for == state.name, do: false, else: true
        else
          # If we are not waiting, we continue to not wait.
          false
        end
        res
      end

      defp out(state, message) do
        unless LCRDT.Environment.is_silent(), do: IO.puts("#{__MODULE__}/#{state.name}: #{message}")
      end

    end
  end
end
