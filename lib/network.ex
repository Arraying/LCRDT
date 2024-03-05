defmodule LCRDT.Network do
  def all_nodes(), do: [:foo, :bar, :baz]
  def coordinator(), do: :coordinator
  defmodule Messages do
    def prepare_request(), do: :prepare_request
    def vote_response(), do: :vote_response
  end
  defmodule VoteMessages do
    def vote_commit(), do: :commit
    def vote_abort(), do: :abort
  end
end
