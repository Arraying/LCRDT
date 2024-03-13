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
          {i, _} when i > 0 ->
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

  def is_silent() do
    case System.fetch_env("NOLOG") do
      {:ok, value} ->
        String.downcase(value) == "true"
      _ ->
        false
    end
  end

  def set_silent(value) when is_boolean(value) do
    System.put_env("NOLOG", "#{value}")
  end

  def get_auto_allocation() do
    default = -1
    case System.fetch_env("AUTO") do
      {:ok, value} ->
        case Integer.parse(value) do
          {i, _} when i > 0 ->
            i
          _ ->
            default
        end
      _ ->
        default
    end
  end

  def set_auto_allocation(value) when is_number(value) and (value > 0 or value == -1) do
    System.put_env("AUTO", "#{value}")
  end

end
