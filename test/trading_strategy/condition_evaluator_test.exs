defmodule TradingStrategy.ConditionEvaluatorTest do
  use ExUnit.Case, async: true
  alias TradingStrategy.ConditionEvaluator

  describe "evaluate/2 - boolean logic AND" do
    test "returns true when all conditions are true" do
      condition = %{
        type: :when_all,
        conditions: [true, true, true]
      }

      assert ConditionEvaluator.evaluate(condition, %{})
    end

    test "returns false when any condition is false" do
      condition = %{
        type: :when_all,
        conditions: [true, false, true]
      }

      refute ConditionEvaluator.evaluate(condition, %{})
    end

    test "returns false when all conditions are false" do
      condition = %{
        type: :when_all,
        conditions: [false, false]
      }

      refute ConditionEvaluator.evaluate(condition, %{})
    end
  end

  describe "evaluate/2 - boolean logic OR" do
    test "returns true when at least one condition is true" do
      condition = %{
        type: :when_any,
        conditions: [false, true, false]
      }

      assert ConditionEvaluator.evaluate(condition, %{})
    end

    test "returns false when all conditions are false" do
      condition = %{
        type: :when_any,
        conditions: [false, false, false]
      }

      refute ConditionEvaluator.evaluate(condition, %{})
    end

    test "returns true when all conditions are true" do
      condition = %{
        type: :when_any,
        conditions: [true, true]
      }

      assert ConditionEvaluator.evaluate(condition, %{})
    end
  end

  describe "evaluate/2 - boolean logic NOT" do
    test "returns true when condition is false" do
      condition = %{
        type: :when_not,
        condition: false
      }

      assert ConditionEvaluator.evaluate(condition, %{})
    end

    test "returns false when condition is true" do
      condition = %{
        type: :when_not,
        condition: true
      }

      refute ConditionEvaluator.evaluate(condition, %{})
    end
  end

  describe "evaluate/2 - cross_above" do
    test "returns true when indicator crosses above" do
      condition = %{
        type: :cross_above,
        indicator1: :fast,
        indicator2: :slow
      }

      context = %{
        indicators: %{fast: 110, slow: 100},
        historical_indicators: %{
          fast: [95],
          slow: [100]
        }
      }

      assert ConditionEvaluator.evaluate(condition, context)
    end

    test "returns false when indicator is above but didn't cross" do
      condition = %{
        type: :cross_above,
        indicator1: :fast,
        indicator2: :slow
      }

      context = %{
        indicators: %{fast: 110, slow: 100},
        historical_indicators: %{
          fast: [105],
          slow: [100]
        }
      }

      refute ConditionEvaluator.evaluate(condition, context)
    end

    test "returns false when indicator is below" do
      condition = %{
        type: :cross_above,
        indicator1: :fast,
        indicator2: :slow
      }

      context = %{
        indicators: %{fast: 95, slow: 100},
        historical_indicators: %{
          fast: [90],
          slow: [100]
        }
      }

      refute ConditionEvaluator.evaluate(condition, context)
    end
  end

  describe "evaluate/2 - cross_below" do
    test "returns true when indicator crosses below" do
      condition = %{
        type: :cross_below,
        indicator1: :fast,
        indicator2: :slow
      }

      context = %{
        indicators: %{fast: 95, slow: 100},
        historical_indicators: %{
          fast: [105],
          slow: [100]
        }
      }

      assert ConditionEvaluator.evaluate(condition, context)
    end

    test "returns false when indicator is below but didn't cross" do
      condition = %{
        type: :cross_below,
        indicator1: :fast,
        indicator2: :slow
      }

      context = %{
        indicators: %{fast: 95, slow: 100},
        historical_indicators: %{
          fast: [90],
          slow: [100]
        }
      }

      refute ConditionEvaluator.evaluate(condition, context)
    end
  end

  describe "evaluate/2 - pattern matching" do
    test "returns true when pattern is present" do
      condition = %{
        type: :pattern,
        name: :hammer
      }

      context = %{
        patterns: [:hammer, :doji]
      }

      assert ConditionEvaluator.evaluate(condition, context)
    end

    test "returns false when pattern is not present" do
      condition = %{
        type: :pattern,
        name: :hammer
      }

      context = %{
        patterns: [:doji, :shooting_star]
      }

      refute ConditionEvaluator.evaluate(condition, context)
    end

    test "returns false when no patterns detected" do
      condition = %{
        type: :pattern,
        name: :hammer
      }

      context = %{patterns: []}

      refute ConditionEvaluator.evaluate(condition, context)
    end
  end

  describe "evaluate/2 - comparison operators" do
    test "evaluates > operator" do
      condition = {:>, [], [%{type: :indicator_ref, name: :rsi}, 70]}
      context = %{indicators: %{rsi: 75}}

      assert ConditionEvaluator.evaluate(condition, context)

      context = %{indicators: %{rsi: 65}}
      refute ConditionEvaluator.evaluate(condition, context)
    end

    test "evaluates < operator" do
      condition = {:<, [], [%{type: :indicator_ref, name: :rsi}, 30]}
      context = %{indicators: %{rsi: 25}}

      assert ConditionEvaluator.evaluate(condition, context)

      context = %{indicators: %{rsi: 35}}
      refute ConditionEvaluator.evaluate(condition, context)
    end

    test "evaluates >= operator" do
      condition = {:>=, [], [%{type: :indicator_ref, name: :rsi}, 50]}
      context = %{indicators: %{rsi: 50}}

      assert ConditionEvaluator.evaluate(condition, context)

      context = %{indicators: %{rsi: 51}}
      assert ConditionEvaluator.evaluate(condition, context)

      context = %{indicators: %{rsi: 49}}
      refute ConditionEvaluator.evaluate(condition, context)
    end

    test "evaluates <= operator" do
      condition = {:<=, [], [%{type: :indicator_ref, name: :rsi}, 50]}
      context = %{indicators: %{rsi: 50}}

      assert ConditionEvaluator.evaluate(condition, context)

      context = %{indicators: %{rsi: 49}}
      assert ConditionEvaluator.evaluate(condition, context)

      context = %{indicators: %{rsi: 51}}
      refute ConditionEvaluator.evaluate(condition, context)
    end

    test "evaluates == operator" do
      condition = {:==, [], [%{type: :indicator_ref, name: :rsi}, 50]}
      context = %{indicators: %{rsi: 50}}

      assert ConditionEvaluator.evaluate(condition, context)

      context = %{indicators: %{rsi: 51}}
      refute ConditionEvaluator.evaluate(condition, context)
    end

    test "evaluates != operator" do
      condition = {:!=, [], [%{type: :indicator_ref, name: :rsi}, 50]}
      context = %{indicators: %{rsi: 51}}

      assert ConditionEvaluator.evaluate(condition, context)

      context = %{indicators: %{rsi: 50}}
      refute ConditionEvaluator.evaluate(condition, context)
    end
  end

  describe "evaluate/2 - nested conditions" do
    test "evaluates nested AND within OR" do
      condition = %{
        type: :when_any,
        conditions: [
          %{
            type: :when_all,
            conditions: [
              {:>, [], [%{type: :indicator_ref, name: :rsi}, 70]},
              {:<, [], [%{type: :indicator_ref, name: :volume}, 1000]}
            ]
          },
          {:>, [], [%{type: :indicator_ref, name: :price}, 100]}
        ]
      }

      # First AND condition true
      context = %{indicators: %{rsi: 75, volume: 800, price: 90}}
      assert ConditionEvaluator.evaluate(condition, context)

      # Second condition true
      context = %{indicators: %{rsi: 60, volume: 1200, price: 110}}
      assert ConditionEvaluator.evaluate(condition, context)

      # Both false
      context = %{indicators: %{rsi: 60, volume: 1200, price: 90}}
      refute ConditionEvaluator.evaluate(condition, context)
    end
  end

  describe "get_indicator_value/2" do
    test "retrieves indicator value from context" do
      context = %{indicators: %{rsi: 55.5, sma: 100.0}}

      assert ConditionEvaluator.get_indicator_value(:rsi, context) == 55.5
      assert ConditionEvaluator.get_indicator_value(:sma, context) == 100.0
    end

    test "returns 0.0 for missing indicator" do
      context = %{indicators: %{}}
      assert ConditionEvaluator.get_indicator_value(:missing, context) == 0.0
    end
  end

  describe "get_previous_indicator_value/2" do
    test "retrieves previous indicator value from context" do
      context = %{
        historical_indicators: %{
          rsi: [50.0, 48.0, 52.0]
        }
      }

      assert ConditionEvaluator.get_previous_indicator_value(:rsi, context) == 50.0
    end

    test "returns 0.0 for missing historical data" do
      context = %{historical_indicators: %{}}
      assert ConditionEvaluator.get_previous_indicator_value(:missing, context) == 0.0
    end

    test "returns 0.0 for empty historical data" do
      context = %{historical_indicators: %{rsi: []}}
      assert ConditionEvaluator.get_previous_indicator_value(:rsi, context) == 0.0
    end
  end

  describe "build_context/3" do
    test "builds a context from market data and indicators" do
      market_data = %{close: 100, high: 105, low: 95, open: 98}
      indicator_values = %{rsi: 55, sma: 100}

      context = ConditionEvaluator.build_context(market_data, indicator_values)

      assert context.indicators == indicator_values
      assert context.candles == market_data
      assert %DateTime{} = context.timestamp
    end

    test "accepts optional parameters" do
      market_data = %{close: 100}
      indicator_values = %{rsi: 55}
      historical = %{rsi: [50, 52]}
      patterns = [:hammer]
      timestamp = ~U[2025-01-01 00:00:00Z]

      context =
        ConditionEvaluator.build_context(market_data, indicator_values,
          historical_indicators: historical,
          patterns: patterns,
          timestamp: timestamp
        )

      assert context.historical_indicators == historical
      assert context.patterns == patterns
      assert context.timestamp == timestamp
    end
  end
end
