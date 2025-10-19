defmodule TradingStrategy.PositionTest do
  use ExUnit.Case, async: true
  alias TradingStrategy.{Position, Signal}

  describe "open/2" do
    test "opens a long position from an entry signal" do
      signal = Signal.new(:entry, :long, "BTCUSD", 50000.0)
      position = Position.open(signal, 1.0)

      assert position.symbol == "BTCUSD"
      assert position.direction == :long
      assert position.entry_price == 50000.0
      assert position.quantity == 1.0
      assert position.status == :open
      assert position.exit_price == nil
      assert position.pnl == nil
    end

    test "opens a short position from an entry signal" do
      signal = Signal.new(:entry, :short, "ETHUSD", 3000.0)
      position = Position.open(signal, 2.0)

      assert position.direction == :short
      assert position.entry_price == 3000.0
      assert position.quantity == 2.0
      assert position.status == :open
    end

    test "generates a unique ID" do
      signal = Signal.new(:entry, :long, "TEST", 100.0)
      pos1 = Position.open(signal, 1.0)
      pos2 = Position.open(signal, 1.0)

      assert pos1.id != pos2.id
      assert is_binary(pos1.id)
      assert String.length(pos1.id) == 32
    end

    test "accepts custom ID and metadata" do
      signal = Signal.new(:entry, :long, "TEST", 100.0)
      metadata = %{note: "test position"}
      position = Position.open(signal, 1.0, id: "custom-id", metadata: metadata)

      assert position.id == "custom-id"
      assert position.metadata == metadata
    end
  end

  describe "close/2" do
    test "closes a long position with profit" do
      entry_signal = Signal.new(:entry, :long, "BTCUSD", 50000.0)
      position = Position.open(entry_signal, 1.0)

      exit_signal = Signal.new(:exit, :long, "BTCUSD", 52000.0)
      closed_position = Position.close(position, exit_signal)

      assert closed_position.status == :closed
      assert closed_position.exit_price == 52000.0
      assert closed_position.pnl == 2000.0
      assert closed_position.pnl_percent == 4.0
    end

    test "closes a long position with loss" do
      entry_signal = Signal.new(:entry, :long, "BTCUSD", 50000.0)
      position = Position.open(entry_signal, 1.0)

      exit_signal = Signal.new(:exit, :long, "BTCUSD", 48000.0)
      closed_position = Position.close(position, exit_signal)

      assert closed_position.pnl == -2000.0
      assert closed_position.pnl_percent == -4.0
    end

    test "closes a short position with profit" do
      entry_signal = Signal.new(:entry, :short, "BTCUSD", 50000.0)
      position = Position.open(entry_signal, 1.0)

      exit_signal = Signal.new(:exit, :short, "BTCUSD", 48000.0)
      closed_position = Position.close(position, exit_signal)

      assert closed_position.pnl == 2000.0
      assert closed_position.pnl_percent == 4.0
    end

    test "closes a short position with loss" do
      entry_signal = Signal.new(:entry, :short, "BTCUSD", 50000.0)
      position = Position.open(entry_signal, 1.0)

      exit_signal = Signal.new(:exit, :short, "BTCUSD", 52000.0)
      closed_position = Position.close(position, exit_signal)

      assert closed_position.pnl == -2000.0
      assert closed_position.pnl_percent == -4.0
    end

    test "calculates P&L with multiple quantity" do
      entry_signal = Signal.new(:entry, :long, "BTCUSD", 50000.0)
      position = Position.open(entry_signal, 2.5)

      exit_signal = Signal.new(:exit, :long, "BTCUSD", 51000.0)
      closed_position = Position.close(position, exit_signal)

      assert closed_position.pnl == 2500.0
    end
  end

  describe "open?/1" do
    test "returns true for open positions" do
      signal = Signal.new(:entry, :long, "TEST", 100.0)
      position = Position.open(signal, 1.0)

      assert Position.open?(position)
    end

    test "returns false for closed positions" do
      entry_signal = Signal.new(:entry, :long, "TEST", 100.0)
      position = Position.open(entry_signal, 1.0)

      exit_signal = Signal.new(:exit, :long, "TEST", 110.0)
      closed_position = Position.close(position, exit_signal)

      refute Position.open?(closed_position)
    end
  end

  describe "closed?/1" do
    test "returns false for open positions" do
      signal = Signal.new(:entry, :long, "TEST", 100.0)
      position = Position.open(signal, 1.0)

      refute Position.closed?(position)
    end

    test "returns true for closed positions" do
      entry_signal = Signal.new(:entry, :long, "TEST", 100.0)
      position = Position.open(entry_signal, 1.0)

      exit_signal = Signal.new(:exit, :long, "TEST", 110.0)
      closed_position = Position.close(position, exit_signal)

      assert Position.closed?(closed_position)
    end
  end

  describe "calculate_pnl/2" do
    test "calculates P&L for long positions" do
      signal = Signal.new(:entry, :long, "TEST", 100.0)
      position = Position.open(signal, 1.0)

      assert Position.calculate_pnl(position, 110.0) == 10.0
      assert Position.calculate_pnl(position, 90.0) == -10.0
    end

    test "calculates P&L for short positions" do
      signal = Signal.new(:entry, :short, "TEST", 100.0)
      position = Position.open(signal, 1.0)

      assert Position.calculate_pnl(position, 90.0) == 10.0
      assert Position.calculate_pnl(position, 110.0) == -10.0
    end
  end

  describe "calculate_pnl_percent/2" do
    test "calculates P&L percentage for long positions" do
      signal = Signal.new(:entry, :long, "TEST", 100.0)
      position = Position.open(signal, 1.0)

      assert Position.calculate_pnl_percent(position, 110.0) == 10.0
      assert Position.calculate_pnl_percent(position, 90.0) == -10.0
    end

    test "calculates P&L percentage for short positions" do
      signal = Signal.new(:entry, :short, "TEST", 100.0)
      position = Position.open(signal, 1.0)

      assert Position.calculate_pnl_percent(position, 90.0) == 10.0
      assert Position.calculate_pnl_percent(position, 110.0) == -10.0
    end
  end

  describe "unrealized_pnl/2" do
    test "returns unrealized P&L for open positions" do
      signal = Signal.new(:entry, :long, "TEST", 100.0)
      position = Position.open(signal, 1.0)

      assert Position.unrealized_pnl(position, 110.0) == 10.0
      assert Position.unrealized_pnl(position, 95.0) == -5.0
    end

    test "returns realized P&L for closed positions" do
      entry_signal = Signal.new(:entry, :long, "TEST", 100.0)
      position = Position.open(entry_signal, 1.0)

      exit_signal = Signal.new(:exit, :long, "TEST", 110.0)
      closed_position = Position.close(position, exit_signal)

      # Should return the locked-in P&L regardless of current price
      assert Position.unrealized_pnl(closed_position, 120.0) == 10.0
      assert Position.unrealized_pnl(closed_position, 90.0) == 10.0
    end
  end
end
