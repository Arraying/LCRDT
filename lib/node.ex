defmodule LCRDT.Node do
  @moduledoc """
  This represents a node.
  A node is a supervisor of two processes:
  1. The CRDT that is running.
  2. Its underlying 2PC instance.
  """

  def start_link(crdt_type, id) do
    IO.puts("#{__MODULE__}/#{id}: Starting")
    crdt_name = :"#{id}_crdt"
    _tpc_name = :"#{id}_tpc"
    children = [
      Supervisor.child_spec({crdt_type, crdt_name}, id: crdt_name)
    ]
    Supervisor.start_link(children, strategy: :one_for_all)
  end
end
