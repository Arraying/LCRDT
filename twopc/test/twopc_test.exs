defmodule TwopcTest do
  use ExUnit.Case
  doctest Twopc

  test "greets the world" do
    assert Twopc.hello() == :world
  end
end
