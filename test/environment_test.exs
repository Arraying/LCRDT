defmodule LCRDT.EnvironmentTest do
  use ExUnit.Case
  alias LCRDT.Counter
  alias LCRDT.Environment
  alias LCRDT.OrSet
  doctest LCRDT.Environment

  setup do
    {:ok, _} = Application.ensure_all_started(:lcrdt)
    on_exit(fn ->
      Application.stop(:lcrdt)
      # So we don't get in the way of other test suites.
      System.delete_env("CRDT")
      System.delete_env("STOCK")
    end)
  end

  test "setting to counter works" do
    Environment.use_crdt(Counter)
    assert Environment.get_crdt() == Counter
  end

  test "setting to or-set works" do
    Environment.use_crdt(OrSet)
    assert Environment.get_crdt() == OrSet
  end

  test "setting stock works" do
    Environment.set_stock(19)
    assert Environment.get_stock() == 19
  end
end
