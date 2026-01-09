defmodule TradingStrategy.Strategies.SignalEvaluatorTest do
  use ExUnit.Case, async: true
  alias TradingStrategy.Strategies.SignalEvaluator

  setup do
    strategy = %{
      "name" => "Test Strategy",
      "indicators" => [
        %{"name" => "rsi_14", "type" => "rsi", "parameters" => %{"period" => 14}},
        %{"name" => "sma_50", "type" => "sma", "parameters" => %{"period" => 50}}
      ],
      "entry_conditions" => "rsi_14 < 30 AND close > sma_50",
      "exit_conditions" => "rsi_14 > 70",
      "stop_conditions" => "rsi_14 < 25"
    }

    current_bar = %{
      "timestamp" => ~U[2024-01-01 00:00:00Z],
      "open" => Decimal.new("42000"),
      "high" => Decimal.new("42500"),
      "low" => Decimal.new("41800"),
      "close" => Decimal.new("42200"),
      "volume" => Decimal.new("1000"),
      "symbol" => "BTC/USD"
    }

    market_data = generate_sample_data(60)

    %{
      strategy: strategy,
      current_bar: current_bar,
      market_data: market_data
    }
  end

  describe "evaluate_signals/4" do
    test "evaluates entry signal when conditions met", %{
      strategy: strategy,
      current_bar: bar,
      market_data: data
    } do
      # Pre-calculated indicator values showing entry condition met
      indicator_values = %{
        # < 30 (oversold)
        "rsi_14" => 25.0,
        # < close (42200)
        "sma_50" => 41000.0
      }

      assert {:ok, result} =
               SignalEvaluator.evaluate_signals(strategy, data, bar, indicator_values)

      assert result.entry == true
      assert result.exit == false
      assert result.stop == false
      assert is_map(result.context)
      assert result.timestamp == ~U[2024-01-01 00:00:00Z]
    end

    test "evaluates exit signal when conditions met", %{
      strategy: strategy,
      current_bar: bar,
      market_data: data
    } do
      indicator_values = %{
        # > 70 (overbought)
        "rsi_14" => 75.0,
        "sma_50" => 41000.0
      }

      assert {:ok, result} =
               SignalEvaluator.evaluate_signals(strategy, data, bar, indicator_values)

      assert result.entry == false
      assert result.exit == true
      assert result.stop == false
    end

    test "evaluates stop signal when conditions met", %{
      strategy: strategy,
      current_bar: bar,
      market_data: data
    } do
      indicator_values = %{
        # < 25 (extreme oversold)
        "rsi_14" => 20.0,
        "sma_50" => 41000.0
      }

      assert {:ok, result} =
               SignalEvaluator.evaluate_signals(strategy, data, bar, indicator_values)

      assert result.entry == false
      assert result.exit == false
      assert result.stop == true
    end

    test "no signals when conditions not met", %{
      strategy: strategy,
      current_bar: bar,
      market_data: data
    } do
      indicator_values = %{
        # Neutral
        "rsi_14" => 50.0,
        "sma_50" => 41000.0
      }

      assert {:ok, result} =
               SignalEvaluator.evaluate_signals(strategy, data, bar, indicator_values)

      assert result.entry == false
      assert result.exit == false
      assert result.stop == false
    end

    test "includes context with indicator values", %{
      strategy: strategy,
      current_bar: bar,
      market_data: data
    } do
      indicator_values = %{
        "rsi_14" => 25.0,
        "sma_50" => 41000.0
      }

      assert {:ok, result} =
               SignalEvaluator.evaluate_signals(strategy, data, bar, indicator_values)

      assert is_map(result.context)
      assert result.context["rsi_14"] == 25.0
      assert result.context["sma_50"] == 41000.0
      assert result.context["close"] == 42200.0
      assert result.context["open"] == 42000.0
    end

    test "handles nil conditions as false", %{current_bar: bar, market_data: data} do
      strategy = %{
        "indicators" => [],
        "entry_conditions" => nil,
        "exit_conditions" => nil,
        "stop_conditions" => nil
      }

      indicator_values = %{}

      assert {:ok, result} =
               SignalEvaluator.evaluate_signals(strategy, data, bar, indicator_values)

      assert result.entry == false
      assert result.exit == false
      assert result.stop == false
    end

    test "returns error for invalid condition syntax", %{current_bar: bar, market_data: data} do
      strategy = %{
        "indicators" => [],
        # Invalid expression
        "entry_conditions" => "invalid syntax ((",
        "exit_conditions" => "true",
        "stop_conditions" => "false"
      }

      indicator_values = %{}

      assert {:error, _reason} =
               SignalEvaluator.evaluate_signals(strategy, data, bar, indicator_values)
    end
  end

  describe "generate_signal/4" do
    test "generates entry signal with full details" do
      evaluation_result = %{
        entry: true,
        exit: false,
        stop: false,
        context: %{
          "rsi_14" => 25.0,
          "sma_50" => 41000.0,
          "close" => 42200.0,
          "symbol" => "BTC/USD"
        },
        timestamp: ~U[2024-01-01 00:00:00Z]
      }

      assert {:ok, signal} =
               SignalEvaluator.generate_signal(
                 :entry,
                 "strategy-123",
                 "session-456",
                 evaluation_result
               )

      assert signal.signal_type == "entry"
      assert signal.strategy_id == "strategy-123"
      assert signal.session_id == "session-456"
      assert signal.timestamp == ~U[2024-01-01 00:00:00Z]
      assert signal.price_at_signal == 42200.0
      assert signal.trading_pair == "BTC/USD"
      assert is_map(signal.trigger_conditions)
      assert is_map(signal.indicator_values)
    end

    test "generates exit signal" do
      evaluation_result = %{
        entry: false,
        exit: true,
        stop: false,
        context: %{"close" => 43000.0, "symbol" => "BTC/USD"},
        timestamp: ~U[2024-01-02 00:00:00Z]
      }

      assert {:ok, signal} =
               SignalEvaluator.generate_signal(
                 :exit,
                 "strategy-123",
                 "session-456",
                 evaluation_result
               )

      assert signal.signal_type == "exit"
      assert signal.price_at_signal == 43000.0
    end

    test "generates stop signal" do
      evaluation_result = %{
        entry: false,
        exit: false,
        stop: true,
        context: %{"close" => 40000.0, "symbol" => "BTC/USD"},
        timestamp: ~U[2024-01-03 00:00:00Z]
      }

      assert {:ok, signal} =
               SignalEvaluator.generate_signal(
                 :stop,
                 "strategy-123",
                 "session-456",
                 evaluation_result
               )

      assert signal.signal_type == "stop"
      assert signal.price_at_signal == 40000.0
    end

    test "returns error when signal conditions not met" do
      evaluation_result = %{
        entry: false,
        exit: false,
        stop: false,
        context: %{"close" => 42000.0},
        timestamp: ~U[2024-01-01 00:00:00Z]
      }

      assert {:error, message} =
               SignalEvaluator.generate_signal(
                 :entry,
                 "strategy-123",
                 "session-456",
                 evaluation_result
               )

      assert message =~ "Signal conditions not met"
    end

    test "extracts only indicator values, not reserved variables" do
      evaluation_result = %{
        entry: true,
        exit: false,
        stop: false,
        context: %{
          "rsi_14" => 25.0,
          "sma_50" => 41000.0,
          "macd" => 100.0,
          # Reserved, should be excluded
          "close" => 42200.0,
          # Reserved, should be excluded
          "open" => 42000.0,
          # Reserved, should be excluded
          "volume" => 1000.0,
          # Reserved, should be excluded
          "symbol" => "BTC/USD"
        },
        timestamp: ~U[2024-01-01 00:00:00Z]
      }

      {:ok, signal} =
        SignalEvaluator.generate_signal(
          :entry,
          "strategy-123",
          "session-456",
          evaluation_result
        )

      # Should only include indicators
      assert signal.indicator_values["rsi_14"] == 25.0
      assert signal.indicator_values["sma_50"] == 41000.0
      assert signal.indicator_values["macd"] == 100.0

      # Should not include reserved variables
      refute Map.has_key?(signal.indicator_values, "close")
      refute Map.has_key?(signal.indicator_values, "open")
      refute Map.has_key?(signal.indicator_values, "volume")
      refute Map.has_key?(signal.indicator_values, "symbol")
    end
  end

  describe "validate_conditions/1" do
    test "validates strategy with correct indicator references" do
      strategy = %{
        "indicators" => [
          %{"name" => "rsi_14"},
          %{"name" => "sma_50"}
        ],
        "entry_conditions" => "rsi_14 < 30",
        "exit_conditions" => "rsi_14 > 70",
        "stop_conditions" => "rsi_14 < 25"
      }

      assert :ok = SignalEvaluator.validate_conditions(strategy)
    end

    test "returns error for undefined indicator in entry conditions" do
      strategy = %{
        "indicators" => [
          %{"name" => "rsi_14"}
        ],
        # Not defined
        "entry_conditions" => "undefined_indicator < 30",
        "exit_conditions" => "rsi_14 > 70",
        "stop_conditions" => "rsi_14 < 25"
      }

      assert {:error, errors} = SignalEvaluator.validate_conditions(strategy)
      assert is_list(errors)
      assert length(errors) > 0
      assert Enum.any?(errors, fn err -> String.contains?(err, "undefined_indicator") end)
    end

    test "allows reserved variables in conditions" do
      strategy = %{
        "indicators" => [
          %{"name" => "sma_50"}
        ],
        # 'close' is reserved, should be allowed
        "entry_conditions" => "close > sma_50",
        "exit_conditions" => "close < sma_50",
        "stop_conditions" => "false"
      }

      assert :ok = SignalEvaluator.validate_conditions(strategy)
    end

    test "validates multiple indicators in complex conditions" do
      strategy = %{
        "indicators" => [
          %{"name" => "rsi_14"},
          %{"name" => "sma_50"},
          %{"name" => "ema_20"}
        ],
        "entry_conditions" => "rsi_14 < 30 AND close > sma_50 AND ema_20 > sma_50",
        "exit_conditions" => "rsi_14 > 70 OR close < sma_50",
        "stop_conditions" => "rsi_14 < 25"
      }

      assert :ok = SignalEvaluator.validate_conditions(strategy)
    end

    test "handles empty indicators list" do
      strategy = %{
        "indicators" => [],
        # Only uses reserved variables
        "entry_conditions" => "close > 42000",
        "exit_conditions" => "close < 40000",
        "stop_conditions" => "false"
      }

      assert :ok = SignalEvaluator.validate_conditions(strategy)
    end
  end

  describe "detect_conflicts/1" do
    test "detects entry and exit conflict" do
      result = %{entry: true, exit: true, stop: false}

      assert {:error, message} = SignalEvaluator.detect_conflicts(result)
      assert message =~ "entry and exit"
    end

    test "detects entry and stop conflict" do
      result = %{entry: true, exit: false, stop: true}

      assert {:error, message} = SignalEvaluator.detect_conflicts(result)
      assert message =~ "entry and stop"
    end

    test "allows exit and stop simultaneously (exit takes precedence)" do
      result = %{entry: false, exit: true, stop: true}

      # Exit and stop can both be true (exit is handled first)
      assert :ok = SignalEvaluator.detect_conflicts(result)
    end

    test "no conflict when only one signal true" do
      assert :ok = SignalEvaluator.detect_conflicts(%{entry: true, exit: false, stop: false})
      assert :ok = SignalEvaluator.detect_conflicts(%{entry: false, exit: true, stop: false})
      assert :ok = SignalEvaluator.detect_conflicts(%{entry: false, exit: false, stop: true})
    end

    test "no conflict when no signals" do
      result = %{entry: false, exit: false, stop: false}

      assert :ok = SignalEvaluator.detect_conflicts(result)
    end
  end

  # Helper Functions

  defp generate_sample_data(count) do
    Enum.map(1..count, fn i ->
      %{
        "timestamp" => DateTime.add(~U[2024-01-01 00:00:00Z], i * 3600, :second),
        "open" => Decimal.from_float(42000.0 + :rand.uniform(1000) - 500),
        "high" => Decimal.from_float(42500.0 + :rand.uniform(1000) - 500),
        "low" => Decimal.from_float(41500.0 + :rand.uniform(1000) - 500),
        "close" => Decimal.from_float(42000.0 + :rand.uniform(1000) - 500),
        "volume" => Decimal.from_float(1000.0 + :rand.uniform(500)),
        "symbol" => "BTC/USD"
      }
    end)
  end
end
