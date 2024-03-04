defmodule TPC.Follower do
  use GenServer

  def start_link(name) do
    IO.puts("Follower #{name} starting")
    GenServer.start_link(__MODULE__, name, name: name);
  end

  @impl true
  def init(coordinator_pid) do
    IO.puts("Just started follower with coordinator reference: #{inspect(coordinator_pid)}")
    # State = {coordinator pid}
    {:ok, {coordinator_pid}}
  end

  @impl true
  def handle_cast({:prepare_request, requester_pid, amount}, {coordinator_pid} = state) do
    # TODO: check if it's safe to commit
    # Make call to CRDT
    condition = true
    if condition do
      # Send ok to coordinator
      vote = TPC.Network.VoteMessages.vote_commit()
      GenServer.cast(coordinator_pid, {:vote_response, self(), TPC.Network.VoteMessages.vote_commit(), amount})
    else
      # Send not ok to coordinator
      GenServer.cast(coordinator_pid, {:vote_response, self(), TPC.Network.VoteMessages.vote_abort(), amount})
    end

    IO.puts("Follower #{inspect(self())} sent a vote response to coordinator #{inspect(coordinator_pid)}")
    {:noreply, state}
  end

  @impl true
  def handle_cast({:commit, requester_pid, amount}, state) do
    IO.puts("Process #{inspect(self()) } is committing")
    # Log commit statement
    # Release locks
    # TODO: Do we send ack to coordinator?
    {:noreply, state}
  end

end
