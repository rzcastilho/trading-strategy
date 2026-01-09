defmodule TradingStrategy.Backtesting.EquityCurve do
  @moduledoc """
  Generates equity curve data for visualization of backtest performance.

  Provides formatted equity curve data suitable for charting and analysis
  of portfolio value evolution over time.
  """

  @doc """
  Generates equity curve from historical equity data.

  ## Parameters
    - `equity_history`: List of {timestamp, equity} tuples

  ## Returns
    - List of equity curve points with metadata

  ## Examples

      iex> history = [
      ...>   {~U[2023-01-01 00:00:00Z], 10000},
      ...>   {~U[2023-01-02 00:00:00Z], 10150},
      ...>   {~U[2023-01-03 00:00:00Z], 10050}
      ...> ]
      iex> EquityCurve.generate(history)
      [
        %{timestamp: ~U[2023-01-01 00:00:00Z], equity: 10000, return: 0.0},
        %{timestamp: ~U[2023-01-02 00:00:00Z], equity: 10150, return: 0.015},
        %{timestamp: ~U[2023-01-03 00:00:00Z], equity: 10050, return: -0.0099}
      ]
  """
  @spec generate(list(tuple())) :: list(map())
  def generate([]), do: []

  def generate(equity_history) do
    [{first_ts, first_equity} | _] = equity_history

    equity_history
    |> Enum.with_index()
    |> Enum.map(fn {{timestamp, equity}, index} ->
      # Calculate return from previous point
      period_return =
        if index > 0 do
          {_prev_ts, prev_equity} = Enum.at(equity_history, index - 1)

          if prev_equity > 0 do
            (equity - prev_equity) / prev_equity
          else
            0.0
          end
        else
          0.0
        end

      # Calculate cumulative return from start
      cumulative_return =
        if first_equity > 0 do
          (equity - first_equity) / first_equity
        else
          0.0
        end

      %{
        timestamp: timestamp,
        equity: Float.round(equity, 2),
        period_return: Float.round(period_return, 6),
        cumulative_return: Float.round(cumulative_return, 6)
      }
    end)
  end

  @doc """
  Generates equity curve with drawdown information.

  ## Parameters
    - `equity_history`: List of {timestamp, equity} tuples

  ## Returns
    - List of equity curve points with drawdown data
  """
  @spec generate_with_drawdown(list(tuple())) :: list(map())
  def generate_with_drawdown(equity_history) do
    base_curve = generate(equity_history)

    # Calculate running peak and drawdown
    {curve_with_dd, _peak} =
      Enum.reduce(base_curve, {[], 0}, fn point, {acc, peak} ->
        new_peak = max(peak, point.equity)

        drawdown =
          if new_peak > 0 do
            (new_peak - point.equity) / new_peak
          else
            0.0
          end

        point_with_dd =
          Map.merge(point, %{
            peak_equity: Float.round(new_peak, 2),
            drawdown: Float.round(drawdown, 6)
          })

        {[point_with_dd | acc], new_peak}
      end)

    Enum.reverse(curve_with_dd)
  end

  @doc """
  Samples the equity curve to reduce data points for visualization.

  Useful for long backtests where plotting every point is impractical.

  ## Parameters
    - `equity_curve`: Full equity curve
    - `max_points`: Maximum number of points to return (default: 1000)

  ## Returns
    - Sampled equity curve
  """
  @spec sample(list(map()), integer()) :: list(map())
  def sample(equity_curve, max_points \\ 1000) do
    total_points = length(equity_curve)

    if total_points <= max_points do
      equity_curve
    else
      # Calculate sampling interval
      interval = div(total_points, max_points)

      equity_curve
      |> Enum.with_index()
      |> Enum.filter(fn {_point, index} ->
        # Always include last point
        rem(index, interval) == 0 || index == total_points - 1
      end)
      |> Enum.map(fn {point, _index} -> point end)
    end
  end

  @doc """
  Calculates summary statistics for the equity curve.

  ## Parameters
    - `equity_curve`: Equity curve data

  ## Returns
    - Map with summary statistics
  """
  @spec calculate_summary(list(map())) :: map()
  def calculate_summary([]), do: %{}

  def calculate_summary(equity_curve) do
    equities = Enum.map(equity_curve, & &1.equity)
    returns = Enum.map(equity_curve, & &1.period_return) |> Enum.filter(&(&1 != 0))

    %{
      start_equity: List.first(equities),
      end_equity: List.last(equities),
      peak_equity: Enum.max(equities),
      trough_equity: Enum.min(equities),
      total_points: length(equity_curve),
      avg_period_return:
        if(length(returns) > 0, do: Enum.sum(returns) / length(returns), else: 0.0),
      volatility: calculate_volatility(returns)
    }
  end

  # Private Functions

  defp calculate_volatility([]), do: 0.0
  defp calculate_volatility(returns) when length(returns) < 2, do: 0.0

  defp calculate_volatility(returns) do
    mean = Enum.sum(returns) / length(returns)

    variance =
      Enum.reduce(returns, 0, fn r, acc ->
        acc + :math.pow(r - mean, 2)
      end) / (length(returns) - 1)

    :math.sqrt(variance)
  end
end
