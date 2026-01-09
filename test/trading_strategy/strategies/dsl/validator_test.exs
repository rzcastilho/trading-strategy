defmodule TradingStrategy.Strategies.DSL.ValidatorTest do
  use ExUnit.Case, async: true

  alias TradingStrategy.Strategies.DSL.Validator

  describe "validate/1 - complete strategy validation" do
    test "validates a complete valid strategy" do
      strategy = %{
        "name" => "RSI Mean Reversion",
        "trading_pair" => "BTC/USD",
        "timeframe" => "1h",
        "indicators" => [
          %{
            "type" => "rsi",
            "name" => "rsi_14",
            "parameters" => %{"period" => 14}
          }
        ],
        "entry_conditions" => "rsi_14 < 30",
        "exit_conditions" => "rsi_14 > 70",
        "stop_conditions" => "rsi_14 < 25",
        "position_sizing" => %{
          "type" => "percentage",
          "percentage_of_capital" => 0.10,
          "max_position_size" => 0.25
        },
        "risk_parameters" => %{
          "max_daily_loss" => 0.03,
          "max_drawdown" => 0.15
        }
      }

      assert {:ok, ^strategy} = Validator.validate(strategy)
    end

    test "returns errors for missing required fields" do
      strategy = %{
        "name" => "Test Strategy"
      }

      assert {:error, errors} = Validator.validate(strategy)
      assert is_list(errors)
      assert length(errors) > 0
      assert Enum.any?(errors, &String.contains?(&1, "Missing required fields"))
    end

    test "returns error for non-map input" do
      assert {:error, ["Strategy must be a map"]} = Validator.validate("not a map")
      assert {:error, ["Strategy must be a map"]} = Validator.validate(nil)
      assert {:error, ["Strategy must be a map"]} = Validator.validate([])
    end
  end

  describe "validate/1 - name validation" do
    setup do
      base_strategy = %{
        "name" => "Valid Name",
        "trading_pair" => "BTC/USD",
        "timeframe" => "1h",
        "indicators" => [],
        "entry_conditions" => "close > 100",
        "exit_conditions" => "close < 90",
        "stop_conditions" => "close < 85",
        "position_sizing" => %{"type" => "percentage", "percentage_of_capital" => 0.10},
        "risk_parameters" => %{"max_daily_loss" => 0.03, "max_drawdown" => 0.15}
      }

      {:ok, base_strategy: base_strategy}
    end

    test "accepts valid name", %{base_strategy: strategy} do
      assert {:ok, _} = Validator.validate(strategy)
    end

    test "rejects empty name", %{base_strategy: strategy} do
      strategy = Map.put(strategy, "name", "")

      assert {:error, errors} = Validator.validate(strategy)
      assert Enum.any?(errors, &String.contains?(&1, "Name must be at least 1 character"))
    end

    test "rejects name longer than 100 characters", %{base_strategy: strategy} do
      long_name = String.duplicate("a", 101)
      strategy = Map.put(strategy, "name", long_name)

      assert {:error, errors} = Validator.validate(strategy)
      assert Enum.any?(errors, &String.contains?(&1, "Name must be at most 100 characters"))
    end

    test "rejects non-string name", %{base_strategy: strategy} do
      strategy = Map.put(strategy, "name", 123)

      assert {:error, errors} = Validator.validate(strategy)
      assert Enum.any?(errors, &String.contains?(&1, "Name must be a string"))
    end
  end

  describe "validate/1 - trading pair validation" do
    setup do
      base_strategy = %{
        "name" => "Test",
        "trading_pair" => "BTC/USD",
        "timeframe" => "1h",
        "indicators" => [],
        "entry_conditions" => "close > 100",
        "exit_conditions" => "close < 90",
        "stop_conditions" => "close < 85",
        "position_sizing" => %{"type" => "percentage", "percentage_of_capital" => 0.10},
        "risk_parameters" => %{"max_daily_loss" => 0.03, "max_drawdown" => 0.15}
      }

      {:ok, base_strategy: base_strategy}
    end

    test "accepts valid trading pairs", %{base_strategy: strategy} do
      valid_pairs = ["BTC/USD", "ETH/BTC", "ADA/USDT", "DOT/EUR"]

      for pair <- valid_pairs do
        strategy = Map.put(strategy, "trading_pair", pair)
        assert {:ok, _} = Validator.validate(strategy)
      end
    end

    test "rejects invalid trading pair format", %{base_strategy: strategy} do
      invalid_pairs = ["BTCUSD", "BTC-USD", "BTC", "/USD", "BTC/"]

      for pair <- invalid_pairs do
        strategy = Map.put(strategy, "trading_pair", pair)
        assert {:error, errors} = Validator.validate(strategy)
        assert Enum.any?(errors, &String.contains?(&1, "Trading pair must be in format"))
      end
    end
  end

  describe "validate/1 - timeframe validation" do
    setup do
      base_strategy = %{
        "name" => "Test",
        "trading_pair" => "BTC/USD",
        "timeframe" => "1h",
        "indicators" => [],
        "entry_conditions" => "close > 100",
        "exit_conditions" => "close < 90",
        "stop_conditions" => "close < 85",
        "position_sizing" => %{"type" => "percentage", "percentage_of_capital" => 0.10},
        "risk_parameters" => %{"max_daily_loss" => 0.03, "max_drawdown" => 0.15}
      }

      {:ok, base_strategy: base_strategy}
    end

    test "accepts valid timeframes", %{base_strategy: strategy} do
      valid_timeframes = ["1m", "5m", "15m", "1h", "4h", "1d"]

      for timeframe <- valid_timeframes do
        strategy = Map.put(strategy, "timeframe", timeframe)
        assert {:ok, _} = Validator.validate(strategy)
      end
    end

    test "rejects invalid timeframe", %{base_strategy: strategy} do
      strategy = Map.put(strategy, "timeframe", "2h")

      assert {:error, errors} = Validator.validate(strategy)
      assert Enum.any?(errors, &String.contains?(&1, "Invalid timeframe"))
    end
  end

  describe "validate/1 - position sizing validation" do
    setup do
      base_strategy = %{
        "name" => "Test",
        "trading_pair" => "BTC/USD",
        "timeframe" => "1h",
        "indicators" => [],
        "entry_conditions" => "close > 100",
        "exit_conditions" => "close < 90",
        "stop_conditions" => "close < 85",
        "position_sizing" => %{"type" => "percentage", "percentage_of_capital" => 0.10},
        "risk_parameters" => %{"max_daily_loss" => 0.03, "max_drawdown" => 0.15}
      }

      {:ok, base_strategy: base_strategy}
    end

    test "accepts valid percentage sizing", %{base_strategy: strategy} do
      sizing = %{
        "type" => "percentage",
        "percentage_of_capital" => 0.10,
        "max_position_size" => 0.25
      }

      strategy = Map.put(strategy, "position_sizing", sizing)
      assert {:ok, _} = Validator.validate(strategy)
    end

    test "accepts valid fixed_amount sizing", %{base_strategy: strategy} do
      sizing = %{
        "type" => "fixed_amount",
        "fixed_amount" => 1000.0
      }

      strategy = Map.put(strategy, "position_sizing", sizing)
      assert {:ok, _} = Validator.validate(strategy)
    end

    test "rejects percentage sizing without percentage_of_capital", %{base_strategy: strategy} do
      sizing = %{"type" => "percentage"}

      strategy = Map.put(strategy, "position_sizing", sizing)

      assert {:error, errors} = Validator.validate(strategy)
      assert Enum.any?(errors, &String.contains?(&1, "percentage_of_capital is required"))
    end

    test "rejects percentage out of range", %{base_strategy: strategy} do
      sizing = %{
        "type" => "percentage",
        "percentage_of_capital" => 1.5
      }

      strategy = Map.put(strategy, "position_sizing", sizing)

      assert {:error, errors} = Validator.validate(strategy)
      assert Enum.any?(errors, &String.contains?(&1, "percentage_of_capital must be at most"))
    end

    test "rejects invalid sizing type", %{base_strategy: strategy} do
      sizing = %{
        "type" => "invalid_type",
        "percentage_of_capital" => 0.10
      }

      strategy = Map.put(strategy, "position_sizing", sizing)

      assert {:error, errors} = Validator.validate(strategy)
      assert Enum.any?(errors, &String.contains?(&1, "Invalid position sizing type"))
    end
  end

  describe "validate/1 - indicator validation integration" do
    setup do
      base_strategy = %{
        "name" => "Test",
        "trading_pair" => "BTC/USD",
        "timeframe" => "1h",
        "indicators" => [],
        "entry_conditions" => "close > 100",
        "exit_conditions" => "close < 90",
        "stop_conditions" => "close < 85",
        "position_sizing" => %{"type" => "percentage", "percentage_of_capital" => 0.10},
        "risk_parameters" => %{"max_daily_loss" => 0.03, "max_drawdown" => 0.15}
      }

      {:ok, base_strategy: base_strategy}
    end

    test "accepts strategy with valid indicators", %{base_strategy: strategy} do
      indicators = [
        %{"type" => "rsi", "name" => "rsi_14", "parameters" => %{"period" => 14}},
        %{"type" => "sma", "name" => "sma_50", "parameters" => %{"period" => 50}}
      ]

      strategy = Map.put(strategy, "indicators", indicators)
      assert {:ok, _} = Validator.validate(strategy)
    end

    test "rejects duplicate indicator names", %{base_strategy: strategy} do
      indicators = [
        %{"type" => "rsi", "name" => "rsi_14", "parameters" => %{"period" => 14}},
        %{"type" => "sma", "name" => "rsi_14", "parameters" => %{"period" => 50}}
      ]

      strategy = Map.put(strategy, "indicators", indicators)

      assert {:error, errors} = Validator.validate(strategy)
      assert Enum.any?(errors, &String.contains?(&1, "Duplicate indicator names"))
    end
  end

  describe "validate/1 - condition validation integration" do
    setup do
      base_strategy = %{
        "name" => "Test",
        "trading_pair" => "BTC/USD",
        "timeframe" => "1h",
        "indicators" => [
          %{"type" => "rsi", "name" => "rsi_14", "parameters" => %{"period" => 14}}
        ],
        "entry_conditions" => "rsi_14 < 30",
        "exit_conditions" => "rsi_14 > 70",
        "stop_conditions" => "rsi_14 < 25",
        "position_sizing" => %{"type" => "percentage", "percentage_of_capital" => 0.10},
        "risk_parameters" => %{"max_daily_loss" => 0.03, "max_drawdown" => 0.15}
      }

      {:ok, base_strategy: base_strategy}
    end

    test "accepts valid conditions with defined indicators", %{base_strategy: strategy} do
      assert {:ok, _} = Validator.validate(strategy)
    end

    test "rejects conditions referencing undefined indicators", %{base_strategy: strategy} do
      strategy = Map.put(strategy, "entry_conditions", "undefined_indicator < 30")

      assert {:error, errors} = Validator.validate(strategy)
      assert Enum.any?(errors, &String.contains?(&1, "Undefined variable"))
    end

    test "accepts conditions with reserved variables", %{base_strategy: strategy} do
      strategy = Map.put(strategy, "entry_conditions", "close > 100 AND rsi_14 < 30")

      assert {:ok, _} = Validator.validate(strategy)
    end
  end

  describe "validate/1 - risk parameters validation integration" do
    setup do
      base_strategy = %{
        "name" => "Test",
        "trading_pair" => "BTC/USD",
        "timeframe" => "1h",
        "indicators" => [],
        "entry_conditions" => "close > 100",
        "exit_conditions" => "close < 90",
        "stop_conditions" => "close < 85",
        "position_sizing" => %{"type" => "percentage", "percentage_of_capital" => 0.10},
        "risk_parameters" => %{"max_daily_loss" => 0.03, "max_drawdown" => 0.15}
      }

      {:ok, base_strategy: base_strategy}
    end

    test "accepts conservative risk parameters", %{base_strategy: strategy} do
      assert {:ok, _} = Validator.validate(strategy)
    end

    test "warns on aggressive risk parameters", %{base_strategy: strategy} do
      risk_params = %{
        "max_daily_loss" => 0.10,
        "max_drawdown" => 0.25
      }

      strategy = Map.put(strategy, "risk_parameters", risk_params)

      assert {:error, errors} = Validator.validate(strategy)
      assert Enum.any?(errors, &String.contains?(&1, "Warning"))
      assert Enum.any?(errors, &String.contains?(&1, "30%"))
    end

    test "rejects missing required risk parameters", %{base_strategy: strategy} do
      strategy = Map.put(strategy, "risk_parameters", %{})

      assert {:error, errors} = Validator.validate(strategy)
      assert Enum.any?(errors, &String.contains?(&1, "max_daily_loss"))
      assert Enum.any?(errors, &String.contains?(&1, "max_drawdown"))
    end
  end
end
