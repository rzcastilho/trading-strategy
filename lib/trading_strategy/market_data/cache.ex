defmodule TradingStrategy.MarketData.Cache do
  @moduledoc """
  ETS-based cache for storing latest market data (tickers, trades, candles).

  Provides fast, in-memory access to real-time market data for strategy
  execution and indicator calculations. Data is ephemeral and not persisted
  beyond the lifetime of the application.

  ## Table Structure

  ### Ticker Cache
  - Table: `:market_data_tickers`
  - Key: `symbol` (string)
  - Value: `{timestamp, ticker_data}`

  ### Trade Cache
  - Table: `:market_data_trades`
  - Key: `{symbol, trade_id}` (composite key)
  - Value: `trade_data`

  ### Candle Cache (for building from trades)
  - Table: `:market_data_candles`
  - Key: `{symbol, timeframe, timestamp}` (composite key)
  - Value: `candle_data`

  ## Performance
  - O(1) read/write operations
  - No locks for concurrent reads
  - Suitable for high-frequency updates (>1000/sec)
  """

  use GenServer
  require Logger

  @ticker_table :market_data_tickers
  @trade_table :market_data_trades
  @candle_table :market_data_candles

  # Maximum number of trades to keep per symbol (ring buffer)
  @max_trades_per_symbol 1000

  # Client API

  @doc """
  Starts the cache GenServer and initializes ETS tables.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Store or update ticker data for a symbol.

  ## Parameters
  - `symbol`: Trading pair symbol (e.g., "BTCUSDT")
  - `ticker_data`: Map containing ticker information

  ## Returns
  - `:ok`

  ## Examples
      iex> Cache.put_ticker("BTCUSDT", %{
      ...>   price: "43250.50",
      ...>   timestamp: ~U[2025-12-04 12:34:56Z],
      ...>   volume: "1234.56"
      ...> })
      :ok
  """
  def put_ticker(symbol, ticker_data) do
    timestamp = DateTime.utc_now()
    :ets.insert(@ticker_table, {symbol, {timestamp, ticker_data}})
    :ok
  end

  @doc """
  Retrieve latest ticker data for a symbol.

  ## Parameters
  - `symbol`: Trading pair symbol

  ## Returns
  - `{:ok, {timestamp, data}}` if data exists
  - `{:error, :not_found}` if no data available

  ## Examples
      iex> Cache.get_ticker("BTCUSDT")
      {:ok, {~U[2025-12-04 12:34:56Z], %{price: "43250.50", ...}}}
  """
  def get_ticker(symbol) do
    case :ets.lookup(@ticker_table, symbol) do
      [{^symbol, {timestamp, data}}] -> {:ok, {timestamp, data}}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Get only the latest price for a symbol (convenience function).

  ## Parameters
  - `symbol`: Trading pair symbol

  ## Returns
  - `{:ok, price_string}` if data exists
  - `{:error, :not_found}` if no data available
  """
  def get_latest_price(symbol) do
    case get_ticker(symbol) do
      {:ok, {_timestamp, %{price: price}}} -> {:ok, price}
      {:ok, {_timestamp, data}} -> {:ok, Map.get(data, "price")}
      error -> error
    end
  end

  @doc """
  Get latest ticker data (alias for get_ticker).
  """
  def get_latest(symbol), do: get_ticker(symbol)

  @doc """
  Store trade data for a symbol.

  Maintains a ring buffer of the last N trades per symbol.

  ## Parameters
  - `symbol`: Trading pair symbol
  - `trade_data`: Map containing trade information (must include trade_id or id)

  ## Returns
  - `:ok`

  ## Examples
      iex> Cache.put_trade("BTCUSDT", %{
      ...>   trade_id: "12345",
      ...>   price: "43250.50",
      ...>   quantity: "0.5",
      ...>   timestamp: ~U[2025-12-04 12:34:56Z],
      ...>   side: :buy
      ...> })
      :ok
  """
  def put_trade(symbol, trade_data) do
    trade_id =
      Map.get(trade_data, :trade_id) || Map.get(trade_data, "trade_id") ||
        Map.get(trade_data, :id) || Map.get(trade_data, "id")

    if trade_id do
      key = {symbol, trade_id}
      :ets.insert(@trade_table, {key, trade_data})

      # Implement ring buffer: remove oldest trades if exceeds limit
      cleanup_old_trades(symbol)

      :ok
    else
      Logger.warning("[Cache] Trade data missing trade_id, skipping: #{inspect(trade_data)}")
      {:error, :missing_trade_id}
    end
  end

  @doc """
  Retrieve recent trades for a symbol.

  ## Parameters
  - `symbol`: Trading pair symbol
  - `limit`: Maximum number of trades to return (default: 100)

  ## Returns
  - List of trade data maps, sorted by timestamp descending (most recent first)

  ## Examples
      iex> Cache.get_trades("BTCUSDT", 10)
      [%{trade_id: "12345", price: "43250.50", ...}, ...]
  """
  def get_trades(symbol, limit \\ 100) do
    # Match all trades for this symbol
    pattern = {{symbol, :_}, :_}

    @trade_table
    |> :ets.match_object(pattern)
    |> Enum.map(fn {{_symbol, _trade_id}, data} -> data end)
    |> Enum.sort_by(
      fn trade ->
        timestamp = Map.get(trade, :timestamp) || Map.get(trade, "timestamp")
        if timestamp, do: DateTime.to_unix(timestamp), else: 0
      end,
      :desc
    )
    |> Enum.take(limit)
  end

  @doc """
  Store candle data for a symbol and timeframe.

  ## Parameters
  - `symbol`: Trading pair symbol
  - `timeframe`: Timeframe string (e.g., "1m", "1h", "1d")
  - `candle_data`: Map containing OHLCV data with timestamp

  ## Returns
  - `:ok`

  ## Examples
      iex> Cache.put_candle("BTCUSDT", "1h", %{
      ...>   timestamp: ~U[2025-12-04 12:00:00Z],
      ...>   open: "43000.00",
      ...>   high: "43500.00",
      ...>   low: "42800.00",
      ...>   close: "43250.00",
      ...>   volume: "1234.56"
      ...> })
      :ok
  """
  def put_candle(symbol, timeframe, candle_data) do
    timestamp = Map.get(candle_data, :timestamp) || Map.get(candle_data, "timestamp")

    if timestamp do
      key = {symbol, timeframe, timestamp}
      :ets.insert(@candle_table, {key, candle_data})
      :ok
    else
      Logger.warning("[Cache] Candle data missing timestamp, skipping")
      {:error, :missing_timestamp}
    end
  end

  @doc """
  Retrieve recent candles for a symbol and timeframe.

  ## Parameters
  - `symbol`: Trading pair symbol
  - `timeframe`: Timeframe string
  - `limit`: Maximum number of candles to return (default: 100)

  ## Returns
  - List of candle data maps, sorted by timestamp ascending (oldest first)

  ## Examples
      iex> Cache.get_candles("BTCUSDT", "1h", 50)
      [%{timestamp: ~U[...], open: "...", ...}, ...]
  """
  def get_candles(symbol, timeframe, limit \\ 100) do
    pattern = {{symbol, timeframe, :_}, :_}

    @candle_table
    |> :ets.match_object(pattern)
    |> Enum.map(fn {{_symbol, _timeframe, _timestamp}, data} -> data end)
    |> Enum.sort_by(
      fn candle ->
        timestamp = Map.get(candle, :timestamp) || Map.get(candle, "timestamp")
        if timestamp, do: DateTime.to_unix(timestamp), else: 0
      end,
      :asc
    )
    # Take last N (most recent)
    |> Enum.take(-limit)
  end

  @doc """
  Clear all cached data for a symbol.

  ## Parameters
  - `symbol`: Trading pair symbol

  ## Returns
  - `:ok`
  """
  def clear_symbol(symbol) do
    # Clear ticker
    :ets.delete(@ticker_table, symbol)

    # Clear trades
    pattern = {{symbol, :_}, :_}
    :ets.match_delete(@trade_table, pattern)

    # Clear candles
    pattern = {{symbol, :_, :_}, :_}
    :ets.match_delete(@candle_table, pattern)

    :ok
  end

  @doc """
  Clear all cached data from all tables.

  ## Returns
  - `:ok`
  """
  def clear_all do
    :ets.delete_all_objects(@ticker_table)
    :ets.delete_all_objects(@trade_table)
    :ets.delete_all_objects(@candle_table)
    :ok
  end

  @doc """
  Get cache statistics.

  ## Returns
  - Map with cache statistics
  """
  def stats do
    %{
      ticker_count: :ets.info(@ticker_table, :size),
      trade_count: :ets.info(@trade_table, :size),
      candle_count: :ets.info(@candle_table, :size),
      memory_bytes:
        :ets.info(@ticker_table, :memory) +
          :ets.info(@trade_table, :memory) +
          :ets.info(@candle_table, :memory)
    }
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Create ETS tables for caching market data
    :ets.new(@ticker_table, [:named_table, :set, :public, read_concurrency: true])
    :ets.new(@trade_table, [:named_table, :set, :public, read_concurrency: true])
    :ets.new(@candle_table, [:named_table, :set, :public, read_concurrency: true])

    Logger.info("[Cache] Initialized ETS tables for market data caching")

    {:ok, %{}}
  end

  # Private Functions

  defp cleanup_old_trades(symbol) do
    # Count trades for this symbol
    pattern = {{symbol, :_}, :_}
    count = length(:ets.match_object(@trade_table, pattern))

    if count > @max_trades_per_symbol do
      # Get all trades, sort by timestamp, delete oldest
      trades =
        @trade_table
        |> :ets.match_object(pattern)
        |> Enum.sort_by(
          fn {{_symbol, _trade_id}, data} ->
            timestamp = Map.get(data, :timestamp) || Map.get(data, "timestamp")
            if timestamp, do: DateTime.to_unix(timestamp), else: 0
          end,
          :asc
        )

      # Delete oldest trades (keep only max limit)
      to_delete = count - @max_trades_per_symbol

      trades
      |> Enum.take(to_delete)
      |> Enum.each(fn {{s, tid}, _data} ->
        :ets.delete(@trade_table, {s, tid})
      end)
    end
  end
end
