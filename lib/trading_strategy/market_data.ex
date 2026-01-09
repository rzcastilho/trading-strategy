defmodule TradingStrategy.MarketData do
  @moduledoc """
  Context module for market data operations.

  Provides functions to fetch, store, and query historical and real-time OHLCV market data.
  Uses TimescaleDB for efficient time-series storage and querying.
  """

  import Ecto.Query
  alias TradingStrategy.Repo
  alias TradingStrategy.MarketData.MarketData, as: MarketDataSchema
  require Logger

  @doc """
  Gets historical market data for a given symbol and time range.

  Uses CryptoExchange.API.get_historical_klines_bulk for fetching data from exchanges.

  ## Parameters
    - `symbol`: Trading pair (e.g., "BTCUSDT")
    - `timeframe`: Candlestick interval (e.g., "1h", "1d")
    - `opts`: Keyword list with options:
      - `:start_time` - Start time (DateTime, required)
      - `:end_time` - End time (DateTime, required)
      - `:exchange` - Exchange name (default: "binance")

  ## Returns
    - `{:ok, [market_data]}` - List of MarketData structs
    - `{:error, reason}` - Error tuple

  ## Examples

      iex> start_time = ~U[2023-01-01 00:00:00Z]
      iex> end_time = ~U[2023-01-31 23:59:59Z]
      iex> MarketData.get_historical_data("BTCUSDT", "1d", start_time: start_time, end_time: end_time)
      {:ok, [%MarketDataSchema{}, ...]}
  """
  @spec get_historical_data(String.t(), String.t(), keyword()) ::
          {:ok, list(MarketDataSchema.t())} | {:error, term()}
  def get_historical_data(symbol, timeframe, opts) do
    start_time = Keyword.fetch!(opts, :start_time)
    end_time = Keyword.fetch!(opts, :end_time)
    exchange = Keyword.get(opts, :exchange, "binance")

    # First, try to get from database
    case get_from_database(symbol, timeframe, start_time, end_time, exchange) do
      {:ok, data} when length(data) > 0 ->
        Logger.info("Retrieved #{length(data)} bars from database for #{symbol} #{timeframe}")

        {:ok, data}

      _ ->
        # If not in database, fetch from exchange
        Logger.info("Fetching historical data from #{exchange} for #{symbol} #{timeframe}")
        fetch_and_store(symbol, timeframe, start_time, end_time, exchange)
    end
  end

  @doc """
  Stores market data in the database.

  ## Parameters
    - `attrs`: Map with market data attributes

  ## Returns
    - `{:ok, market_data}` - Stored MarketData struct
    - `{:error, changeset}` - Error changeset

  ## Examples

      iex> attrs = %{
      ...>   symbol: "BTCUSDT",
      ...>   timestamp: ~U[2023-01-01 00:00:00Z],
      ...>   open: Decimal.new("42000.00"),
      ...>   high: Decimal.new("43000.00"),
      ...>   low: Decimal.new("41000.00"),
      ...>   close: Decimal.new("42500.00"),
      ...>   volume: Decimal.new("1000.50"),
      ...>   timeframe: "1h",
      ...>   data_source: "binance"
      ...> }
      iex> MarketData.create_market_data(attrs)
      {:ok, %MarketDataSchema{}}
  """
  @spec create_market_data(map()) ::
          {:ok, MarketDataSchema.t()} | {:error, Ecto.Changeset.t()}
  def create_market_data(attrs) do
    %MarketDataSchema{}
    |> MarketDataSchema.changeset(attrs)
    |> Repo.insert(
      on_conflict: :nothing,
      conflict_target: [:symbol, :timestamp, :timeframe, :data_source]
    )
  end

  @doc """
  Stores multiple market data records efficiently.

  ## Parameters
    - `data_list`: List of market data attribute maps

  ## Returns
    - `{:ok, count}` - Number of records inserted
    - `{:error, reason}` - Error tuple

  ## Examples

      iex> data = [%{symbol: "BTCUSDT", ...}, %{symbol: "ETHUSDT", ...}]
      iex> MarketData.bulk_create_market_data(data)
      {:ok, 2}
  """
  @spec bulk_create_market_data(list(map())) :: {:ok, integer()} | {:error, term()}
  def bulk_create_market_data([]), do: {:ok, 0}

  def bulk_create_market_data(data_list) when is_list(data_list) do
    try do
      changesets =
        Enum.map(data_list, fn attrs ->
          MarketDataSchema.changeset(%MarketDataSchema{}, attrs)
        end)

      # Validate all changesets
      invalid =
        Enum.filter(changesets, fn cs ->
          not cs.valid?
        end)

      if length(invalid) > 0 do
        {:error, "#{length(invalid)} invalid records in bulk insert"}
      else
        # Insert all valid records
        {count, _} =
          Repo.insert_all(
            MarketDataSchema,
            Enum.map(data_list, &prepare_for_insert/1),
            on_conflict: :nothing,
            conflict_target: [:symbol, :timestamp, :timeframe, :data_source]
          )

        {:ok, count}
      end
    rescue
      error ->
        Logger.error("Bulk insert failed: #{Exception.message(error)}")
        {:error, error}
    end
  end

  @doc """
  Gets the latest market data for a symbol and timeframe.

  ## Parameters
    - `symbol`: Trading pair
    - `timeframe`: Candlestick interval
    - `opts`: Optional parameters (exchange, limit)

  ## Returns
    - `{:ok, market_data}` - Latest MarketData struct
    - `{:error, :not_found}` - No data found

  ## Examples

      iex> MarketData.get_latest_bar("BTCUSDT", "1h")
      {:ok, %MarketDataSchema{}}
  """
  @spec get_latest_bar(String.t(), String.t(), keyword()) ::
          {:ok, MarketDataSchema.t()} | {:error, :not_found}
  def get_latest_bar(symbol, timeframe, opts \\ []) do
    exchange = Keyword.get(opts, :exchange, "binance")

    query =
      from(m in MarketDataSchema,
        where: m.symbol == ^symbol,
        where: m.timeframe == ^timeframe,
        where: m.data_source == ^exchange,
        order_by: [desc: m.timestamp],
        limit: 1
      )

    case Repo.one(query) do
      nil -> {:error, :not_found}
      data -> {:ok, data}
    end
  end

  # Private Functions

  defp get_from_database(symbol, timeframe, start_time, end_time, exchange) do
    query =
      from(m in MarketDataSchema,
        where: m.symbol == ^symbol,
        where: m.timeframe == ^timeframe,
        where: m.exchange == ^exchange,
        where: m.timestamp >= ^start_time,
        where: m.timestamp <= ^end_time,
        order_by: [asc: m.timestamp]
      )

    data = Repo.all(query)
    {:ok, data}
  rescue
    error ->
      Logger.error("Database query failed: #{Exception.message(error)}")
      {:error, error}
  end

  defp fetch_and_store(symbol, timeframe, start_time, end_time, exchange) do
    # Convert timeframe to CryptoExchange format
    interval = convert_timeframe(timeframe)

    # Fetch from exchange
    case CryptoExchange.API.get_historical_klines_bulk(
           String.to_atom(exchange),
           symbol,
           interval,
           DateTime.to_unix(start_time, :millisecond),
           DateTime.to_unix(end_time, :millisecond)
         ) do
      {:ok, klines} when is_list(klines) ->
        # Convert to our format and store
        market_data =
          Enum.map(klines, fn kline ->
            convert_kline_to_market_data(kline, symbol, timeframe, exchange)
          end)

        case bulk_create_market_data(market_data) do
          {:ok, count} ->
            Logger.info("Stored #{count} bars for #{symbol} #{timeframe}")
            # Return the data from database to ensure consistency
            get_from_database(symbol, timeframe, start_time, end_time, exchange)

          error ->
            error
        end

      {:error, reason} = error ->
        Logger.error("Failed to fetch historical data: #{inspect(reason)}")
        error

      other ->
        Logger.error("Unexpected response from exchange: #{inspect(other)}")
        {:error, :unexpected_response}
    end
  end

  defp convert_kline_to_market_data(kline, symbol, timeframe, exchange) do
    # CryptoExchange kline format: [timestamp, open, high, low, close, volume, ...]
    [timestamp_ms, open, high, low, close, volume | _] = kline

    %{
      symbol: symbol,
      timestamp: DateTime.from_unix!(timestamp_ms, :millisecond),
      open: Decimal.new(to_string(open)),
      high: Decimal.new(to_string(high)),
      low: Decimal.new(to_string(low)),
      close: Decimal.new(to_string(close)),
      volume: Decimal.new(to_string(volume)),
      timeframe: timeframe,
      data_source: exchange,
      quality_flag: "complete"
    }
  end

  defp convert_timeframe(timeframe) do
    # Map our timeframe format to CryptoExchange interval format
    case timeframe do
      "1m" -> "1m"
      "5m" -> "5m"
      "15m" -> "15m"
      "1h" -> "1h"
      "4h" -> "4h"
      "1d" -> "1d"
      other -> other
    end
  end

  defp prepare_for_insert(attrs) do
    attrs
    |> Map.put(:inserted_at, DateTime.utc_now() |> DateTime.truncate(:second))
    |> Map.put(:updated_at, DateTime.utc_now() |> DateTime.truncate(:second))
  end
end
