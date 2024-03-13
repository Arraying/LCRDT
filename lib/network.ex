defmodule LCRDT.Network do
  def all_nodes(), do: [:foo, :bar, :baz]
  def node_to_crdt(node_name), do: :"#{node_name}_crdt"
  def node_to_tpc(node_name), do: :"#{node_name}_tpc"
  def coordinator(), do: :coordinator
  # defmodule Messages do
  #   def prepare_request(), do: :prepare_request
  #   def vote_response(), do: :vote_response
  # end
  # defmodule VoteMessages do
  #   def vote_commit(), do: :commit
  #   def vote_abort(), do: :abort
  # end

  def reliable_call(pid, request) do
    # Under some occasions (like gracefully stopping?) even :infinity will disconnect.
    # This is not great because we want to infinitely block.
    # So instead, we will just retry until it works out.
    try do
      GenServer.call(pid, request, :infinity)
    catch
      _ ->
        # We just sleep and retry later.
        # It's not perfect, but it'll work.
        :timer.sleep(100)
        reliable_call(pid, request)
    end
  end
end
