defmodule TradingStrategy.TestHelpers do
  @moduledoc """
  Shared test helpers, fixtures, and utilities for testing the trading strategy library.
  """

  import ExUnit.Assertions

  alias TradingStrategy.{Definition, Signal, Position, Types}

  @doc """
  Generates sample market data for testing.

  ## Options

    * `:count` - Number of candles to generate (default: 100)
    * `:trend` - Trend direction: :up, :down, or :sideways (default: :up)
    * `:volatility` - Volatility level: :low, :medium, :high (default: :medium)
  """
  def generate_market_data(opts \\ []) do
    count = Keyword.get(opts, :count, 100)
    trend = Keyword.get(opts, :trend, :up)
    volatility = Keyword.get(opts, :volatility, :medium)

    base_price = 100.0
    volatility_factor = volatility_multiplier(volatility)
    trend_factor = trend_multiplier(trend)

    Enum.reduce(1..count, [], fn i, acc ->
      # Get previous close as float for calculations
      prev_close_float =
        if acc == [] do
          base_price
        else
          List.first(acc).close |> Decimal.to_float()
        end

      # Add trend and random noise
      trend_change = trend_factor
      noise = (:rand.uniform() - 0.5) * 2 * volatility_factor
      close = prev_close_float * (1 + trend_change + noise)

      # Generate OHLC
      range = close * volatility_factor
      high = close + :rand.uniform() * range
      low = close - :rand.uniform() * range
      open = low + :rand.uniform() * (high - low)

      candle = %{
        open: Decimal.from_float(Float.round(open, 2)),
        high: Decimal.from_float(Float.round(high, 2)),
        low: Decimal.from_float(Float.round(low, 2)),
        close: Decimal.from_float(Float.round(close, 2)),
        volume: :rand.uniform(1000) + 500,
        timestamp: DateTime.add(~U[2025-01-01 00:00:00Z], i * 3600, :second)
      }

      [candle | acc]
    end)
    |> Enum.reverse()
  end

  defp volatility_multiplier(:low), do: 0.005
  defp volatility_multiplier(:medium), do: 0.02
  defp volatility_multiplier(:high), do: 0.05

  defp trend_multiplier(:up), do: 0.001
  defp trend_multiplier(:down), do: -0.001
  defp trend_multiplier(:sideways), do: 0.0

  @doc """
  Creates a simple test strategy definition.
  """
  def simple_strategy do
    Definition.new(:test_strategy, description: "Test strategy")
    |> Definition.add_indicator(:sma_fast, TestIndicator, period: 10)
    |> Definition.add_indicator(:sma_slow, TestIndicator, period: 30)
    |> Definition.add_entry_signal(:long, %{
      type: :when_all,
      conditions: [
        %{type: :cross_above, indicator1: :sma_fast, indicator2: :sma_slow}
      ]
    })
    |> Definition.add_exit_signal(%{
      type: :cross_below,
      indicator1: :sma_fast,
      indicator2: :sma_slow
    })
  end

  @doc """
  Creates sample candle data for pattern testing.
  """
  def hammer_pattern do
    # Hammer: small body at top, long lower shadow (2x body), little/no upper shadow
    # The last candle is the hammer pattern
    # body = |close - open| = |98 - 97| = 1
    # lower shadow = min(open, close) - low = 97 - 95 = 2 (2x body ✓)
    # upper shadow = high - max(open, close) = 98.2 - 98 = 0.2 (< 0.3 body ✓)
    [
      Types.new_ohlcv(100, 102, 99, 101, 1000, ~U[2025-01-01 00:00:00Z]),
      Types.new_ohlcv(101, 103, 100, 102, 1100, ~U[2025-01-01 01:00:00Z]),
      Types.new_ohlcv(97, 98.2, 95, 98, 1000, ~U[2025-01-01 02:00:00Z])
    ]
  end

  def bullish_engulfing_pattern do
    [
      Types.new_ohlcv(100, 101, 98, 99, 1000, ~U[2025-01-01 00:00:00Z]),
      Types.new_ohlcv(98, 105, 97, 104, 1500, ~U[2025-01-01 01:00:00Z])
    ]
  end

  def bearish_engulfing_pattern do
    [
      Types.new_ohlcv(100, 102, 99, 101, 1000, ~U[2025-01-01 00:00:00Z]),
      Types.new_ohlcv(102, 103, 96, 97, 1500, ~U[2025-01-01 01:00:00Z])
    ]
  end

  def doji_pattern do
    [
      Types.new_ohlcv(100, 105, 95, 100.5, 1000, ~U[2025-01-01 00:00:00Z])
    ]
  end

  def morning_star_pattern do
    # Morning star: bearish candle, small body star, bullish candle closing above midpoint
    [
      Types.new_ohlcv(102, 103, 98, 99, 1000, ~U[2025-01-01 00:00:00Z]),   # Bearish
      Types.new_ohlcv(99, 100, 98, 99.5, 800, ~U[2025-01-01 01:00:00Z]),   # Small star
      Types.new_ohlcv(100, 105, 99, 104, 1200, ~U[2025-01-01 02:00:00Z])   # Bullish, closes above midpoint (100.5)
    ]
  end

  def evening_star_pattern do
    # Evening star: bullish candle, small body star, bearish candle closing below midpoint
    [
      Types.new_ohlcv(100, 103, 99, 102, 1000, ~U[2025-01-01 00:00:00Z]),  # Bullish
      Types.new_ohlcv(101, 102, 100, 101.5, 800, ~U[2025-01-01 01:00:00Z]), # Small star
      Types.new_ohlcv(101, 102, 95, 96, 1200, ~U[2025-01-01 02:00:00Z])    # Bearish, closes below midpoint (101)
    ]
  end

  @doc """
  Creates a test signal.
  """
  def test_signal(opts \\ []) do
    Signal.new(
      Keyword.get(opts, :type, :entry),
      Keyword.get(opts, :direction, :long),
      Keyword.get(opts, :symbol, "TEST"),
      Keyword.get(opts, :price, 100.0),
      opts
    )
  end

  @doc """
  Creates a test position.
  """
  def test_position(opts \\ []) do
    signal = test_signal(opts)
    quantity = Keyword.get(opts, :quantity, 1.0)
    Position.open(signal, quantity, opts)
  end

  @doc """
  Asserts that a signal matches expected attributes.
  """
  def assert_signal(signal, expected) do
    if type = expected[:type], do: assert(signal.type == type)
    if direction = expected[:direction], do: assert(signal.direction == direction)
    if symbol = expected[:symbol], do: assert(signal.symbol == symbol)
    if price = expected[:price], do: assert(signal.price == price)
  end

  @doc """
  Asserts that a position matches expected attributes.
  """
  def assert_position(position, expected) do
    if status = expected[:status], do: assert(position.status == status)
    if direction = expected[:direction], do: assert(position.direction == direction)

    if entry_price = expected[:entry_price],
      do: assert(position.entry_price == entry_price)

    if exit_price = expected[:exit_price], do: assert(position.exit_price == exit_price)
  end

  @doc """
  Rounds a float to the specified number of decimal places.
  """
  def round_float(value, precision \\ 2) do
    Float.round(value, precision)
  end

  @doc """
  Asserts that two floats are approximately equal within a tolerance.
  """
  def assert_float_equal(actual, expected, tolerance \\ 0.01) do
    assert abs(actual - expected) < tolerance,
           "Expected #{expected}, got #{actual} (tolerance: #{tolerance})"
  end
end

defmodule TestIndicator do
  @moduledoc """
  Mock indicator module for testing with Decimal support.
  """

  def calculate(data, opts) do
    period = Keyword.get(opts, :period, 10)

    if length(data) < period do
      Decimal.new("0")
    else
      sum = data
      |> Enum.take(-period)
      |> Enum.reduce(Decimal.new("0"), &Decimal.add/2)

      Decimal.div(sum, Decimal.new(period))
    end
  end
end
