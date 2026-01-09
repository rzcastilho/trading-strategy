# Market Data Seeder
#
# Seeds the database with 2 years of historical OHLCV data for backtesting.
# Uses CryptoExchange.API.get_historical_klines_bulk to fetch data from exchanges.
#
# Usage:
#   mix run priv/repo/seeds/market_data.exs
#
# Configuration:
#   Set TRADING_PAIRS environment variable for custom pairs (default: "BTCUSDT,ETHUSDT")
#   Set TIMEFRAMES environment variable for custom timeframes (default: "1h,1d")
#   Set YEARS_BACK environment variable for custom history length (default: 2)

alias TradingStrategy.MarketData
require Logger

# Configuration
trading_pairs = System.get_env("TRADING_PAIRS", "BTCUSDT,ETHUSDT") |> String.split(",")
timeframes = System.get_env("TIMEFRAMES", "1h,1d") |> String.split(",")
years_back = System.get_env("YEARS_BACK", "2") |> String.to_integer()
exchange = System.get_env("EXCHANGE", "binance")

# Calculate time range
end_time = DateTime.utc_now()
start_time = DateTime.add(end_time, -years_back * 365 * 24 * 60 * 60, :second)

Logger.info("=" <> String.duplicate("=", 70))
Logger.info("Market Data Seeder")
Logger.info("=" <> String.duplicate("=", 70))
Logger.info("Exchange: #{exchange}")
Logger.info("Trading Pairs: #{Enum.join(trading_pairs, ", ")}")
Logger.info("Timeframes: #{Enum.join(timeframes, ", ")}")
Logger.info("Time Range: #{DateTime.to_date(start_time)} to #{DateTime.to_date(end_time)}")
Logger.info("=" <> String.duplicate("=", 70))

# Seed data for each combination
total_combinations = length(trading_pairs) * length(timeframes)
current = 0

results =
  for pair <- trading_pairs,
      timeframe <- timeframes do
    current = current + 1

    Logger.info(
      "[#{current}/#{total_combinations}] Fetching #{pair} #{timeframe}..."
    )

    case MarketData.get_historical_data(pair, timeframe,
           start_time: start_time,
           end_time: end_time,
           exchange: exchange
         ) do
      {:ok, data} ->
        Logger.info(
          "[#{current}/#{total_combinations}] ✓ Stored #{length(data)} bars for #{pair} #{timeframe}"
        )

        %{pair: pair, timeframe: timeframe, bars: length(data), status: :success}

      {:error, reason} ->
        Logger.error(
          "[#{current}/#{total_combinations}] ✗ Failed to fetch #{pair} #{timeframe}: #{inspect(reason)}"
        )

        %{pair: pair, timeframe: timeframe, bars: 0, status: :error, reason: reason}
    end
  end

# Summary
Logger.info("=" <> String.duplicate("=", 70))
Logger.info("Seeding Summary")
Logger.info("=" <> String.duplicate("=", 70))

successful = Enum.filter(results, &(&1.status == :success))
failed = Enum.filter(results, &(&1.status == :error))
total_bars = Enum.reduce(successful, 0, fn result, acc -> acc + result.bars end)

Logger.info("Successful: #{length(successful)}/#{total_combinations}")
Logger.info("Failed: #{length(failed)}/#{total_combinations}")
Logger.info("Total bars stored: #{total_bars}")

if length(failed) > 0 do
  Logger.warning("Failed combinations:")

  Enum.each(failed, fn result ->
    Logger.warning("  - #{result.pair} #{result.timeframe}: #{inspect(result.reason)}")
  end)
end

Logger.info("=" <> String.duplicate("=", 70))
Logger.info("Seeding completed!")
Logger.info("=" <> String.duplicate("=", 70))

# Return results for script usage
results
