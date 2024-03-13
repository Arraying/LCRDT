defmodule Performance do
  def start_test(num_crdts \\ 3, num_processes_per_crdt \\ 50, num_iterations_per_process \\ 10000) do
    IO.puts("Starting CRDT test...")

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

    # Calculate and print the elapsed time for the whole test
    elapsed_test_time = (end_test_time - start_test_time) / 1_000_000  # Convert to milliseconds
    IO.puts("CRDT test completed.")
    IO.puts("Total Elapsed Time for the whole test: #{elapsed_test_time} milliseconds")
  end

  defp start_crdts(num_crdts) do
    Enum.map(1..num_crdts, fn index ->
      # Start a unique CRDT and return its pid
      {:ok, pid} = LCRDT.Counter.start_link(:"crdt_#{index}")
      pid
    end)
  end

  defp spawn_processes(crdt, num_processes, num_iterations) do
    Enum.each(1..num_processes, fn _ ->
      spawn(fn -> increment_counter(crdt, num_iterations) end)
    end)
  end

  defp increment_counter(crdt, num_iterations) do
    # Start the timer for this CRDT
    start_crdt_time = System.monotonic_time()

    Enum.each(1..num_iterations, fn _ ->
      # Increment the counter in the CRDT
      LCRDT.Counter.inc(crdt)
    end)

    # Stop the timer for this CRDT
    end_crdt_time = System.monotonic_time()

    # Calculate and print the elapsed time for this CRDT
    elapsed_crdt_time = (end_crdt_time - start_crdt_time) / 1_000_000  # Convert to milliseconds
    IO.puts("Finished incrementing counter in CRDT #{inspect crdt}. Elapsed Time: #{elapsed_crdt_time} milliseconds")
  end
end

# Start the test
Performance.start_test()
