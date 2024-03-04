defmodule TPC.Application do
  use Application

  def start(_start_type, _start_args) do
    # Start coordinator
    {:ok, coordinator_pid} = GenServer.start_link(TPC.Coordinator, :ok, name: TPC.Network.coordinator())
    IO.puts("Just started coordinator with PID: #{inspect(coordinator_pid)}")

    # Start followers
    follower_pids = TPC.Network.all_followers()
    |> Enum.map(fn follower ->
      {:ok, follower_pid} = GenServer.start_link(TPC.Follower, coordinator_pid, name: follower)
      IO.puts("Just started follower with PID: #{inspect(follower_pid)}")
      GenServer.cast(TPC.Network.coordinator(), {:new_follower, follower})
      follower_pid
    end)

    # TODO: Remove on merging
    # Trigger 2PC
    requester_pid = List.last(follower_pids)
    GenServer.cast(coordinator_pid, {:prepare, requester_pid, 1})
    IO.puts("Voting phase triggered. Prepare requests sent to followers.")

    {:ok, coordinator_pid}
  end

end
