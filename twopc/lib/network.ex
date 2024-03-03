defmodule TPC.Network do
  def all_followers(), do: [:foo, :bar, :baz]
  def coordinator(), do: :coordinator
  defmodule Messages do
    def prepare_request(), do: :prepare_request
    def vote_response(), do: :vote_response
  end
end
