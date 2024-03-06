defmodule LCRDT.CRDT do
  @moduledoc """
  A common abstraction for CvCRDTs.
  This implements state synchronization and syncing.
  """

  @callback initial_state(term) :: term
  @callback merge_state(other_state :: term, state :: term) :: term
  @callback name_from_state(term) :: term
  @callback prepare(term, term) :: {term, term}
  @callback commit(term, term) :: term
  @callback abort(term, term) :: term
  @callback replay(term, term) :: term

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
        {:ok, initial_state(name)}
      end

      @impl true
      def handle_cast({:request_leases, amount}, state) do
        name = name_from_state(state)
        LCRDT.Participant.allocate(name, amount)
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
      def handle_cast({:commit, body}, state) do
        {:noreply, commit(body, state)}
      end

      @impl true
      def handle_cast({:abort, body}, state) do
        {:noreply, abort(body, state)}
      end

      @impl true
      def handle_call({:prepare, body}, _from, state1) do
        {res, state2} = prepare(body, state1)
        IO.puts("#{name_from_state(state1)} got asked to prepare")
        {:reply, res, state2}
      end

      @impl true
      def handle_call({:replay, body}, _from, state) do
        IO.puts("#{__MODULE__}/#{name_from_state(state)}: Replaying #{inspect(body)}")
        {:reply, :ok, replay(body, state)}
      end
      # <-- /CRDT communication -->

      # Just returns the state.
      @impl true
      def handle_call(:dump, _from, state) do
        {:reply, state, state}
      end

      # This will receive the sync signal and perform synchronization.
      @impl true
      def handle_info(:autosync, state) do
        name = name_from_state(state)
        IO.puts("#{__MODULE__}/#{name}: Performing periodic sync")
        sync(name)
        {:noreply, state}
      end
    end
  end
end
