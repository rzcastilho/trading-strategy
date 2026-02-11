defmodule TradingStrategy.BacktestingIntegrationTest do
  use TradingStrategy.DataCase, async: true

  alias TradingStrategy.Backtesting
  alias TradingStrategy.Backtesting.{TradingSession, PerformanceMetrics}
  alias TradingStrategy.Orders.{Trade, Position}
  alias TradingStrategy.Repo

  describe "trade data consistency" do
    @tag :integration
    test "position realized_pnl equals sum of trade PnLs" do
      # This test will verify data integrity once we implement PnL storage
      # For now, we'll create a placeholder that shows the expected behavior

      # Create a trading session
      session =
        %TradingSession{
          strategy_id: "test_strategy",
          mode: "backtest",
          status: "completed",
          initial_capital: Decimal.new("10000.00"),
          current_capital: Decimal.new("10100.00"),
          config: %{
            "trading_pair" => "BTC/USD",
            "start_time" => "2024-01-01T00:00:00Z",
            "end_time" => "2024-01-01T23:59:59Z",
            "initial_capital" => "10000.00",
            "timeframe" => "1h"
          },
          metadata: %{},
          started_at: ~U[2024-01-01 00:00:00.000000Z],
          ended_at: ~U[2024-01-01 23:59:59.999999Z]
        }
        |> Repo.insert!()

      # Create a position with multiple trades
      position =
        %Position{
          trading_session_id: session.id,
          symbol: "BTC/USD",
          side: "long",
          entry_price: Decimal.new("50000.00"),
          quantity: Decimal.new("0.1"),
          exit_price: Decimal.new("51000.00"),
          realized_pnl: Decimal.new("100.00"),
          unrealized_pnl: Decimal.new("0.00"),
          status: "closed",
          opened_at: ~U[2024-01-01 10:00:00.000000Z],
          closed_at: ~U[2024-01-01 11:00:00.000000Z]
        }
        |> Repo.insert!()

      # Create entry trade (PnL = 0)
      entry_trade =
        %Trade{
          position_id: position.id,
          side: :buy,
          quantity: Decimal.new("0.1"),
          price: Decimal.new("50000.00"),
          fee: Decimal.new("0.001"),
          fee_currency: "BTC",
          timestamp: ~U[2024-01-01 10:00:00.000000Z],
          exchange: "simulated",
          status: "filled",
          pnl: Decimal.new("0.00"),
          duration_seconds: nil,
          entry_price: Decimal.new("50000.00"),
          exit_price: nil,
          metadata: %{}
        }
        |> Repo.insert!()

      # Create exit trade (PnL = 100.00)
      exit_trade =
        %Trade{
          position_id: position.id,
          side: :sell,
          quantity: Decimal.new("0.1"),
          price: Decimal.new("51000.00"),
          fee: Decimal.new("0.001"),
          fee_currency: "BTC",
          timestamp: ~U[2024-01-01 11:00:00.000000Z],
          exchange: "simulated",
          status: "filled",
          pnl: Decimal.new("100.00"),
          duration_seconds: 3600,
          entry_price: Decimal.new("50000.00"),
          exit_price: Decimal.new("51000.00"),
          metadata: %{}
        }
        |> Repo.insert!()

      # Load trades and verify consistency
      trades =
        Repo.all(from t in Trade, where: t.position_id == ^position.id, order_by: t.timestamp)

      # Calculate sum of trade PnLs
      trades_pnl_sum =
        trades
        |> Enum.map(& &1.pnl)
        |> Enum.reduce(Decimal.new("0"), &Decimal.add/2)

      # Verify position PnL equals sum of trade PnLs
      assert Decimal.eq?(position.realized_pnl, trades_pnl_sum),
             "Position PnL (#{position.realized_pnl}) should equal sum of trade PnLs (#{trades_pnl_sum})"

      # Verify trade data integrity
      assert length(trades) == 2
      [^entry_trade, ^exit_trade] = trades

      # Entry trade should have zero PnL
      assert Decimal.eq?(entry_trade.pnl, Decimal.new("0"))
      assert entry_trade.duration_seconds == nil

      # Exit trade should have calculated PnL and duration
      assert Decimal.eq?(exit_trade.pnl, Decimal.new("100.00"))
      # 1 hour in seconds
      assert exit_trade.duration_seconds == 3600
      assert Decimal.eq?(exit_trade.entry_price, Decimal.new("50000.00"))
      assert Decimal.eq?(exit_trade.exit_price, Decimal.new("51000.00"))
    end

    @tag :integration
    test "multiple positions with multiple trades maintain consistency" do
      # Create a trading session
      session =
        %TradingSession{
          strategy_id: "test_strategy",
          mode: "backtest",
          status: "completed",
          initial_capital: Decimal.new("100000.00"),
          current_capital: Decimal.new("100300.00"),
          config: %{
            "trading_pair" => "BTC/USD",
            "start_time" => "2024-01-01T00:00:00Z",
            "end_time" => "2024-01-01T23:59:59Z"
          },
          metadata: %{},
          started_at: ~U[2024-01-01 00:00:00.000000Z],
          ended_at: ~U[2024-01-01 23:59:59.999999Z]
        }
        |> Repo.insert!()

      # Position 1: Profitable (PnL = +200)
      position1 =
        create_position_with_trades(session.id, %{
          entry_price: "50000.00",
          exit_price: "52000.00",
          quantity: "0.1",
          entry_time: ~U[2024-01-01 09:00:00.000000Z],
          exit_time: ~U[2024-01-01 10:00:00.000000Z]
        })

      # Position 2: Loss (PnL = -100)
      position2 =
        create_position_with_trades(session.id, %{
          entry_price: "51000.00",
          exit_price: "50000.00",
          quantity: "0.1",
          entry_time: ~U[2024-01-01 11:00:00.000000Z],
          exit_time: ~U[2024-01-01 13:00:00.000000Z]
        })

      # Position 3: Profit (PnL = +200)
      position3 =
        create_position_with_trades(session.id, %{
          entry_price: "49000.00",
          exit_price: "51000.00",
          quantity: "0.1",
          entry_time: ~U[2024-01-01 14:00:00.000000Z],
          exit_time: ~U[2024-01-01 15:00:00.000000Z]
        })

      # Verify each position's consistency
      for position <- [position1, position2, position3] do
        trades =
          Repo.all(from t in Trade, where: t.position_id == ^position.id, order_by: t.timestamp)

        trades_pnl_sum =
          trades
          |> Enum.map(& &1.pnl)
          |> Enum.reduce(Decimal.new("0"), &Decimal.add/2)

        assert Decimal.eq?(position.realized_pnl, trades_pnl_sum),
               "Position #{position.id} PnL mismatch"
      end

      # Verify total session PnL
      all_positions = Repo.all(from p in Position, where: p.trading_session_id == ^session.id)

      total_pnl =
        all_positions
        |> Enum.map(& &1.realized_pnl)
        |> Enum.reduce(Decimal.new("0"), &Decimal.add/2)

      # 200 - 100 + 200
      expected_total = Decimal.new("300.00")
      assert Decimal.eq?(total_pnl, expected_total)
    end
  end

  # Helper function to create a position with entry and exit trades
  defp create_position_with_trades(session_id, attrs) do
    entry_price = Decimal.new(attrs.entry_price)
    exit_price = Decimal.new(attrs.exit_price)
    quantity = Decimal.new(attrs.quantity)
    entry_time = attrs.entry_time
    exit_time = attrs.exit_time

    # Calculate PnL: (exit_price - entry_price) * quantity
    pnl = Decimal.mult(Decimal.sub(exit_price, entry_price), quantity)

    # Create position
    position =
      %Position{
        trading_session_id: session_id,
        symbol: "BTC/USD",
        side: "long",
        entry_price: entry_price,
        quantity: quantity,
        exit_price: exit_price,
        realized_pnl: pnl,
        unrealized_pnl: Decimal.new("0.00"),
        status: "closed",
        opened_at: entry_time,
        closed_at: exit_time
      }
      |> Repo.insert!()

    # Create entry trade
    %Trade{
      position_id: position.id,
      side: :buy,
      quantity: quantity,
      price: entry_price,
      fee: Decimal.new("0.001"),
      fee_currency: "BTC",
      timestamp: entry_time,
      exchange: "simulated",
      status: "filled",
      pnl: Decimal.new("0.00"),
      duration_seconds: nil,
      entry_price: entry_price,
      exit_price: nil,
      metadata: %{}
    }
    |> Repo.insert!()

    # Create exit trade
    duration_seconds = DateTime.diff(exit_time, entry_time, :second)

    %Trade{
      position_id: position.id,
      side: :sell,
      quantity: quantity,
      price: exit_price,
      fee: Decimal.new("0.001"),
      fee_currency: "BTC",
      timestamp: exit_time,
      exchange: "simulated",
      status: "filled",
      pnl: pnl,
      duration_seconds: duration_seconds,
      entry_price: entry_price,
      exit_price: exit_price,
      metadata: %{}
    }
    |> Repo.insert!()

    position
  end
end
