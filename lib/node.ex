defmodule LCRDT.Node do
  @moduledoc """
  This represents a node.
  A node is a supervisor of two processes:
  1. The CRDT that is running.
  2. Its underlying 2PC instance.
  """

  def start_link(crdt_type, id) do
    IO.puts("#{__MODULE__}/#{id}: Starting")
    crdt_name = LCRDT.Network.node_to_crdt(id)
    tpc_name = LCRDT.Network.node_to_tpc(id)
    children = [
      Supervisor.child_spec({crdt_type, crdt_name}, id: crdt_name),
      Supervisor.child_spec({LCRDT.Participant, {get_name(id, tpc_name), crdt_name}}, id: tpc_name)
    ]
    Supervisor.start_link(children, strategy: :one_for_all)
  end

  defp get_name(id, tpc_name), do: (if id == :foo, do: LCRDT.Network.coordinator(), else: tpc_name)
end
