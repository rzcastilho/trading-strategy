defmodule TradingStrategy.PaperTradingHelpers do
  @moduledoc """
  Helper functions for paper trading tests.

  Provides common fixtures, data generators, and mock implementations
  for testing paper trading functionality.
  """

  @doc """
  Generates a sample strategy definition for testing.
  """
  def sample_strategy(opts \\ []) do
    %{
      "name" => Keyword.get(opts, :name, "Test Strategy"),
      "indicators" =>
        Keyword.get(opts, :indicators, [
          %{"name" => "rsi_14", "type" => "rsi", "parameters" => %{"period" => 14}},
          %{"name" => "sma_50", "type" => "sma", "parameters" => %{"period" => 50}}
        ]),
      "entry_conditions" =>
        Keyword.get(opts, :entry_conditions, "rsi_14 < 30 AND close > sma_50"),
      "exit_conditions" => Keyword.get(opts, :exit_conditions, "rsi_14 > 70"),
      "stop_conditions" => Keyword.get(opts, :stop_conditions, "rsi_14 < 25")
    }
  end

  @doc """
  Generates a sample OHLCV bar for testing.
  """
  def sample_bar(opts \\ []) do
    timestamp = Keyword.get(opts, :timestamp, DateTime.utc_now())
    base_price = Keyword.get(opts, :base_price, 43000.0)

    %{
      timestamp: timestamp,
      open: Decimal.from_float(base_price),
      high: Decimal.from_float(base_price * 1.01),
      low: Decimal.from_float(base_price * 0.99),
      close: Decimal.from_float(base_price),
      volume: Decimal.from_float(1000.0),
      symbol: Keyword.get(opts, :symbol, "BTC/USD")
    }
  end

  @doc """
  Generates sample indicator values for testing.
  """
  def sample_indicator_values(opts \\ []) do
    %{
      "rsi_14" => Keyword.get(opts, :rsi, 50.0),
      "sma_50" => Keyword.get(opts, :sma, 42000.0)
    }
  end

  @doc """
  Generates a sample ticker update for testing.
  """
  def sample_ticker(symbol, price \\ "43250.50") do
    %{
      symbol: symbol,
      price: price,
      volume: "1234.56",
      timestamp: DateTime.utc_now(),
      bid: to_string(String.to_float(price) - 0.5),
      ask: to_string(String.to_float(price) + 0.5)
    }
  end

  @doc """
  Generates a sample trade update for testing.
  """
  def sample_trade(symbol, opts \\ []) do
    %{
      trade_id: Keyword.get(opts, :trade_id, "#{System.unique_integer([:positive])}"),
      symbol: symbol,
      price: Keyword.get(opts, :price, "43250.50"),
      quantity: Keyword.get(opts, :quantity, "0.5"),
      timestamp: Keyword.get(opts, :timestamp, DateTime.utc_now()),
      side: Keyword.get(opts, :side, :buy)
    }
  end

  @doc """
  Generates a series of sample bars for backtesting.
  """
  def sample_bar_series(count, opts \\ []) do
    base_price = Keyword.get(opts, :base_price, 43000.0)
    start_time = Keyword.get(opts, :start_time, ~U[2025-12-04 00:00:00Z])
    interval_seconds = Keyword.get(opts, :interval_seconds, 3600)

    Enum.map(0..(count - 1), fn i ->
      timestamp = DateTime.add(start_time, i * interval_seconds, :second)
      price_variation = :rand.uniform(200) - 100

      %{
        timestamp: timestamp,
        open: Decimal.from_float(base_price + price_variation),
        high: Decimal.from_float(base_price + price_variation + 50),
        low: Decimal.from_float(base_price + price_variation - 50),
        close: Decimal.from_float(base_price + price_variation),
        volume: Decimal.from_float(1000.0 + :rand.uniform(500)),
        symbol: Keyword.get(opts, :symbol, "BTC/USD")
      }
    end)
  end

  @doc """
  Creates a position tracker with open positions for testing.
  """
  def tracker_with_positions(initial_capital \\ 10000.0, positions \\ []) do
    alias TradingStrategy.PaperTrading.PositionTracker

    tracker = PositionTracker.init(initial_capital)

    Enum.reduce(positions, tracker, fn position_spec, acc_tracker ->
      symbol = Keyword.fetch!(position_spec, :symbol)
      side = Keyword.fetch!(position_spec, :side)
      entry_price = Keyword.fetch!(position_spec, :entry_price)
      timestamp = Keyword.get(position_spec, :timestamp, DateTime.utc_now())
      quantity = Keyword.get(position_spec, :quantity)

      opts = if quantity, do: [quantity: quantity], else: []

      case PositionTracker.open_position(acc_tracker, symbol, side, entry_price, timestamp, opts) do
        {:ok, new_tracker, _position} -> new_tracker
        {:error, _reason} -> acc_tracker
      end
    end)
  end

  @doc """
  Waits for a message with timeout.
  """
  def wait_for_message(pattern, timeout \\ 1000) do
    receive do
      ^pattern -> :ok
    after
      timeout -> {:error, :timeout}
    end
  end

  @doc """
  Asserts that a value is within a delta of expected value.
  """
  def assert_in_delta(value, expected, delta) do
    diff = abs(value - expected)

    if diff > delta do
      raise ExUnit.AssertionError,
        message: "Expected #{inspect(value)} to be within #{delta} of #{inspect(expected)}"
    end

    true
  end
end
