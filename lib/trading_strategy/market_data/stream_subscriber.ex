defmodule TradingStrategy.MarketData.StreamSubscriber do
  @moduledoc """
  Manages real-time market data stream subscriptions using CryptoExchange.API.

  Integrates with Phoenix.PubSub to broadcast ticker and trade updates
  to interested processes throughout the application.

  ## Responsibilities
  - Subscribe to real-time ticker updates via CryptoExchange.API.subscribe_to_ticker/1
  - Subscribe to trade streams via CryptoExchange.API.subscribe_to_trades/1
  - Broadcast updates via Phoenix.PubSub for local distribution
  - Handle connection failures and reconnection logic

  ## PubSub Topics
  - `"ticker:SYMBOL"` - Real-time price updates for a trading pair
  - `"trades:SYMBOL"` - Real-time trade stream for a trading pair
  """

  use GenServer
  require Logger

  alias Phoenix.PubSub

  @pubsub_name TradingStrategy.PubSub

  # Client API

  @doc """
  Starts the stream subscriber GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Subscribe to ticker updates for a trading pair.

  Connects to the exchange WebSocket and begins broadcasting updates
  to the PubSub topic "ticker:SYMBOL".

  ## Parameters
  - `symbol`: Trading pair symbol (e.g., "BTCUSDT")
  - `exchange`: Exchange name (default: "binance")

  ## Returns
  - `:ok` if subscription successful
  - `{:error, reason}` if subscription failed

  ## Examples
      iex> StreamSubscriber.subscribe_ticker("BTCUSDT")
      :ok

      iex> StreamSubscriber.subscribe_ticker("ETHUSDT", "binance")
      :ok
  """
  def subscribe_ticker(symbol, exchange \\ "binance") do
    GenServer.call(__MODULE__, {:subscribe_ticker, symbol, exchange})
  end

  @doc """
  Subscribe to trade stream for a trading pair.

  Connects to the exchange WebSocket and begins broadcasting trade updates
  to the PubSub topic "trades:SYMBOL".

  ## Parameters
  - `symbol`: Trading pair symbol (e.g., "BTCUSDT")
  - `exchange`: Exchange name (default: "binance")

  ## Returns
  - `:ok` if subscription successful
  - `{:error, reason}` if subscription failed

  ## Examples
      iex> StreamSubscriber.subscribe_trades("BTCUSDT")
      :ok
  """
  def subscribe_trades(symbol, exchange \\ "binance") do
    GenServer.call(__MODULE__, {:subscribe_trades, symbol, exchange})
  end

  @doc """
  Unsubscribe from ticker updates for a trading pair.

  ## Parameters
  - `symbol`: Trading pair symbol to unsubscribe from

  ## Returns
  - `:ok` if unsubscription successful
  """
  def unsubscribe_ticker(symbol) do
    GenServer.call(__MODULE__, {:unsubscribe_ticker, symbol})
  end

  @doc """
  Unsubscribe from trade stream for a trading pair.

  ## Parameters
  - `symbol`: Trading pair symbol to unsubscribe from

  ## Returns
  - `:ok` if unsubscription successful
  """
  def unsubscribe_trades(symbol) do
    GenServer.call(__MODULE__, {:unsubscribe_trades, symbol})
  end

  @doc """
  Get list of active ticker subscriptions.

  ## Returns
  - List of subscribed trading pair symbols
  """
  def list_ticker_subscriptions do
    GenServer.call(__MODULE__, :list_ticker_subscriptions)
  end

  @doc """
  Get list of active trade subscriptions.

  ## Returns
  - List of subscribed trading pair symbols
  """
  def list_trade_subscriptions do
    GenServer.call(__MODULE__, :list_trade_subscriptions)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    state = %{
      # %{symbol => subscription_ref}
      ticker_subscriptions: %{},
      # %{symbol => subscription_ref}
      trade_subscriptions: %{},
      exchange: "binance"
    }

    Logger.info("[StreamSubscriber] Started")

    {:ok, state}
  end

  @impl true
  def handle_call({:subscribe_ticker, symbol, exchange}, _from, state) do
    case Map.get(state.ticker_subscriptions, symbol) do
      nil ->
        # Not yet subscribed, create new subscription
        case CryptoExchange.API.subscribe_to_ticker(symbol) do
          {:ok, subscription_ref} ->
            Logger.info("[StreamSubscriber] Subscribed to ticker: #{symbol}")

            new_subscriptions = Map.put(state.ticker_subscriptions, symbol, subscription_ref)
            new_state = %{state | ticker_subscriptions: new_subscriptions, exchange: exchange}

            {:reply, :ok, new_state}

          {:error, reason} = error ->
            Logger.error(
              "[StreamSubscriber] Failed to subscribe to ticker #{symbol}: #{inspect(reason)}"
            )

            {:reply, error, state}
        end

      _subscription_ref ->
        # Already subscribed
        Logger.debug("[StreamSubscriber] Already subscribed to ticker: #{symbol}")
        {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call({:subscribe_trades, symbol, exchange}, _from, state) do
    case Map.get(state.trade_subscriptions, symbol) do
      nil ->
        # Not yet subscribed, create new subscription
        case CryptoExchange.API.subscribe_to_trades(symbol) do
          {:ok, subscription_ref} ->
            Logger.info("[StreamSubscriber] Subscribed to trades: #{symbol}")

            new_subscriptions = Map.put(state.trade_subscriptions, symbol, subscription_ref)
            new_state = %{state | trade_subscriptions: new_subscriptions, exchange: exchange}

            {:reply, :ok, new_state}

          {:error, reason} = error ->
            Logger.error(
              "[StreamSubscriber] Failed to subscribe to trades #{symbol}: #{inspect(reason)}"
            )

            {:reply, error, state}
        end

      _subscription_ref ->
        # Already subscribed
        Logger.debug("[StreamSubscriber] Already subscribed to trades: #{symbol}")
        {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call({:unsubscribe_ticker, symbol}, _from, state) do
    case Map.get(state.ticker_subscriptions, symbol) do
      nil ->
        {:reply, :ok, state}

      subscription_ref ->
        # Note: CryptoExchange library should provide unsubscribe functionality
        # For now, we just remove from our tracking
        Logger.info("[StreamSubscriber] Unsubscribed from ticker: #{symbol}")
        new_subscriptions = Map.delete(state.ticker_subscriptions, symbol)
        new_state = %{state | ticker_subscriptions: new_subscriptions}
        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call({:unsubscribe_trades, symbol}, _from, state) do
    case Map.get(state.trade_subscriptions, symbol) do
      nil ->
        {:reply, :ok, state}

      subscription_ref ->
        Logger.info("[StreamSubscriber] Unsubscribed from trades: #{symbol}")
        new_subscriptions = Map.delete(state.trade_subscriptions, symbol)
        new_state = %{state | trade_subscriptions: new_subscriptions}
        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call(:list_ticker_subscriptions, _from, state) do
    symbols = Map.keys(state.ticker_subscriptions)
    {:reply, symbols, state}
  end

  @impl true
  def handle_call(:list_trade_subscriptions, _from, state) do
    symbols = Map.keys(state.trade_subscriptions)
    {:reply, symbols, state}
  end

  @impl true
  def handle_info({:ticker_update, symbol, data}, state) do
    # Broadcast ticker update to PubSub subscribers
    Logger.debug("[StreamSubscriber] Ticker update for #{symbol}: #{inspect(data)}")

    PubSub.broadcast(@pubsub_name, "ticker:#{symbol}", {:ticker_update, symbol, data})

    {:noreply, state}
  end

  @impl true
  def handle_info({:trade_update, symbol, data}, state) do
    # Broadcast trade update to PubSub subscribers
    Logger.debug("[StreamSubscriber] Trade update for #{symbol}: #{inspect(data)}")

    PubSub.broadcast(@pubsub_name, "trades:#{symbol}", {:trade_update, symbol, data})

    {:noreply, state}
  end

  @impl true
  def handle_info({:websocket_disconnected, symbol}, state) do
    Logger.warning(
      "[StreamSubscriber] WebSocket disconnected for #{symbol}, attempting reconnection..."
    )

    # Attempt to reconnect after a delay
    Process.send_after(self(), {:reconnect_ticker, symbol}, 5_000)

    {:noreply, state}
  end

  @impl true
  def handle_info({:reconnect_ticker, symbol}, state) do
    Logger.info("[StreamSubscriber] Reconnecting ticker for #{symbol}")

    case CryptoExchange.API.subscribe_to_ticker(symbol) do
      {:ok, subscription_ref} ->
        Logger.info("[StreamSubscriber] Successfully reconnected ticker: #{symbol}")
        new_subscriptions = Map.put(state.ticker_subscriptions, symbol, subscription_ref)
        new_state = %{state | ticker_subscriptions: new_subscriptions}
        {:noreply, new_state}

      {:error, reason} ->
        Logger.error(
          "[StreamSubscriber] Reconnection failed for #{symbol}: #{inspect(reason)}, retrying in 10s"
        )

        Process.send_after(self(), {:reconnect_ticker, symbol}, 10_000)
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("[StreamSubscriber] Received unknown message: #{inspect(msg)}")
    {:noreply, state}
  end
end
