defmodule LCRDT.Store do
  @moduledoc """
  Wrapper for storing and reading CRDT state.
  """

 @storedir "crdt_store"

  def read(name) do
    case File.read(file_name(name)) do
      {:ok, bytes} -> :erlang.binary_to_term(bytes)
      {:error, _} -> Map.new()
    end
  end

  def write(name, state) do
    bytes = :erlang.term_to_binary(state)
    File.write!(file_name(name), bytes)
  end

  def clean_slate() do
    File.rm_rf!(@storedir)
  end

  defp file_name(name) do
    File.mkdir_p!(@storedir)
    Path.join(@storedir, "#{name}.storeb")
  end

end
