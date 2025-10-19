defmodule TradingStrategy.DefinitionTest do
  use ExUnit.Case, async: true
  alias TradingStrategy.Definition

  describe "new/2" do
    test "creates a new strategy definition with name" do
      definition = Definition.new(:my_strategy)

      assert definition.name == :my_strategy
      assert definition.description == ""
      assert definition.indicators == %{}
      assert definition.entry_signals == []
      assert definition.exit_signals == []
      assert definition.timeframes == ["1h"]
    end

    test "accepts options" do
      definition =
        Definition.new(:my_strategy,
          description: "Test strategy",
          timeframes: ["1h", "4h"],
          parameters: %{risk: 0.02},
          metadata: %{author: "Test"}
        )

      assert definition.description == "Test strategy"
      assert definition.timeframes == ["1h", "4h"]
      assert definition.parameters == %{risk: 0.02}
      assert definition.metadata == %{author: "Test"}
    end
  end

  describe "add_indicator/4" do
    test "adds an indicator to the strategy" do
      definition =
        Definition.new(:test)
        |> Definition.add_indicator(:sma, TestIndicator, period: 20)

      assert Map.has_key?(definition.indicators, :sma)
      assert definition.indicators[:sma].name == :sma
      assert definition.indicators[:sma].module == TestIndicator
      assert definition.indicators[:sma].params == [period: 20]
    end

    test "adds multiple indicators" do
      definition =
        Definition.new(:test)
        |> Definition.add_indicator(:sma_fast, TestIndicator, period: 10)
        |> Definition.add_indicator(:sma_slow, TestIndicator, period: 30)
        |> Definition.add_indicator(:rsi, TestIndicator, period: 14)

      assert map_size(definition.indicators) == 3
      assert Map.has_key?(definition.indicators, :sma_fast)
      assert Map.has_key?(definition.indicators, :sma_slow)
      assert Map.has_key?(definition.indicators, :rsi)
    end

    test "overwrites indicator with same name" do
      definition =
        Definition.new(:test)
        |> Definition.add_indicator(:sma, TestIndicator, period: 20)
        |> Definition.add_indicator(:sma, TestIndicator, period: 50)

      assert map_size(definition.indicators) == 1
      assert definition.indicators[:sma].params == [period: 50]
    end
  end

  describe "add_entry_signal/3" do
    test "adds an entry signal" do
      condition = %{type: :when_all, conditions: []}

      definition =
        Definition.new(:test)
        |> Definition.add_entry_signal(:long, condition)

      assert length(definition.entry_signals) == 1
      assert hd(definition.entry_signals).direction == :long
      assert hd(definition.entry_signals).condition == condition
    end

    test "adds multiple entry signals" do
      long_condition = %{type: :when_all, conditions: []}
      short_condition = %{type: :when_any, conditions: []}

      definition =
        Definition.new(:test)
        |> Definition.add_entry_signal(:long, long_condition)
        |> Definition.add_entry_signal(:short, short_condition)

      assert length(definition.entry_signals) == 2
    end
  end

  describe "add_exit_signal/2" do
    test "adds an exit signal" do
      condition = %{type: :when_all, conditions: []}

      definition =
        Definition.new(:test)
        |> Definition.add_exit_signal(condition)

      assert length(definition.exit_signals) == 1
      assert hd(definition.exit_signals).condition == condition
    end

    test "adds multiple exit signals" do
      condition1 = %{type: :when_all, conditions: []}
      condition2 = %{type: :when_any, conditions: []}

      definition =
        Definition.new(:test)
        |> Definition.add_exit_signal(condition1)
        |> Definition.add_exit_signal(condition2)

      assert length(definition.exit_signals) == 2
    end
  end

  describe "validate/1" do
    test "validates a complete strategy definition" do
      definition =
        Definition.new(:test)
        |> Definition.add_indicator(:sma, TestIndicator, period: 20)
        |> Definition.add_entry_signal(:long, %{type: :when_all, conditions: []})

      assert {:ok, ^definition} = Definition.validate(definition)
    end

    test "fails validation with invalid name" do
      definition = %Definition{name: nil}
      assert {:error, :invalid_name} = Definition.validate(definition)
    end

    test "fails validation without indicators" do
      definition = Definition.new(:test)
      assert {:error, :no_indicators_defined} = Definition.validate(definition)
    end

    test "fails validation without entry signals" do
      definition =
        Definition.new(:test)
        |> Definition.add_indicator(:sma, TestIndicator, period: 20)

      assert {:error, :no_entry_signals_defined} = Definition.validate(definition)
    end

    test "passes validation without exit signals" do
      definition =
        Definition.new(:test)
        |> Definition.add_indicator(:sma, TestIndicator, period: 20)
        |> Definition.add_entry_signal(:long, %{type: :when_all, conditions: []})

      assert {:ok, ^definition} = Definition.validate(definition)
    end
  end
end

defmodule TestIndicator do
  def calculate(_data, _params), do: Decimal.new("0")
end
