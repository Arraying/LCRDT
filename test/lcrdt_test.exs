defmodule LCRDTTest do
  use ExUnit.Case
  doctest LCRDT

  test "greets the world" do
    assert LCRDT.hello() == :world
  end
end
