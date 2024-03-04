defmodule TPC.Coordinator do
  use GenServer

  def start_link(name) do
    IO.puts("Coordinator #{name} starting")
    GenServer.start_link(__MODULE__, name, name: name);
  end

  def print_followers(pid) do
    GenServer.call(pid, :print_followers)
  end

  @impl true
  def init(name) do
    # State = {name, followers, votes, acks}
    # Name - might be redundant
    # Followers - map of {follower name, follower pid}
    # Votes - map of {follower pid, vote}
    # Acks - used for logging whether commit on follower was successful, map of {follower pid, ack}
    {:ok, {name, Map.new(), Map.new()}}
  end

  @impl true
  def handle_call(:print_followers, _from, {_name, followers, _votes} = state) do
    Enum.each(followers, fn {name, pid} ->
      IO.puts("Follower #{inspect(name)} with PID #{inspect(pid)}")
    end)

    {:reply, :ok, state}
  end

  @impl true
  def handle_cast({:new_follower, new_follower}, {name, followers, votes} = _state) do
    new_follower_pid = Process.whereis(new_follower)
    {:noreply, {name, Map.put(followers, new_follower, new_follower_pid), votes}}
  end

  @impl true
  def handle_cast({:prepare, requester_pid, amount}, {_name, followers, _votes} = state) do
    # Include leader
    followers_with_leader = Map.put(followers, self(), self())
    # We go over all the followers
    # in order to log prepare step
    Enum.each(followers_with_leader, fn {name, pid} ->
      GenServer.cast(pid, {:prepare_request, requester_pid, amount})
      IO.puts("Coordinator #{inspect(self())} sent a prepare request to follower #{inspect(pid)}")
    end)
    {:noreply, state}
  end

  # TODO: Abstract with :prepare_request in follower
  @impl true
  def handle_cast({:prepare_request, requester_pid, _amount}, state) do
    # Handle prepare request message
    {:noreply, state}
  end

  @impl true
  def handle_cast({:vote_response, sender_pid, vote, amount}, {name, followers, votes} = _state) do
    # Handle vote response message
    if vote == TPC.Network.VoteMessages.vote_commit() do
      IO.puts("Vote response was :ok, putting vote into votes map")
      new_votes = Map.put(votes, sender_pid, vote)
      if Map.size(new_votes) == Map.size(followers) do
        IO.puts("All votes are in, let's commit")
        # Commit on leader
        GenServer.cast(self(), {:commit, sender_pid, amount})
        # Commit on followers
        Enum.each(followers, fn {name, pid} ->
          GenServer.cast(pid, {:commit, sender_pid, amount})
        end)
      end
      {:noreply, {name, followers, new_votes}}
    else
      IO.puts("Vote response was not :ok, let's abort")
      {:noreply, {name, followers, votes}}
    end
  end

  # TODO: Abstract with :commit in follower
  @impl true
  def handle_cast({:commit, requester_pid, amount}, state) do
    IO.puts("Process #{inspect(self()) } is committing")
    # Log commit statement
    # Release locks
    # TODO: Do we send ack to coordinator?
    {:noreply, state}
  end

end
