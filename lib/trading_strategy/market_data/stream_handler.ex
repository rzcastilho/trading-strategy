defmodule TradingStrategy.MarketData.StreamHandler do
  @moduledoc """
  Handles incoming market data stream messages from Phoenix.PubSub.

  This module processes ticker and trade updates received from the StreamSubscriber
  and performs the following actions:
  - Updates the market data cache
  - Triggers indicator calculations
  - Notifies interested processes (paper trading sessions, live trading sessions)

  ## Message Format

  ### Ticker Updates
  Message: `{:ticker_update, symbol, data}`

  Data structure (from CryptoExchange.API):
  ```elixir
  %{
    symbol: "BTCUSDT",
    price: "43250.50",
    timestamp: ~U[2025-12-04 12:34:56Z],
    volume: "1234.56",
    high_24h: "44000.00",
    low_24h: "42000.00"
  }
  ```

  ### Trade Updates
  Message: `{:trade_update, symbol, data}`

  Data structure:
  ```elixir
  %{
    symbol: "BTCUSDT",
    price: "43250.50",
    quantity: "0.5",
    timestamp: ~U[2025-12-04 12:34:56Z],
    side: :buy | :sell
  }
  ```

  ## Usage

  To subscribe to market data updates:

  ```elixir
  # In your GenServer
  def init(state) do
    # Subscribe to ticker updates for BTC
    Phoenix.PubSub.subscribe(TradingStrategy.PubSub, "ticker:BTCUSDT")

    {:ok, state}
  end

  def handle_info({:ticker_update, symbol, data}, state) do
    # Handle the ticker update
    # This will be called automatically by StreamHandler
    {:noreply, state}
  end
  ```
  """

  use GenServer
  require Logger

  alias TradingStrategy.MarketData.Cache
  alias Phoenix.PubSub

  @pubsub_name TradingStrategy.PubSub

  # Client API

  @doc """
  Starts the stream handler GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Subscribe this handler to market data updates for a symbol.

  ## Parameters
  - `symbol`: Trading pair symbol (e.g., "BTCUSDT")
  - `types`: List of data types to subscribe to ([:ticker, :trades] or subset)

  ## Returns
  - `:ok`

  ## Examples
      iex> StreamHandler.subscribe("BTCUSDT", [:ticker])
      :ok

      iex> StreamHandler.subscribe("ETHUSDT", [:ticker, :trades])
      :ok
  """
  def subscribe(symbol, types \\ [:ticker, :trades]) do
    GenServer.call(__MODULE__, {:subscribe, symbol, types})
  end

  @doc """
  Unsubscribe from market data updates for a symbol.

  ## Parameters
  - `symbol`: Trading pair symbol to unsubscribe from
  - `types`: List of data types to unsubscribe from

  ## Returns
  - `:ok`
  """
  def unsubscribe(symbol, types \\ [:ticker, :trades]) do
    GenServer.call(__MODULE__, {:unsubscribe, symbol, types})
  end

  @doc """
  Get latest market data for a symbol from cache.

  ## Parameters
  - `symbol`: Trading pair symbol

  ## Returns
  - `{:ok, data}` if data exists in cache
  - `{:error, :not_found}` if no data available
  """
  def get_latest(symbol) do
    Cache.get_latest(symbol)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    state = %{
      # Track our PubSub subscriptions
      subscriptions: MapSet.new()
    }

    Logger.info("[StreamHandler] Started")

    {:ok, state}
  end

  @impl true
  def handle_call({:subscribe, symbol, types}, _from, state) do
    new_state =
      Enum.reduce(types, state, fn type, acc_state ->
        topic = build_topic(symbol, type)

        if MapSet.member?(acc_state.subscriptions, topic) do
          # Already subscribed
          acc_state
        else
          # Subscribe to PubSub topic
          :ok = PubSub.subscribe(@pubsub_name, topic)
          Logger.info("[StreamHandler] Subscribed to #{topic}")

          %{acc_state | subscriptions: MapSet.put(acc_state.subscriptions, topic)}
        end
      end)

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:unsubscribe, symbol, types}, _from, state) do
    new_state =
      Enum.reduce(types, state, fn type, acc_state ->
        topic = build_topic(symbol, type)

        if MapSet.member?(acc_state.subscriptions, topic) do
          # Unsubscribe from PubSub topic
          :ok = PubSub.unsubscribe(@pubsub_name, topic)
          Logger.info("[StreamHandler] Unsubscribed from #{topic}")

          %{acc_state | subscriptions: MapSet.delete(acc_state.subscriptions, topic)}
        else
          acc_state
        end
      end)

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_info({:ticker_update, symbol, data}, state) do
    Logger.debug("[StreamHandler] Processing ticker update for #{symbol}")

    # Update cache with latest ticker data
    :ok = Cache.put_ticker(symbol, data)

    # Broadcast to any additional interested processes
    # This allows other parts of the system to react to ticker updates
    PubSub.broadcast_from(
      @pubsub_name,
      self(),
      "market_data:#{symbol}",
      {:market_data_updated, symbol, :ticker, data}
    )

    {:noreply, state}
  end

  @impl true
  def handle_info({:trade_update, symbol, data}, state) do
    Logger.debug("[StreamHandler] Processing trade update for #{symbol}")

    # Update cache with latest trade data
    :ok = Cache.put_trade(symbol, data)

    # Broadcast to interested processes
    PubSub.broadcast_from(
      @pubsub_name,
      self(),
      "market_data:#{symbol}",
      {:market_data_updated, symbol, :trade, data}
    )

    {:noreply, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("[StreamHandler] Received unknown message: #{inspect(msg)}")
    {:noreply, state}
  end

  # Private Functions

  defp build_topic(symbol, :ticker), do: "ticker:#{symbol}"
  defp build_topic(symbol, :trades), do: "trades:#{symbol}"
end
