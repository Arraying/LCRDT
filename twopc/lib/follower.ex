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

end
