defmodule TradingStrategy.Backtesting.MetricsCalculator do
  @moduledoc """
  Calculates performance metrics for backtest results.

  Computes standard trading metrics including returns, risk-adjusted metrics,
  win rates, drawdowns, and trade statistics.
  """

  @doc """
  Calculates comprehensive performance metrics from backtest results.

  ## Parameters
    - `trades`: List of executed trades
    - `equity_history`: List of {timestamp, equity} tuples
    - `initial_capital`: Starting capital

  ## Returns
    - Map with performance metrics

  ## Examples

      iex> MetricsCalculator.calculate_metrics(trades, equity_history, 10000)
      %{
        total_return: 0.15,
        total_return_abs: 1500,
        win_rate: 0.60,
        max_drawdown: 0.12,
        sharpe_ratio: 1.25,
        ...
      }
  """
  @spec calculate_metrics(list(map()), list(tuple()), number()) :: map()
  def calculate_metrics(trades, equity_history, initial_capital) do
    final_equity =
      case List.last(equity_history) do
        {_timestamp, equity} -> equity
        _ -> initial_capital
      end

    # Calculate return metrics
    total_return = (final_equity - initial_capital) / initial_capital
    total_return_abs = final_equity - initial_capital

    # Trade statistics
    trade_count = length(trades)

    # T085: Handle zero trades edge case - return flat metrics
    if trade_count == 0 do
      # Still calculate drawdown and sharpe from equity history (unrealized PnL tracking)
      max_drawdown = calculate_max_drawdown(equity_history)
      sharpe_ratio = calculate_sharpe_ratio(equity_history, initial_capital)

      %{
        total_return: Float.round(total_return, 4),
        total_return_abs: Float.round(total_return_abs, 2),
        win_rate: nil,
        # N/A for zero trades
        max_drawdown: Float.round(max_drawdown, 4),
        # Calculate from equity curve
        sharpe_ratio: if(sharpe_ratio == 0.0, do: nil, else: Float.round(sharpe_ratio, 4)),
        # nil if zero
        trade_count: 0,
        winning_trades: 0,
        losing_trades: 0,
        average_win: nil,
        # N/A
        average_loss: nil,
        # N/A
        profit_factor: nil,
        # N/A
        max_consecutive_wins: 0,
        max_consecutive_losses: 0,
        average_trade_duration_minutes: nil,
        # N/A
        final_equity: Float.round(final_equity, 2),
        initial_capital: initial_capital / 1.0
      }
    else
      # Normal calculation for backtests with trades
      winning_trades = Enum.filter(trades, fn t -> Map.get(t, :pnl, 0) > 0 end)
      losing_trades = Enum.filter(trades, fn t -> Map.get(t, :pnl, 0) < 0 end)

      win_rate = length(winning_trades) / trade_count

      # Average trade metrics
      avg_win =
        if length(winning_trades) > 0 do
          Enum.sum(Enum.map(winning_trades, &Map.get(&1, :pnl, 0))) / length(winning_trades)
        else
          0.0
        end

      avg_loss =
        if length(losing_trades) > 0 do
          Enum.sum(Enum.map(losing_trades, &Map.get(&1, :pnl, 0))) / length(losing_trades)
        else
          0.0
        end

      # Profit factor
      gross_profit = Enum.sum(Enum.map(winning_trades, &Map.get(&1, :pnl, 0)))
      gross_loss = abs(Enum.sum(Enum.map(losing_trades, &Map.get(&1, :pnl, 0))))

      profit_factor =
        if gross_loss > 0 do
          gross_profit / gross_loss
        else
          if gross_profit > 0, do: :infinity, else: 0.0
        end

      # Drawdown metrics
      max_drawdown = calculate_max_drawdown(equity_history)

      # Risk-adjusted metrics
      sharpe_ratio = calculate_sharpe_ratio(equity_history, initial_capital)

      # Trade duration
      avg_trade_duration = calculate_average_trade_duration(trades)

      # Consecutive wins/losses
      {max_consecutive_wins, max_consecutive_losses} = calculate_consecutive_streaks(trades)

      %{
        total_return: Float.round(total_return, 4),
        total_return_abs: Float.round(total_return_abs, 2),
        win_rate: Float.round(win_rate, 4),
        max_drawdown: Float.round(max_drawdown, 4),
        sharpe_ratio: Float.round(sharpe_ratio, 4),
        trade_count: trade_count,
        winning_trades: length(winning_trades),
        losing_trades: length(losing_trades),
        average_win: Float.round(avg_win, 2),
        average_loss: Float.round(avg_loss, 2),
        profit_factor:
          if(profit_factor == :infinity, do: 999.99, else: Float.round(profit_factor, 2)),
        max_consecutive_wins: max_consecutive_wins,
        max_consecutive_losses: max_consecutive_losses,
        average_trade_duration_minutes: avg_trade_duration,
        final_equity: Float.round(final_equity, 2),
        initial_capital: initial_capital / 1.0
      }
    end
  end

  # Private Functions

  defp calculate_max_drawdown(equity_history) do
    equity_values = Enum.map(equity_history, fn {_ts, equity} -> equity end)

    {_peak, max_dd} =
      Enum.reduce(equity_values, {0.0, 0.0}, fn equity, {peak, max_drawdown} ->
        new_peak = max(peak, equity)

        drawdown =
          if new_peak > 0 do
            (new_peak - equity) / new_peak
          else
            0.0
          end

        {new_peak, max(max_drawdown, drawdown)}
      end)

    max_dd
  end

  defp calculate_sharpe_ratio(equity_history, _initial_capital) do
    # Calculate period returns
    returns =
      equity_history
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(fn [{_t1, e1}, {_t2, e2}] ->
        if e1 > 0, do: (e2 - e1) / e1, else: 0.0
      end)

    if length(returns) < 2 do
      0.0
    else
      mean_return = Enum.sum(returns) / length(returns)

      variance =
        Enum.reduce(returns, 0.0, fn r, acc ->
          acc + :math.pow(r - mean_return, 2)
        end) / length(returns)

      std_dev = :math.sqrt(variance)

      if std_dev > 0 do
        # Annualized Sharpe (assuming daily returns, 252 trading days)
        sharpe = mean_return / std_dev
        sharpe * :math.sqrt(252)
      else
        0.0
      end
    end
  end

  defp calculate_average_trade_duration(trades) do
    # T072: Use duration_seconds field from exit trades
    durations =
      trades
      |> Enum.filter(fn t -> Map.get(t, :duration_seconds) != nil end)
      # Convert to minutes
      |> Enum.map(fn t -> Map.get(t, :duration_seconds, 0) / 60 end)

    if length(durations) > 0 do
      round(Enum.sum(durations) / length(durations))
    else
      0
    end
  end

  defp calculate_consecutive_streaks(trades) do
    # Get PnL sequence
    pnl_sequence = Enum.map(trades, fn t -> Map.get(t, :pnl, 0) end)

    # Reduce returns {max_wins, max_losses, current_wins, current_losses}
    {max_wins, max_losses, _current_wins, _current_losses} =
      Enum.reduce(pnl_sequence, {0, 0, 0, 0}, fn pnl, {max_w, max_l, curr_w, curr_l} ->
        cond do
          pnl > 0 ->
            # Winning trade
            new_curr_w = curr_w + 1
            {max(max_w, new_curr_w), max_l, new_curr_w, 0}

          pnl < 0 ->
            # Losing trade
            new_curr_l = curr_l + 1
            {max_w, max(max_l, new_curr_l), 0, new_curr_l}

          true ->
            # Break-even trade
            {max_w, max_l, 0, 0}
        end
      end)

    {max_wins, max_losses}
  end
end
