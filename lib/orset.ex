defmodule LCRDT.OrSet do
  @moduledoc """
  This represents an OR-Set CRDT.
  """
  use GenServer

  def start_link(name) do
    IO.puts("OrSet #{name} starting")
    GenServer.start_link(__MODULE__, name, name: name);
  end

  def init(_) do
    {:ok, {}}
  end

end
