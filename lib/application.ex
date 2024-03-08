defmodule LCRDT.Application do
  @moduledoc """
  This is the top level application for the LCRDT.
  This will spawn the CRDT and corresponding helper functionality.
  The start function is invoked automatically.
  """
  use Application

  def start(_, _) do
    crdt = case System.fetch_env("CRDT") do
      {:ok, "counter"} -> LCRDT.Counter
      {:ok, "orset"} -> LCRDT.OrSet
      _ -> LCRDT.Counter
    end
    LCRDT.Logging.clean_slate()
    LCRDT.Store.clean_slate()
    children = Enum.map(LCRDT.Network.all_nodes(), &(make_node(&1, crdt)))
    Supervisor.start_link(children, strategy: :one_for_all)
  end

  defp make_node(id, crdt) do
    %{
      id: {LCRDT.Node, id},
      start: {LCRDT.Node, :start_link, [crdt, id]},
      type: :supervisor
    }
  end
end
