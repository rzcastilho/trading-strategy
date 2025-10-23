defmodule TradingStrategy.DecimalHelpers do
  @moduledoc """
  Shared utilities for ensuring Decimal precision throughout the library.

  This module provides helper functions to convert various numeric types
  to Decimal, ensuring exact precision for all financial calculations.

  ## Usage

      iex> DecimalHelpers.ensure_decimal(42)
      #Decimal<42>

      iex> DecimalHelpers.ensure_decimal(3.14)
      #Decimal<3.14>

      iex> DecimalHelpers.ensure_decimal_components(%{upper: 100.5, lower: 95.2})
      %{upper: #Decimal<100.5>, lower: #Decimal<95.2>}
  """

  @doc """
  Ensures a value is converted to Decimal for precision.

  Handles various input types:
  - `Decimal.t()` - Returns as-is
  - `integer()` - Converts via `Decimal.new/1`
  - `float()` - Converts via `Decimal.from_float/1`
  - `binary()` - Converts via `Decimal.new/1`
  - Invalid input - Returns `nil`

  ## Examples

      iex> ensure_decimal(Decimal.new(42))
      #Decimal<42>

      iex> ensure_decimal(42)
      #Decimal<42>

      iex> ensure_decimal(3.14)
      #Decimal<3.14>

      iex> ensure_decimal("99.99")
      #Decimal<99.99>

      iex> ensure_decimal(:invalid)
      nil
  """
  def ensure_decimal(%Decimal{} = value), do: value

  def ensure_decimal(value) when is_integer(value) do
    Decimal.new(value)
  rescue
    _ -> nil
  end

  def ensure_decimal(value) when is_float(value) do
    Decimal.from_float(value)
  rescue
    _ -> nil
  end

  def ensure_decimal(value) when is_binary(value) do
    Decimal.new(value)
  rescue
    _ -> nil
  end

  def ensure_decimal(_), do: nil

  @doc """
  Ensures all values in a map are converted to Decimal.

  Takes a map and converts each value to Decimal using `ensure_decimal/1`.
  Useful for multi-value indicators that return component maps.

  ## Examples

      iex> ensure_decimal_components(%{upper: 100, middle: 95, lower: 90})
      %{upper: #Decimal<100>, middle: #Decimal<95>, lower: #Decimal<90>}

      iex> ensure_decimal_components(%{value: 42.5})
      %{value: #Decimal<42.5>}
  """
  def ensure_decimal_components(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {k, ensure_decimal(v)} end)
  end
end
