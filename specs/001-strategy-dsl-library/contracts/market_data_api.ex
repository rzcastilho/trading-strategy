# Market Data API Contract
#
# This module defines the Elixir behaviour contract for market data operations.
# Covers FR-024 through FR-027 (Data Management requirements)

defmodule TradingStrategy.Contracts.MarketDataAPI do
  @moduledoc """
  Contract for retrieving and managing market data (OHLCV bars).

  Handles historical data retrieval (FR-024), real-time data streaming (FR-025),
  indicator calculation (FR-026), and value caching (FR-027).
  """

  @type ohlcv_bar :: %{
    symbol: String.t(),
    timestamp: DateTime.t(),
    open: Decimal.t(),
    high: Decimal.t(),
    low: Decimal.t(),
    close: Decimal.t(),
    volume: Decimal.t(),
    timeframe: String.t(),
    data_source: String.t()
  }

  @type stream_subscription :: %{
    subscription_id: String.t(),
    symbol: String.t(),
    timeframe: String.t(),
    callback: (ohlcv_bar() -> any()),
    status: :active | :paused | :stopped
  }

  @type indicator_result :: %{
    indicator_type: atom(),
    values: [float()] | map(),  # List for simple indicators, map for complex (MACD, BB)
    calculated_at: DateTime.t(),
    parameters: map()
  }

  @doc """
  Fetches historical OHLCV data for backtesting.

  Implements FR-024 (retrieve historical market data for backtesting).

  ## Parameters
  - `symbol`: Trading pair (e.g., "BTC/USD")
  - `timeframe`: Candlestick interval ("1m", "5m", "1h", "1d", etc.)
  - `start_date`: Beginning of date range
  - `end_date`: End of date range
  - `data_source`: Exchange name ("binance", "coinbase", "kraken")
  - `opts`: Optional parameters
    - `limit`: Max bars to return (default 1000)
    - `include_incomplete`: Boolean, include current incomplete bar (default false)

  ## Returns
  - `{:ok, [ohlcv_bar, ...]}` with historical bars in chronological order
  - `{:error, :invalid_symbol}` if trading pair not supported
  - `{:error, :invalid_timeframe}` if timeframe not supported by exchange
  - `{:error, :no_data_available}` if no data exists for date range
  - `{:error, :exchange_error}` with error details from exchange

  ## Examples
      iex> fetch_historical_ohlcv("BTC/USD", "1h", ~U[2024-01-01 00:00:00Z], ~U[2024-12-31 23:59:59Z], "binance")
      {:ok, [
        %{
          symbol: "BTC/USD",
          timestamp: ~U[2024-01-01 00:00:00Z],
          open: Decimal.new("42150.00"),
          high: Decimal.new("42350.00"),
          low: Decimal.new("42050.00"),
          close: Decimal.new("42280.00"),
          volume: Decimal.new("125.45"),
          timeframe: "1h",
          data_source: "binance"
        },
        ...
      ]}

  ## Notes
  - Data cached in PostgreSQL + TimescaleDB for performance
  - Handles pagination automatically for large date ranges
  - Validates OHLC consistency (low <= open/close <= high)
  """
  @callback fetch_historical_ohlcv(
    symbol :: String.t(),
    timeframe :: String.t(),
    start_date :: DateTime.t(),
    end_date :: DateTime.t(),
    data_source :: String.t(),
    opts :: keyword()
  ) :: {:ok, [ohlcv_bar()]} |
       {:error, :invalid_symbol | :invalid_timeframe | :no_data_available | :exchange_error}

  @doc """
  Subscribes to real-time OHLCV data stream via WebSocket.

  Implements FR-025 (retrieve real-time market data for paper/live trading).

  ## Parameters
  - `symbol`: Trading pair to subscribe
  - `timeframe`: Candlestick interval
  - `data_source`: Exchange name
  - `callback`: Function called on each new bar (bar :: ohlcv_bar()) -> any()

  ## Returns
  - `{:ok, subscription_id}` with unique subscription identifier
  - `{:error, :invalid_symbol}` if trading pair not supported
  - `{:error, :websocket_connection_failed}` if cannot connect to exchange
  - `{:error, :subscription_limit_reached}` if too many active subscriptions

  ## Examples
      iex> subscribe_realtime_ohlcv("BTC/USD", "1m", "binance", fn bar ->
        IO.inspect(bar, label: "New bar received")
      end)
      {:ok, "sub_abc123"}

  ## Notes
  - WebSocket connection managed by supervision tree
  - Automatic reconnection on disconnect (exponential backoff)
  - Callback executed in separate process (doesn't block stream)
  - Handles exchange ping/pong frames automatically
  """
  @callback subscribe_realtime_ohlcv(
    symbol :: String.t(),
    timeframe :: String.t(),
    data_source :: String.t(),
    callback :: (ohlcv_bar() -> any())
  ) :: {:ok, String.t()} |
       {:error, :invalid_symbol | :websocket_connection_failed | :subscription_limit_reached}

  @doc """
  Unsubscribes from a real-time data stream.

  ## Parameters
  - `subscription_id`: UUID returned by subscribe_realtime_ohlcv

  ## Returns
  - `:ok` if successfully unsubscribed
  - `{:error, :not_found}` if subscription doesn't exist
  """
  @callback unsubscribe_realtime_ohlcv(subscription_id :: String.t()) ::
    :ok | {:error, :not_found}

  @doc """
  Calculates an indicator from market data.

  Implements FR-026 (calculate indicator values based on market data).

  ## Parameters
  - `indicator_type`: Atom representing indicator (:rsi, :macd, :sma, :ema, :bb, etc.)
  - `market_data`: List of OHLCV bars (must be sufficient for calculation)
  - `parameters`: Map of indicator-specific parameters

  ## Returns
  - `{:ok, indicator_result}` with calculated values
  - `{:error, :insufficient_data}` if not enough bars for calculation
  - `{:error, :invalid_parameters}` if parameters invalid
  - `{:error, :unsupported_indicator}` if indicator type not implemented

  ## Examples
      iex> calculate_indicator(:rsi, ohlcv_bars, %{period: 14})
      {:ok, %{
        indicator_type: :rsi,
        values: [30.5, 42.3, 55.1, ...],
        calculated_at: ~U[2025-12-04 12:34:56Z],
        parameters: %{period: 14}
      }}

      iex> calculate_indicator(:macd, ohlcv_bars, %{short: 12, long: 26, signal: 9})
      {:ok, %{
        indicator_type: :macd,
        values: %{
          macd: [0.5, 1.2, -0.3, ...],
          signal: [0.4, 0.8, 0.1, ...],
          histogram: [0.1, 0.4, -0.4, ...]
        },
        calculated_at: ~U[2025-12-04 12:34:56Z],
        parameters: %{short_period: 12, long_period: 26, signal_period: 9}
      }}

  ## Supported Indicators (FR-003)
  - Moving Averages: :sma, :ema, :wma, :hma, :kama
  - Oscillators: :rsi, :macd, :stochastic, :williams_r, :cci, :roc
  - Volatility: :bb (Bollinger Bands), :atr, :std_dev
  - Volume: :obv, :vwap, :adi, :cmf, :mfi

  ## Notes
  - Uses trading-indicators library (TradingIndicators.Trend/Momentum/Volatility/Volume modules)
  - Caching handled by cache_indicator_values/4
  - Returns values aligned with input market_data timestamps
  - Supports both batch calculation and streaming for real-time updates
  """
  @callback calculate_indicator(
    indicator_type :: atom(),
    market_data :: [ohlcv_bar()],
    parameters :: map()
  ) :: {:ok, indicator_result()} |
       {:error, :insufficient_data | :invalid_parameters | :unsupported_indicator}

  @doc """
  Caches calculated indicator values to avoid redundant computation.

  Implements FR-027 (cache calculated indicator values).

  ## Parameters
  - `strategy_id`: UUID of strategy (cache key component)
  - `indicator_name`: Name from strategy definition (e.g., "rsi_14")
  - `timestamp`: Bar timestamp for this calculation
  - `indicator_result`: Calculated values to cache

  ## Returns
  - `:ok` if successfully cached

  ## Notes
  - Stored in ETS table for fast access
  - Cache key: {strategy_id, indicator_name, timestamp}
  - Invalidated when new market data arrives for timeframe
  - TTL: Until next bar completes (automatic cleanup)
  """
  @callback cache_indicator_values(
    strategy_id :: String.t(),
    indicator_name :: String.t(),
    timestamp :: DateTime.t(),
    indicator_result :: indicator_result()
  ) :: :ok

  @doc """
  Retrieves cached indicator values.

  ## Parameters
  - `strategy_id`: UUID of strategy
  - `indicator_name`: Name from strategy definition
  - `timestamp`: Bar timestamp to retrieve

  ## Returns
  - `{:ok, indicator_result}` if cached value exists
  - `{:error, :not_cached}` if value not in cache (needs calculation)

  ## Notes
  - Check cache before calling calculate_indicator for performance
  - Cache hit rate typically >90% for active strategies
  """
  @callback get_cached_indicator_values(
    strategy_id :: String.t(),
    indicator_name :: String.t(),
    timestamp :: DateTime.t()
  ) :: {:ok, indicator_result()} | {:error, :not_cached}

  @doc """
  Retrieves the latest N bars for a symbol from cache or database.

  ## Parameters
  - `symbol`: Trading pair
  - `timeframe`: Candlestick interval
  - `count`: Number of bars to retrieve (default 500)
  - `data_source`: Exchange name

  ## Returns
  - `{:ok, [ohlcv_bar, ...]}` with latest bars in reverse chronological order
  - `{:error, :no_data_available}` if no data exists

  ## Notes
  - First checks ETS cache (last N bars sliding window)
  - Falls back to PostgreSQL query if not cached
  - Used by strategy evaluation for recent history context
  """
  @callback get_latest_bars(
    symbol :: String.t(),
    timeframe :: String.t(),
    count :: integer(),
    data_source :: String.t()
  ) :: {:ok, [ohlcv_bar()]} | {:error, :no_data_available}

  @doc """
  Validates market data quality (consistency checks).

  ## Parameters
  - `bar`: OHLCV bar to validate

  ## Returns
  - `:ok` if bar passes all validation rules
  - `{:error, [validation_error, ...]}` with specific errors

  ## Validation Rules
  1. OHLC Consistency: low <= open <= high, low <= close <= high
  2. Positive prices: open, high, low, close > 0
  3. Non-negative volume: volume >= 0
  4. Timestamp alignment: aligns to timeframe boundary
  5. No duplicates: unique (symbol, timestamp, timeframe, data_source)

  ## Examples
      iex> validate_market_data(%{
        open: Decimal.new("100"),
        high: Decimal.new("90"),  # ERROR: high < open
        low: Decimal.new("95"),
        close: Decimal.new("98"),
        volume: Decimal.new("50")
      })
      {:error, ["OHLC consistency: high (90.00) < open (100.00)"]}
  """
  @callback validate_market_data(bar :: ohlcv_bar()) ::
    :ok | {:error, [String.t()]}

  @doc """
  Stores market data to persistent storage (PostgreSQL + TimescaleDB).

  ## Parameters
  - `bars`: List of OHLCV bars to persist

  ## Returns
  - `{:ok, count}` with number of bars inserted
  - `{:error, :database_error}` if persistence fails

  ## Notes
  - Upserts (insert or ignore duplicates)
  - TimescaleDB automatically partitions by time
  - Indexed on (symbol, timestamp DESC) for fast queries
  """
  @callback store_market_data(bars :: [ohlcv_bar()]) ::
    {:ok, integer()} | {:error, :database_error}
end
