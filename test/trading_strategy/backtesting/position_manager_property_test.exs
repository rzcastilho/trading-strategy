defmodule TradingStrategy.Backtesting.PositionManagerPropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias TradingStrategy.Backtesting.PositionManager

  describe "property-based tests for PnL accuracy" do
    property "long position PnL equals (exit_price - entry_price) * quantity" do
      check all entry_price <- float(min: 0.01, max: 100_000.0),
                exit_price <- float(min: 0.01, max: 100_000.0),
                quantity <- float(min: 0.001, max: 100.0),
                initial_capital <- float(min: 10_000.0, max: 1_000_000.0),
                max_runs: 100 do

        # Ensure sufficient capital for the trade
        cost = entry_price * quantity

        if cost < initial_capital do
          manager = PositionManager.init(initial_capital)
          entry_time = ~U[2024-01-01 10:00:00Z]
          exit_time = ~U[2024-01-01 11:00:00Z]

          {:ok, manager} = PositionManager.open_position(manager, "BTC/USD", :long, entry_price, quantity, entry_time)
          {:ok, _updated_manager, pnl} = PositionManager.close_position(manager, exit_price, exit_time)

          # Calculate expected PnL
          expected_pnl = (exit_price - entry_price) * quantity

          # Allow for floating-point precision errors
          assert_in_delta pnl, expected_pnl, 0.01
        end
      end
    end

    property "short position PnL equals (entry_price - exit_price) * quantity" do
      check all entry_price <- float(min: 0.01, max: 100_000.0),
                exit_price <- float(min: 0.01, max: 100_000.0),
                quantity <- float(min: 0.001, max: 100.0),
                initial_capital <- float(min: 10_000.0, max: 1_000_000.0),
                max_runs: 100 do

        cost = entry_price * quantity

        if cost < initial_capital do
          manager = PositionManager.init(initial_capital)
          entry_time = ~U[2024-01-01 10:00:00Z]
          exit_time = ~U[2024-01-01 11:00:00Z]

          {:ok, manager} = PositionManager.open_position(manager, "BTC/USD", :short, entry_price, quantity, entry_time)
          {:ok, _updated_manager, pnl} = PositionManager.close_position(manager, exit_price, exit_time)

          # Calculate expected PnL for short
          expected_pnl = (entry_price - exit_price) * quantity

          assert_in_delta pnl, expected_pnl, 0.01
        end
      end
    end

    property "total realized PnL equals sum of all position PnLs" do
      check all prices <- list_of(float(min: 1000.0, max: 100_000.0), min_length: 4, max_length: 10),
                initial_capital <- float(min: 100_000.0, max: 1_000_000.0),
                max_runs: 50 do

        manager = PositionManager.init(initial_capital)
        entry_time = ~U[2024-01-01 10:00:00Z]

        # Execute trades with pairs of prices (entry, exit)
        price_pairs = Enum.chunk_every(prices, 2, 2, :discard)

        {final_manager, pnls} =
          Enum.reduce(price_pairs, {manager, []}, fn [entry_price, exit_price], {mgr, pnl_list} ->
            # Use small quantity to avoid capital exhaustion
            quantity = 0.01
            cost = entry_price * quantity

            if cost < PositionManager.get_available_capital(mgr) do
              exit_time = DateTime.add(entry_time, length(pnl_list) * 3600, :second)

              {:ok, mgr} = PositionManager.open_position(mgr, "BTC/USD", :long, entry_price, quantity, entry_time)
              {:ok, mgr, pnl} = PositionManager.close_position(mgr, exit_price, exit_time)

              {mgr, [pnl | pnl_list]}
            else
              {mgr, pnl_list}
            end
          end)

        # Verify total PnL equals sum of individual PnLs
        expected_total = Enum.sum(pnls)
        actual_total = PositionManager.get_total_realized_pnl(final_manager)

        assert_in_delta actual_total, expected_total, 0.1
      end
    end

    property "capital conservation: final equity equals initial capital plus total PnL" do
      check all entry_price <- float(min: 1000.0, max: 50_000.0),
                exit_price <- float(min: 1000.0, max: 50_000.0),
                quantity <- float(min: 0.01, max: 1.0),
                initial_capital <- float(min: 100_000.0, max: 500_000.0),
                side <- member_of([:long, :short]),
                max_runs: 100 do

        cost = entry_price * quantity

        if cost < initial_capital do
          manager = PositionManager.init(initial_capital)
          entry_time = ~U[2024-01-01 10:00:00Z]
          exit_time = ~U[2024-01-01 11:00:00Z]

          {:ok, manager} = PositionManager.open_position(manager, "BTC/USD", side, entry_price, quantity, entry_time)
          {:ok, updated_manager, pnl} = PositionManager.close_position(manager, exit_price, exit_time)

          # Final capital should equal initial capital + realized PnL
          final_equity = PositionManager.calculate_total_equity(updated_manager)
          expected_equity = initial_capital + pnl

          assert_in_delta final_equity, expected_equity, 0.1
        end
      end
    end

    property "PnL sign is correct: profit when price moves favorably" do
      check all entry_price <- float(min: 1000.0, max: 50_000.0),
                price_move_pct <- float(min: -50.0, max: 50.0),
                quantity <- float(min: 0.01, max: 1.0),
                initial_capital <- float(min: 100_000.0, max: 500_000.0),
                side <- member_of([:long, :short]),
                max_runs: 100 do

        exit_price = entry_price * (1 + price_move_pct / 100)

        # Skip if exit price is invalid
        if exit_price > 0 do
          cost = entry_price * quantity

          if cost < initial_capital do
            manager = PositionManager.init(initial_capital)
            entry_time = ~U[2024-01-01 10:00:00Z]
            exit_time = ~U[2024-01-01 11:00:00Z]

            {:ok, manager} = PositionManager.open_position(manager, "BTC/USD", side, entry_price, quantity, entry_time)
            {:ok, _updated_manager, pnl} = PositionManager.close_position(manager, exit_price, exit_time)

            # Verify PnL sign
            case side do
              :long ->
                cond do
                  exit_price > entry_price ->
                    assert pnl > 0 || abs(pnl) < 0.01, "Long position should profit when price increases"
                  exit_price < entry_price ->
                    assert pnl < 0 || abs(pnl) < 0.01, "Long position should lose when price decreases"
                  true ->
                    assert_in_delta pnl, 0.0, 0.01
                end

              :short ->
                cond do
                  exit_price < entry_price ->
                    assert pnl > 0 || abs(pnl) < 0.01, "Short position should profit when price decreases"
                  exit_price > entry_price ->
                    assert pnl < 0 || abs(pnl) < 0.01, "Short position should lose when price increases"
                  true ->
                    assert_in_delta pnl, 0.0, 0.01
                end
            end
          end
        end
      end
    end
  end
end
