defmodule TradingStrategy.IntegrationTest do
  use ExUnit.Case
  import TradingStrategy.TestHelpers

  @moduletag :integration

  describe "end-to-end strategy lifecycle" do
    test "complete workflow: define -> backtest -> analyze" do
      # Step 1: Define a strategy using DSL
      defmodule IntegrationTestStrategy do
        use TradingStrategy.DSL

        defstrategy :integration_test do
          description "Integration test strategy"

          indicator :sma_fast, TestIndicator, period: 5
          indicator :sma_slow, TestIndicator, period: 15

          entry_signal :long do
            when_all do
              cross_above(:sma_fast, :sma_slow)
            end
          end

          exit_signal do
            cross_below(:sma_fast, :sma_slow)
          end
        end
      end

      # Step 2: Generate test market data
      market_data = generate_market_data(count: 100, trend: :up, volatility: :medium)

      # Step 3: Run backtest
      strategy = IntegrationTestStrategy.strategy_definition()

      result =
        TradingStrategy.backtest(
          strategy: strategy,
          market_data: market_data,
          symbol: "TEST",
          initial_capital: 10_000,
          commission: 0.001
        )

      # Step 4: Validate results
      assert result.strategy == :integration_test
      assert result.symbol == "TEST"
      assert is_map(result.metrics)
      assert is_list(result.trades)
      assert is_list(result.signals)
      assert is_list(result.equity_curve)

      # Verify metrics structure
      metrics = result.metrics
      assert is_number(metrics.total_trades)
      assert is_number(metrics.win_rate)
      assert is_number(metrics.net_profit)
      assert is_number(metrics.max_drawdown)
    end

    test "pattern-based strategy workflow" do
      defmodule PatternStrategy do
        use TradingStrategy.DSL

        defstrategy :pattern_test do
          description "Pattern-based test strategy"

          indicator :rsi, TestIndicator, period: 14

          entry_signal :long do
            when_all do
              indicator(:rsi) < 40
              pattern(:hammer)
            end
          end

          exit_signal do
            indicator(:rsi) > 60
          end
        end
      end

      # Generate data with patterns
      market_data = generate_market_data(count: 50, volatility: :high)

      strategy = PatternStrategy.strategy_definition()

      result =
        TradingStrategy.backtest(
          strategy: strategy,
          market_data: market_data,
          symbol: "PATTERN_TEST"
        )

      assert result.strategy == :pattern_test
      assert is_map(result.metrics)
    end
  end

  describe "real-time strategy execution workflow" do
    test "processes streaming market data" do
      # Define strategy
      strategy = simple_strategy()

      # Start engine
      {:ok, engine} =
        TradingStrategy.start_strategy(
          strategy: strategy,
          symbol: "STREAM_TEST",
          initial_capital: 10_000,
          name: :"test_engine_#{:erlang.unique_integer()}"
        )

      # Generate and process candles
      market_data = generate_market_data(count: 10)

      results =
        Enum.map(market_data, fn candle ->
          {:ok, result} = TradingStrategy.process_data(engine, candle)
          result
        end)

      # Verify processing
      assert length(results) == 10

      # Check final state
      state = TradingStrategy.get_state(engine)
      assert is_map(state)
      assert state.strategy.name == :test_strategy

      # Cleanup
      TradingStrategy.stop(engine)
    end
  end

  describe "multi-indicator strategy" do
    test "combines multiple indicators and conditions" do
      defmodule MultiIndicatorStrategy do
        use TradingStrategy.DSL

        defstrategy :multi_indicator do
          description "Multi-indicator test"

          indicator :sma_short, TestIndicator, period: 5
          indicator :sma_medium, TestIndicator, period: 10
          indicator :sma_long, TestIndicator, period: 20
          indicator :rsi, TestIndicator, period: 14

          entry_signal :long do
            when_all do
              cross_above(:sma_short, :sma_medium)
              indicator(:sma_medium) > indicator(:sma_long)
              indicator(:rsi) > 30
              indicator(:rsi) < 70
            end
          end

          exit_signal do
            when_any do
              cross_below(:sma_short, :sma_medium)
              indicator(:rsi) > 75
              indicator(:rsi) < 25
            end
          end
        end
      end

      market_data = generate_market_data(count: 100, trend: :up)
      strategy = MultiIndicatorStrategy.strategy_definition()

      result =
        TradingStrategy.backtest(
          strategy: strategy,
          market_data: market_data,
          symbol: "MULTI"
        )

      # Verify all indicators were calculated
      assert map_size(strategy.indicators) == 4
      assert result.strategy == :multi_indicator
    end
  end

  describe "real trading-indicators integration" do
    test "calculates SMA indicator correctly" do
      # Use actual SMA indicator from trading-indicators library
      defmodule SMATestStrategy do
        use TradingStrategy.DSL

        defstrategy :sma_test do
          description "SMA integration test"

          indicator :sma_3, TradingIndicators.Trend.SMA, period: 3, source: :close
          indicator :sma_5, TradingIndicators.Trend.SMA, period: 5, source: :close

          entry_signal :long do
            cross_above(:sma_3, :sma_5)
          end

          exit_signal do
            cross_below(:sma_3, :sma_5)
          end
        end
      end

      market_data = generate_market_data(count: 20, trend: :up)
      strategy = SMATestStrategy.strategy_definition()

      result =
        TradingStrategy.backtest(
          strategy: strategy,
          market_data: market_data,
          symbol: "SMA_TEST"
        )

      # Verify strategy executed successfully with real indicators
      assert result.strategy == :sma_test
      assert is_map(result.metrics)
      assert is_list(result.signals)
    end

    test "validates indicator parameters properly" do
      alias TradingStrategy.Indicators

      # Valid parameters
      assert {:ok, :valid} =
               Indicators.validate_indicator_params(
                 TradingIndicators.Trend.SMA,
                 period: 20,
                 source: :close
               )

      # Invalid parameters (negative period)
      assert {:error, _reason} =
               Indicators.validate_indicator_params(
                 TradingIndicators.Trend.SMA,
                 period: -1,
                 source: :close
               )
    end

    test "checks data sufficiency correctly" do
      alias TradingStrategy.Indicators

      sufficient_data = generate_market_data(count: 20)
      insufficient_data = generate_market_data(count: 5)

      # Should pass with sufficient data
      assert :ok =
               Indicators.check_sufficient_data(
                 TradingIndicators.Trend.SMA,
                 sufficient_data,
                 period: 10
               )

      # Should fail with insufficient data
      assert :insufficient_data =
               Indicators.check_sufficient_data(
                 TradingIndicators.Trend.SMA,
                 insufficient_data,
                 period: 10
               )
    end

    test "retrieves parameter metadata" do
      alias TradingStrategy.Indicators

      metadata = Indicators.get_parameter_metadata(TradingIndicators.Trend.SMA)

      assert is_list(metadata)
      assert length(metadata) > 0

      # Verify metadata structure
      period_meta = Enum.find(metadata, fn m -> m.name == :period end)
      assert period_meta != nil
      assert period_meta.type == :integer
      assert is_number(period_meta.default)
    end

    test "detects streaming support" do
      alias TradingStrategy.Indicators

      # Real indicators should support streaming
      assert Indicators.supports_streaming?(TradingIndicators.Trend.SMA) == true
      assert Indicators.supports_streaming?(TradingIndicators.Momentum.RSI) == true

      # Test indicator doesn't
      assert Indicators.supports_streaming?(TestIndicator) == false
    end

    test "calculates multiple real indicators" do
      defmodule MultiRealIndicatorStrategy do
        use TradingStrategy.DSL

        defstrategy :multi_real do
          description "Multiple real indicators"

          indicator :sma, TradingIndicators.Trend.SMA, period: 10, source: :close
          indicator :rsi, TradingIndicators.Momentum.RSI, period: 14, source: :close
          indicator :ema, TradingIndicators.Trend.EMA, period: 12, source: :close

          entry_signal :long do
            when_all do
              indicator(:rsi) < 40
              indicator(:sma) < indicator(:ema)
            end
          end

          exit_signal do
            indicator(:rsi) > 60
          end
        end
      end

      market_data = generate_market_data(count: 50, volatility: :medium)
      strategy = MultiRealIndicatorStrategy.strategy_definition()

      result =
        TradingStrategy.backtest(
          strategy: strategy,
          market_data: market_data,
          symbol: "MULTI_REAL"
        )

      # All indicators should calculate successfully
      assert result.strategy == :multi_real
      assert map_size(strategy.indicators) == 3
    end
  end

  describe "edge cases and error handling" do
    test "handles empty market data gracefully" do
      strategy = simple_strategy()

      result =
        TradingStrategy.backtest(
          strategy: strategy,
          market_data: [],
          symbol: "EMPTY"
        )

      assert result.metrics.total_trades == 0
      assert result.trades == []
    end

    test "handles insufficient data for indicators" do
      strategy = simple_strategy()

      # Only 2 candles, but strategy needs more for SMA calculation
      market_data = generate_market_data(count: 2)

      result =
        TradingStrategy.backtest(
          strategy: strategy,
          market_data: market_data,
          symbol: "INSUFFICIENT"
        )

      # Should complete without errors
      assert is_map(result.metrics)
    end
  end
end
