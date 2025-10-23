# Debug script for Bollinger Bands breakout strategy
# This script helps diagnose why the strategy might not be generating signals
#
# Run with: mix run examples/debug_bollinger_breakout.exs

alias TradingStrategy.{Types, Engine, Indicators}

defmodule DebugBollingerStrategy do
  use TradingStrategy.DSL

  defstrategy :bollinger_breakout do
    description "Bollinger Bands breakout with volume confirmation"

    # Define indicators
    indicator :bb, TradingIndicators.Volatility.BollingerBands, period: 20, deviation: 2, source: :close
    indicator :volume_sma, TradingIndicators.Trend.SMA, period: 20, source: :volume

    # Long entry signal (upper band breakout)
    entry_signal :long do
      when_all do
        indicator(:close) > indicator(:bb, :upper_band)
        indicator(:volume) > indicator(:volume_sma)
      end
    end

    # Short entry signal (lower band breakout)
    entry_signal :short do
      when_all do
        indicator(:close) < indicator(:bb, :lower_band)
        indicator(:volume) > indicator(:volume_sma)
      end
    end

    # Exit signal (return to middle band)
    exit_signal do
      when_any do
        # Long exit: price falls back to middle band
        when_all do
          cross_below(:close, indicator(:bb, :middle_band))
        end
        # Short exit: price rises back to middle band
        when_all do
          cross_above(:close, indicator(:bb, :middle_band))
        end
      end
    end
  end
end

IO.puts("\n=== Bollinger Bands Breakout Strategy Debugger ===\n")

# Step 1: Load the strategy
IO.puts("Step 1: Loading strategy...")
strategy = DebugBollingerStrategy.strategy_definition()
IO.puts("✓ Strategy loaded: #{strategy.name}")
IO.puts("  Indicators: #{inspect(Map.keys(strategy.indicators))}")
IO.puts("  Entry signals: #{length(strategy.entry_signals)}")
IO.puts("  Exit signals: #{length(strategy.exit_signals)}")

# Step 2: Generate test data with known characteristics
IO.puts("\nStep 2: Generating test market data...")

# Generate data that should trigger signals:
# - Establish bands with low volatility
# - Create SUSTAINED breakouts (price stays beyond bands) with high volume
generate_breakout_data = fn ->
  base_time = DateTime.utc_now()

  # First 20 candles: very tight sideways movement around 100 (low volatility to create tight bands)
  sideways = for i <- 0..19 do
    # Very small random movement (±0.3)
    noise = rem(i, 3) - 1  # -1, 0, or 1
    price = Decimal.new("100") |> Decimal.add(Decimal.new("#{noise * 0.3}"))
    Types.new_ohlcv(
      Decimal.sub(price, Decimal.new("0.15")),
      Decimal.add(price, Decimal.new("0.15")),
      Decimal.sub(price, Decimal.new("0.15")),
      price,
      10000,  # Consistent low volume
      DateTime.add(base_time, i * 86400, :second)
    )
  end

  # Next candle: Initial breakout above (gap up with volume)
  initial_breakout_up = [
    Types.new_ohlcv(
      Decimal.new("105"),
      Decimal.new("106"),
      Decimal.new("104.5"),
      Decimal.new("105.5"),  # Jump from ~100 to 105.5
      25000,  # High volume
      DateTime.add(base_time, 20 * 86400, :second)
    )
  ]

  # Next 5 candles: Price STAYS above upper band at elevated levels
  sustained_high = for i <- 21..25 do
    # Price stays in 105-107 range (will be above the original tight upper band)
    base_price = 105.5
    variation = rem(i, 3) * 0.5  # 0, 0.5, or 1.0
    price = Decimal.new("#{base_price + variation}")
    Types.new_ohlcv(
      Decimal.sub(price, Decimal.new("0.3")),
      Decimal.add(price, Decimal.new("0.4")),
      Decimal.sub(price, Decimal.new("0.4")),
      price,
      20000 + i * 100,  # Sustained high volume
      DateTime.add(base_time, i * 86400, :second)
    )
  end

  # Gradual return to normal
  consolidate = for i <- 26..30 do
    price = Decimal.new("#{106 - (i - 25) * 1.2}")  # Slowly back to ~100
    Types.new_ohlcv(
      Decimal.sub(price, Decimal.new("0.5")),
      Decimal.add(price, Decimal.new("0.5")),
      Decimal.sub(price, Decimal.new("0.5")),
      price,
      12000,
      DateTime.add(base_time, i * 86400, :second)
    )
  end

  # More sideways to re-establish tight bands
  more_sideways = for i <- 31..45 do
    noise = rem(i, 3) - 1
    price = Decimal.new("100") |> Decimal.add(Decimal.new("#{noise * 0.3}"))
    Types.new_ohlcv(
      Decimal.sub(price, Decimal.new("0.15")),
      Decimal.add(price, Decimal.new("0.15")),
      Decimal.sub(price, Decimal.new("0.15")),
      price,
      10000,
      DateTime.add(base_time, i * 86400, :second)
    )
  end

  # Initial breakout below (gap down with volume)
  initial_breakout_down = [
    Types.new_ohlcv(
      Decimal.new("94.5"),
      Decimal.new("95"),
      Decimal.new("94"),
      Decimal.new("94.5"),  # Drop from ~100 to 94.5
      25000,  # High volume
      DateTime.add(base_time, 46 * 86400, :second)
    )
  ]

  # Next 5 candles: Price STAYS below lower band at depressed levels
  sustained_low = for i <- 47..51 do
    # Price stays in 93-95 range (will be below the original tight lower band)
    base_price = 94.5
    variation = rem(i, 3) * -0.5  # 0, -0.5, or -1.0
    price = Decimal.new("#{base_price + variation}")
    Types.new_ohlcv(
      Decimal.sub(price, Decimal.new("0.4")),
      Decimal.add(price, Decimal.new("0.3")),
      Decimal.sub(price, Decimal.new("0.4")),
      price,
      20000 + i * 100,  # Sustained high volume
      DateTime.add(base_time, i * 86400, :second)
    )
  end

  # Final return to normal
  final_consolidate = for i <- 52..57 do
    price = Decimal.new("#{94 + (i - 51) * 1.0}")  # Back to ~100
    Types.new_ohlcv(
      Decimal.sub(price, Decimal.new("0.5")),
      Decimal.add(price, Decimal.new("0.5")),
      Decimal.sub(price, Decimal.new("0.5")),
      price,
      12000,
      DateTime.add(base_time, i * 86400, :second)
    )
  end

  sideways ++ initial_breakout_up ++ sustained_high ++ consolidate ++ more_sideways ++
    initial_breakout_down ++ sustained_low ++ final_consolidate
end

market_data = generate_breakout_data.()
IO.puts("✓ Generated #{length(market_data)} candles")
IO.puts("  Price range: #{Enum.map(market_data, & &1.close) |> Enum.min()} to #{Enum.map(market_data, & &1.close) |> Enum.max()}")
IO.puts("  Volume range: #{Enum.map(market_data, & &1.volume) |> Enum.min()} to #{Enum.map(market_data, & &1.volume) |> Enum.max()}")

# Step 3: Calculate indicators manually to verify they work
IO.puts("\nStep 3: Testing indicator calculations...")

# Test with first 25 candles (enough for 20-period BB)
test_data = Enum.take(market_data, 25)
indicator_config = strategy.indicators[:bb]

IO.puts("  Testing BollingerBands indicator...")
IO.puts("    Module: #{inspect(indicator_config.module)}")
IO.puts("    Params: #{inspect(indicator_config.params)}")

# Validate parameters
case Indicators.validate_indicator_params(indicator_config.module, indicator_config.params) do
  {:ok, :valid} ->
    IO.puts("    ✓ Parameters valid")
  {:error, reason} ->
    IO.puts("    ✗ Parameter validation failed: #{inspect(reason)}")
end

# Check data sufficiency
case Indicators.check_sufficient_data(indicator_config.module, test_data, indicator_config.params) do
  :ok ->
    IO.puts("    ✓ Sufficient data (#{length(test_data)} candles)")
  :insufficient_data ->
    IO.puts("    ✗ Insufficient data (need more than #{length(test_data)} candles)")
end

# Calculate the indicator
bb_value = Indicators.calculate_indicator(indicator_config, test_data)
IO.puts("    Result: #{inspect(bb_value, pretty: true)}")

case bb_value do
  nil ->
    IO.puts("    ✗ Indicator returned nil - calculation failed!")
  %{upper_band: _, middle_band: _, lower_band: _} = bands ->
    IO.puts("    ✓ Multi-value indicator returned correctly")
    IO.puts("      Upper band: #{bands.upper_band}")
    IO.puts("      Middle band: #{bands.middle_band}")
    IO.puts("      Lower band: #{bands.lower_band}")
  other ->
    IO.puts("    ⚠ Unexpected format: #{inspect(other)}")
end

# Test volume SMA
volume_config = strategy.indicators[:volume_sma]
volume_value = Indicators.calculate_indicator(volume_config, test_data)
IO.puts("\n  Testing Volume SMA indicator...")
IO.puts("    Result: #{inspect(volume_value)}")

# Step 4: Run a backtest
IO.puts("\nStep 4: Running backtest...")

try do
  result = TradingStrategy.backtest(
    strategy: strategy,
    market_data: market_data,
    symbol: "DEBUG_TEST",
    initial_capital: 10_000,
    commission: 0.001
  )

  IO.puts("✓ Backtest completed successfully")
  IO.puts("\n=== Results ===")
  IO.puts("Total signals: #{length(result.signals)}")
  IO.puts("Total trades: #{result.metrics.total_trades}")
  IO.puts("Win rate: #{Float.round(result.metrics.win_rate, 2)}%")
  IO.puts("Net profit: $#{Float.round(result.metrics.net_profit, 2)}")

  if length(result.signals) == 0 do
    IO.puts("\n⚠ WARNING: No signals generated!")
    IO.puts("\nPossible issues:")
    IO.puts("  1. Indicator values are nil (check logs for calculation errors)")
    IO.puts("  2. Conditions are never satisfied (indicator values don't meet criteria)")
    IO.puts("  3. Data format issue (OHLCV structure not recognized)")
    IO.puts("  4. Multi-value component access not working")
  else
    IO.puts("\n✓ Signals generated successfully!")
    IO.puts("\nFirst few signals:")
    result.signals
    |> Enum.take(5)
    |> Enum.each(fn signal ->
      IO.puts("  - #{signal.type} #{signal.direction} at #{signal.price} (#{signal.timestamp})")
    end)
  end
rescue
  error ->
    IO.puts("✗ Backtest failed with error: #{inspect(error)}")
    IO.puts("\nStacktrace:")
    IO.puts(Exception.format_stacktrace(__STACKTRACE__))
end

# Step 5: Test with Engine (real-time processing)
IO.puts("\n\nStep 5: Testing with Engine (real-time mode)...")

try do
  {:ok, engine} = Engine.start_link(
    strategy: strategy,
    symbol: "DEBUG_ENGINE",
    initial_capital: 10_000,
    max_positions: 3,
    name: :"debug_engine_#{:erlang.unique_integer()}"
  )

  IO.puts("✓ Engine started")

  # Process all candles to see breakouts
  test_candles = market_data

  IO.puts("Processing #{length(test_candles)} candles...")

  results = Enum.with_index(test_candles, 1)
  |> Enum.map(fn {candle, idx} ->
    {:ok, result} = Engine.process_market_data(engine, candle)

    # Show every 10th candle, OR candles 20-27 (breakout zone), OR candles 46-53 (breakout down zone), OR signals
    should_show = rem(idx, 10) == 0 or length(result.signals) > 0 or (idx >= 20 and idx <= 27) or (idx >= 46 and idx <= 53)

    if should_show do
      state = Engine.get_state(engine)
      IO.puts("\nCandle #{idx}:")
      IO.puts("  Price: #{candle.close}, Volume: #{candle.volume}")
      IO.puts("  Indicators: #{inspect(state.indicator_values, pretty: true, limit: :infinity)}")

      if length(result.signals) > 0 do
        IO.puts("  ✓ SIGNAL GENERATED: #{inspect(result.signals)}")
      end
    end

    result
  end)

  all_signals = Enum.flat_map(results, & &1.signals)
  IO.puts("\n✓ Processed all candles")
  IO.puts("Total signals: #{length(all_signals)}")

  Engine.stop(engine)
rescue
  error ->
    IO.puts("✗ Engine test failed: #{inspect(error)}")
    IO.puts("\nStacktrace:")
    IO.puts(Exception.format_stacktrace(__STACKTRACE__))
end

IO.puts("\n=== Debug session complete ===\n")
