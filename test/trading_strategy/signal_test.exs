defmodule TradingStrategy.SignalTest do
  use ExUnit.Case, async: true
  alias TradingStrategy.Signal

  describe "new/4" do
    test "creates an entry signal for long position" do
      signal = Signal.new(:entry, :long, "BTCUSD", 50000.0)

      assert signal.type == :entry
      assert signal.direction == :long
      assert signal.symbol == "BTCUSD"
      assert signal.price == 50000.0
      assert %DateTime{} = signal.timestamp
    end

    test "creates an exit signal for short position" do
      signal = Signal.new(:exit, :short, "ETHUSD", 3000.0)

      assert signal.type == :exit
      assert signal.direction == :short
      assert signal.symbol == "ETHUSD"
      assert signal.price == 3000.0
    end

    test "accepts custom timestamp" do
      timestamp = ~U[2025-01-01 12:00:00Z]
      signal = Signal.new(:entry, :long, "TEST", 100.0, timestamp: timestamp)

      assert signal.timestamp == timestamp
    end

    test "accepts strategy name" do
      signal = Signal.new(:entry, :long, "TEST", 100.0, strategy: :my_strategy)

      assert signal.strategy == :my_strategy
    end

    test "accepts metadata" do
      metadata = %{reason: "MA crossover", confidence: 0.85}
      signal = Signal.new(:entry, :long, "TEST", 100.0, metadata: metadata)

      assert signal.metadata == metadata
    end
  end

  describe "entry?/1" do
    test "returns true for entry signals" do
      signal = Signal.new(:entry, :long, "TEST", 100.0)
      assert Signal.entry?(signal)
    end

    test "returns false for exit signals" do
      signal = Signal.new(:exit, :long, "TEST", 100.0)
      refute Signal.entry?(signal)
    end

    test "returns false for non-signal values" do
      refute Signal.entry?(nil)
      refute Signal.entry?(%{type: :something_else})
    end
  end

  describe "exit?/1" do
    test "returns true for exit signals" do
      signal = Signal.new(:exit, :long, "TEST", 100.0)
      assert Signal.exit?(signal)
    end

    test "returns false for entry signals" do
      signal = Signal.new(:entry, :long, "TEST", 100.0)
      refute Signal.exit?(signal)
    end
  end

  describe "long?/1" do
    test "returns true for long signals" do
      signal = Signal.new(:entry, :long, "TEST", 100.0)
      assert Signal.long?(signal)
    end

    test "returns false for short signals" do
      signal = Signal.new(:entry, :short, "TEST", 100.0)
      refute Signal.long?(signal)
    end
  end

  describe "short?/1" do
    test "returns true for short signals" do
      signal = Signal.new(:entry, :short, "TEST", 100.0)
      assert Signal.short?(signal)
    end

    test "returns false for long signals" do
      signal = Signal.new(:entry, :long, "TEST", 100.0)
      refute Signal.short?(signal)
    end
  end
end
