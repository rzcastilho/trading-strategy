defmodule TradingStrategy.Backtesting.EquityCurve do
  @moduledoc """
  Generates equity curve data for visualization of backtest performance.

  Provides formatted equity curve data suitable for charting and analysis
  of portfolio value evolution over time.

  The equity curve shows portfolio value at different points in time, sampled
  to a maximum of 1000 points for efficient storage and visualization.
  """

  @doc """
  Generates equity curve from historical equity data.

  ## Parameters
    - `equity_history`: List of {timestamp, equity} tuples where equity is Decimal
    - `initial_capital`: Starting capital (Decimal) - used if history is empty

  ## Returns
    - List of {DateTime, Decimal} tuples in chronological order

  ## Examples

      iex> history = [
      ...>   {~U[2023-01-01 00:00:00Z], Decimal.new("10000")},
      ...>   {~U[2023-01-02 00:00:00Z], Decimal.new("10150")},
      ...>   {~U[2023-01-03 00:00:00Z], Decimal.new("10050")}
      ...> ]
      iex> EquityCurve.generate(history, Decimal.new("10000"))
      [
        {~U[2023-01-01 00:00:00Z], #Decimal<10000>},
        {~U[2023-01-02 00:00:00Z], #Decimal<10150>},
        {~U[2023-01-03 00:00:00Z], #Decimal<10050>}
      ]
  """
  @spec generate(list(tuple()), Decimal.t()) :: list(tuple())
  def generate(equity_history, _initial_capital) when is_list(equity_history) do
    # Return equity history sorted by timestamp
    Enum.sort_by(equity_history, fn {timestamp, _value} -> timestamp end, DateTime)
  end

  @doc """
  Generates equity curve with drawdown information (legacy function).

  ## Parameters
    - `equity_history`: List of {timestamp, equity} tuples

  ## Returns
    - List of equity curve points with drawdown data
  """
  @spec generate_with_drawdown(list(tuple())) :: list(map())
  def generate_with_drawdown(equity_history) do
    base_curve = generate_legacy(equity_history)

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

  # Legacy generate function for backward compatibility
  defp generate_legacy([]), do: []

  defp generate_legacy(equity_history) do
    [{first_ts, first_equity} | _] = equity_history

    equity_history
    |> Enum.with_index()
    |> Enum.map(fn {{timestamp, equity}, index} ->
      # Convert Decimal to float if needed
      equity_float = if is_struct(equity, Decimal), do: Decimal.to_float(equity), else: equity

      # Calculate return from previous point
      period_return =
        if index > 0 do
          {_prev_ts, prev_equity} = Enum.at(equity_history, index - 1)
          prev_float = if is_struct(prev_equity, Decimal), do: Decimal.to_float(prev_equity), else: prev_equity

          if prev_float > 0 do
            (equity_float - prev_float) / prev_float
          else
            0.0
          end
        else
          0.0
        end

      # Calculate cumulative return from start
      first_float = if is_struct(first_equity, Decimal), do: Decimal.to_float(first_equity), else: first_equity
      cumulative_return =
        if first_float > 0 do
          (equity_float - first_float) / first_float
        else
          0.0
        end

      %{
        timestamp: timestamp,
        equity: Float.round(equity_float, 2),
        period_return: Float.round(period_return, 6),
        cumulative_return: Float.round(cumulative_return, 6)
      }
    end)
  end

  @doc """
  Samples the equity curve to reduce data points for visualization.

  When an equity curve has more points than max_points, this function samples
  it down while preserving:
  - The first and last points (start and end of backtest)
  - Approximately uniform distribution across the time range
  - Chronological order

  ## Parameters
    - `equity_curve`: Full equity curve - List of {DateTime, Decimal} tuples
    - `max_points`: Maximum number of points to return (default: 1000)

  ## Returns
    - Sampled equity curve with length <= max_points
  """
  @spec sample(list(tuple()), integer()) :: list(tuple())
  def sample(curve, max_points \\ 1000)

  def sample([], _max_points), do: []
  def sample([single_point], _max_points), do: [single_point]

  def sample(curve, max_points) when length(curve) <= max_points do
    curve
  end

  def sample(curve, max_points) when is_list(curve) and max_points > 0 do
    total_points = length(curve)

    # Calculate sample rate to ensure we don't exceed max_points
    # Add 1 to ensure we round up, so we get fewer points than max_points
    sample_rate = max(div(total_points - 1, max_points - 1), 1)

    # Get first and last points
    first = List.first(curve)
    last = List.last(curve)

    # Sample middle points
    middle_points =
      curve
      |> Enum.drop(1)  # Skip first
      |> Enum.drop(-1)  # Skip last
      |> Enum.with_index()
      |> Enum.filter(fn {_point, index} ->
        rem(index, sample_rate) == 0
      end)
      |> Enum.map(fn {point, _index} -> point end)

    # Combine: first + middle + last
    result = [first | middle_points] ++ [last]

    # Ensure we don't exceed max_points
    if length(result) > max_points do
      # Aggressively sample from middle
      new_sample_rate = div(length(middle_points), max_points - 2) + 1
      sampled_middle = Enum.take_every(middle_points, new_sample_rate) |> Enum.take(max_points - 2)
      [first | sampled_middle] ++ [last]
    else
      result
    end
  end

  @doc """
  Converts an equity curve to JSON-compatible format.

  Converts DateTime timestamps to ISO8601 strings and Decimal values to floats
  for JSON serialization and API responses.

  ## Parameters
    - `curve`: List of {DateTime.t(), Decimal.t()} tuples

  ## Returns
    - List of maps with "timestamp" (ISO8601 string) and "value" (float) keys

  ## Examples
      iex> curve = [{~U[2024-01-01 00:00:00Z], Decimal.new("10000.50")}]
      iex> EquityCurve.to_json_format(curve)
      [%{"timestamp" => "2024-01-01T00:00:00Z", "value" => 10000.5}]
  """
  @spec to_json_format(list(tuple())) :: list(map())
  def to_json_format(curve) when is_list(curve) do
    Enum.map(curve, fn {timestamp, value} ->
      # Safely convert value to float (handle both Decimal and numeric types)
      value_float =
        case value do
          %Decimal{} = d -> Decimal.to_float(d)
          n when is_number(n) -> n / 1.0
          _ -> 0.0
        end

      %{
        "timestamp" => DateTime.to_iso8601(timestamp),
        "value" => value_float
      }
    end)
  end

  @doc """
  Calculates metadata about equity curve sampling.

  Provides information about the sampling process for debugging and transparency.

  ## Parameters
    - `original_length`: Integer - Number of points before sampling
    - `sampled_length`: Integer - Number of points after sampling
    - `trade_count`: Integer - Number of trades in the backtest

  ## Returns
    - Map with sampling metadata

  ## Examples
      iex> EquityCurve.sampling_metadata(5000, 1000, 50)
      %{
        sampled: true,
        sample_rate: 5,
        original_length: 5000,
        sampled_length: 1000,
        trade_points_included: 50
      }
  """
  @spec sampling_metadata(integer(), integer(), integer()) :: map()
  def sampling_metadata(original_length, sampled_length, trade_count) do
    sampled = original_length > sampled_length
    sample_rate = if sampled, do: div(original_length, sampled_length), else: 1

    %{
      sampled: sampled,
      sample_rate: sample_rate,
      original_length: original_length,
      sampled_length: sampled_length,
      trade_points_included: trade_count
    }
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
