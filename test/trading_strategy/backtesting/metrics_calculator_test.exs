defmodule TradingStrategy.Backtesting.MetricsCalculatorTest do
  use ExUnit.Case, async: true

  alias TradingStrategy.Backtesting.MetricsCalculator

  describe "calculate_metrics/3 - edge cases" do
    test "zero trades returns N/A for trade-dependent metrics" do
      # Empty trades list
      trades = []

      # Flat equity curve (no trades)
      equity_history = [
        {~U[2024-01-01 00:00:00Z], 10000.0},
        {~U[2024-01-01 01:00:00Z], 10000.0},
        {~U[2024-01-01 02:00:00Z], 10000.0}
      ]

      initial_capital = 10000.0

      metrics = MetricsCalculator.calculate_metrics(trades, equity_history, initial_capital)

      # Verify metrics for zero trades
      assert metrics.total_return == 0.0
      assert metrics.total_return_abs == 0.0
      assert metrics.trade_count == 0
      assert metrics.winning_trades == 0
      assert metrics.losing_trades == 0
      assert metrics.max_consecutive_wins == 0
      assert metrics.max_consecutive_losses == 0
      assert metrics.max_drawdown == 0.0
      assert metrics.final_equity == 10000.0

      # These should be nil (N/A) for zero trades
      assert metrics.win_rate == nil
      assert metrics.sharpe_ratio == nil
      assert metrics.average_win == nil
      assert metrics.average_loss == nil
      assert metrics.profit_factor == nil
      assert metrics.average_trade_duration_minutes == nil
    end

    test "all winning trades calculates correctly" do
      trades = [
        %{pnl: 100.0, duration_seconds: 3600},
        %{pnl: 150.0, duration_seconds: 7200},
        %{pnl: 200.0, duration_seconds: 5400}
      ]

      equity_history = [
        {~U[2024-01-01 00:00:00Z], 10000.0},
        {~U[2024-01-01 01:00:00Z], 10100.0},
        {~U[2024-01-01 02:00:00Z], 10250.0},
        {~U[2024-01-01 03:00:00Z], 10450.0}
      ]

      initial_capital = 10000.0

      metrics = MetricsCalculator.calculate_metrics(trades, equity_history, initial_capital)

      assert metrics.trade_count == 3
      assert metrics.winning_trades == 3
      assert metrics.losing_trades == 0
      assert metrics.win_rate == 1.0
      assert metrics.average_win == 150.0
      assert metrics.average_loss == 0.0
      assert metrics.profit_factor == 999.99  # Infinity case
      assert metrics.total_return_abs == 450.0
      assert metrics.max_consecutive_wins == 3
      assert metrics.max_consecutive_losses == 0
    end

    test "all losing trades calculates correctly" do
      trades = [
        %{pnl: -100.0, duration_seconds: 3600},
        %{pnl: -150.0, duration_seconds: 7200},
        %{pnl: -200.0, duration_seconds: 5400}
      ]

      equity_history = [
        {~U[2024-01-01 00:00:00Z], 10000.0},
        {~U[2024-01-01 01:00:00Z], 9900.0},
        {~U[2024-01-01 02:00:00Z], 9750.0},
        {~U[2024-01-01 03:00:00Z], 9550.0}
      ]

      initial_capital = 10000.0

      metrics = MetricsCalculator.calculate_metrics(trades, equity_history, initial_capital)

      assert metrics.trade_count == 3
      assert metrics.winning_trades == 0
      assert metrics.losing_trades == 3
      assert metrics.win_rate == 0.0
      assert metrics.average_win == 0.0
      assert metrics.average_loss == -150.0
      assert metrics.profit_factor == 0.0
      assert metrics.total_return_abs == -450.0
      assert metrics.max_consecutive_wins == 0
      assert metrics.max_consecutive_losses == 3
      assert metrics.max_drawdown > 0
    end

    test "mixed winning and losing trades calculates correctly" do
      trades = [
        %{pnl: 100.0, duration_seconds: 3600},
        %{pnl: -50.0, duration_seconds: 1800},
        %{pnl: 200.0, duration_seconds: 7200},
        %{pnl: -75.0, duration_seconds: 3600},
        %{pnl: 150.0, duration_seconds: 5400}
      ]

      equity_history = [
        {~U[2024-01-01 00:00:00Z], 10000.0},
        {~U[2024-01-01 01:00:00Z], 10100.0},
        {~U[2024-01-01 02:00:00Z], 10050.0},
        {~U[2024-01-01 03:00:00Z], 10250.0},
        {~U[2024-01-01 04:00:00Z], 10175.0},
        {~U[2024-01-01 05:00:00Z], 10325.0}
      ]

      initial_capital = 10000.0

      metrics = MetricsCalculator.calculate_metrics(trades, equity_history, initial_capital)

      assert metrics.trade_count == 5
      assert metrics.winning_trades == 3
      assert metrics.losing_trades == 2
      assert metrics.win_rate == 0.6
      assert metrics.average_win == 150.0
      assert metrics.average_loss == -62.5
      assert metrics.total_return_abs == 325.0

      # Profit factor = gross_profit / gross_loss = 450 / 125 = 3.6
      assert metrics.profit_factor == 3.6
    end

    test "breakeven trades (zero PnL) are handled correctly" do
      trades = [
        %{pnl: 100.0, duration_seconds: 3600},
        %{pnl: 0.0, duration_seconds: 1800},
        # Breakeven trade
        %{pnl: -50.0, duration_seconds: 3600}
      ]

      equity_history = [
        {~U[2024-01-01 00:00:00Z], 10000.0},
        {~U[2024-01-01 01:00:00Z], 10100.0},
        {~U[2024-01-01 02:00:00Z], 10100.0},
        {~U[2024-01-01 03:00:00Z], 10050.0}
      ]

      initial_capital = 10000.0

      metrics = MetricsCalculator.calculate_metrics(trades, equity_history, initial_capital)

      assert metrics.trade_count == 3
      assert metrics.winning_trades == 1
      assert metrics.losing_trades == 1
      # Breakeven trade not counted
      assert metrics.win_rate == 0.3333
      # 1/3 winning
      assert metrics.total_return_abs == 50.0
    end

    test "handles very small PnL values correctly" do
      trades = [
        %{pnl: 0.01, duration_seconds: 3600},
        %{pnl: -0.01, duration_seconds: 3600},
        %{pnl: 0.02, duration_seconds: 3600}
      ]

      equity_history = [
        {~U[2024-01-01 00:00:00Z], 10000.0},
        {~U[2024-01-01 01:00:00Z], 10000.01},
        {~U[2024-01-01 02:00:00Z], 10000.00},
        {~U[2024-01-01 03:00:00Z], 10000.02}
      ]

      initial_capital = 10000.0

      metrics = MetricsCalculator.calculate_metrics(trades, equity_history, initial_capital)

      assert metrics.trade_count == 3
      assert metrics.total_return_abs == 0.02
      assert is_float(metrics.profit_factor)
    end

    test "consecutive wins and losses tracked correctly" do
      trades = [
        %{pnl: 100.0, duration_seconds: 3600},
        # Win
        %{pnl: 50.0, duration_seconds: 3600},
        # Win
        %{pnl: 75.0, duration_seconds: 3600},
        # Win
        %{pnl: -30.0, duration_seconds: 3600},
        # Loss
        %{pnl: -40.0, duration_seconds: 3600},
        # Loss
        %{pnl: 60.0, duration_seconds: 3600},
        # Win
        %{pnl: -20.0, duration_seconds: 3600}
        # Loss
      ]

      equity_history = [
        {~U[2024-01-01 00:00:00Z], 10000.0},
        {~U[2024-01-01 01:00:00Z], 10100.0},
        {~U[2024-01-01 02:00:00Z], 10150.0},
        {~U[2024-01-01 03:00:00Z], 10225.0},
        {~U[2024-01-01 04:00:00Z], 10195.0},
        {~U[2024-01-01 05:00:00Z], 10155.0},
        {~U[2024-01-01 06:00:00Z], 10215.0},
        {~U[2024-01-01 07:00:00Z], 10195.0}
      ]

      initial_capital = 10000.0

      metrics = MetricsCalculator.calculate_metrics(trades, equity_history, initial_capital)

      assert metrics.max_consecutive_wins == 3
      assert metrics.max_consecutive_losses == 2
    end

    test "average trade duration calculated correctly" do
      trades = [
        %{pnl: 100.0, duration_seconds: 3600},
        # 60 minutes
        %{pnl: 50.0, duration_seconds: 7200},
        # 120 minutes
        %{pnl: 75.0, duration_seconds: 5400}
        # 90 minutes
      ]

      equity_history = [
        {~U[2024-01-01 00:00:00Z], 10000.0},
        {~U[2024-01-01 01:00:00Z], 10100.0},
        {~U[2024-01-01 02:00:00Z], 10150.0},
        {~U[2024-01-01 03:00:00Z], 10225.0}
      ]

      initial_capital = 10000.0

      metrics = MetricsCalculator.calculate_metrics(trades, equity_history, initial_capital)

      # Average: (60 + 120 + 90) / 3 = 90 minutes
      assert metrics.average_trade_duration_minutes == 90
    end

    test "trades without duration_seconds field are ignored in duration calculation" do
      trades = [
        %{pnl: 100.0, duration_seconds: 3600},
        %{pnl: 50.0},
        # Missing duration_seconds
        %{pnl: 75.0, duration_seconds: 7200}
      ]

      equity_history = [
        {~U[2024-01-01 00:00:00Z], 10000.0},
        {~U[2024-01-01 01:00:00Z], 10100.0},
        {~U[2024-01-01 02:00:00Z], 10150.0},
        {~U[2024-01-01 03:00:00Z], 10225.0}
      ]

      initial_capital = 10000.0

      metrics = MetricsCalculator.calculate_metrics(trades, equity_history, initial_capital)

      # Average of only the trades with duration: (60 + 120) / 2 = 90 minutes
      assert metrics.average_trade_duration_minutes == 90
    end

    test "handles empty equity history gracefully" do
      trades = []
      equity_history = []
      initial_capital = 10000.0

      metrics = MetricsCalculator.calculate_metrics(trades, equity_history, initial_capital)

      # Should use initial capital as final equity
      assert metrics.final_equity == 10000.0
      assert metrics.total_return == 0.0
      assert metrics.max_drawdown == 0.0
    end

    test "calculates max drawdown correctly" do
      trades = []

      # Equity curve with significant drawdown
      equity_history = [
        {~U[2024-01-01 00:00:00Z], 10000.0},
        {~U[2024-01-01 01:00:00Z], 11000.0},
        # Peak
        {~U[2024-01-01 02:00:00Z], 10500.0},
        # Drawdown starts
        {~U[2024-01-01 03:00:00Z], 9500.0},
        # Drawdown continues (1500 from peak = 13.6%)
        {~U[2024-01-01 04:00:00Z], 10000.0},
        # Recovery
        {~U[2024-01-01 05:00:00Z], 11500.0}
        # New peak
      ]

      initial_capital = 10000.0

      metrics = MetricsCalculator.calculate_metrics(trades, equity_history, initial_capital)

      # Max drawdown: (11000 - 9500) / 11000 = 0.1364
      assert_in_delta metrics.max_drawdown, 0.1364, 0.001
    end

    test "sharpe ratio is nil for zero trades" do
      trades = []

      equity_history = [
        {~U[2024-01-01 00:00:00Z], 10000.0},
        {~U[2024-01-01 01:00:00Z], 10000.0}
      ]

      initial_capital = 10000.0

      metrics = MetricsCalculator.calculate_metrics(trades, equity_history, initial_capital)

      assert metrics.sharpe_ratio == nil
    end

    test "handles single trade correctly" do
      trades = [
        %{pnl: 150.0, duration_seconds: 3600}
      ]

      equity_history = [
        {~U[2024-01-01 00:00:00Z], 10000.0},
        {~U[2024-01-01 01:00:00Z], 10150.0}
      ]

      initial_capital = 10000.0

      metrics = MetricsCalculator.calculate_metrics(trades, equity_history, initial_capital)

      assert metrics.trade_count == 1
      assert metrics.winning_trades == 1
      assert metrics.losing_trades == 0
      assert metrics.win_rate == 1.0
      assert metrics.average_win == 150.0
      assert metrics.max_consecutive_wins == 1
      assert metrics.max_consecutive_losses == 0
    end
  end
end
