defmodule TradingStrategy.StrategyEditor.SyncBenchmarkTest do
  @moduledoc """
  Benchmark tests for bidirectional synchronization performance.

  Verifies SC-005: Strategies with up to 20 indicators + 10 conditions
  synchronize within 500ms in both directions.
  """
  use ExUnit.Case, async: false

  alias TradingStrategy.StrategyEditor.{Synchronizer, BuilderState}

  @twenty_indicator_strategy """
  defmodule ComplexStrategy do
    use TradingStrategy.Dsl

    strategy "Complex Multi-Indicator Strategy" do
      # Basic Configuration
      trading_pair "BTC/USD"
      timeframe "1h"

      # 20 Indicators
      indicator :sma, name: :sma_20, period: 20
      indicator :sma, name: :sma_50, period: 50
      indicator :sma, name: :sma_200, period: 200
      indicator :ema, name: :ema_12, period: 12
      indicator :ema, name: :ema_26, period: 26
      indicator :rsi, name: :rsi_14, period: 14
      indicator :rsi, name: :rsi_21, period: 21
      indicator :macd, name: :macd_1, fast: 12, slow: 26, signal: 9
      indicator :bollinger_bands, name: :bb_20, period: 20, std_dev: 2
      indicator :atr, name: :atr_14, period: 14
      indicator :stochastic, name: :stoch_14, period: 14
      indicator :adx, name: :adx_14, period: 14
      indicator :obv, name: :obv
      indicator :vwap, name: :vwap
      indicator :cci, name: :cci_20, period: 20
      indicator :williams_r, name: :wr_14, period: 14
      indicator :mfi, name: :mfi_14, period: 14
      indicator :trix, name: :trix_15, period: 15
      indicator :roc, name: :roc_12, period: 12
      indicator :momentum, name: :mom_10, period: 10

      # 10 Entry Conditions
      entry_condition do
        sma_20 > sma_50 and
        sma_50 > sma_200 and
        rsi_14 > 30 and rsi_14 < 70 and
        macd_1.histogram > 0 and
        close > bb_20.upper * 0.98 and
        atr_14 > 0 and
        stoch_14.k > 20 and
        adx_14 > 25 and
        volume > vwap.volume * 1.5
      end

      # Exit Condition
      exit_condition do
        rsi_14 > 70 or
        close < sma_20 or
        macd_1.histogram < 0 or
        stoch_14.k > 80
      end

      # Stop Loss
      stop_loss type: :trailing, percentage: 0.02

      # Position Sizing
      position_sizing type: :percentage, percentage: 0.10

      # Risk Parameters
      risk_management do
        max_daily_loss 0.03
        max_drawdown 0.15
        max_position_size 0.10
      end
    end
  end
  """

  describe "builder_to_dsl performance (SC-005)" do
    test "20-indicator strategy converts to DSL within 500ms" do
      # Parse DSL to BuilderState
      {:ok, builder_state} = Synchronizer.dsl_to_builder(@twenty_indicator_strategy)

      # Benchmark builder_to_dsl
      {time_microseconds, {:ok, _dsl_text}} =
        :timer.tc(fn ->
          Synchronizer.builder_to_dsl(builder_state, [])
        end)

      time_milliseconds = time_microseconds / 1000

      assert time_milliseconds < 500,
             "Builder → DSL took #{time_milliseconds}ms, expected < 500ms"

      # Log for monitoring
      IO.puts(
        "\n[BENCHMARK] Builder → DSL (20 indicators): #{Float.round(time_milliseconds, 2)}ms"
      )
    end

    test "20-indicator strategy with 100 comments converts within 500ms" do
      # Generate many comments to stress-test comment preservation
      comments =
        for i <- 1..100 do
          %{line: i, column: 1, text: "# Comment #{i}", preserved_from_dsl: true}
        end

      {:ok, builder_state} = Synchronizer.dsl_to_builder(@twenty_indicator_strategy)

      {time_microseconds, {:ok, _dsl_text}} =
        :timer.tc(fn ->
          Synchronizer.builder_to_dsl(builder_state, comments)
        end)

      time_milliseconds = time_microseconds / 1000

      assert time_milliseconds < 500,
             "Builder → DSL with 100 comments took #{time_milliseconds}ms, expected < 500ms"

      IO.puts(
        "[BENCHMARK] Builder → DSL (20 indicators + 100 comments): #{Float.round(time_milliseconds, 2)}ms"
      )
    end
  end

  describe "dsl_to_builder performance (SC-005)" do
    test "20-indicator strategy parses to BuilderState within 500ms" do
      {time_microseconds, {:ok, _builder_state}} =
        :timer.tc(fn ->
          Synchronizer.dsl_to_builder(@twenty_indicator_strategy)
        end)

      time_milliseconds = time_microseconds / 1000

      assert time_milliseconds < 500,
             "DSL → Builder took #{time_milliseconds}ms, expected < 500ms"

      IO.puts("[BENCHMARK] DSL → Builder (20 indicators): #{Float.round(time_milliseconds, 2)}ms")
    end

    test "100 rapid DSL → Builder conversions maintain performance" do
      times =
        for _ <- 1..100 do
          {time_microseconds, {:ok, _builder_state}} =
            :timer.tc(fn ->
              Synchronizer.dsl_to_builder(@twenty_indicator_strategy)
            end)

          time_microseconds / 1000
        end

      avg_time = Enum.sum(times) / length(times)
      # 95th percentile
      p95_time = Enum.at(Enum.sort(times), 94)
      max_time = Enum.max(times)

      assert p95_time < 500,
             "P95 latency #{p95_time}ms exceeds 500ms target"

      IO.puts("\n[BENCHMARK] DSL → Builder (100 iterations):")
      IO.puts("  Average: #{Float.round(avg_time, 2)}ms")
      IO.puts("  P95: #{Float.round(p95_time, 2)}ms")
      IO.puts("  Max: #{Float.round(max_time, 2)}ms")
    end
  end

  describe "round-trip performance (SC-001)" do
    test "DSL → Builder → DSL round-trip within 1000ms total" do
      {time_microseconds, result} =
        :timer.tc(fn ->
          with {:ok, builder_state} <- Synchronizer.dsl_to_builder(@twenty_indicator_strategy),
               {:ok, dsl_text} <- Synchronizer.builder_to_dsl(builder_state, []) do
            {:ok, dsl_text}
          end
        end)

      time_milliseconds = time_microseconds / 1000

      assert {:ok, _dsl_text} = result

      assert time_milliseconds < 1000,
             "Round-trip took #{time_milliseconds}ms, expected < 1000ms"

      IO.puts(
        "[BENCHMARK] Full round-trip (20 indicators): #{Float.round(time_milliseconds, 2)}ms"
      )
    end
  end

  describe "memory usage benchmarks" do
    test "20-indicator BuilderState fits within reasonable memory (<5MB)" do
      {:ok, builder_state} = Synchronizer.dsl_to_builder(@twenty_indicator_strategy)

      # Estimate memory footprint
      binary_size = :erlang.term_to_binary(builder_state) |> byte_size()
      memory_mb = binary_size / (1024 * 1024)

      assert memory_mb < 5.0,
             "BuilderState requires #{memory_mb}MB, expected < 5MB"

      IO.puts("[BENCHMARK] BuilderState memory: #{Float.round(memory_mb, 3)}MB")
    end
  end
end
