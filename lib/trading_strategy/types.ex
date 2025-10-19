defmodule TradingStrategy.Types do
  @moduledoc """
  Type definitions and helper functions for the TradingStrategy library.

  This module provides the core OHLCV (Open, High, Low, Close, Volume) type
  definition and utility functions for working with market data using Decimal
  precision.

  ## Why Decimal?

  Financial calculations require exact precision to avoid accumulating rounding
  errors. Using Decimal ensures that:

  - Price values are represented exactly (e.g., 0.1 is exactly 0.1)
  - No floating-point rounding errors in calculations
  - Backtesting results are reproducible and accurate
  - Meets financial industry standards for precision

  ## OHLCV Structure

  All market data in TradingStrategy uses the following structure:

      %{
        open: Decimal.t(),      # Opening price
        high: Decimal.t(),      # Highest price
        low: Decimal.t(),       # Lowest price
        close: Decimal.t(),     # Closing price
        volume: integer(),      # Trading volume
        timestamp: DateTime.t() # Candle timestamp
      }

  ## Creating OHLCV Data

  Use the helper functions to create properly formatted candle data:

      # Recommended: Use new_ohlcv/6
      candle = Types.new_ohlcv(100, 105, 95, 102, 1000, ~U[2025-01-01 00:00:00Z])

      # Or convert existing numeric data
      old_candle = %{open: 100, high: 105, low: 95, close: 102, volume: 1000, timestamp: ~U[...]}
      candle = Types.normalize_ohlcv(old_candle)

  ## Integration

  This module works seamlessly with:

  - `TradingStrategy.Indicators` - Returns Decimal values
  - `TradingStrategy.Patterns` - Uses Decimal for pattern detection
  - `TradingStrategy.Backtest` - Processes Decimal market data
  - `TradingStrategy.Engine` - Handles Decimal real-time data
  """

  @typedoc """
  OHLCV (Open, High, Low, Close, Volume) candle data structure.

  All price values (open, high, low, close) use Decimal for precision.
  Volume is a non-negative integer.
  Timestamp is a DateTime struct.
  """
  @type ohlcv :: %{
          open: Decimal.t(),
          high: Decimal.t(),
          low: Decimal.t(),
          close: Decimal.t(),
          volume: non_neg_integer(),
          timestamp: DateTime.t()
        }

  @doc """
  Creates a new OHLCV candle with Decimal values.

  Accepts numeric or Decimal values for prices and converts them to Decimal.

  ## Examples

      iex> TradingStrategy.Types.new_ohlcv(100, 105, 95, 102, 1000)
      %{
        open: Decimal.new("100"),
        high: Decimal.new("105"),
        low: Decimal.new("95"),
        close: Decimal.new("102"),
        volume: 1000,
        timestamp: ~U[...]
      }
  """
  def new_ohlcv(open, high, low, close, volume, timestamp \\ DateTime.utc_now()) do
    %{
      open: to_decimal(open),
      high: to_decimal(high),
      low: to_decimal(low),
      close: to_decimal(close),
      volume: volume,
      timestamp: timestamp
    }
  end

  @doc """
  Converts a value to Decimal.

  ## Examples

      iex> TradingStrategy.Types.to_decimal(100)
      Decimal.new("100")

      iex> TradingStrategy.Types.to_decimal(100.5)
      Decimal.new("100.5")

      iex> TradingStrategy.Types.to_decimal(Decimal.new("50"))
      Decimal.new("50")
  """
  def to_decimal(%Decimal{} = value), do: value
  def to_decimal(value) when is_integer(value), do: Decimal.new(value)
  def to_decimal(value) when is_float(value), do: Decimal.from_float(value)
  def to_decimal(value) when is_binary(value), do: Decimal.new(value)

  @doc """
  Validates that a map contains all required OHLCV fields.

  ## Examples

      iex> candle = %{
      ...>   open: Decimal.new("100"),
      ...>   high: Decimal.new("105"),
      ...>   low: Decimal.new("95"),
      ...>   close: Decimal.new("102"),
      ...>   volume: 1000,
      ...>   timestamp: ~U[2025-01-01 00:00:00Z]
      ...> }
      iex> TradingStrategy.Types.valid_ohlcv?(candle)
      true

      iex> TradingStrategy.Types.valid_ohlcv?(%{})
      false
  """
  def valid_ohlcv?(candle) when is_map(candle) do
    required_keys = [:open, :high, :low, :close, :volume, :timestamp]
    Enum.all?(required_keys, &Map.has_key?(candle, &1))
  end

  def valid_ohlcv?(_), do: false

  @doc """
  Converts numeric OHLCV values to Decimal OHLCV.

  Useful for converting test data or legacy data to the correct format.

  ## Examples

      iex> candle = %{open: 100, high: 105, low: 95, close: 102, volume: 1000, timestamp: ~U[2025-01-01 00:00:00Z]}
      iex> TradingStrategy.Types.normalize_ohlcv(candle)
      %{
        open: Decimal.new("100"),
        high: Decimal.new("105"),
        low: Decimal.new("95"),
        close: Decimal.new("102"),
        volume: 1000,
        timestamp: ~U[2025-01-01 00:00:00Z]
      }
  """
  def normalize_ohlcv(%{} = candle) do
    %{
      open: to_decimal(candle.open),
      high: to_decimal(candle.high),
      low: to_decimal(candle.low),
      close: to_decimal(candle.close),
      volume: candle.volume,
      timestamp: candle.timestamp
    }
  end

  @doc """
  Normalizes a list of OHLCV candles.
  """
  def normalize_ohlcv_list(candles) when is_list(candles) do
    Enum.map(candles, &normalize_ohlcv/1)
  end
end
