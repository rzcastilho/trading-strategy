defmodule TradingStrategy.DSLTest do
  use ExUnit.Case, async: true
  alias TradingStrategy.Definition

  # Test strategy using the DSL
  defmodule TestStrategy do
    use TradingStrategy.DSL

    defstrategy :test_ma_cross do
      description "Test MA crossover strategy"

      indicator :sma_fast, TestIndicator, period: 10
      indicator :sma_slow, TestIndicator, period: 30

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

  defmodule ComplexStrategy do
    use TradingStrategy.DSL

    defstrategy :complex_strategy do
      description "Complex strategy with multiple conditions"

      indicator :rsi, TestIndicator, period: 14
      indicator :sma, TestIndicator, period: 20

      entry_signal :long do
        when_all do
          indicator(:rsi) > 30
          indicator(:rsi) < 70
          pattern(:hammer)
        end
      end

      entry_signal :short do
        when_any do
          indicator(:rsi) > 80
          pattern(:shooting_star)
        end
      end

      exit_signal do
        when_not do
          indicator(:rsi) > 50
        end
      end
    end
  end

  describe "defstrategy macro" do
    test "creates a strategy_definition/0 function" do
      assert function_exported?(TestStrategy, :strategy_definition, 0)
      definition = TestStrategy.strategy_definition()
      assert %Definition{} = definition
    end

    test "creates a name/0 function" do
      assert function_exported?(TestStrategy, :name, 0)
      assert TestStrategy.name() == :test_ma_cross
    end

    test "sets the strategy name" do
      definition = TestStrategy.strategy_definition()
      assert definition.name == :test_ma_cross
    end

    test "sets the description" do
      definition = TestStrategy.strategy_definition()
      assert definition.description == "Test MA crossover strategy"
    end
  end

  describe "indicator macro" do
    test "adds indicators to the definition" do
      definition = TestStrategy.strategy_definition()
      assert map_size(definition.indicators) == 2
      assert Map.has_key?(definition.indicators, :sma_fast)
      assert Map.has_key?(definition.indicators, :sma_slow)
    end

    test "stores indicator configuration" do
      definition = TestStrategy.strategy_definition()
      sma_fast = definition.indicators[:sma_fast]

      assert sma_fast.name == :sma_fast
      assert sma_fast.module == TestIndicator
      assert sma_fast.params == [period: 10]
    end
  end

  describe "entry_signal macro" do
    test "adds entry signals to the definition" do
      definition = TestStrategy.strategy_definition()
      assert length(definition.entry_signals) == 1
    end

    test "sets signal direction" do
      definition = TestStrategy.strategy_definition()
      signal = hd(definition.entry_signals)
      assert signal.direction == :long
    end

    test "compiles conditions" do
      definition = TestStrategy.strategy_definition()
      signal = hd(definition.entry_signals)
      assert is_map(signal.condition)
    end

    test "supports multiple entry signals" do
      definition = ComplexStrategy.strategy_definition()
      assert length(definition.entry_signals) == 2

      directions = Enum.map(definition.entry_signals, & &1.direction)
      assert :long in directions
      assert :short in directions
    end
  end

  describe "exit_signal macro" do
    test "adds exit signals to the definition" do
      definition = TestStrategy.strategy_definition()
      assert length(definition.exit_signals) == 1
    end

    test "compiles exit conditions" do
      definition = TestStrategy.strategy_definition()
      signal = hd(definition.exit_signals)
      assert is_map(signal.condition)
    end
  end

  describe "when_all macro" do
    test "creates AND condition structure" do
      definition = TestStrategy.strategy_definition()
      signal = hd(definition.entry_signals)
      assert signal.condition.type == :when_all
      assert is_list(signal.condition.conditions)
    end
  end

  describe "when_any macro" do
    test "creates OR condition structure" do
      definition = ComplexStrategy.strategy_definition()
      short_signal = Enum.find(definition.entry_signals, &(&1.direction == :short))
      assert short_signal.condition.type == :when_any
    end
  end

  describe "when_not macro" do
    test "creates NOT condition structure" do
      definition = ComplexStrategy.strategy_definition()
      exit_signal = hd(definition.exit_signals)
      assert exit_signal.condition.type == :when_not
    end
  end

  describe "cross_above macro" do
    test "creates cross_above condition" do
      definition = TestStrategy.strategy_definition()
      signal = hd(definition.entry_signals)
      condition = hd(signal.condition.conditions)

      assert condition.type == :cross_above
      assert condition.indicator1 == :sma_fast
      assert condition.indicator2 == :sma_slow
    end
  end

  describe "cross_below macro" do
    test "creates cross_below condition" do
      definition = TestStrategy.strategy_definition()
      exit_signal = hd(definition.exit_signals)

      assert exit_signal.condition.type == :cross_below
      assert exit_signal.condition.indicator1 == :sma_fast
      assert exit_signal.condition.indicator2 == :sma_slow
    end
  end

  describe "indicator macro (in conditions)" do
    test "creates indicator reference" do
      definition = ComplexStrategy.strategy_definition()
      long_signal = Enum.find(definition.entry_signals, &(&1.direction == :long))

      # The conditions should be AST nodes that reference indicators
      assert is_list(long_signal.condition.conditions)
    end
  end

  describe "pattern macro" do
    test "creates pattern condition" do
      definition = ComplexStrategy.strategy_definition()
      long_signal = Enum.find(definition.entry_signals, &(&1.direction == :long))

      # Find the pattern condition in the list
      pattern_condition = Enum.find(long_signal.condition.conditions, fn cond ->
        is_map(cond) && Map.get(cond, :type) == :pattern
      end)

      assert pattern_condition
      assert pattern_condition.type == :pattern
      assert pattern_condition.name == :hammer
    end
  end
end

defmodule TestIndicator do
  def calculate(_data, _params), do: Decimal.new("0")
end
