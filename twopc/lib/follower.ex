defmodule TPC.Follower do
  use GenServer

  def start_link(name) do
    IO.puts("Follower #{name} starting")
    GenServer.start_link(__MODULE__, name, name: name);
  end

  @impl true
  def init(coordinator_pid) do
    IO.puts("Just started follower with coordinator reference: #{inspect(coordinator_pid)}")
    {:ok, coordinator_pid}
  end

  @impl true
  def handle_cast({:prepare_request, coordinator_pid}, state) do
    vote = :ok
    GenServer.cast(coordinator_pid, {:vote_response, self(), vote})
    IO.puts("Follower #{inspect(self())} sent a vote response to coordinator #{inspect(coordinator_pid)}")
    {:noreply, state}
  end

end
