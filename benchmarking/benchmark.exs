defmodule LCRDT.Benchmark do
  use ExUnit.Case
  alias LCRDT.Counter

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

  # test "Ist mir scheiss egal, wir testen nur counter" do


  #   LCRDT.Environment.set_auto_allocation(-1)
  #   Enum.each(get_nodes(), fn crdts ->
  #     Counter.request_leases(crdts, 1_500_000)
  #   end)

  #   :timer.sleep(5000)
  #   run_test(100, 1000)
  # end

  test "Wir testen nur counter 2" do


    LCRDT.Environment.set_auto_allocation(2000)

    run_test(100, 1000)
  end

  defp run_test(num_workers, num_requests_per_worker) do
    num_crdts = length(LCRDT.Network.all_nodes())
    total = num_crdts * num_workers
    {:ok, _ } = GenServer.start_link(LCRDT.Performance.Timer, total, name: :sam)

    Enum.each(get_nodes(), fn crdts ->

      Enum.each(1..num_workers, fn _ ->
        spawn(fn -> worker(crdts, num_requests_per_worker) end)
      end)
    end)
    GenServer.call(:sam, :wait, :infinity)
  end

  defp worker(crdts, n) do
    Enum.each(1..n, fn _ ->
      :inc = Counter.inc(crdts)
    end)
    GenServer.cast(:sam, :done)
  end

  defp get_nodes do
    Enum.map(LCRDT.Network.all_nodes(), fn crdt ->
      LCRDT.Network.node_to_crdt(crdt)
    end)
  end
end
