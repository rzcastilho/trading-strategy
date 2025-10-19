defmodule TradingStrategy.BacktestTest do
  use ExUnit.Case, async: true
  alias TradingStrategy.{Backtest, Definition, Position}
  import TradingStrategy.TestHelpers

  setup do
    strategy = simple_strategy()
    market_data = generate_market_data(count: 50, trend: :up)

    {:ok, strategy: strategy, market_data: market_data}
  end

  describe "run/1" do
    test "runs a complete backtest", %{strategy: strategy, market_data: data} do
      result =
        Backtest.run(
          strategy: strategy,
          market_data: data,
          symbol: "TEST",
          initial_capital: 10_000
        )

      assert result.strategy == :test_strategy
      assert result.symbol == "TEST"
      assert is_map(result.metrics)
      assert is_list(result.trades)
      assert is_list(result.signals)
      assert is_list(result.equity_curve)
    end

    test "calculates metrics correctly", %{strategy: strategy, market_data: data} do
      result =
        Backtest.run(
          strategy: strategy,
          market_data: data,
          initial_capital: 10_000
        )

      metrics = result.metrics

      assert is_number(metrics.total_trades)
      assert is_number(metrics.win_rate)
      assert is_number(metrics.profit_factor)
      assert is_number(metrics.net_profit)
      assert is_number(metrics.max_drawdown)
      assert is_number(metrics.sharpe_ratio)
    end

    test "applies commission and slippage", %{strategy: strategy, market_data: data} do
      result =
        Backtest.run(
          strategy: strategy,
          market_data: data,
          initial_capital: 10_000,
          commission: 0.001,
          slippage: 0.0005
        )

      # Commission and slippage should be calculated if there are trades
      assert is_number(result.metrics.total_commission)
      assert is_number(result.metrics.total_slippage)

      # If there are trades, commission/slippage should be > 0
      if result.metrics.total_trades > 0 do
        assert result.metrics.total_commission > 0
        assert result.metrics.total_slippage > 0
      end
    end
  end

  describe "calculate_metrics/4" do
    test "returns zero metrics for no trades" do
      metrics = Backtest.calculate_metrics([], 10_000, 0.001, 0.0)

      assert metrics.total_trades == 0
      assert metrics.win_rate == 0.0
      assert metrics.net_profit == 0.0
    end

    test "calculates metrics for profitable trades" do
      trades = [
        %Position{
          pnl: 100, pnl_percent: 10, status: :closed,
          entry_price: 100, exit_price: 110, quantity: 1, direction: :long
        },
        %Position{
          pnl: 200, pnl_percent: 20, status: :closed,
          entry_price: 100, exit_price: 120, quantity: 1, direction: :long
        },
        %Position{
          pnl: -50, pnl_percent: -5, status: :closed,
          entry_price: 100, exit_price: 95, quantity: 1, direction: :long
        }
      ]

      metrics = Backtest.calculate_metrics(trades, 10_000, 0, 0)

      assert metrics.total_trades == 3
      assert metrics.winning_trades == 2
      assert metrics.losing_trades == 1
      assert_float_equal(metrics.win_rate, 66.67, 0.1)
      assert metrics.gross_profit == 300
      assert metrics.gross_loss == 50
    end
  end

  describe "calculate_equity_curve/2" do
    test "generates equity curve from positions" do
      timestamp1 = ~U[2025-01-01 00:00:00Z]
      timestamp2 = ~U[2025-01-01 01:00:00Z]

      trades = [
        %Position{
          id: "1", pnl: 100, exit_time: timestamp1, status: :closed,
          entry_price: 100, exit_price: 110, quantity: 1, direction: :long
        },
        %Position{
          id: "2", pnl: 50, exit_time: timestamp2, status: :closed,
          entry_price: 110, exit_price: 115, quantity: 1, direction: :long
        }
      ]

      curve = Backtest.calculate_equity_curve(trades, 10_000)

      assert length(curve) == 2
      assert hd(curve).equity == 10_100
      assert List.last(curve).equity == 10_150
    end

    test "returns empty curve for no trades" do
      curve = Backtest.calculate_equity_curve([], 10_000)
      assert curve == []
    end
  end

  describe "calculate_max_drawdown/2" do
    test "calculates maximum drawdown" do
      trades = [
        %Position{
          pnl: 1000, exit_time: ~U[2025-01-01 00:00:00Z], status: :closed,
          entry_price: 100, exit_price: 110, quantity: 100, direction: :long
        },
        %Position{
          pnl: -500, exit_time: ~U[2025-01-01 01:00:00Z], status: :closed,
          entry_price: 110, exit_price: 105, quantity: 100, direction: :long
        },
        %Position{
          pnl: -300, exit_time: ~U[2025-01-01 02:00:00Z], status: :closed,
          entry_price: 105, exit_price: 102, quantity: 100, direction: :long
        },
        %Position{
          pnl: 200, exit_time: ~U[2025-01-01 03:00:00Z], status: :closed,
          entry_price: 102, exit_price: 104, quantity: 100, direction: :long
        }
      ]

      {max_dd, max_dd_pct} = Backtest.calculate_max_drawdown(trades, 10_000)

      assert max_dd > 0
      assert max_dd_pct > 0
    end

    test "returns zero for no trades" do
      {max_dd, max_dd_pct} = Backtest.calculate_max_drawdown([], 10_000)
      assert max_dd == 0.0
      assert max_dd_pct == 0.0
    end
  end

  describe "calculate_sharpe_ratio/2" do
    test "calculates Sharpe ratio" do
      trades = [
        %Position{pnl_percent: 5, status: :closed, entry_price: 100, quantity: 1, direction: :long},
        %Position{pnl_percent: 3, status: :closed, entry_price: 100, quantity: 1, direction: :long},
        %Position{pnl_percent: -2, status: :closed, entry_price: 100, quantity: 1, direction: :long},
        %Position{pnl_percent: 4, status: :closed, entry_price: 100, quantity: 1, direction: :long}
      ]

      sharpe = Backtest.calculate_sharpe_ratio(trades)
      assert is_number(sharpe)
    end

    test "returns zero for insufficient trades" do
      assert Backtest.calculate_sharpe_ratio([]) == 0.0

      single_trade = %Position{
        pnl_percent: 5, status: :closed, entry_price: 100, quantity: 1, direction: :long
      }
      assert Backtest.calculate_sharpe_ratio([single_trade]) == 0.0
    end
  end
end
