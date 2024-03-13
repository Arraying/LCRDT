defmodule LCRDT.Environment do
  @moduledoc """
  Contains the configurable environment variable.
  """

  def get_crdt() do
    case System.fetch_env("CRDT") do
      {:ok, "counter"} ->
        LCRDT.Counter
      {:ok, "orset"} ->
        LCRDT.OrSet
      _ ->
        LCRDT.Counter
    end
  end

  def use_crdt(module) when is_atom(module) do
    name = case module do
      LCRDT.Counter ->
        "counter"
      LCRDT.OrSet ->
        "orset"
      _ ->
        "counter"
    end
    System.put_env("CRDT", name)
  end

  def get_stock() do
    default = 100
    case System.fetch_env("STOCK") do
      {:ok, value} ->
        case Integer.parse(value) do
          {i, _} ->
            i
          _ ->
            default
        end
      _ ->
        default
    end
  end

  def set_stock(stock) when is_integer(stock) and stock > 0 do
    System.put_env("STOCK", Integer.to_string(stock))
  end

end
