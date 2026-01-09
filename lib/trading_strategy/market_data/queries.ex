defmodule TradingStrategy.MarketData.Queries do
  @moduledoc """
  TimescaleDB-optimized queries for efficient time-series data operations.

  Provides functions that leverage TimescaleDB's time_bucket and other
  hypertable features for fast aggregation and analysis of market data.
  """

  import Ecto.Query
  alias TradingStrategy.Repo
  alias TradingStrategy.MarketData.MarketData, as: MarketDataSchema

  @doc """
  Aggregates market data using TimescaleDB's time_bucket function.

  Useful for downsampling (e.g., 1h bars to 1d bars) or computing statistics
  over time windows.

  ## Parameters
    - `symbol`: Trading pair
    - `timeframe`: Source timeframe (e.g., "1h")
    - `bucket_interval`: Aggregation interval (e.g., "1 day", "4 hours")
    - `start_time`: Start of time range
    - `end_time`: End of time range

  ## Returns
    - `{:ok, [aggregated_data]}` - List of aggregated OHLCV data
    - `{:error, reason}` - Error tuple

  ## Examples

      iex> # Aggregate 1h bars into 1d bars
      iex> Queries.time_bucket_aggregate("BTCUSDT", "1h", "1 day", start_time, end_time)
      {:ok, [%{bucket: ~U[2023-01-01 00:00:00Z], open: ..., high: ..., ...}]}
  """
  @spec time_bucket_aggregate(String.t(), String.t(), String.t(), DateTime.t(), DateTime.t()) ::
          {:ok, list(map())} | {:error, term()}
  def time_bucket_aggregate(symbol, timeframe, bucket_interval, start_time, end_time) do
    # TimescaleDB time_bucket query
    # Note: This uses raw SQL for time_bucket, which is a TimescaleDB function
    query = """
    SELECT
      time_bucket($1::interval, timestamp) AS bucket,
      (array_agg(open ORDER BY timestamp ASC))[1] AS open,
      MAX(high) AS high,
      MIN(low) AS low,
      (array_agg(close ORDER BY timestamp DESC))[1] AS close,
      SUM(volume) AS volume,
      COUNT(*) AS bar_count
    FROM market_data
    WHERE symbol = $2
      AND timeframe = $3
      AND timestamp >= $4
      AND timestamp <= $5
    GROUP BY bucket
    ORDER BY bucket ASC
    """

    case Repo.query(query, [
           bucket_interval,
           symbol,
           timeframe,
           start_time,
           end_time
         ]) do
      {:ok, %{rows: rows, columns: columns}} ->
        results =
          Enum.map(rows, fn row ->
            columns
            |> Enum.zip(row)
            |> Map.new()
            |> convert_aggregated_row()
          end)

        {:ok, results}

      {:error, reason} = error ->
        require Logger

        Logger.error(
          "Time bucket aggregation failed for #{symbol} #{timeframe}: #{inspect(reason)}"
        )

        error
    end
  end

  @doc """
  Gets a rolling window of market data for technical indicator calculation.

  Returns the last N bars before (and including) the given timestamp.

  ## Parameters
    - `symbol`: Trading pair
    - `timeframe`: Candlestick interval
    - `timestamp`: Reference timestamp
    - `window_size`: Number of bars to retrieve
    - `opts`: Options (exchange, include_current)

  ## Returns
    - `{:ok, [market_data]}` - List of MarketData structs (oldest first)
    - `{:error, :insufficient_data}` - Not enough data available

  ## Examples

      iex> # Get last 50 bars for SMA(50) calculation
      iex> Queries.get_rolling_window("BTCUSDT", "1h", ~U[2023-01-15 12:00:00Z], 50)
      {:ok, [%MarketDataSchema{}, ...]}
  """
  @spec get_rolling_window(String.t(), String.t(), DateTime.t(), integer(), keyword()) ::
          {:ok, list(MarketDataSchema.t())} | {:error, :insufficient_data}
  def get_rolling_window(symbol, timeframe, timestamp, window_size, opts \\ []) do
    exchange = Keyword.get(opts, :exchange, "binance")
    include_current = Keyword.get(opts, :include_current, true)

    comparison_operator = if include_current, do: :<=, else: :<

    query =
      from(m in MarketDataSchema,
        where: m.symbol == ^symbol,
        where: m.timeframe == ^timeframe,
        where: m.data_source == ^exchange,
        where: field(m, :timestamp) <= ^timestamp,
        order_by: [desc: m.timestamp],
        limit: ^window_size
      )

    # Apply the comparison operator dynamically
    query =
      if comparison_operator == :< do
        from(m in query, where: m.timestamp < ^timestamp)
      else
        query
      end

    case Repo.all(query) do
      data when length(data) < window_size ->
        {:error, :insufficient_data}

      data ->
        # Reverse to get oldest first (chronological order)
        {:ok, Enum.reverse(data)}
    end
  end

  @doc """
  Gets market data statistics for a time range using TimescaleDB's first() and last() functions.

  ## Parameters
    - `symbol`: Trading pair
    - `timeframe`: Candlestick interval
    - `start_time`: Start of range
    - `end_time`: End of range

  ## Returns
    - `{:ok, stats}` - Map with statistics
    - `{:error, reason}` - Error tuple

  ## Examples

      iex> Queries.get_statistics("BTCUSDT", "1h", start_time, end_time)
      {:ok, %{
        bar_count: 730,
        period_open: Decimal.new("42000"),
        period_close: Decimal.new("45000"),
        period_high: Decimal.new("48000"),
        period_low: Decimal.new("40000"),
        total_volume: Decimal.new("1000000")
      }}
  """
  @spec get_statistics(String.t(), String.t(), DateTime.t(), DateTime.t()) ::
          {:ok, map()} | {:error, term()}
  def get_statistics(symbol, timeframe, start_time, end_time) do
    # Use TimescaleDB first() and last() functions for efficient queries
    query = """
    SELECT
      COUNT(*) AS bar_count,
      first(open, timestamp) AS period_open,
      last(close, timestamp) AS period_close,
      MAX(high) AS period_high,
      MIN(low) AS period_low,
      SUM(volume) AS total_volume
    FROM market_data
    WHERE symbol = $1
      AND timeframe = $2
      AND timestamp >= $3
      AND timestamp <= $4
    """

    case Repo.query(query, [symbol, timeframe, start_time, end_time]) do
      {:ok, %{rows: [[count, open, close, high, low, volume]], columns: _}} ->
        {:ok,
         %{
           bar_count: count,
           period_open: open,
           period_close: close,
           period_high: high,
           period_low: low,
           total_volume: volume
         }}

      {:ok, %{rows: [], columns: _}} ->
        {:error, :no_data}

      {:error, reason} = error ->
        require Logger
        Logger.error("Statistics query failed for #{symbol} #{timeframe}: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Checks data quality and identifies gaps in market data.

  Returns list of missing time periods where data is expected but not present.

  ## Parameters
    - `symbol`: Trading pair
    - `timeframe`: Candlestick interval
    - `start_time`: Start of range
    - `end_time`: End of range

  ## Returns
    - `{:ok, gaps}` - List of gap periods
    - `{:error, reason}` - Error tuple

  ## Examples

      iex> Queries.find_data_gaps("BTCUSDT", "1h", start_time, end_time)
      {:ok, [
        %{expected: ~U[2023-01-15 10:00:00Z], missing_count: 3},
        %{expected: ~U[2023-01-20 14:00:00Z], missing_count: 1}
      ]}
  """
  @spec find_data_gaps(String.t(), String.t(), DateTime.t(), DateTime.t()) ::
          {:ok, list(map())} | {:error, term()}
  def find_data_gaps(symbol, timeframe, start_time, end_time) do
    interval = timeframe_to_interval(timeframe)

    # Generate expected timestamps and find missing ones
    query = """
    WITH expected_times AS (
      SELECT generate_series(
        $3::timestamptz,
        $4::timestamptz,
        $5::interval
      ) AS expected_timestamp
    ),
    actual_times AS (
      SELECT timestamp
      FROM market_data
      WHERE symbol = $1
        AND timeframe = $2
        AND timestamp >= $3
        AND timestamp <= $4
    )
    SELECT e.expected_timestamp, COUNT(a.timestamp) AS present
    FROM expected_times e
    LEFT JOIN actual_times a ON e.expected_timestamp = a.timestamp
    GROUP BY e.expected_timestamp
    HAVING COUNT(a.timestamp) = 0
    ORDER BY e.expected_timestamp ASC
    """

    case Repo.query(query, [symbol, timeframe, start_time, end_time, interval]) do
      {:ok, %{rows: rows}} ->
        gaps =
          Enum.map(rows, fn [timestamp, _] ->
            %{expected: timestamp, missing: true}
          end)

        {:ok, gaps}

      {:error, reason} = error ->
        require Logger
        Logger.error("Gap detection failed for #{symbol} #{timeframe}: #{inspect(reason)}")
        error
    end
  end

  # Private Functions

  defp convert_aggregated_row(row) do
    row
    |> Map.update("bucket", nil, fn
      nil -> nil
      val when is_binary(val) -> DateTime.from_iso8601(val) |> elem(1)
      val -> val
    end)
    |> Map.update("open", nil, &maybe_to_decimal/1)
    |> Map.update("high", nil, &maybe_to_decimal/1)
    |> Map.update("low", nil, &maybe_to_decimal/1)
    |> Map.update("close", nil, &maybe_to_decimal/1)
    |> Map.update("volume", nil, &maybe_to_decimal/1)
  end

  defp maybe_to_decimal(nil), do: nil
  defp maybe_to_decimal(value) when is_binary(value), do: Decimal.new(value)
  defp maybe_to_decimal(%Decimal{} = value), do: value
  defp maybe_to_decimal(value) when is_number(value), do: Decimal.new(to_string(value))

  defp timeframe_to_interval(timeframe) do
    case timeframe do
      "1m" -> "1 minute"
      "5m" -> "5 minutes"
      "15m" -> "15 minutes"
      "1h" -> "1 hour"
      "4h" -> "4 hours"
      "1d" -> "1 day"
      other -> other
    end
  end
end
