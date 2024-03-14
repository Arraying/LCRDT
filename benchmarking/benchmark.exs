defmodule LCRDT.Benchmark do
  use ExUnit.Case
  alias LCRDT.Counter

  @moduletag timeout: :infinity

  setup do
    LCRDT.Environment.set_sync_interval(20_000)
    LCRDT.Environment.set_stock(10_000_000)
    LCRDT.Environment.use_crdt(Counter)
    LCRDT.Environment.set_silent(true)
    {:ok, _} = Application.ensure_all_started(:lcrdt)
    on_exit(fn ->
      Application.stop(:lcrdt)
      LCRDT.Environment.set_auto_allocation(-1)
    end)
  end

  test "1 alloc" do
    lag_nodes()
    LCRDT.Environment.set_auto_allocation(1)
    run_test(1, 100, 10)
  end

  test "10 alloc" do
    lag_nodes()
    LCRDT.Environment.set_auto_allocation(10)
    run_test(10, 100, 10)
  end

  test "100 alloc" do
    lag_nodes()
    LCRDT.Environment.set_auto_allocation(100)
    run_test(100, 100, 10)
  end

  test "500 alloc" do
    lag_nodes()
    LCRDT.Environment.set_auto_allocation(500)
    run_test(500, 100, 10)
  end

  test "1000 alloc" do
    lag_nodes()
    LCRDT.Environment.set_auto_allocation(1000)
    run_test(1000, 100, 10)
  end

  defp run_test(initial_allocation, num_workers, num_requests_per_worker) do
    num_crdts = length(LCRDT.Network.all_nodes())
    total = num_crdts * num_workers
    {:ok, _ } = GenServer.start_link(LCRDT.Performance.Timer, total, name: :sam)
    Enum.each(get_nodes(), fn crdts ->
      Counter.request_leases(crdts, initial_allocation)
    end)
    Enum.each(get_nodes(), fn crdts ->
      Enum.each(1..num_workers, fn _ ->
        spawn(fn -> worker(crdts, num_requests_per_worker) end)
      end)
    end)
    {time, viols} = GenServer.call(:sam, :wait, :infinity)
    IO.puts("Stats for #{initial_allocation} @ #{num_workers} @ #{num_requests_per_worker}")
    IO.puts("Total time (ms): #{time}")
    IO.puts("Total lease violations: #{viols}")
  end

  defp worker(crdts, n) do
    # We also want to count how many lease violations we hit.
    viols = crawl(crdts, n, 0)
    GenServer.cast(:sam, {:done, viols})
  end

  defp crawl(target, left, viols) do
    unless left == 0 do
      case Counter.inc(target) do
        :inc ->
          crawl(target, left - 1, viols)
        :lease_violation ->
          crawl(target, left, viols + 1)
      end
    else
      viols
    end
  end

  defp lag_nodes do
    tpcs = Enum.map(LCRDT.Network.all_nodes, &(LCRDT.Network.node_to_tpc(&1)))
    Enum.each(tpcs, fn tpc ->
      name = if tpc == :foo_tpc, do: :coordinator, else: tpc
      LCRDT.Injections.inject(name, LCRDT.Injections.neutral(), LCRDT.Injections.Lag.finalize())
    end)
  end

  defp get_nodes do
    Enum.map(LCRDT.Network.all_nodes(), fn crdt ->
      LCRDT.Network.node_to_crdt(crdt)
    end)
  end
end
