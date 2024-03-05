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
        GenServer.cast(Network.coordinator(), {:new_follower, name})
        []
      else
        [name]
      end

    # Handle recoveries.
    # If we have an uncommited change in the log, we need to handle this.
    logs = Logging.read(name)
    if Logging.has_uncommitted(logs) do
      # We have to re-transmit our vote response.
      # TODO: Retransmit.
    end

    state = %PState{name: name, application_pid: application_pid, logs: logs, followers: followers}
    {:ok, state}
  end

  @impl true
  def handle_cast({:new_follower, their_pid}, state1) do
    out(state1, "Added follower with PID #{their_pid}")
    state2 = %{state1 | followers: [their_pid | state1.followers]}
    {:noreply, state2}
  end

  @impl true
  def handle_cast({:start, body}, state) do
    cond do
      # Edge case: trying to start with non-coordinator.
      state.name != Network.coordinator() ->
        out(state, "ERROR, only the coordinator can handle starts")
        {:noreply, state}
      # Edge case: trying to start during a concurrent transaction.
      state.stage != :idle ->
        out(state, "ERROR, starts can only be executed in idle state")
        {:noreply, state}
      # Regular execution.
      true ->
        Enum.each(state.followers, fn follower_pid ->
          GenServer.cast(follower_pid, {:prepare_request, body})
          out(state, "Sent a prepare request to follower #{follower_pid}")
        end)
        {:noreply, %{state | stage: :prepared}}
    end
  end

  # @impl true
  # def handle_cast({:prepare_request, crdt_pid, body}, state) do
  #   # Make call to CRDT
  #   vote = case GenServer.call(crdt_pid, {:prepare, body}) do
  #     :ok ->
  #       # Send ok to coordinator
  #       Network.VoteMessages.vote_commit()
  #     :abort ->
  #       # Send not ok to coordinator
  #       Network.VoteMessages.vote_abort()
  #   end

  #   GenServer.cast(Network.coordinator(), {:vote_response, self(), vote, body})
  #   IO.puts("Follower #{inspect(self())} sent a vote response to coordinator #{inspect(Network.coordinator())}")
  #   {:noreply, state}
  # end

  # @impl true
  # def handle_cast({:vote_response, sender_pid, vote, body}, {name, application_pid, followers, votes} = _state) do
  #   # Handle vote response message
  #   if vote == Network.VoteMessages.vote_commit() do
  #     IO.puts("Vote response was :ok, putting vote into votes map")
  #     new_votes = Map.put(votes, sender_pid, vote)
  #     if Map.size(new_votes) == Map.size(followers) do
  #       IO.puts("All votes are in, let's commit")
  #       # Commit on leader
  #       GenServer.cast(Network.coordinator(), {:commit, sender_pid, body})
  #       # Commit on followers
  #       Enum.each(followers, fn {name, pid} ->
  #         GenServer.cast(pid, {:commit, sender_pid, body})
  #       end)
  #     end
  #     {:noreply, {name, application_pid, followers, new_votes}}
  #   else
  #     IO.puts("Vote response was not :ok, let's abort")
  #     {:noreply, {name, application_pid, followers, votes}}
  #   end
  # end

  # @impl true
  # def handle_cast({:commit, requester_pid, body}, state) do
  #   IO.puts("Process #{inspect(self()) } is committing to all CRDTs")
  #   all_crdts = Network.all_nodes()
  #   Enum.each(all_crdts, fn crdt_pid ->
  #     GenServer.cast(crdt_pid, {:commit, body})
  #   end)

  #   # TODO:
  #   # Log commit statement
  #   # Release locks

  #   # Remove followers
  #   {:noreply, state}
  # end

  defp out(state, message), do: IO.puts("#{__MODULE__}/#{state.name}: #{message}")

end
