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

  def peek_change(logs) do
    case logs do
      [{:change, tid, _} | _] ->
        {:found, tid}
      _ ->
        :not_found
    end
  end

  def find_outcome(logs, tid) do
    case logs do
      # Base case: we could not find a committed change corresponding to that transaction.
      [] ->
        :not_found
      # We found one that matches.
      [{:finalize, outcome, ^tid} | {:change, _, body}] ->
        # We know that after (so before in terms of time) there will be a change.
        # This is the change that we are interested in, as this is the last committed change.
        {:found, outcome, body}
      # We did not find a match, continue recursively.
      [_ | next] ->
        find_outcome(next, tid)
    end
  end

  def log_change(name, logs1, tid, body) do
    logs2 = [{:change, tid, body} | logs1]
    write(name, logs2)
    logs2
  end

  def log_commit(name, logs1, tid) do
    logs2 = [{:finalize, :commit, tid} | logs1]
    write(name, logs2)
    logs2
  end

  def log_abort(name, logs1, tid) do
    logs2 = [{:finalize, :abort, tid} | logs1]
    write(name, logs2)
    logs2
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

  def clean_slate() do
    File.rm_rf!(@logdir)
  end

  defp file_name(name) do
    File.mkdir_p!(@logdir)
    Path.join(@logdir, "#{name}.logb")
  end
end
