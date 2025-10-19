defmodule TradingStrategyTest do
  use ExUnit.Case
  alias TradingStrategy.Definition
  import TradingStrategy.TestHelpers

  setup do
    strategy = simple_strategy()
    market_data = generate_market_data(count: 20)

    {:ok, strategy: strategy, market_data: market_data}
  end

  describe "new_strategy/2" do
    test "creates a new strategy definition" do
      strategy = TradingStrategy.new_strategy(:test, description: "Test")

      assert %Definition{} = strategy
      assert strategy.name == :test
      assert strategy.description == "Test"
    end
  end

  describe "validate_strategy/1" do
    test "validates a complete strategy", %{strategy: strategy} do
      assert {:ok, ^strategy} = TradingStrategy.validate_strategy(strategy)
    end

    test "fails for invalid strategy" do
      invalid_strategy = Definition.new(:invalid)
      assert {:error, _reason} = TradingStrategy.validate_strategy(invalid_strategy)
    end
  end

  describe "backtest/1" do
    test "runs a backtest", %{strategy: strategy, market_data: data} do
      result =
        TradingStrategy.backtest(
          strategy: strategy,
          market_data: data,
          symbol: "TEST"
        )

      assert is_map(result)
      assert result.strategy == :test_strategy
      assert is_map(result.metrics)
    end
  end

  describe "calculate_indicators/2" do
    test "calculates indicators for strategy", %{strategy: strategy, market_data: data} do
      indicators = TradingStrategy.calculate_indicators(strategy, data)

      assert is_map(indicators)
      assert Map.has_key?(indicators, :sma_fast)
      assert Map.has_key?(indicators, :sma_slow)
    end
  end

  describe "detect_patterns/1" do
    test "detects patterns in candle data" do
      candles = hammer_pattern()
      patterns = TradingStrategy.detect_patterns(candles)

      assert is_list(patterns)
      assert :hammer in patterns
    end

    test "returns empty list for no patterns" do
      candles = [%{open: 100, high: 101, low: 99, close: 100.5, volume: 1000}]
      patterns = TradingStrategy.detect_patterns(candles)

      assert patterns == []
    end
  end

  describe "evaluate_condition/2" do
    test "evaluates a simple condition" do
      condition = %{type: :when_all, conditions: [true, true]}
      context = %{}

      assert TradingStrategy.evaluate_condition(condition, context) == true
    end

    test "evaluates indicator comparison" do
      condition = {:>, [], [%{type: :indicator_ref, name: :rsi}, 70]}
      context = %{indicators: %{rsi: 75}}

      assert TradingStrategy.evaluate_condition(condition, context) == true
    end
  end
end
