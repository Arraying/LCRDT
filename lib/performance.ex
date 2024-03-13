defmodule Performance do
  # Function to run tests with different parameter combinations
  def run_tests(test_params_list) do
    Enum.map(test_params_list, &start_test/1)
  end

  # Function to start the test with given parameters
  def start_test(%{num_crdts: num_crdts, num_processes_per_crdt: num_processes_per_crdt, num_iterations_per_process: num_iterations_per_process}) do
    # Start the timer for the whole test
    start_test_time = System.monotonic_time()

    # Start CRDTs
    crdts = start_crdts(num_crdts)

    # Spawn processes to increment counters in each CRDT
    Enum.each(crdts, fn crdt ->
      spawn_processes(crdt, num_processes_per_crdt, num_iterations_per_process)
    end)

    # Wait for all processes to finish
    :timer.sleep(5000)

    # Stop the timer for the whole test
    end_test_time = System.monotonic_time()

    # Calculate the elapsed time for the whole test
    elapsed_test_time = (end_test_time - start_test_time) / 1_000_000  # Convert to milliseconds

    # Return the total elapsed time for the whole test
    elapsed_test_time
  end

  # Function to start CRDTs
  defp start_crdts(num_crdts) do
    Enum.map(1..num_crdts, &start_unique_crdt/1)
  end

  # Function to start a unique CRDT
  defp start_unique_crdt(index) do
    case LCRDT.Counter.start_link(:"crdt_#{index}") do
      {:ok, pid} -> pid
      {:error, {:already_started, pid}} -> pid
      error -> raise error
    end
  end

  # Function to spawn processes for incrementing counters
  defp spawn_processes(crdt, num_processes, num_iterations) do
    Enum.each(1..num_processes, fn _ ->
      spawn(fn -> increment_counter(crdt, num_iterations) end)
    end)
  end

  # Function to increment the counter in a CRDT
  defp increment_counter(crdt, num_iterations) do
    # Start the timer for this CRDT
    start_crdt_time = System.monotonic_time()

    Enum.each(1..num_iterations, fn _ ->
      # Increment the counter in the CRDT
      LCRDT.Counter.inc(crdt)
    end)

    # Stop the timer for this CRDT
    end_crdt_time = System.monotonic_time()

    # Calculate the elapsed time for this CRDT
    elapsed_crdt_time = (end_crdt_time - start_crdt_time) / 1_000_000  # Convert to milliseconds

    # Return the elapsed time for this CRDT
    elapsed_crdt_time
  end
end

# Define a list of parameter combinations to test
test_params_list = [
  %{num_crdts: 3, num_processes_per_crdt: 50, num_iterations_per_process: 10000},
  %{num_crdts: 5, num_processes_per_crdt: 10000, num_iterations_per_process: 20000},
  %{num_crdts: 10, num_processes_per_crdt: 20000, num_iterations_per_process: 50000}
]

# Run the tests with different parameter combinations
results = Performance.run_tests(test_params_list)

# Print the results
Enum.each(results, fn result ->
  IO.puts("Total Elapsed Time for the whole test: #{result} milliseconds")
end)
