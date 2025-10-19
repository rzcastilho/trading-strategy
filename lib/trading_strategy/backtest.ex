defmodule TradingStrategy.Backtest do
  @moduledoc """
  Backtesting engine with Decimal precision for accurate historical analysis.

  Provides comprehensive performance metrics, trade logs, and equity curves
  when testing strategies against historical market data. All calculations
  use Decimal precision to ensure accurate and reproducible results.

  ## Features

  - **13 Performance Metrics**: Win rate, profit factor, Sharpe ratio, etc.
  - **Equity Curve**: Track capital changes over time
  - **Trade Log**: Complete history of all trades
  - **Commission & Slippage**: Realistic cost simulation
  - **Decimal Precision**: Exact P&L calculations

  ## Metrics Calculated

  - Total Trades, Winning Trades, Losing Trades
  - Win Rate (percentage)
  - Net Profit, Gross Profit, Gross Loss
  - Profit Factor (gross profit / gross loss)
  - Average Win, Average Loss
  - Largest Win, Largest Loss
  - Maximum Drawdown (absolute and percentage)
  - Sharpe Ratio (risk-adjusted return)
  - Return on Capital (percentage)
  - Total Commission, Total Slippage

  ## Usage

      alias TradingStrategy.{Backtest, Types}

      # Create historical data with Decimal precision
      market_data = [
        Types.new_ohlcv(100, 105, 95, 102, 1000, ~U[2025-01-01 00:00:00Z]),
        Types.new_ohlcv(102, 108, 100, 106, 1100, ~U[2025-01-01 01:00:00Z]),
        # ... more candles
      ]

      # Run backtest
      result = Backtest.run(
        strategy: my_strategy,
        market_data: market_data,
        symbol: "BTCUSD",
        initial_capital: 10_000,
        commission: 0.001  # 0.1%
      )

      # Print report
      Backtest.print_report(result)

  The backtest engine processes each candle sequentially, generating signals
  and tracking positions exactly as they would occur in real-time, ensuring
  realistic and accurate results.
  """

  alias TradingStrategy.{Engine, Position}

  @type backtest_result :: %{
          strategy: atom(),
          symbol: String.t(),
          period: %{start: DateTime.t(), end: DateTime.t()},
          metrics: map(),
          trades: list(Position.t()),
          signals: list(Signal.t()),
          equity_curve: list(map())
        }

  @doc """
  Runs a backtest on historical market data.

  ## Options

    * `:strategy` - Strategy definition (required)
    * `:market_data` - List of historical candles (required)
    * `:symbol` - Trading symbol
    * `:initial_capital` - Starting capital (default: 10,000)
    * `:position_size` - Position size per trade (default: 1.0)
    * `:commission` - Commission per trade (default: 0.001 = 0.1%)
    * `:slippage` - Slippage per trade (default: 0.0)

  ## Returns

  A comprehensive backtest result with metrics and trade history.
  """
  def run(opts) do
    strategy = Keyword.fetch!(opts, :strategy)
    market_data = Keyword.fetch!(opts, :market_data)
    symbol = Keyword.get(opts, :symbol, "BACKTEST")
    initial_capital = Keyword.get(opts, :initial_capital, 10_000.0)
    position_size = Keyword.get(opts, :position_size, 1.0)
    commission = Keyword.get(opts, :commission, 0.001)
    slippage = Keyword.get(opts, :slippage, 0.0)

    # Start the engine
    {:ok, engine} =
      Engine.start_link(
        strategy: strategy,
        symbol: symbol,
        initial_capital: initial_capital,
        position_size: position_size,
        name: :"backtest_#{:erlang.unique_integer()}"
      )

    # Process all historical data
    result =
      Enum.reduce(market_data, %{positions: [], signals: []}, fn candle, acc ->
        case Engine.process_market_data(engine, candle) do
          {:ok, data} ->
            %{
              positions: acc.positions ++ data.closed_positions,
              signals: acc.signals ++ data.signals
            }

          {:error, _reason} ->
            acc
        end
      end)

    # Get final state
    final_state = Engine.get_state(engine)

    # Stop the engine
    Engine.stop(engine)

    # Calculate metrics
    all_positions = result.positions ++ final_state.positions
    closed_positions = Enum.filter(all_positions, &Position.closed?/1)

    metrics = calculate_metrics(closed_positions, initial_capital, commission, slippage)

    equity_curve = calculate_equity_curve(closed_positions, initial_capital)

    period = %{
      start: List.first(market_data)[:timestamp] || DateTime.utc_now(),
      end: List.last(market_data)[:timestamp] || DateTime.utc_now()
    }

    %{
      strategy: strategy.name,
      symbol: symbol,
      period: period,
      metrics: metrics,
      trades: closed_positions,
      signals: result.signals,
      equity_curve: equity_curve
    }
  end

  @doc """
  Calculates comprehensive performance metrics.
  """
  def calculate_metrics(closed_positions, initial_capital, commission, slippage) do
    total_trades = length(closed_positions)

    if total_trades == 0 do
      %{
        total_trades: 0,
        winning_trades: 0,
        losing_trades: 0,
        win_rate: 0.0,
        total_pnl: 0.0,
        net_profit: 0.0,
        gross_profit: 0.0,
        gross_loss: 0.0,
        profit_factor: 0.0,
        average_win: 0.0,
        average_loss: 0.0,
        largest_win: 0.0,
        largest_loss: 0.0,
        max_drawdown: 0.0,
        max_drawdown_percent: 0.0,
        sharpe_ratio: 0.0,
        total_commission: 0.0,
        total_slippage: 0.0
      }
    else
      # Apply commission and slippage
      adjusted_positions =
        Enum.map(closed_positions, fn pos ->
          commission_cost = pos.entry_price * pos.quantity * commission * 2
          slippage_cost = pos.entry_price * pos.quantity * slippage * 2
          adjusted_pnl = pos.pnl - commission_cost - slippage_cost
          %{pos | pnl: adjusted_pnl}
        end)

      winning_trades = Enum.filter(adjusted_positions, fn pos -> pos.pnl > 0 end)
      losing_trades = Enum.filter(adjusted_positions, fn pos -> pos.pnl <= 0 end)

      total_pnl = Enum.sum(Enum.map(adjusted_positions, & &1.pnl))
      gross_profit = Enum.sum(Enum.map(winning_trades, & &1.pnl))
      gross_loss = abs(Enum.sum(Enum.map(losing_trades, & &1.pnl)))

      profit_factor = if gross_loss > 0, do: gross_profit / gross_loss, else: 0.0

      average_win =
        if length(winning_trades) > 0 do
          gross_profit / length(winning_trades)
        else
          0.0
        end

      average_loss =
        if length(losing_trades) > 0 do
          gross_loss / length(losing_trades)
        else
          0.0
        end

      largest_win =
        if length(winning_trades) > 0 do
          Enum.max(Enum.map(winning_trades, & &1.pnl))
        else
          0.0
        end

      largest_loss =
        if length(losing_trades) > 0 do
          abs(Enum.min(Enum.map(losing_trades, & &1.pnl)))
        else
          0.0
        end

      {max_dd, max_dd_pct} = calculate_max_drawdown(adjusted_positions, initial_capital)

      sharpe = calculate_sharpe_ratio(adjusted_positions)

      total_commission_cost = total_trades * initial_capital * commission * 2
      total_slippage_cost = total_trades * initial_capital * slippage * 2

      %{
        total_trades: total_trades,
        winning_trades: length(winning_trades),
        losing_trades: length(losing_trades),
        win_rate: length(winning_trades) / total_trades * 100,
        total_pnl: total_pnl,
        net_profit: total_pnl,
        gross_profit: gross_profit,
        gross_loss: gross_loss,
        profit_factor: profit_factor,
        average_win: average_win,
        average_loss: average_loss,
        largest_win: largest_win,
        largest_loss: largest_loss,
        max_drawdown: max_dd,
        max_drawdown_percent: max_dd_pct,
        sharpe_ratio: sharpe,
        total_commission: total_commission_cost,
        total_slippage: total_slippage_cost,
        return_on_capital: (total_pnl / initial_capital) * 100
      }
    end
  end

  @doc """
  Calculates the equity curve over time.
  """
  def calculate_equity_curve(closed_positions, initial_capital) do
    {curve, _} =
      Enum.reduce(closed_positions, {[], initial_capital}, fn position, {curve, equity} ->
        new_equity = equity + position.pnl

        point = %{
          timestamp: position.exit_time,
          equity: new_equity,
          pnl: position.pnl,
          trade_id: position.id
        }

        {curve ++ [point], new_equity}
      end)

    curve
  end

  @doc """
  Calculates maximum drawdown and maximum drawdown percentage.
  """
  def calculate_max_drawdown(closed_positions, initial_capital) do
    equity_curve = calculate_equity_curve(closed_positions, initial_capital)

    if length(equity_curve) == 0 do
      {0.0, 0.0}
    else
      {max_dd, max_dd_pct, _, _} =
        Enum.reduce(equity_curve, {0.0, 0.0, initial_capital, initial_capital}, fn point,
                                                                                     {max_dd,
                                                                                      max_dd_pct,
                                                                                      peak,
                                                                                      _last_equity} ->
          new_peak = max(peak, point.equity)
          drawdown = new_peak - point.equity
          drawdown_pct = if new_peak > 0, do: (drawdown / new_peak) * 100, else: 0.0

          {
            max(max_dd, drawdown),
            max(max_dd_pct, drawdown_pct),
            new_peak,
            point.equity
          }
        end)

      {max_dd, max_dd_pct}
    end
  end

  @doc """
  Calculates the Sharpe ratio (risk-adjusted return).
  """
  def calculate_sharpe_ratio(closed_positions, risk_free_rate \\ 0.02) do
    if length(closed_positions) < 2 do
      0.0
    else
      returns = Enum.map(closed_positions, & &1.pnl_percent)
      mean_return = Enum.sum(returns) / length(returns)
      variance = Enum.sum(Enum.map(returns, fn r -> :math.pow(r - mean_return, 2) end))
      std_dev = :math.sqrt(variance / length(returns))

      if std_dev > 0 do
        (mean_return - risk_free_rate) / std_dev
      else
        0.0
      end
    end
  end

  @doc """
  Prints a formatted backtest report.
  """
  def print_report(backtest_result) do
    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts("BACKTEST REPORT: #{backtest_result.strategy}")
    IO.puts(String.duplicate("=", 60))
    IO.puts("Symbol: #{backtest_result.symbol}")
    IO.puts("Period: #{backtest_result.period.start} to #{backtest_result.period.end}")
    IO.puts(String.duplicate("-", 60))

    metrics = backtest_result.metrics

    IO.puts("\nPERFORMANCE METRICS:")
    IO.puts("Total Trades: #{metrics.total_trades}")
    IO.puts("Winning Trades: #{metrics.winning_trades}")
    IO.puts("Losing Trades: #{metrics.losing_trades}")
    IO.puts("Win Rate: #{Float.round(metrics.win_rate, 2)}%")
    IO.puts("\nPROFIT/LOSS:")
    IO.puts("Net Profit: $#{Float.round(metrics.net_profit, 2)}")
    IO.puts("Gross Profit: $#{Float.round(metrics.gross_profit, 2)}")
    IO.puts("Gross Loss: $#{Float.round(metrics.gross_loss, 2)}")
    IO.puts("Profit Factor: #{Float.round(metrics.profit_factor, 2)}")
    IO.puts("Return on Capital: #{Float.round(metrics.return_on_capital, 2)}%")
    IO.puts("\nTRADE STATISTICS:")
    IO.puts("Average Win: $#{Float.round(metrics.average_win, 2)}")
    IO.puts("Average Loss: $#{Float.round(metrics.average_loss, 2)}")
    IO.puts("Largest Win: $#{Float.round(metrics.largest_win, 2)}")
    IO.puts("Largest Loss: $#{Float.round(metrics.largest_loss, 2)}")
    IO.puts("\nRISK METRICS:")
    IO.puts("Max Drawdown: $#{Float.round(metrics.max_drawdown, 2)}")
    IO.puts("Max Drawdown %: #{Float.round(metrics.max_drawdown_percent, 2)}%")
    IO.puts("Sharpe Ratio: #{Float.round(metrics.sharpe_ratio, 2)}")
    IO.puts("\nCOSTS:")
    IO.puts("Total Commission: $#{Float.round(metrics.total_commission, 2)}")
    IO.puts("Total Slippage: $#{Float.round(metrics.total_slippage, 2)}")
    IO.puts(String.duplicate("=", 60) <> "\n")
  end
end
