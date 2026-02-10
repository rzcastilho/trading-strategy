defmodule TradingStrategy.Backtesting.PerformanceProfileTest do
  use TradingStrategy.DataCase, async: false

  alias TradingStrategy.Backtesting.Engine
  alias TradingStrategy.MarketData.Bar
  alias TradingStrategy.Strategies.Strategy

  @moduletag :performance
  @moduletag timeout: :infinity

  describe "Performance profiling" do
    setup do
      strategy = %Strategy{
        id: "profile_strategy",
        name: "Profile Strategy",
        description: "Strategy for performance profiling",
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

    @tag :profile
    test "profile execution time for different dataset sizes", %{strategy: strategy} do
      IO.puts("\n=== Performance Profiling ===\n")

      # Test with increasing dataset sizes
      sizes = [1_000, 5_000, 10_000]

      results =
        Enum.map(sizes, fn size ->
          bars = generate_bars(size)

          {time_microseconds, _result} = :timer.tc(fn ->
            run_backtest_silent(strategy, bars)
          end)

          time_ms = time_microseconds / 1_000
          bars_per_second = size / (time_microseconds / 1_000_000)
          time_per_bar_us = time_microseconds / size

          result = %{
            size: size,
            time_ms: Float.round(time_ms, 2),
            time_per_bar_us: Float.round(time_per_bar_us, 2),
            bars_per_second: Float.round(bars_per_second, 2)
          }

          IO.puts("Dataset: #{size} bars")
          IO.puts("  Total time: #{result.time_ms} ms")
          IO.puts("  Time per bar: #{result.time_per_bar_us} μs")
          IO.puts("  Throughput: #{result.bars_per_second} bars/sec")
          IO.puts("")

          result
        end)

      # Check for O(n²) behavior
      # If performance is O(n²), doubling the input size should quadruple the time
      # If performance is O(n), doubling the input size should double the time

      [r1, r2, r3] = results

      # Calculate scaling factors
      scale_1_to_2 = r2.time_ms / r1.time_ms
      size_ratio_1_to_2 = r2.size / r1.size

      scale_2_to_3 = r3.time_ms / r2.time_ms
      size_ratio_2_to_3 = r3.size / r2.size

      IO.puts("=== Scaling Analysis ===")
      IO.puts("#{r1.size} -> #{r2.size} bars (#{size_ratio_1_to_2}x size): #{Float.round(scale_1_to_2, 2)}x time")
      IO.puts("#{r2.size} -> #{r3.size} bars (#{size_ratio_2_to_3}x size): #{Float.round(scale_2_to_3, 2)}x time")
      IO.puts("")

      # For O(n) complexity: time scale should roughly equal size scale
      # For O(n²) complexity: time scale should equal size scale squared
      # We'll allow some overhead, so we check if time_scale < (size_scale * 1.5)
      # This means we're not seeing quadratic behavior

      max_acceptable_scale_1_to_2 = size_ratio_1_to_2 * 1.5
      max_acceptable_scale_2_to_3 = size_ratio_2_to_3 * 1.5

      IO.puts("Expected scaling (O(n)): ~#{Float.round(size_ratio_1_to_2, 2)}x time")
      IO.puts("Actual scaling: #{Float.round(scale_1_to_2, 2)}x time")
      IO.puts("Max acceptable (1.5x linear): #{Float.round(max_acceptable_scale_1_to_2, 2)}x time")
      IO.puts("")

      if scale_1_to_2 <= max_acceptable_scale_1_to_2 and scale_2_to_3 <= max_acceptable_scale_2_to_3 do
        IO.puts("✅ Performance is approximately O(n) - No quadratic behavior detected")
      else
        IO.puts("⚠️  Performance may have worse than O(n) complexity")
      end

      IO.puts("============================\n")

      # Assert linear or near-linear scaling
      assert scale_1_to_2 <= max_acceptable_scale_1_to_2,
             "Performance degraded more than expected from #{r1.size} to #{r2.size} bars"

      assert scale_2_to_3 <= max_acceptable_scale_2_to_3,
             "Performance degraded more than expected from #{r2.size} to #{r3.size} bars"
    end

    # Helper functions

    defp generate_bars(count) do
      base_time = ~U[2024-01-01 00:00:00Z]
      base_price = 50_000.0

      Enum.map(0..(count - 1), fn i ->
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

    defp run_backtest_silent(strategy, bars) do
      # Suppress logs during profiling
      Logger.configure(level: :error)

      config = [
        strategy_id: strategy.id,
        trading_pair: "BTC/USD",
        start_time: ~U[2024-01-01 00:00:00Z],
        end_time: DateTime.add(~U[2024-01-01 00:00:00Z], length(bars) * 60, :second),
        initial_capital: 10_000,
        timeframe: "1m",
        exchange: "test"
      ]

      # Mock MarketData to return our generated bars
      with_mock(TradingStrategy.MarketData, [:passthrough],
        get_historical_data: fn _, _, _ -> {:ok, bars} end
      ) do
        result = Engine.run_backtest(strategy, config)
        Logger.configure(level: :info)
        result
      end
    end
  end
end
