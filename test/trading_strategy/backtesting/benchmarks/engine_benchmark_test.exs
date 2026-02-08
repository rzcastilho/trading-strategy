defmodule TradingStrategy.Backtesting.Benchmarks.EngineBenchmarkTest do
  use TradingStrategy.DataCase, async: false

  alias TradingStrategy.Backtesting
  alias TradingStrategy.Backtesting.Engine
  alias TradingStrategy.MarketData.Bar
  alias TradingStrategy.Strategies.Strategy

  @moduletag :benchmark
  @moduletag timeout: :infinity

  describe "Engine performance benchmarks" do
    setup do
      # Create a simple test strategy that generates some trades
      strategy = %Strategy{
        id: "benchmark_strategy",
        name: "Benchmark Strategy",
        description: "Simple strategy for benchmarking",
        rules: %{
          entry: [
            %{
              type: :indicator,
              indicator: :rsi,
              params: %{period: 14},
              condition: :below,
              value: 30
            }
          ],
          exit: [
            %{
              type: :indicator,
              indicator: :rsi,
              params: %{period: 14},
              condition: :above,
              value: 70
            }
          ]
        },
        risk_management: %{
          position_size_pct: 10.0,
          stop_loss_pct: 2.0,
          take_profit_pct: 5.0
        }
      }

      {:ok, strategy: strategy}
    end

    @tag :benchmark_10k
    test "benchmark with 10K bars", %{strategy: strategy} do
      bars = generate_bars(10_000)

      {time_microseconds, _result} = :timer.tc(fn ->
        execute_benchmark(strategy, bars)
      end)

      time_ms = time_microseconds / 1_000
      bars_per_second = 10_000 / (time_microseconds / 1_000_000)

      IO.puts("\n=== 10K Bars Benchmark ===")
      IO.puts("Total time: #{Float.round(time_ms, 2)} ms")
      IO.puts("Time per bar: #{Float.round(time_microseconds / 10_000, 2)} μs")
      IO.puts("Throughput: #{Float.round(bars_per_second, 2)} bars/second")
      IO.puts("==========================\n")

      # Performance target: Should complete in reasonable time
      # This will be our baseline for measuring 30% improvement
      assert time_ms < 10_000, "10K bars should complete within 10 seconds"
    end

    @tag :benchmark_50k
    test "benchmark with 50K bars", %{strategy: strategy} do
      bars = generate_bars(50_000)

      {time_microseconds, _result} = :timer.tc(fn ->
        execute_benchmark(strategy, bars)
      end)

      time_ms = time_microseconds / 1_000
      bars_per_second = 50_000 / (time_microseconds / 1_000_000)

      IO.puts("\n=== 50K Bars Benchmark ===")
      IO.puts("Total time: #{Float.round(time_ms, 2)} ms")
      IO.puts("Time per bar: #{Float.round(time_microseconds / 50_000, 2)} μs")
      IO.puts("Throughput: #{Float.round(bars_per_second, 2)} bars/second")
      IO.puts("==========================\n")

      # Should scale linearly (not O(n²))
      assert time_ms < 50_000, "50K bars should complete within 50 seconds"
    end

    @tag :benchmark_100k
    test "benchmark with 100K bars", %{strategy: strategy} do
      bars = generate_bars(100_000)

      {time_microseconds, _result} = :timer.tc(fn ->
        execute_benchmark(strategy, bars)
      end)

      time_ms = time_microseconds / 1_000
      bars_per_second = 100_000 / (time_microseconds / 1_000_000)
      memory_mb = :erlang.memory(:total) / (1024 * 1024)

      IO.puts("\n=== 100K Bars Benchmark ===")
      IO.puts("Total time: #{Float.round(time_ms, 2)} ms")
      IO.puts("Time per bar: #{Float.round(time_microseconds / 100_000, 2)} μs")
      IO.puts("Throughput: #{Float.round(bars_per_second, 2)} bars/second")
      IO.puts("Memory used: #{Float.round(memory_mb, 2)} MB")
      IO.puts("===========================\n")

      # Should scale linearly and not exhaust memory (SC-006)
      assert time_ms < 100_000, "100K bars should complete within 100 seconds"
      assert memory_mb < 1_000, "Should not exceed 1GB memory usage"
    end

    # Helper functions

    defp generate_bars(count) do
      base_time = ~U[2024-01-01 00:00:00Z]
      base_price = 50_000.0

      Enum.map(0..(count - 1), fn i ->
        # Generate realistic OHLCV data with some volatility
        # RSI oscillates to trigger entry/exit signals periodically
        cycle_position = rem(i, 100) / 100.0
        price_variation = :math.sin(cycle_position * 2 * :math.pi()) * 500
        current_price = base_price + price_variation

        %Bar{
          trading_pair: "BTC/USD",
          timeframe: "1m",
          timestamp: DateTime.add(base_time, i * 60, :second),
          open: Decimal.from_float(current_price),
          high: Decimal.from_float(current_price + 50),
          low: Decimal.from_float(current_price - 50),
          close: Decimal.from_float(current_price + (:rand.uniform() - 0.5) * 100),
          volume: Decimal.from_float(100.0 + :rand.uniform() * 50),
          metadata: %{}
        }
      end)
    end

    defp execute_benchmark(strategy, bars) do
      config = %{
        strategy_id: strategy.id,
        trading_pair: "BTC/USD",
        start_time: ~U[2024-01-01 00:00:00Z],
        end_time: DateTime.add(~U[2024-01-01 00:00:00Z], length(bars) * 60, :second),
        initial_capital: Decimal.new("10000"),
        timeframe: "1m",
        mode: "backtest"
      }

      # Create trading session
      {:ok, session} = Backtesting.create_trading_session(config)

      # Execute backtest loop with generated bars
      initial_state = %{
        session_id: session.id,
        strategy: strategy,
        config: config,
        bars: bars,
        positions: [],
        current_capital: Decimal.new("10000"),
        equity_history: [],
        bar_index: 0,
        total_bars: length(bars)
      }

      # Run the backtest loop
      final_state = Engine.execute_backtest_loop(initial_state, bars, strategy)

      # Return final state for validation
      final_state
    end
  end
end
