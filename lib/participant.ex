defmodule LCRDT.Participant do
  alias LCRDT.Logging
  alias LCRDT.Network
  use GenServer

  # All state (only some of it relevant to non-leader)
  # Name - the PID of the process
  # Application PID - the PID of the linked application layer
  # Logs - the persistant storage log.
  # Followers - the PID of the followers (incl. self)
  # In progress
  # Votes - map of PID and vote
  defmodule PState do
    defstruct [
      :name,
      :application_pid,
      :logs,
      :followers,
      :tid,
      stage: :idle,
      votes: Map.new()
    ]
  end

  def start_link({name, application_pid}) do
    IO.puts("#{__MODULE__}/#{name}: Starting")
    GenServer.start_link(__MODULE__, {name, application_pid}, name: name);
  end

  def allocate(application_pid, lease_amount) do
    # Body = {:allocate, amount, allocater_pid}
    GenServer.cast(Network.coordinator(), {:start, {:allocate, lease_amount, application_pid}})
  end

  def deallocate(application_pid, lease_amount) do
    # Body = {:deallocate, amount, deallocater_pid}
    GenServer.cast(Network.coordinator(), {:start, {:deallocate, lease_amount, application_pid}})
  end

  @impl true
  def init({name, application_pid}) do
    # TODO: consider adding leader to followers
    followers =
      if name != Network.coordinator() do
        # We indicate that we are a follower.
        GenServer.cast(Network.coordinator(), {:new_follower, name})
        # We also send the recovery signal to the coordinator.
        GenServer.cast(Network.coordinator(), {:recovery, name})
        []
      else
        [name]
      end

    # Handle recoveries.
    # If we have an uncommited change in the log, we need to handle this.
    logs = Logging.read(name)
    # Go through all the changes in the log and apply them.
    apply_logs(logs, application_pid)
    if Logging.has_uncommitted(logs) do
      # We have to re-transmit our vote response.
      # TODO: Retransmit.
    end

    state = %PState{name: name, application_pid: application_pid, logs: logs, followers: followers}
    {:ok, state}
  end

  @impl true
  def handle_cast({:new_follower, their_pid}, state1) do
    out(state1, "Discovered follower with PID #{their_pid}")
    # We only want to add them if they do not exist. If they crashed and restart, they will exist.
    followers = if Enum.member?(state1.followers, their_pid), do: state1.followers, else: [their_pid | state1.followers]
    state2 = %{state1 | followers: followers}
    {:noreply, state2}
  end

  @impl true
  def handle_cast({:start, body}, state1) do
    cond do
      # Edge case: trying to start with non-coordinator.
      state1.name != Network.coordinator() ->
        out(state1, "ERROR, only the coordinator can handle starts")
        {:noreply, state1}
      # Edge case: trying to start during a concurrent transaction.
      state1.stage != :idle ->
        out(state1, "ERROR, starts can only be executed in idle state")
        {:noreply, state1}
      # Regular execution.
      true ->
        # We assign this a new transaction ID.
        state2 = %{state1 | tid: :erlang.make_ref()}
        # Now we must tell all followers to prepare.
        Enum.each(state2.followers, fn follower_pid ->
          GenServer.cast(follower_pid, {:prepare_request, state2.tid, body})
          out(state2, "Sent a prepare request to follower #{follower_pid}")
        end)
        # We now set the state to be in preparation, this is needed for recovery.
        {:noreply, %{state2 | stage: :prepared}}
    end
  end

  @impl true
  def handle_cast({:prepare_request, tid, body}, state1) do
    # First, we have to make a call to the application layer to determine what to do.
    # The application layer will tell us either OK or abort.
    {vote, state2} = case GenServer.call(state1.application_pid, {:prepare, body}, :infinity) do
      :ok ->
        # If this is okay, we need to add it to our own log.
        logs = Logging.log_change(state1.logs, tid, body)
        {:ok, %{state1 | logs: logs}}
      :abort ->
        # If this is not okay, then we just need to return the message.
        {:abort, state1}
    end
    # Send the response to the actual coordinator.
    GenServer.cast(Network.coordinator(), {:vote_response, tid, state2.name, vote, body})
    out(state2, "Sent a vote response to coodinator: #{vote}")
    {:noreply, state2}
  end

  @impl true
  def handle_cast({:vote_response, _tid, vote_caster, vote, body}, state1) do
    # TODO: Check if we are finalized. If so, let the node know of the outcome.
    # Handle vote response messages.
    state2 = %{state1 | votes: Map.put(state1.votes, vote_caster, vote)}
    # We wait for all votes to arrive before we possibly abort.
    # This is so we can be sure we don't get out of order. I think that could be an edge case.
    state3 =
      if map_size(state2.votes) == length(state2.followers) do
        num_aborts = Enum.count(Map.values(state2.votes), fn x -> x == :abort end)
        out(state2, "Received #{num_aborts} aborts")
        # Naturally, we abort if at least one node says to abort.
        action = if num_aborts == 0, do: :commit, else: :abort
        # Broadcast the outcome to all followers.
        Enum.each(state2.followers, fn follower_pid ->
          GenServer.cast(follower_pid, {:finalize, state2.tid, action, body})
          out(state2, "Sent a finalize request to follower #{follower_pid}")
        end)
        # We are done with this now!
        # We can reset the state back to blank now.
        out(state2, "Resetting the state")
        %{state2 | tid: nil, stage: :idle, votes: Map.new()}
      else
        state2
      end
    # Last but not least, we update the state.
    {:noreply, state3}
  end

  @impl true
  def handle_cast({:finalize, tid, :commit, body}, state) do
    # Send a COMMIT indication.
    GenServer.cast(state.application_pid, {:commit, body})
    logs = Logging.log_commit(state.logs, tid)
    {:noreply, %{state | logs: logs}}
  end

  @impl true
  def handle_cast({:finalize, tid, :abort, body}, state) do
    # Send an ABORT indication.
    GenServer.cast(state.application_pid, {:commit, body})
    logs = Logging.log_abort(state.logs, tid)
    {:noreply, %{state | logs: logs}}
  end

  def handle_cast({:recovery, _recovered_pid}, state) do
    # TODO: Proper recovery handling.
    {:noreply, state}
  end

  defp apply_logs(_logs, _application_pid) do
    # TODO: Execute these one by one.
  end

  defp out(state, message), do: IO.puts("#{__MODULE__}/#{state.name}: #{message}")
end
