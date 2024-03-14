defmodule LCRDT.Injections do
  import Bitwise

  def union(original, new), do: original ||| new
  def activated(crashpoints, test), do: (crashpoints &&& test) != 0
  def inject(pid, crashpoints, lagpoints), do: GenServer.cast(pid, {:inject_fault, crashpoints, lagpoints})
  def neutral(), do: 0
  defmodule Crash do
    # Follower crashpoints.
    def before_prepare(), do: 1
    def during_prepare(), do: 1 <<< 1
    def after_prepare(), do: 1 <<< 2
    # Coordinator crashpoints.
    def before_prepare_request(), do: 1 <<< 3
    def after_prepare_request(), do: 1 <<< 4
    def before_finalize(), do: 1 <<< 5
  end
  defmodule Lag do
    def finalize(), do: 1
  end
end
