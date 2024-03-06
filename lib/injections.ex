defmodule LCRDT.Injections do
  import Bitwise

  def union(original, new), do: original ||| new
  def activated(crashpoints, test), do: (crashpoints &&& test) != 0
  def inject(pid, crashpoints, lagpoints), do: GenServer.cast(pid, {:inject_fault, crashpoints, lagpoints})
  def neutral(), do: 0
  defmodule Crash do
    def before_prepare(), do: 1
    def during_prepare(), do: 1 <<< 1
    def after_prepare(), do: 1 <<< 2
  end
  defmodule Lag do
    # TODO: Implement lagpoints.
  end
end