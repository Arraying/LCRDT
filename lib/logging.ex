defmodule LCRDT.Logging do
  @moduledoc """
  Represents a wrapper around logging functions.

  The log is a list of operations where the front indicates latest operation.
  This log is not in human readable format.

  Types of log messages:
  - {:change, tid, body}
  - {:finalize, :commit, tid}
  - {:finalize, :abort, tid}
  """
  @logdir "logs"

  def has_uncommitted(logs) do
    case logs do
      [{:change, _, _} | _] -> true
      _ -> false
    end
  end

  def read(name) do
    case File.read(file_name(name)) do
      {:ok, bytes} -> :erlang.binary_to_term(bytes)
      {:error, _} -> []
    end
  end

  def write(name, logs) do
    bytes = :erlang.term_to_binary(logs)
    File.write!(file_name(name), bytes)
  end

  defp file_name(name) do
    File.mkdir_p!(@logdir)
    Path.join(@logdir, "#{name}.logb")
  end
end
