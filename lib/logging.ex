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

  def find_vote(logs, tid) do
    case logs do
      # Base case: we found no change, so it must have been an abort.
      [] ->
        :abort
      [{:change, ^tid, _} | _] ->
        :ok
      [_ | next] ->
        find_vote(next, tid)
    end
  end

  def find_outcome(logs, tid) do
    case logs do
      # Base case: we could not find a committed change corresponding to that transaction.
      [] ->
        :not_found
      # We found one that matches.
      [{:finalize, outcome, ^tid} | _next] ->
        # We will find the body through the coordinator.
        {:found, outcome}
      # We did not find a match, continue recursively.
      [_ | next] ->
        find_outcome(next, tid)
    end
  end

  def run(logs, application_pid) do
    simulate(Enum.reverse(logs), application_pid)
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

  defp simulate(logs, application_pid) do
    case logs do
      # We have a change that was comitted.
      [{:change, _, body} | [{:finalize, :commit, _} | next]] ->
        GenServer.call(application_pid, {:replay, body}, :infinity)
        simulate(next, application_pid)
      # Uncommitted change
      [{:change, _, body}] ->
        # Deliver to the layer above.
        GenServer.call(application_pid, {:replay, body}, :infinity)
        :done
      # We have a change that was not committed or an abort.
      [_ | next] ->
        simulate(next, application_pid)
      # We have reached the end of the simulation.
      _ ->
        :done
    end
  end

  defp file_name(name) do
    File.mkdir_p!(@logdir)
    Path.join(@logdir, "#{name}.logb")
  end
end
