defmodule LCRDT.Application do
  @moduledoc """
  This is the top level application for the LCRDT.
  This will spawn the CRDT and corresponding helper functionality.
  The start function is invoked automatically.
  """
  use Application

  def start(_, _) do
    children = Enum.map(LCRDT.Network.all_nodes(), &(Supervisor.child_spec({LCRDT.Counter, &1}, id: &1)))
    Supervisor.start_link(children, strategy: :one_for_all)
  end
end
