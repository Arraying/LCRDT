defmodule TPC.Coordinator do
  use GenServer

  # State = {name, followers, votes, acks}

  def start_link(name) do
    IO.puts("Coordinator #{name} starting")
    GenServer.start_link(__MODULE__, name, name: name);
  end

  def print_followers(pid) do
    GenServer.call(pid, :print_followers)
  end

  @impl true
  def init(name) do
    {:ok, {name, Map.new()}}
  end

  @impl true
  def handle_cast({:new_follower, new_follower}, {name, followers} = state) do
    new_follower_pid = Process.whereis(new_follower)
    {:noreply, {name, Map.put(followers, new_follower, new_follower_pid)}}
  end

  @impl true
  def handle_call(:print_followers, _from, {name, followers}) do
    Enum.each(followers, fn {name, pid} ->
      IO.puts("Follower #{inspect(name)} with PID #{inspect(pid)}")
    end)

    {:reply, :ok, {name, followers}}
  end

  @impl true
  def handle_cast({:prepare_request, _coordinator_pid}, state) do
    # Handle prepare request message
    {:noreply, state}
  end

  @impl true
  def handle_cast({:vote_response, _pid, _vote}, state) do
    # Handle vote response
    {:noreply, state}
  end

  def send_prepare_requests(coordinator_pid, followers) do
    _prepare_request = TPC.Network.Messages.prepare_request()
    all_followers = [:coordinator | followers] # Include coordinator itself
    Enum.each(all_followers, fn follower_name ->
      pid =
        case follower_name do
          :coordinator -> coordinator_pid
          _ -> Process.whereis(follower_name)
        end
      if pid == coordinator_pid do
        IO.puts("Sending prepare request to itself (coordinator) with PID #{inspect(pid)}")
      else
        IO.puts("Sending prepare request to follower #{follower_name} with PID #{inspect(pid)}")
      end
      GenServer.cast(pid, {:prepare_request, coordinator_pid})
    end)
  end

end
