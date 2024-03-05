defmodule LCRDT.Participant do
  use GenServer

  def start_link(name) do
    IO.puts("Participant #{name} starting")
    GenServer.start_link(__MODULE__, name, name: name);
  end

  def allocate(allocater_pid, crdt_pid, lease_amount) do
    # Body = {:allocate, amount, allocater_pid}
    GenServer.cast(LCRDT.Network.coordinator(), {:start, crdt_pid, {:allocate, lease_amount, allocater_pid}})
  end

  def deallocate(deallocater_pid, crdt_pid, lease_amount) do
    # Body = {:deallocate, amount, deallocater_pid}
    GenServer.cast(LCRDT.Network.coordinator(), {:start, crdt_pid, {:deallocate, lease_amount, deallocater_pid}})
  end

  @impl true
  def init(name) do
    # Leader state = {name, followers, votes, acks}
    # Name - might be redundant
    # Followers - map of {follower name, follower pid}
    # Votes - map of {follower pid, vote}
    # (Skipped for now) Acks - used for logging whether commit on follower was successful, map of {follower pid, ack}

    # TODO: consider adding leader to followers
    {:ok, {name, Map.new(), Map.new()}}
  end

  @impl true
  def handle_cast({:new_follower, new_follower_name,  new_follower_pid}, {name, followers, votes} = _state) do
    IO.puts("Coordinator #{inspect(LCRDT.Network.coordinator())} added follower with PID #{inspect(new_follower_pid)}")
    {:noreply, {name, Map.put(followers, new_follower_name, new_follower_pid), votes}}
  end

  @impl true
  def handle_cast({:start, crdt_pid, body}, {name, followers, _votes} = state) do
    # Check if node leader
    if name == LCRDT.Network.coordinator() do
      # Include leader
      followers_with_leader = Map.put(followers, LCRDT.Network.coordinator(), LCRDT.Network.coordinator())
      # We go over all the followers
      # in order to log prepare step
      Enum.each(followers_with_leader, fn {name, pid} ->
        GenServer.cast(pid, {:prepare_request, crdt_pid, body})
        IO.puts("Coordinator #{inspect(LCRDT.Network.coordinator())} sent a prepare request to follower #{inspect(pid)}")
      end)
    else
      IO.puts("Only coordinator can send prepare requests")
    end
    {:noreply, state}
  end

  @impl true
  def handle_cast({:prepare_request, crdt_pid, body}, state) do
    # Make call to CRDT
    vote = case GenServer.call(crdt_pid, {:prepare, body}) do
      :ok ->
        # Send ok to coordinator
        LCRDT.Network.VoteMessages.vote_commit()
      :abort ->
        # Send not ok to coordinator
        LCRDT.Network.VoteMessages.vote_abort()
    end

    GenServer.cast(LCRDT.Network.coordinator(), {:vote_response, self(), vote, body})
    IO.puts("Follower #{inspect(self())} sent a vote response to coordinator #{inspect(LCRDT.Network.coordinator())}")
    {:noreply, state}
  end

  @impl true
  def handle_cast({:vote_response, sender_pid, vote, body}, {name, followers, votes} = _state) do
    # Handle vote response message
    if vote == LCRDT.Network.VoteMessages.vote_commit() do
      IO.puts("Vote response was :ok, putting vote into votes map")
      new_votes = Map.put(votes, sender_pid, vote)
      if Map.size(new_votes) == Map.size(followers) do
        IO.puts("All votes are in, let's commit")
        # Commit on leader
        GenServer.cast(LCRDT.Network.coordinator(), {:commit, sender_pid, body})
        # Commit on followers
        Enum.each(followers, fn {name, pid} ->
          GenServer.cast(pid, {:commit, sender_pid, body})
        end)
      end
      {:noreply, {name, followers, new_votes}}
    else
      IO.puts("Vote response was not :ok, let's abort")
      {:noreply, {name, followers, votes}}
    end
  end

  @impl true
  def handle_cast({:commit, requester_pid, body}, state) do
    IO.puts("Process #{inspect(self()) } is committing to all CRDTs")
    all_crdts = LCRDT.Network.all_nodes()
    Enum.each(all_crdts, fn crdt_pid ->
      GenServer.cast(crdt_pid, {:commit, body})
    end)

    # TODO:
    # Log commit statement
    # Release locks

    # Remove followers
    {:noreply, state}
  end

end
