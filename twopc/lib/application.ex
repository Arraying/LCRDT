defmodule TPC.Application do
  use Application

  def start(_start_type, _start_args) do
    # Start coordinator + followers
    children = Enum.map(TPC.Network.all_followers(), &(Supervisor.child_spec({TPC.Participant, &1}, id: &1)))
    leader_children = [{TPC.Participant, TPC.Network.coordinator()} | children]
    random_var = Supervisor.start_link(leader_children, strategy: :one_for_all)

    # Add followers to coordinator's state
    TPC.Network.all_followers()
    |> Enum.each(fn follower_name ->
      GenServer.cast(TPC.Network.coordinator(), {:new_follower, follower_name, follower_name})
    end)

    # TODO: Remove on merging
    # Random test
    # TPC.Participant.allocate(:foo, 10)

    random_var
  end

end
