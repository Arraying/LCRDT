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

end
