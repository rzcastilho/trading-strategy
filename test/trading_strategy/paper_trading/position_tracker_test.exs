defmodule TradingStrategy.PaperTrading.PositionTrackerTest do
  use ExUnit.Case, async: true

  alias TradingStrategy.PaperTrading.PositionTracker

  describe "init/2" do
    test "initializes with default parameters" do
      tracker = PositionTracker.init(10000.0)

      assert tracker.initial_capital == 10000.0
      assert tracker.available_capital == 10000.0
      assert tracker.open_positions == %{}
      assert tracker.closed_positions == []
      assert tracker.total_realized_pnl == 0.0
      assert tracker.total_unrealized_pnl == 0.0
      assert tracker.position_sizing_mode == :percentage
      assert tracker.position_size_pct == 0.1
    end

    test "initializes with custom position sizing" do
      tracker =
        PositionTracker.init(10000.0, position_sizing: :fixed_amount, position_size_pct: 0.2)

      assert tracker.position_sizing_mode == :fixed_amount
      assert tracker.position_size_pct == 0.2
    end

    test "handles integer capital" do
      tracker = PositionTracker.init(10000)
      assert tracker.initial_capital == 10000.0
    end
  end

  describe "open_position/6" do
    setup do
      %{tracker: PositionTracker.init(10000.0)}
    end

    test "opens a long position successfully", %{tracker: tracker} do
      timestamp = DateTime.utc_now()

      assert {:ok, updated_tracker, position} =
               PositionTracker.open_position(tracker, "BTC/USD", :long, 43000.0, timestamp)

      assert position.symbol == "BTC/USD"
      assert position.side == :long
      assert position.entry_price == 43000.0
      assert position.quantity > 0
      assert position.entry_timestamp == timestamp
      assert position.unrealized_pnl == 0.0
      assert is_binary(position.position_id)

      assert map_size(updated_tracker.open_positions) == 1
      assert updated_tracker.available_capital < tracker.available_capital
    end

    test "opens a short position successfully", %{tracker: tracker} do
      timestamp = DateTime.utc_now()

      assert {:ok, updated_tracker, position} =
               PositionTracker.open_position(tracker, "ETH/USD", :short, 2250.0, timestamp)

      assert position.side == :short
      assert position.entry_price == 2250.0
    end

    test "calculates position size based on percentage mode", %{tracker: tracker} do
      # Default is 10% of available capital
      timestamp = DateTime.utc_now()
      entry_price = 40000.0

      {:ok, _updated_tracker, position} =
        PositionTracker.open_position(tracker, "BTC/USD", :long, entry_price, timestamp)

      expected_capital = 10000.0 * 0.1
      expected_quantity = expected_capital / entry_price

      assert_in_delta position.quantity, expected_quantity, 0.0001
    end

    test "calculates position size with custom percentage", %{tracker: _tracker} do
      tracker = PositionTracker.init(10000.0, position_size_pct: 0.2)
      timestamp = DateTime.utc_now()
      entry_price = 50000.0

      {:ok, _updated_tracker, position} =
        PositionTracker.open_position(tracker, "BTC/USD", :long, entry_price, timestamp)

      expected_capital = 10000.0 * 0.2
      expected_quantity = expected_capital / entry_price

      assert_in_delta position.quantity, expected_quantity, 0.0001
    end

    test "supports manual quantity override", %{tracker: tracker} do
      timestamp = DateTime.utc_now()

      {:ok, _updated_tracker, position} =
        PositionTracker.open_position(tracker, "BTC/USD", :long, 40000.0, timestamp,
          quantity: 0.5
        )

      assert position.quantity == 0.5
    end

    test "deducts capital when position opened", %{tracker: tracker} do
      timestamp = DateTime.utc_now()
      entry_price = 40000.0

      {:ok, updated_tracker, position} =
        PositionTracker.open_position(tracker, "BTC/USD", :long, entry_price, timestamp)

      cost = position.quantity * entry_price
      expected_capital = tracker.available_capital - cost

      assert_in_delta updated_tracker.available_capital, expected_capital, 0.01
    end

    test "returns error when insufficient capital", %{tracker: tracker} do
      timestamp = DateTime.utc_now()

      # Try to manually set quantity that exceeds capital
      assert {:error, message} =
               PositionTracker.open_position(tracker, "BTC/USD", :long, 40000.0, timestamp,
                 quantity: 10.0
               )

      assert message =~ "Insufficient capital"
    end

    test "allows multiple positions", %{tracker: tracker} do
      timestamp = DateTime.utc_now()

      {:ok, tracker, _pos1} =
        PositionTracker.open_position(tracker, "BTC/USD", :long, 43000.0, timestamp)

      {:ok, tracker, _pos2} =
        PositionTracker.open_position(tracker, "ETH/USD", :long, 2250.0, timestamp)

      assert map_size(tracker.open_positions) == 2
    end

    test "generates unique position IDs", %{tracker: tracker} do
      timestamp = DateTime.utc_now()

      {:ok, tracker, pos1} =
        PositionTracker.open_position(tracker, "BTC/USD", :long, 43000.0, timestamp)

      {:ok, _tracker, pos2} =
        PositionTracker.open_position(tracker, "BTC/USD", :long, 43000.0, timestamp)

      assert pos1.position_id != pos2.position_id
    end
  end

  describe "close_position/4" do
    setup do
      tracker = PositionTracker.init(10000.0)
      timestamp = DateTime.utc_now()

      {:ok, tracker, position} =
        PositionTracker.open_position(tracker, "BTC/USD", :long, 43000.0, timestamp)

      %{tracker: tracker, position: position, timestamp: timestamp}
    end

    test "closes a long position with profit", %{tracker: tracker, position: position} do
      exit_timestamp = DateTime.utc_now()
      exit_price = 45000.0

      assert {:ok, updated_tracker, closed_position} =
               PositionTracker.close_position(
                 tracker,
                 position.position_id,
                 exit_price,
                 exit_timestamp
               )

      assert closed_position.position_id == position.position_id
      assert closed_position.exit_price == 45000.0
      assert closed_position.exit_timestamp == exit_timestamp
      assert closed_position.realized_pnl > 0

      assert map_size(updated_tracker.open_positions) == 0
      assert length(updated_tracker.closed_positions) == 1
      assert updated_tracker.total_realized_pnl > 0
    end

    test "closes a long position with loss", %{tracker: tracker, position: position} do
      exit_timestamp = DateTime.utc_now()
      exit_price = 41000.0

      {:ok, updated_tracker, closed_position} =
        PositionTracker.close_position(tracker, position.position_id, exit_price, exit_timestamp)

      assert closed_position.realized_pnl < 0
      assert updated_tracker.total_realized_pnl < 0
    end

    test "returns capital plus profit to available capital", %{
      tracker: tracker,
      position: position
    } do
      exit_price = 45000.0
      exit_timestamp = DateTime.utc_now()

      {:ok, updated_tracker, closed_position} =
        PositionTracker.close_position(tracker, position.position_id, exit_price, exit_timestamp)

      proceeds = exit_price * position.quantity
      expected_capital = tracker.available_capital + proceeds + closed_position.realized_pnl

      assert_in_delta updated_tracker.available_capital, expected_capital, 0.01
    end

    test "returns error for non-existent position", %{tracker: tracker} do
      assert {:error, message} =
               PositionTracker.close_position(tracker, "invalid-id", 45000.0, DateTime.utc_now())

      assert message =~ "Position not found"
    end

    test "closed position does not have unrealized_pnl field", %{
      tracker: tracker,
      position: position
    } do
      {:ok, _tracker, closed_position} =
        PositionTracker.close_position(
          tracker,
          position.position_id,
          45000.0,
          DateTime.utc_now()
        )

      refute Map.has_key?(closed_position, :unrealized_pnl)
      assert Map.has_key?(closed_position, :realized_pnl)
    end
  end

  describe "close_position/4 with short positions" do
    setup do
      tracker = PositionTracker.init(10000.0)
      timestamp = DateTime.utc_now()

      {:ok, tracker, position} =
        PositionTracker.open_position(tracker, "BTC/USD", :short, 43000.0, timestamp)

      %{tracker: tracker, position: position}
    end

    test "closes short position with profit (price down)", %{
      tracker: tracker,
      position: position
    } do
      exit_price = 41000.0

      {:ok, _tracker, closed_position} =
        PositionTracker.close_position(
          tracker,
          position.position_id,
          exit_price,
          DateTime.utc_now()
        )

      assert closed_position.realized_pnl > 0
    end

    test "closes short position with loss (price up)", %{tracker: tracker, position: position} do
      exit_price = 45000.0

      {:ok, _tracker, closed_position} =
        PositionTracker.close_position(
          tracker,
          position.position_id,
          exit_price,
          DateTime.utc_now()
        )

      assert closed_position.realized_pnl < 0
    end
  end

  describe "close_positions_for_symbol/4" do
    setup do
      tracker = PositionTracker.init(20000.0)
      timestamp = DateTime.utc_now()

      {:ok, tracker, _pos1} =
        PositionTracker.open_position(tracker, "BTC/USD", :long, 43000.0, timestamp)

      {:ok, tracker, _pos2} =
        PositionTracker.open_position(tracker, "BTC/USD", :long, 43000.0, timestamp)

      {:ok, tracker, _pos3} =
        PositionTracker.open_position(tracker, "ETH/USD", :long, 2250.0, timestamp)

      %{tracker: tracker}
    end

    test "closes all positions for a symbol", %{tracker: tracker} do
      exit_price = 45000.0
      exit_timestamp = DateTime.utc_now()

      {:ok, updated_tracker, closed_positions} =
        PositionTracker.close_positions_for_symbol(tracker, "BTC/USD", exit_price, exit_timestamp)

      assert length(closed_positions) == 2
      assert Enum.all?(closed_positions, fn pos -> pos.symbol == "BTC/USD" end)
      assert map_size(updated_tracker.open_positions) == 1
    end

    test "does not affect other symbols", %{tracker: tracker} do
      {:ok, updated_tracker, _closed} =
        PositionTracker.close_positions_for_symbol(
          tracker,
          "BTC/USD",
          45000.0,
          DateTime.utc_now()
        )

      # ETH position should still be open
      remaining_positions = PositionTracker.get_open_positions(updated_tracker)
      assert length(remaining_positions) == 1
      assert hd(remaining_positions).symbol == "ETH/USD"
    end

    test "returns empty list when no positions for symbol", %{tracker: tracker} do
      {:ok, updated_tracker, closed_positions} =
        PositionTracker.close_positions_for_symbol(
          tracker,
          "NONEXISTENT/USD",
          45000.0,
          DateTime.utc_now()
        )

      assert closed_positions == []
      assert updated_tracker == tracker
    end
  end

  describe "update_unrealized_pnl/2" do
    setup do
      tracker = PositionTracker.init(10000.0)
      timestamp = DateTime.utc_now()

      {:ok, tracker, _pos1} =
        PositionTracker.open_position(tracker, "BTC/USD", :long, 43000.0, timestamp)

      {:ok, tracker, _pos2} =
        PositionTracker.open_position(tracker, "ETH/USD", :long, 2250.0, timestamp)

      %{tracker: tracker}
    end

    test "updates unrealized PnL for all open positions", %{tracker: tracker} do
      current_prices = %{
        "BTC/USD" => 45000.0,
        "ETH/USD" => 2400.0
      }

      updated_tracker = PositionTracker.update_unrealized_pnl(tracker, current_prices)

      assert updated_tracker.total_unrealized_pnl > 0
    end

    test "calculates unrealized PnL for long positions with profit", %{tracker: tracker} do
      current_prices = %{"BTC/USD" => 45000.0, "ETH/USD" => 2400.0}

      updated_tracker = PositionTracker.update_unrealized_pnl(tracker, current_prices)

      positions = PositionTracker.get_open_positions(updated_tracker)
      assert Enum.all?(positions, fn pos -> pos.unrealized_pnl > 0 end)
    end

    test "calculates unrealized PnL for long positions with loss", %{tracker: tracker} do
      current_prices = %{"BTC/USD" => 41000.0, "ETH/USD" => 2100.0}

      updated_tracker = PositionTracker.update_unrealized_pnl(tracker, current_prices)

      positions = PositionTracker.get_open_positions(updated_tracker)
      assert Enum.all?(positions, fn pos -> pos.unrealized_pnl < 0 end)
      assert updated_tracker.total_unrealized_pnl < 0
    end

    test "skips positions without price update", %{tracker: tracker} do
      current_prices = %{"BTC/USD" => 45000.0}

      updated_tracker = PositionTracker.update_unrealized_pnl(tracker, current_prices)

      # Should still process available prices
      assert updated_tracker.total_unrealized_pnl != 0
    end

    test "handles empty prices map", %{tracker: tracker} do
      updated_tracker = PositionTracker.update_unrealized_pnl(tracker, %{})

      # Should keep existing unrealized PnL (which is 0 initially)
      assert updated_tracker.total_unrealized_pnl == 0.0
    end
  end

  describe "update_unrealized_pnl/2 with short positions" do
    setup do
      tracker = PositionTracker.init(10000.0)
      timestamp = DateTime.utc_now()

      {:ok, tracker, _pos} =
        PositionTracker.open_position(tracker, "BTC/USD", :short, 43000.0, timestamp)

      %{tracker: tracker}
    end

    test "calculates unrealized PnL for short position with profit (price down)", %{
      tracker: tracker
    } do
      current_prices = %{"BTC/USD" => 41000.0}

      updated_tracker = PositionTracker.update_unrealized_pnl(tracker, current_prices)

      assert updated_tracker.total_unrealized_pnl > 0
    end

    test "calculates unrealized PnL for short position with loss (price up)", %{
      tracker: tracker
    } do
      current_prices = %{"BTC/USD" => 45000.0}

      updated_tracker = PositionTracker.update_unrealized_pnl(tracker, current_prices)

      assert updated_tracker.total_unrealized_pnl < 0
    end
  end

  describe "calculate_total_equity/1" do
    setup do
      tracker = PositionTracker.init(10000.0)
      timestamp = DateTime.utc_now()

      {:ok, tracker, _pos} =
        PositionTracker.open_position(tracker, "BTC/USD", :long, 43000.0, timestamp)

      %{tracker: tracker}
    end

    test "calculates total equity including unrealized PnL", %{tracker: tracker} do
      current_prices = %{"BTC/USD" => 45000.0}
      updated_tracker = PositionTracker.update_unrealized_pnl(tracker, current_prices)

      equity = PositionTracker.calculate_total_equity(updated_tracker)

      expected_equity =
        updated_tracker.available_capital + updated_tracker.total_unrealized_pnl

      assert_in_delta equity, expected_equity, 0.01
    end

    test "equity equals initial capital when no price movement", %{tracker: tracker} do
      current_prices = %{"BTC/USD" => 43000.0}
      updated_tracker = PositionTracker.update_unrealized_pnl(tracker, current_prices)

      equity = PositionTracker.calculate_total_equity(updated_tracker)

      assert_in_delta equity, tracker.initial_capital, 0.01
    end
  end

  describe "get_open_positions/1" do
    test "returns empty list when no positions" do
      tracker = PositionTracker.init(10000.0)
      assert [] = PositionTracker.get_open_positions(tracker)
    end

    test "returns all open positions" do
      tracker = PositionTracker.init(10000.0)
      timestamp = DateTime.utc_now()

      {:ok, tracker, _pos1} =
        PositionTracker.open_position(tracker, "BTC/USD", :long, 43000.0, timestamp)

      {:ok, tracker, _pos2} =
        PositionTracker.open_position(tracker, "ETH/USD", :long, 2250.0, timestamp)

      positions = PositionTracker.get_open_positions(tracker)
      assert length(positions) == 2
    end
  end

  describe "get_position/2" do
    setup do
      tracker = PositionTracker.init(10000.0)

      {:ok, tracker, position} =
        PositionTracker.open_position(tracker, "BTC/USD", :long, 43000.0, DateTime.utc_now())

      %{tracker: tracker, position: position}
    end

    test "gets position by ID", %{tracker: tracker, position: position} do
      assert {:ok, found_position} =
               PositionTracker.get_position(tracker, position.position_id)

      assert found_position.position_id == position.position_id
    end

    test "returns error for non-existent position", %{tracker: tracker} do
      assert {:error, :not_found} = PositionTracker.get_position(tracker, "invalid-id")
    end
  end

  describe "has_open_positions?/1" do
    test "returns false when no positions" do
      tracker = PositionTracker.init(10000.0)
      refute PositionTracker.has_open_positions?(tracker)
    end

    test "returns true when positions exist" do
      tracker = PositionTracker.init(10000.0)

      {:ok, tracker, _pos} =
        PositionTracker.open_position(tracker, "BTC/USD", :long, 43000.0, DateTime.utc_now())

      assert PositionTracker.has_open_positions?(tracker)
    end
  end

  describe "get_closed_positions/1" do
    test "returns empty list when no closed positions" do
      tracker = PositionTracker.init(10000.0)
      assert [] = PositionTracker.get_closed_positions(tracker)
    end

    test "returns all closed positions in reverse order" do
      tracker = PositionTracker.init(10000.0)
      timestamp = DateTime.utc_now()

      {:ok, tracker, pos1} =
        PositionTracker.open_position(tracker, "BTC/USD", :long, 43000.0, timestamp)

      {:ok, tracker, _closed1} =
        PositionTracker.close_position(tracker, pos1.position_id, 45000.0, timestamp)

      closed = PositionTracker.get_closed_positions(tracker)
      assert length(closed) == 1
    end
  end

  describe "get_total_realized_pnl/1" do
    test "returns zero when no closed positions" do
      tracker = PositionTracker.init(10000.0)
      assert PositionTracker.get_total_realized_pnl(tracker) == 0.0
    end

    test "returns total realized PnL from closed positions" do
      tracker = PositionTracker.init(10000.0)
      timestamp = DateTime.utc_now()

      {:ok, tracker, pos} =
        PositionTracker.open_position(tracker, "BTC/USD", :long, 43000.0, timestamp)

      {:ok, tracker, _closed} =
        PositionTracker.close_position(tracker, pos.position_id, 45000.0, timestamp)

      assert PositionTracker.get_total_realized_pnl(tracker) > 0
    end
  end

  describe "get_total_unrealized_pnl/1" do
    test "returns zero initially" do
      tracker = PositionTracker.init(10000.0)
      assert PositionTracker.get_total_unrealized_pnl(tracker) == 0.0
    end

    test "returns total unrealized PnL after update" do
      tracker = PositionTracker.init(10000.0)

      {:ok, tracker, _pos} =
        PositionTracker.open_position(tracker, "BTC/USD", :long, 43000.0, DateTime.utc_now())

      tracker = PositionTracker.update_unrealized_pnl(tracker, %{"BTC/USD" => 45000.0})

      assert PositionTracker.get_total_unrealized_pnl(tracker) > 0
    end
  end

  describe "get_available_capital/1" do
    test "returns initial capital when no positions" do
      tracker = PositionTracker.init(10000.0)
      assert PositionTracker.get_available_capital(tracker) == 10000.0
    end

    test "returns reduced capital after opening position" do
      tracker = PositionTracker.init(10000.0)

      {:ok, tracker, _pos} =
        PositionTracker.open_position(tracker, "BTC/USD", :long, 43000.0, DateTime.utc_now())

      assert PositionTracker.get_available_capital(tracker) < 10000.0
    end
  end

  describe "to_map/1 and from_map/1" do
    test "serializes and deserializes tracker state" do
      tracker = PositionTracker.init(10000.0, position_size_pct: 0.15)
      timestamp = DateTime.utc_now()

      {:ok, tracker, _pos} =
        PositionTracker.open_position(tracker, "BTC/USD", :long, 43000.0, timestamp)

      tracker = PositionTracker.update_unrealized_pnl(tracker, %{"BTC/USD" => 45000.0})

      # Serialize
      map = PositionTracker.to_map(tracker)

      assert is_map(map)
      assert map.initial_capital == 10000.0
      assert is_list(map.open_positions)
      assert is_list(map.closed_positions)

      # Deserialize
      restored_tracker = PositionTracker.from_map(map)

      assert restored_tracker.initial_capital == tracker.initial_capital
      assert restored_tracker.available_capital == tracker.available_capital
      assert restored_tracker.total_realized_pnl == tracker.total_realized_pnl
      assert restored_tracker.total_unrealized_pnl == tracker.total_unrealized_pnl
      assert restored_tracker.position_size_pct == 0.15
      assert map_size(restored_tracker.open_positions) == map_size(tracker.open_positions)
    end

    test "handles closed positions in serialization" do
      tracker = PositionTracker.init(10000.0)
      timestamp = DateTime.utc_now()

      {:ok, tracker, pos} =
        PositionTracker.open_position(tracker, "BTC/USD", :long, 43000.0, timestamp)

      {:ok, tracker, _closed} =
        PositionTracker.close_position(tracker, pos.position_id, 45000.0, timestamp)

      map = PositionTracker.to_map(tracker)
      restored = PositionTracker.from_map(map)

      assert length(restored.closed_positions) == 1
      assert hd(restored.closed_positions).realized_pnl > 0
    end
  end
end
