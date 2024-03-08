defmodule LCRDT.CRDT do
  @moduledoc """
  A common abstraction for CvCRDTs.
  This implements state synchronization and syncing.
  """

  # TODO: Implement {:deallocate, amount, pid}

  @callback total_stock() :: term
  @callback initial_state() :: term
  @callback merge_state(other_state :: term, state :: term) :: term

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

      # Manually start a sync.
      def sync(pid) do
        GenServer.cast(pid, :sync)
      end

      # Debug functionality.
      def dump(pid) do
        GenServer.call(pid, :dump)
      end

      # This will initialize the state and start auto-syncing.
      @impl true
      def init(name) do
        :timer.send_interval(10_000_000, :autosync)
        crdt = %{
          name: name,
          leases: Map.new(),
          uncommitted_changes: false,
        }
        domain = initial_state()
        # CRDT state takes priority in terms of conflicts.
        {:ok, Map.merge(domain, crdt)}
      end

      @impl true
      def handle_cast({:request_leases, amount}, state) do
        LCRDT.Participant.allocate(state.name, amount)
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
        {:noreply, merge_state(other_state, state)}
      end

      # <-- CRDT communication -->
      @impl true
      def handle_cast({:commit, _body}, state) do
        # We don't actually care what the body is.
        # Since this is 2PC, everyone needs to have prepared so we have nothing to do here.
        {:noreply, %{state | uncommitted_changes: false}}
      end

      @impl true
      def handle_cast({:abort, {:allocate, amount, process}}, state) do
        if state.uncommitted_changes do
          leases =
            if Map.has_key?(state.leases, process) do
              Map.update!(state.leases, process, fn x -> x - amount end)
            else
              state.leases
            end
          {:noreply, %{state | leases: leases, uncommitted_changes: false}}
        else
          # We were (one of) the one(s) who aborted.
          # It's not in our state so we don't need to undo it.
          {:noreply, state}
        end
      end

      @impl true
      def handle_call({:prepare, {:allocate, amount, process} = body}, _from, state) do
        out(state, "Got asked to prepare #{inspect(body)}")
        if Enum.sum(Map.values(state.leases)) + amount > total_stock() do
          {:reply, :abort, state}
        else
          {:reply, :ok, %{state | leases: add_leases(state.leases, amount, process), uncommitted_changes: true}}
        end
      end

      @impl true
      def handle_call({:replay, {:allocate, amount, process} = body}, _from, state) do
        out(state, "Replaying #{inspect(body)}")
        {:reply, :ok, %{state | leases: add_leases(state.leases, amount, process)}}
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

      defp get_leases(state), do: Map.get(state.leases, get_tpc_name(state.name), 0)

      defp add_leases(leases, amount, process) do
        Map.update(leases, process, amount, fn x -> x + amount end)
      end

      defp out(state, message), do: IO.puts("#{__MODULE__}/#{state.name}: #{message}")

      defp get_tpc_name(name) do
        # Transform CRDT node name to a TPC ONE
        # replace "_crdt" with "_tpc" in the atom name
        name_string = Atom.to_string(name)
        tpc_name_string = String.replace(name_string, "_crdt", "_tpc")
        String.to_atom(tpc_name_string)
      end
    end
  end
end
