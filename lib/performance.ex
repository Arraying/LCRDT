defmodule LCRDT.Performance do

  defmodule Timer do
    use GenServer

    def init(amount) do
      {:ok, {System.monotonic_time(), amount, 0, :nil}}
    end

    def handle_call(:wait, from, {start_test_time, amount, viols, _}) do
      {:noreply, {start_test_time, amount, viols, from}}
    end

    def handle_cast({:done, n}, {start_test_time, amount, viols, from}) do
      new_amount = amount - 1
      new_viols = viols + n
      if new_amount == 0 do
        time_elapsed = (System.monotonic_time() - start_test_time) / 1_000_000
        GenServer.reply(from, {time_elapsed, new_viols})
      end
      {:noreply, {start_test_time, new_amount, new_viols, from}}
    end
  end
end
