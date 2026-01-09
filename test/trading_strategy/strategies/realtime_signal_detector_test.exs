defmodule TradingStrategy.Strategies.RealtimeSignalDetectorTest do
  use ExUnit.Case, async: true

  alias TradingStrategy.Strategies.RealtimeSignalDetector

  @moduletag :capture_log

  setup do
    strategy = %{
      "name" => "Test RSI Strategy",
      "indicators" => [
        %{"name" => "rsi_14", "type" => "rsi", "parameters" => %{"period" => 14}},
        %{"name" => "sma_50", "type" => "sma", "parameters" => %{"period" => 50}}
      ],
      "entry_conditions" => "rsi_14 < 30 AND close > sma_50",
      "exit_conditions" => "rsi_14 > 70",
      "stop_conditions" => "rsi_14 < 25"
    }

    current_bar = %{
      timestamp: ~U[2025-12-04 12:00:00Z],
      open: Decimal.new("42000.00"),
      high: Decimal.new("42500.00"),
      low: Decimal.new("41800.00"),
      close: Decimal.new("42200.00"),
      volume: Decimal.new("1000.00"),
      symbol: "BTC/USD"
    }

    %{
      strategy: strategy,
      current_bar: current_bar
    }
  end

  describe "start_link/1" do
    test "starts the detector GenServer", %{strategy: strategy} do
      assert {:ok, pid} =
               RealtimeSignalDetector.start_link(
                 strategy: strategy,
                 symbol: "BTC/USD"
               )

      assert Process.alive?(pid)

      # Cleanup
      GenServer.stop(pid)
    end

    test "starts with a custom name", %{strategy: strategy} do
      name = :test_detector

      assert {:ok, pid} =
               RealtimeSignalDetector.start_link(
                 strategy: strategy,
                 symbol: "BTC/USD",
                 name: name
               )

      assert Process.whereis(name) == pid

      # Cleanup
      GenServer.stop(pid)
    end

    test "requires strategy parameter" do
      assert_raise KeyError, fn ->
        RealtimeSignalDetector.start_link(symbol: "BTC/USD")
      end
    end

    test "requires symbol parameter", %{strategy: strategy} do
      assert_raise KeyError, fn ->
        RealtimeSignalDetector.start_link(strategy: strategy)
      end
    end
  end

  describe "evaluate/3" do
    setup %{strategy: strategy, current_bar: bar} do
      {:ok, detector} =
        RealtimeSignalDetector.start_link(
          strategy: strategy,
          symbol: "BTC/USD"
        )

      on_exit(fn -> GenServer.stop(detector) end)

      %{detector: detector, bar: bar}
    end

    test "evaluates entry signal when conditions met", %{detector: detector, bar: bar} do
      indicator_values = %{
        "rsi_14" => 25.0,
        "sma_50" => 41000.0
      }

      assert {:ok, signals} = RealtimeSignalDetector.evaluate(detector, indicator_values, bar)

      assert signals.entry == true
      assert signals.exit == false
      assert signals.stop == false
      assert signals.symbol == "BTC/USD"
      assert signals.timestamp == ~U[2025-12-04 12:00:00Z]
      assert is_map(signals.context)
    end

    test "evaluates exit signal when conditions met", %{detector: detector, bar: bar} do
      indicator_values = %{
        "rsi_14" => 75.0,
        "sma_50" => 41000.0
      }

      assert {:ok, signals} = RealtimeSignalDetector.evaluate(detector, indicator_values, bar)

      assert signals.entry == false
      assert signals.exit == true
      assert signals.stop == false
    end

    test "evaluates stop signal when conditions met", %{detector: detector, bar: bar} do
      indicator_values = %{
        "rsi_14" => 20.0,
        "sma_50" => 41000.0
      }

      assert {:ok, signals} = RealtimeSignalDetector.evaluate(detector, indicator_values, bar)

      assert signals.entry == false
      assert signals.exit == false
      assert signals.stop == true
    end

    test "returns no signals when conditions not met", %{detector: detector, bar: bar} do
      indicator_values = %{
        "rsi_14" => 50.0,
        "sma_50" => 41000.0
      }

      assert {:ok, signals} = RealtimeSignalDetector.evaluate(detector, indicator_values, bar)

      assert signals.entry == false
      assert signals.exit == false
      assert signals.stop == false
    end

    test "includes context with OHLCV data and indicators", %{detector: detector, bar: bar} do
      indicator_values = %{
        "rsi_14" => 25.0,
        "sma_50" => 41000.0
      }

      assert {:ok, signals} = RealtimeSignalDetector.evaluate(detector, indicator_values, bar)

      assert signals.context["close"] == 42200.0
      assert signals.context["open"] == 42000.0
      assert signals.context["high"] == 42500.0
      assert signals.context["low"] == 41800.0
      assert signals.context["volume"] == 1000.0
      assert signals.context["rsi_14"] == 25.0
      assert signals.context["sma_50"] == 41000.0
    end

    test "detects conflict when entry and exit both true", %{detector: detector, bar: bar} do
      # Create a strategy with conflicting conditions
      {:ok, conflicting_detector} =
        RealtimeSignalDetector.start_link(
          strategy: %{
            "indicators" => [],
            "entry_conditions" => "close > 42000",
            "exit_conditions" => "close > 42000",
            "stop_conditions" => "false"
          },
          symbol: "BTC/USD"
        )

      on_exit(fn -> GenServer.stop(conflicting_detector) end)

      indicator_values = %{}

      assert {:ok, signals} =
               RealtimeSignalDetector.evaluate(conflicting_detector, indicator_values, bar)

      assert Map.has_key?(signals, :conflict)
      assert signals.conflict =~ "entry and exit"
    end

    test "detects conflict when entry and stop both true", %{detector: detector, bar: bar} do
      {:ok, conflicting_detector} =
        RealtimeSignalDetector.start_link(
          strategy: %{
            "indicators" => [],
            "entry_conditions" => "close > 42000",
            "exit_conditions" => "false",
            "stop_conditions" => "close > 42000"
          },
          symbol: "BTC/USD"
        )

      on_exit(fn -> GenServer.stop(conflicting_detector) end)

      indicator_values = %{}

      assert {:ok, signals} =
               RealtimeSignalDetector.evaluate(conflicting_detector, indicator_values, bar)

      assert Map.has_key?(signals, :conflict)
      assert signals.conflict =~ "entry and stop"
    end

    test "handles invalid condition syntax", %{bar: bar} do
      {:ok, invalid_detector} =
        RealtimeSignalDetector.start_link(
          strategy: %{
            "indicators" => [],
            "entry_conditions" => "invalid syntax ((",
            "exit_conditions" => "false",
            "stop_conditions" => "false"
          },
          symbol: "BTC/USD"
        )

      on_exit(fn -> GenServer.stop(invalid_detector) end)

      indicator_values = %{}

      assert {:error, _reason} =
               RealtimeSignalDetector.evaluate(invalid_detector, indicator_values, bar)
    end
  end

  describe "subscribe/2 and signal notifications" do
    setup %{strategy: strategy, current_bar: bar} do
      {:ok, detector} =
        RealtimeSignalDetector.start_link(
          strategy: strategy,
          symbol: "BTC/USD"
        )

      on_exit(fn -> GenServer.stop(detector) end)

      %{detector: detector, bar: bar}
    end

    test "subscribes to signal notifications", %{detector: detector} do
      assert :ok = RealtimeSignalDetector.subscribe(detector)
    end

    test "receives entry signal notification", %{detector: detector, bar: bar} do
      RealtimeSignalDetector.subscribe(detector)

      indicator_values = %{
        "rsi_14" => 25.0,
        "sma_50" => 41000.0
      }

      RealtimeSignalDetector.evaluate(detector, indicator_values, bar)

      assert_receive {:signal_detected, :entry, signal_data}, 1000

      assert signal_data.signal_type == :entry
      assert signal_data.symbol == "BTC/USD"
      assert signal_data.price == 42200.0
      assert is_map(signal_data.indicator_values)
    end

    test "receives exit signal notification", %{detector: detector, bar: bar} do
      RealtimeSignalDetector.subscribe(detector)

      indicator_values = %{
        "rsi_14" => 75.0,
        "sma_50" => 41000.0
      }

      RealtimeSignalDetector.evaluate(detector, indicator_values, bar)

      assert_receive {:signal_detected, :exit, signal_data}, 1000
      assert signal_data.signal_type == :exit
    end

    test "receives stop signal notification", %{detector: detector, bar: bar} do
      RealtimeSignalDetector.subscribe(detector)

      indicator_values = %{
        "rsi_14" => 20.0,
        "sma_50" => 41000.0
      }

      RealtimeSignalDetector.evaluate(detector, indicator_values, bar)

      assert_receive {:signal_detected, :stop, signal_data}, 1000
      assert signal_data.signal_type == :stop
    end

    test "does not receive notification when no signals", %{detector: detector, bar: bar} do
      RealtimeSignalDetector.subscribe(detector)

      indicator_values = %{
        "rsi_14" => 50.0,
        "sma_50" => 41000.0
      }

      RealtimeSignalDetector.evaluate(detector, indicator_values, bar)

      refute_receive {:signal_detected, _, _}, 500
    end

    test "supports multiple subscribers", %{detector: detector, bar: bar} do
      # Create two subscriber processes
      parent = self()

      subscriber1 =
        spawn(fn ->
          RealtimeSignalDetector.subscribe(detector)

          receive do
            {:signal_detected, signal_type, _data} ->
              send(parent, {:subscriber1, signal_type})
          end
        end)

      subscriber2 =
        spawn(fn ->
          RealtimeSignalDetector.subscribe(detector)

          receive do
            {:signal_detected, signal_type, _data} ->
              send(parent, {:subscriber2, signal_type})
          end
        end)

      # Trigger entry signal
      indicator_values = %{"rsi_14" => 25.0, "sma_50" => 41000.0}
      RealtimeSignalDetector.evaluate(detector, indicator_values, bar)

      # Both should receive
      assert_receive {:subscriber1, :entry}, 1000
      assert_receive {:subscriber2, :entry}, 1000
    end
  end

  describe "unsubscribe/2" do
    setup %{strategy: strategy, current_bar: bar} do
      {:ok, detector} =
        RealtimeSignalDetector.start_link(
          strategy: strategy,
          symbol: "BTC/USD"
        )

      on_exit(fn -> GenServer.stop(detector) end)

      %{detector: detector, bar: bar}
    end

    test "unsubscribes from signal notifications", %{detector: detector, bar: bar} do
      RealtimeSignalDetector.subscribe(detector)
      assert :ok = RealtimeSignalDetector.unsubscribe(detector)

      # Trigger signal
      indicator_values = %{"rsi_14" => 25.0, "sma_50" => 41000.0}
      RealtimeSignalDetector.evaluate(detector, indicator_values, bar)

      # Should not receive notification
      refute_receive {:signal_detected, _, _}, 500
    end
  end

  describe "get_last_signals/1" do
    setup %{strategy: strategy, current_bar: bar} do
      {:ok, detector} =
        RealtimeSignalDetector.start_link(
          strategy: strategy,
          symbol: "BTC/USD"
        )

      on_exit(fn -> GenServer.stop(detector) end)

      %{detector: detector, bar: bar}
    end

    test "returns error when no signals evaluated yet", %{detector: detector} do
      assert {:error, :no_signals} = RealtimeSignalDetector.get_last_signals(detector)
    end

    test "returns last evaluated signals", %{detector: detector, bar: bar} do
      indicator_values = %{"rsi_14" => 25.0, "sma_50" => 41000.0}
      RealtimeSignalDetector.evaluate(detector, indicator_values, bar)

      assert {:ok, signals} = RealtimeSignalDetector.get_last_signals(detector)
      assert signals.entry == true
      assert signals.exit == false
      assert signals.stop == false
    end

    test "updates with latest evaluation", %{detector: detector, bar: bar} do
      # First evaluation - entry signal
      indicator_values_1 = %{"rsi_14" => 25.0, "sma_50" => 41000.0}
      RealtimeSignalDetector.evaluate(detector, indicator_values_1, bar)

      {:ok, signals_1} = RealtimeSignalDetector.get_last_signals(detector)
      assert signals_1.entry == true

      # Second evaluation - exit signal
      indicator_values_2 = %{"rsi_14" => 75.0, "sma_50" => 41000.0}
      RealtimeSignalDetector.evaluate(detector, indicator_values_2, bar)

      {:ok, signals_2} = RealtimeSignalDetector.get_last_signals(detector)
      assert signals_2.entry == false
      assert signals_2.exit == true
    end
  end

  describe "get_signal_history/1" do
    setup %{strategy: strategy, current_bar: bar} do
      {:ok, detector} =
        RealtimeSignalDetector.start_link(
          strategy: strategy,
          symbol: "BTC/USD"
        )

      on_exit(fn -> GenServer.stop(detector) end)

      %{detector: detector, bar: bar}
    end

    test "returns empty history initially", %{detector: detector} do
      assert {:ok, []} = RealtimeSignalDetector.get_signal_history(detector)
    end

    test "records triggered signals in history", %{detector: detector, bar: bar} do
      # Trigger entry signal
      indicator_values = %{"rsi_14" => 25.0, "sma_50" => 41000.0}
      RealtimeSignalDetector.evaluate(detector, indicator_values, bar)

      assert {:ok, history} = RealtimeSignalDetector.get_signal_history(detector)
      assert length(history) == 1

      [signal | _] = history
      assert signal.signal_type == :entry
      assert signal.symbol == "BTC/USD"
      assert signal.price == 42200.0
    end

    test "does not record when no signals triggered", %{detector: detector, bar: bar} do
      # No signals
      indicator_values = %{"rsi_14" => 50.0, "sma_50" => 41000.0}
      RealtimeSignalDetector.evaluate(detector, indicator_values, bar)

      assert {:ok, []} = RealtimeSignalDetector.get_signal_history(detector)
    end

    test "maintains history of multiple signals", %{detector: detector, bar: bar} do
      # Entry signal
      indicator_values_1 = %{"rsi_14" => 25.0, "sma_50" => 41000.0}
      RealtimeSignalDetector.evaluate(detector, indicator_values_1, bar)

      # Exit signal
      indicator_values_2 = %{"rsi_14" => 75.0, "sma_50" => 41000.0}
      RealtimeSignalDetector.evaluate(detector, indicator_values_2, bar)

      # Stop signal
      indicator_values_3 = %{"rsi_14" => 20.0, "sma_50" => 41000.0}
      RealtimeSignalDetector.evaluate(detector, indicator_values_3, bar)

      assert {:ok, history} = RealtimeSignalDetector.get_signal_history(detector)
      assert length(history) == 3

      signal_types = Enum.map(history, & &1.signal_type)
      assert :entry in signal_types
      assert :exit in signal_types
      assert :stop in signal_types
    end

    test "limits history to max size", %{detector: detector, bar: bar} do
      # Trigger many signals (more than @max_signal_history = 100)
      indicator_values = %{"rsi_14" => 25.0, "sma_50" => 41000.0}

      for _ <- 1..150 do
        RealtimeSignalDetector.evaluate(detector, indicator_values, bar)
      end

      assert {:ok, history} = RealtimeSignalDetector.get_signal_history(detector)
      assert length(history) <= 100
    end
  end

  describe "signal data structure" do
    setup %{strategy: strategy, current_bar: bar} do
      {:ok, detector} =
        RealtimeSignalDetector.start_link(
          strategy: strategy,
          symbol: "BTC/USD"
        )

      on_exit(fn -> GenServer.stop(detector) end)

      %{detector: detector, bar: bar}
    end

    test "signal contains all required fields", %{detector: detector, bar: bar} do
      RealtimeSignalDetector.subscribe(detector)

      indicator_values = %{
        "rsi_14" => 25.0,
        "sma_50" => 41000.0,
        "custom_indicator" => 123.45
      }

      RealtimeSignalDetector.evaluate(detector, indicator_values, bar)

      assert_receive {:signal_detected, :entry, signal_data}, 1000

      assert signal_data.signal_type == :entry
      assert signal_data.symbol == "BTC/USD"
      assert signal_data.timestamp == ~U[2025-12-04 12:00:00Z]
      assert signal_data.price == 42200.0
      assert is_map(signal_data.indicator_values)
      assert is_map(signal_data.conditions_met)
    end

    test "extracts only indicator values, excluding reserved variables", %{
      detector: detector,
      bar: bar
    } do
      RealtimeSignalDetector.subscribe(detector)

      indicator_values = %{
        "rsi_14" => 25.0,
        "sma_50" => 41000.0
      }

      RealtimeSignalDetector.evaluate(detector, indicator_values, bar)

      assert_receive {:signal_detected, :entry, signal_data}, 1000

      # Should include indicators
      assert signal_data.indicator_values["rsi_14"] == 25.0
      assert signal_data.indicator_values["sma_50"] == 41000.0

      # Should not include reserved variables
      refute Map.has_key?(signal_data.indicator_values, "close")
      refute Map.has_key?(signal_data.indicator_values, "open")
      refute Map.has_key?(signal_data.indicator_values, "volume")
      refute Map.has_key?(signal_data.indicator_values, "price")
    end

    test "includes conditions_met status", %{detector: detector, bar: bar} do
      RealtimeSignalDetector.subscribe(detector)

      indicator_values = %{"rsi_14" => 25.0, "sma_50" => 41000.0}
      RealtimeSignalDetector.evaluate(detector, indicator_values, bar)

      assert_receive {:signal_detected, :entry, signal_data}, 1000

      assert signal_data.conditions_met.entry == true
      assert signal_data.conditions_met.exit == false
      assert signal_data.conditions_met.stop == false
    end
  end
end
