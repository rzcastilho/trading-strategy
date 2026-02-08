defmodule TradingStrategy.Backtesting.PositionManagerTest do
  use ExUnit.Case, async: true

  alias TradingStrategy.Backtesting.PositionManager

  describe "PnL calculation for long positions" do
    test "calculates positive PnL when exit price is higher than entry" do
      manager = PositionManager.init(10000)
      entry_time = ~U[2024-01-01 10:00:00Z]
      exit_time = ~U[2024-01-01 11:00:00Z]

      # Open long position at $50,000
      {:ok, manager} = PositionManager.open_position(manager, "BTC/USD", :long, 50000, 0.1, entry_time)

      # Close at $51,000 (profit)
      {:ok, updated_manager, pnl} = PositionManager.close_position(manager, 51000, exit_time)

      # Expected PnL: (51000 - 50000) * 0.1 = 100
      assert_in_delta pnl, 100.0, 0.01
      assert_in_delta updated_manager.total_realized_pnl, 100.0, 0.01
    end

    test "calculates negative PnL when exit price is lower than entry" do
      manager = PositionManager.init(10000)
      entry_time = ~U[2024-01-01 10:00:00Z]
      exit_time = ~U[2024-01-01 11:00:00Z]

      # Open long position at $50,000
      {:ok, manager} = PositionManager.open_position(manager, "BTC/USD", :long, 50000, 0.1, entry_time)

      # Close at $49,000 (loss)
      {:ok, updated_manager, pnl} = PositionManager.close_position(manager, 49000, exit_time)

      # Expected PnL: (49000 - 50000) * 0.1 = -100
      assert_in_delta pnl, -100.0, 0.01
      assert_in_delta updated_manager.total_realized_pnl, -100.0, 0.01
    end

    test "calculates zero PnL when exit price equals entry price" do
      manager = PositionManager.init(10000)
      entry_time = ~U[2024-01-01 10:00:00Z]
      exit_time = ~U[2024-01-01 11:00:00Z]

      # Open long position at $50,000
      {:ok, manager} = PositionManager.open_position(manager, "BTC/USD", :long, 50000, 0.1, entry_time)

      # Close at $50,000 (breakeven)
      {:ok, updated_manager, pnl} = PositionManager.close_position(manager, 50000, exit_time)

      # Expected PnL: (50000 - 50000) * 0.1 = 0
      assert_in_delta pnl, 0.0, 0.01
      assert_in_delta updated_manager.total_realized_pnl, 0.0, 0.01
    end

    test "stores entry and exit prices in closed position" do
      manager = PositionManager.init(10000)
      entry_time = ~U[2024-01-01 10:00:00Z]
      exit_time = ~U[2024-01-01 11:00:00Z]

      {:ok, manager} = PositionManager.open_position(manager, "BTC/USD", :long, 50000, 0.1, entry_time)
      {:ok, updated_manager, _pnl} = PositionManager.close_position(manager, 51000, exit_time)

      [closed_position] = PositionManager.get_closed_positions(updated_manager)

      assert_in_delta closed_position.entry_price, 50000.0, 0.01
      assert_in_delta closed_position.exit_price, 51000.0, 0.01
    end
  end

  describe "PnL calculation for short positions" do
    test "calculates positive PnL when exit price is lower than entry" do
      manager = PositionManager.init(10000)
      entry_time = ~U[2024-01-01 10:00:00Z]
      exit_time = ~U[2024-01-01 11:00:00Z]

      # Open short position at $50,000
      {:ok, manager} = PositionManager.open_position(manager, "BTC/USD", :short, 50000, 0.1, entry_time)

      # Close at $49,000 (profit for short)
      {:ok, updated_manager, pnl} = PositionManager.close_position(manager, 49000, exit_time)

      # Expected PnL: (50000 - 49000) * 0.1 = 100
      assert_in_delta pnl, 100.0, 0.01
      assert_in_delta updated_manager.total_realized_pnl, 100.0, 0.01
    end

    test "calculates negative PnL when exit price is higher than entry" do
      manager = PositionManager.init(10000)
      entry_time = ~U[2024-01-01 10:00:00Z]
      exit_time = ~U[2024-01-01 11:00:00Z]

      # Open short position at $50,000
      {:ok, manager} = PositionManager.open_position(manager, "BTC/USD", :short, 50000, 0.1, entry_time)

      # Close at $51,000 (loss for short)
      {:ok, updated_manager, pnl} = PositionManager.close_position(manager, 51000, exit_time)

      # Expected PnL: (50000 - 51000) * 0.1 = -100
      assert_in_delta pnl, -100.0, 0.01
      assert_in_delta updated_manager.total_realized_pnl, -100.0, 0.01
    end

    test "calculates zero PnL when exit price equals entry price" do
      manager = PositionManager.init(10000)
      entry_time = ~U[2024-01-01 10:00:00Z]
      exit_time = ~U[2024-01-01 11:00:00Z]

      # Open short position at $50,000
      {:ok, manager} = PositionManager.open_position(manager, "BTC/USD", :short, 50000, 0.1, entry_time)

      # Close at $50,000 (breakeven)
      {:ok, updated_manager, pnl} = PositionManager.close_position(manager, 50000, exit_time)

      # Expected PnL: (50000 - 50000) * 0.1 = 0
      assert_in_delta pnl, 0.0, 0.01
      assert_in_delta updated_manager.total_realized_pnl, 0.0, 0.01
    end
  end

  describe "trade duration calculation" do
    test "calculates duration in seconds for position held for 1 hour" do
      manager = PositionManager.init(10000)
      entry_time = ~U[2024-01-01 10:00:00Z]
      exit_time = ~U[2024-01-01 11:00:00Z]

      {:ok, manager} = PositionManager.open_position(manager, "BTC/USD", :long, 50000, 0.1, entry_time)
      {:ok, updated_manager, _pnl} = PositionManager.close_position(manager, 51000, exit_time)

      [closed_position] = PositionManager.get_closed_positions(updated_manager)

      # Verify timestamps are stored
      assert closed_position.entry_timestamp == entry_time
      assert closed_position.exit_timestamp == exit_time

      # Calculate duration
      duration_seconds = DateTime.diff(exit_time, entry_time, :second)
      assert duration_seconds == 3600  # 1 hour = 3600 seconds
    end

    test "calculates duration in seconds for position held for 1 day" do
      manager = PositionManager.init(10000)
      entry_time = ~U[2024-01-01 10:00:00Z]
      exit_time = ~U[2024-01-02 10:00:00Z]

      {:ok, manager} = PositionManager.open_position(manager, "BTC/USD", :long, 50000, 0.1, entry_time)
      {:ok, updated_manager, _pnl} = PositionManager.close_position(manager, 51000, exit_time)

      [closed_position] = PositionManager.get_closed_positions(updated_manager)

      duration_seconds = DateTime.diff(exit_time, entry_time, :second)
      assert duration_seconds == 86400  # 1 day = 86400 seconds
    end

    test "calculates duration for multiple positions" do
      manager = PositionManager.init(100000)

      # First position: 1 hour
      entry_time_1 = ~U[2024-01-01 10:00:00Z]
      exit_time_1 = ~U[2024-01-01 11:00:00Z]
      {:ok, manager} = PositionManager.open_position(manager, "BTC/USD", :long, 50000, 0.1, entry_time_1)
      {:ok, manager, _pnl} = PositionManager.close_position(manager, 51000, exit_time_1)

      # Second position: 2 hours
      entry_time_2 = ~U[2024-01-01 12:00:00Z]
      exit_time_2 = ~U[2024-01-01 14:00:00Z]
      {:ok, manager} = PositionManager.open_position(manager, "BTC/USD", :long, 52000, 0.1, entry_time_2)
      {:ok, updated_manager, _pnl} = PositionManager.close_position(manager, 53000, exit_time_2)

      closed_positions = PositionManager.get_closed_positions(updated_manager)
      assert length(closed_positions) == 2

      [pos1, pos2] = closed_positions
      assert DateTime.diff(pos1.exit_timestamp, pos1.entry_timestamp, :second) == 3600   # 1 hour
      assert DateTime.diff(pos2.exit_timestamp, pos2.entry_timestamp, :second) == 7200   # 2 hours
    end
  end
end
