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

    test "returns nil for missing indicator (warmup period)" do
      context = %{indicators: %{}}
      assert ConditionEvaluator.get_indicator_value(:missing, context) == nil
    end

    test "returns nil for indicator with nil value (warmup period)" do
      context = %{indicators: %{rsi: nil}}
      # When accessing price/volume fields, fall back to candles
      context_with_candles = Map.put(context, :candles, [])
      assert ConditionEvaluator.get_indicator_value(:rsi, context_with_candles) == nil
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

    test "returns nil for missing historical data (warmup period)" do
      context = %{historical_indicators: %{}}
      # When accessing price/volume fields, fall back to candles
      context_with_candles = Map.put(context, :candles, [])
      assert ConditionEvaluator.get_previous_indicator_value(:missing, context_with_candles) == nil
    end

    test "returns nil for empty historical data (warmup period)" do
      context = %{historical_indicators: %{rsi: []}}
      # When accessing price/volume fields, fall back to candles
      context_with_candles = Map.put(context, :candles, [])
      assert ConditionEvaluator.get_previous_indicator_value(:rsi, context_with_candles) == nil
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

  describe "multi-value indicator support" do
    test "accesses component of multi-value indicator (MACD)" do
      macd_value = %{
        macd: Decimal.new("0.5"),
        signal: Decimal.new("0.3"),
        histogram: Decimal.new("0.2")
      }

      context = %{indicators: %{macd: macd_value}}

      # Test histogram component access
      histogram_ref = %{type: :indicator_ref, name: :macd, component: :histogram}
      assert ConditionEvaluator.get_indicator_value(histogram_ref, context) == Decimal.new("0.2")

      # Test macd line component access
      macd_ref = %{type: :indicator_ref, name: :macd, component: :macd}
      assert ConditionEvaluator.get_indicator_value(macd_ref, context) == Decimal.new("0.5")

      # Test signal component access
      signal_ref = %{type: :indicator_ref, name: :macd, component: :signal}
      assert ConditionEvaluator.get_indicator_value(signal_ref, context) == Decimal.new("0.3")
    end

    test "accesses component of multi-value indicator (Bollinger Bands)" do
      bb_value = %{
        upper_band: Decimal.new("110"),
        middle_band: Decimal.new("100"),
        lower_band: Decimal.new("90"),
        percent_b: Decimal.new("0.5"),
        bandwidth: Decimal.new("20")
      }

      context = %{indicators: %{bb: bb_value}}

      # Test each component
      upper_ref = %{type: :indicator_ref, name: :bb, component: :upper_band}
      assert ConditionEvaluator.get_indicator_value(upper_ref, context) == Decimal.new("110")

      middle_ref = %{type: :indicator_ref, name: :bb, component: :middle_band}
      assert ConditionEvaluator.get_indicator_value(middle_ref, context) == Decimal.new("100")

      lower_ref = %{type: :indicator_ref, name: :bb, component: :lower_band}
      assert ConditionEvaluator.get_indicator_value(lower_ref, context) == Decimal.new("90")
    end

    test "raises error when accessing multi-value indicator without component" do
      macd_value = %{
        macd: Decimal.new("0.5"),
        signal: Decimal.new("0.3"),
        histogram: Decimal.new("0.2")
      }

      context = %{indicators: %{macd: macd_value}}

      assert_raise ArgumentError, ~r/Indicator :macd returns multiple values/, fn ->
        ConditionEvaluator.get_indicator_value(:macd, context)
      end
    end

    test "raises error when accessing invalid component" do
      macd_value = %{
        macd: Decimal.new("0.5"),
        signal: Decimal.new("0.3"),
        histogram: Decimal.new("0.2")
      }

      context = %{indicators: %{macd: macd_value}}
      invalid_ref = %{type: :indicator_ref, name: :macd, component: :invalid}

      assert_raise ArgumentError, ~r/Invalid component :invalid for indicator :macd/, fn ->
        ConditionEvaluator.get_indicator_value(invalid_ref, context)
      end
    end

    test "raises error when using component access on single-value indicator" do
      context = %{indicators: %{rsi: Decimal.new("70")}}
      component_ref = %{type: :indicator_ref, name: :rsi, component: :value}

      assert_raise ArgumentError, ~r/Indicator :rsi is not a multi-value indicator/, fn ->
        ConditionEvaluator.get_indicator_value(component_ref, context)
      end
    end

    test "evaluates comparison with multi-value indicator component" do
      macd_value = %{
        macd: Decimal.new("0.5"),
        signal: Decimal.new("0.3"),
        histogram: Decimal.new("0.2")
      }

      context = %{indicators: %{macd: macd_value}}

      # Test: histogram > 0
      condition = {:>, [], [%{type: :indicator_ref, name: :macd, component: :histogram}, 0]}
      assert ConditionEvaluator.evaluate(condition, context)

      # Test: histogram < 0.5
      condition = {:<, [], [%{type: :indicator_ref, name: :macd, component: :histogram}, 0.5]}
      assert ConditionEvaluator.evaluate(condition, context)
    end

    test "supports cross detection with multi-value indicator components" do
      macd_current = %{
        macd: Decimal.new("0.5"),
        signal: Decimal.new("0.3"),
        histogram: Decimal.new("0.2")
      }

      macd_previous = %{
        macd: Decimal.new("0.25"),
        signal: Decimal.new("0.3"),
        histogram: Decimal.new("-0.05")
      }

      context = %{
        indicators: %{macd: macd_current},
        historical_indicators: %{macd: [macd_previous]}
      }

      # Test cross above: MACD line crossed above signal line
      macd_ref = %{type: :indicator_ref, name: :macd, component: :macd}
      signal_ref = %{type: :indicator_ref, name: :macd, component: :signal}

      condition = %{type: :cross_above, indicator1: macd_ref, indicator2: signal_ref}
      assert ConditionEvaluator.evaluate(condition, context)
    end

    test "accesses previous component values for cross detection" do
      bb_current = %{
        upper_band: Decimal.new("110"),
        middle_band: Decimal.new("100"),
        lower_band: Decimal.new("90")
      }

      bb_previous = %{
        upper_band: Decimal.new("108"),
        middle_band: Decimal.new("98"),
        lower_band: Decimal.new("88")
      }

      context = %{
        indicators: %{bb: bb_current},
        historical_indicators: %{bb: [bb_previous]}
      }

      # Get previous middle band value
      middle_ref = %{type: :indicator_ref, name: :bb, component: :middle_band}
      previous_value = ConditionEvaluator.get_previous_indicator_value(middle_ref, context)

      assert previous_value == Decimal.new("98")
    end
  end

  describe "nil handling during warmup period" do
    test "comparison with nil indicator returns false (>)" do
      condition = {:>, [], [%{type: :indicator_ref, name: :rsi}, 30]}
      context = %{indicators: %{rsi: nil}, candles: []}

      refute ConditionEvaluator.evaluate(condition, context)
    end

    test "comparison with nil indicator returns false (<)" do
      condition = {:<, [], [%{type: :indicator_ref, name: :rsi}, 70]}
      context = %{indicators: %{rsi: nil}, candles: []}

      refute ConditionEvaluator.evaluate(condition, context)
    end

    test "comparison with nil indicator returns false (>=)" do
      condition = {:>=, [], [%{type: :indicator_ref, name: :rsi}, 50]}
      context = %{indicators: %{rsi: nil}, candles: []}

      refute ConditionEvaluator.evaluate(condition, context)
    end

    test "comparison with nil indicator returns false (<=)" do
      condition = {:<=, [], [%{type: :indicator_ref, name: :rsi}, 50]}
      context = %{indicators: %{rsi: nil}, candles: []}

      refute ConditionEvaluator.evaluate(condition, context)
    end

    test "comparison with nil indicator returns false (==)" do
      condition = {:==, [], [%{type: :indicator_ref, name: :rsi}, 50]}
      context = %{indicators: %{rsi: nil}, candles: []}

      refute ConditionEvaluator.evaluate(condition, context)
    end

    test "comparison with nil indicator returns false (!=)" do
      condition = {:!=, [], [%{type: :indicator_ref, name: :rsi}, 50]}
      context = %{indicators: %{rsi: nil}, candles: []}

      refute ConditionEvaluator.evaluate(condition, context)
    end

    test "when_all with nil indicator returns false" do
      condition = %{
        type: :when_all,
        conditions: [
          {:>, [], [%{type: :indicator_ref, name: :rsi}, 30]},
          {:>, [], [%{type: :indicator_ref, name: :sma}, 100]}
        ]
      }

      # RSI is nil (warmup), SMA has value
      context = %{indicators: %{rsi: nil, sma: Decimal.new("110")}, candles: []}

      refute ConditionEvaluator.evaluate(condition, context)
    end

    test "when_any with nil indicator but other condition true still returns true" do
      condition = %{
        type: :when_any,
        conditions: [
          {:>, [], [%{type: :indicator_ref, name: :rsi}, 70]},
          {:>, [], [%{type: :indicator_ref, name: :sma}, 100]}
        ]
      }

      # RSI is nil (warmup), but SMA condition is true
      context = %{indicators: %{rsi: nil, sma: Decimal.new("110")}, candles: []}

      assert ConditionEvaluator.evaluate(condition, context)
    end

    test "cross detection with nil indicators returns false" do
      condition = %{
        type: :cross_above,
        indicator1: :fast,
        indicator2: :slow
      }

      # Current fast is nil (warmup)
      context = %{
        indicators: %{fast: nil, slow: Decimal.new("100")},
        historical_indicators: %{fast: [nil], slow: [Decimal.new("100")]},
        candles: []
      }

      refute ConditionEvaluator.evaluate(condition, context)
    end

    test "multi-value indicator with nil returns nil" do
      context = %{indicators: %{macd: nil}}

      macd_ref = %{type: :indicator_ref, name: :macd, component: :histogram}
      assert ConditionEvaluator.get_indicator_value(macd_ref, context) == nil
    end
  end
end
