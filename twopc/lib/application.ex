defmodule TPC.Application do
  use Application

  def start(_start_type, _start_args) do
    # Start coordinator
    {:ok, coordinator_pid} = GenServer.start_link(TPC.Coordinator, :ok, name: TPC.Network.coordinator())
    IO.puts("Just started coordinator with PID: #{inspect(coordinator_pid)}")

    # Start followers
    TPC.Network.all_followers()
    |> Enum.each(fn follower ->
      {:ok, follower_pid} = GenServer.start_link(TPC.Follower, coordinator_pid, name: follower)
      IO.puts("Just started follower with PID: #{inspect(follower_pid)}")
      GenServer.cast(TPC.Network.coordinator(), {:new_follower, follower})
    end)

    # Trigger the voting phase by sending prepare requests to followers
    followers = TPC.Network.all_followers()
    TPC.Coordinator.send_prepare_requests(coordinator_pid, followers)
    IO.puts("Voting phase triggered. Prepare requests sent to followers.")

    {:ok, coordinator_pid}
  end

end
