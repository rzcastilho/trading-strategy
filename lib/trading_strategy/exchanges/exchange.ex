defmodule TradingStrategy.Exchanges.Exchange do
  @moduledoc """
  Exchange wrapper abstracting CryptoExchange.API functions.

  Provides a consistent interface for:
  - User connection management (connect_user)
  - Order placement (place_order)
  - Order cancellation (cancel_order)
  - Account balance queries (get_balance)

  This module wraps the crypto-exchange library's CryptoExchange.API module
  to provide additional error handling, logging, and consistency checks.
  """

  require Logger

  @type user_id :: String.t()
  @type api_key :: String.t()
  @type api_secret :: String.t()
  @type symbol :: String.t()
  @type order_id :: String.t()

  @type order_params :: %{
          symbol: symbol(),
          side: :BUY | :SELL,
          type: :MARKET | :LIMIT | :STOP_LOSS,
          quantity: Decimal.t(),
          price: Decimal.t() | nil
        }

  @type balance :: %{
          asset: String.t(),
          free: Decimal.t(),
          locked: Decimal.t()
        }

  @type order_response :: %{
          order_id: String.t(),
          symbol: String.t(),
          status: String.t(),
          price: Decimal.t(),
          quantity: Decimal.t()
        }

  @doc """
  Connect a user to the exchange with their API credentials.

  ## Parameters
  - `user_id`: Unique identifier for the user
  - `api_key`: Exchange API key
  - `api_secret`: Exchange API secret

  ## Returns
  - `{:ok, user_pid}` - Successfully connected user
  - `{:error, reason}` - Connection failed

  ## Examples
      iex> Exchange.connect_user("user_123", "key", "secret")
      {:ok, #PID<0.123.0>}
  """
  @spec connect_user(user_id(), api_key(), api_secret()) :: {:ok, pid()} | {:error, term()}
  def connect_user(user_id, api_key, api_secret) do
    Logger.info("Connecting user to exchange", user_id: user_id)

    case CryptoExchange.API.connect_user(user_id, api_key, api_secret) do
      {:ok, user_pid} = result ->
        Logger.info("User connected successfully", user_id: user_id, user_pid: inspect(user_pid))
        result

      {:error, reason} = error ->
        Logger.error("Failed to connect user to exchange",
          user_id: user_id,
          reason: inspect(reason)
        )

        error
    end
  end

  @doc """
  Place an order on the exchange.

  ## Parameters
  - `user_id`: User identifier (must be connected via connect_user/3)
  - `order_params`: Map containing order details

  ## Order Parameters
  - `:symbol` - Trading pair (e.g., "BTCUSDT")
  - `:side` - :BUY or :SELL
  - `:type` - :MARKET, :LIMIT, or :STOP_LOSS
  - `:quantity` - Order quantity (Decimal)
  - `:price` - Limit price (Decimal, optional for MARKET orders)

  ## Returns
  - `{:ok, order_response}` - Order placed successfully
  - `{:error, reason}` - Order placement failed

  ## Examples
      iex> Exchange.place_order("user_123", %{
      ...>   symbol: "BTCUSDT",
      ...>   side: :BUY,
      ...>   type: :MARKET,
      ...>   quantity: Decimal.new("0.001")
      ...> })
      {:ok, %{order_id: "12345", status: "FILLED", ...}}
  """
  @spec place_order(user_id(), order_params()) :: {:ok, order_response()} | {:error, term()}
  def place_order(user_id, order_params) do
    Logger.info("Placing order on exchange",
      user_id: user_id,
      symbol: order_params[:symbol],
      side: order_params[:side],
      type: order_params[:type],
      quantity: Decimal.to_string(order_params[:quantity])
    )

    case CryptoExchange.API.place_order(user_id, order_params) do
      {:ok, response} = result ->
        Logger.info("Order placed successfully",
          user_id: user_id,
          order_id: response[:order_id],
          status: response[:status]
        )

        result

      {:error, reason} = error ->
        Logger.error("Failed to place order",
          user_id: user_id,
          order_params: inspect(order_params),
          reason: inspect(reason)
        )

        error
    end
  end

  @doc """
  Cancel an existing order on the exchange.

  ## Parameters
  - `user_id`: User identifier
  - `symbol`: Trading pair
  - `order_id`: Exchange order ID to cancel

  ## Returns
  - `{:ok, cancel_response}` - Order cancelled successfully
  - `{:error, reason}` - Cancellation failed

  ## Examples
      iex> Exchange.cancel_order("user_123", "BTCUSDT", "12345")
      {:ok, %{order_id: "12345", status: "CANCELED"}}
  """
  @spec cancel_order(user_id(), symbol(), order_id()) :: {:ok, map()} | {:error, term()}
  def cancel_order(user_id, symbol, order_id) do
    Logger.info("Cancelling order on exchange",
      user_id: user_id,
      symbol: symbol,
      order_id: order_id
    )

    case CryptoExchange.API.cancel_order(user_id, symbol, order_id) do
      {:ok, response} = result ->
        Logger.info("Order cancelled successfully",
          user_id: user_id,
          order_id: order_id,
          status: response[:status]
        )

        result

      {:error, reason} = error ->
        Logger.error("Failed to cancel order",
          user_id: user_id,
          symbol: symbol,
          order_id: order_id,
          reason: inspect(reason)
        )

        error
    end
  end

  @doc """
  Get account balance from the exchange.

  ## Parameters
  - `user_id`: User identifier

  ## Returns
  - `{:ok, balances}` - List of balance maps containing asset, free, and locked amounts
  - `{:error, reason}` - Failed to retrieve balances

  ## Examples
      iex> Exchange.get_balance("user_123")
      {:ok, [
        %{asset: "BTC", free: Decimal.new("1.5"), locked: Decimal.new("0.1")},
        %{asset: "USDT", free: Decimal.new("10000"), locked: Decimal.new("500")}
      ]}
  """
  @spec get_balance(user_id()) :: {:ok, [balance()]} | {:error, term()}
  def get_balance(user_id) do
    Logger.debug("Fetching account balance", user_id: user_id)

    case CryptoExchange.API.get_balance(user_id) do
      {:ok, balances} = result ->
        Logger.debug("Balance retrieved successfully",
          user_id: user_id,
          asset_count: length(balances)
        )

        result

      {:error, reason} = error ->
        Logger.error("Failed to retrieve balance",
          user_id: user_id,
          reason: inspect(reason)
        )

        error
    end
  end

  @doc """
  Get open orders for a user.

  ## Parameters
  - `user_id`: User identifier
  - `symbol`: Trading pair (optional, nil returns all open orders)

  ## Returns
  - `{:ok, orders}` - List of open orders
  - `{:error, reason}` - Failed to retrieve orders
  """
  @spec get_open_orders(user_id(), symbol() | nil) :: {:ok, [map()]} | {:error, term()}
  def get_open_orders(user_id, symbol \\ nil) do
    Logger.debug("Fetching open orders", user_id: user_id, symbol: symbol)

    case CryptoExchange.API.get_open_orders(user_id, symbol) do
      {:ok, orders} = result ->
        Logger.debug("Open orders retrieved",
          user_id: user_id,
          order_count: length(orders)
        )

        result

      {:error, reason} = error ->
        Logger.error("Failed to retrieve open orders",
          user_id: user_id,
          symbol: symbol,
          reason: inspect(reason)
        )

        error
    end
  end

  @doc """
  Get order status from the exchange.

  ## Parameters
  - `user_id`: User identifier
  - `symbol`: Trading pair
  - `order_id`: Exchange order ID

  ## Returns
  - `{:ok, order_status}` - Order status details
  - `{:error, reason}` - Failed to retrieve status
  """
  @spec get_order_status(user_id(), symbol(), order_id()) :: {:ok, map()} | {:error, term()}
  def get_order_status(user_id, symbol, order_id) do
    Logger.debug("Fetching order status",
      user_id: user_id,
      symbol: symbol,
      order_id: order_id
    )

    case CryptoExchange.API.get_order_status(user_id, symbol, order_id) do
      {:ok, status} = result ->
        Logger.debug("Order status retrieved",
          user_id: user_id,
          order_id: order_id,
          status: status[:status]
        )

        result

      {:error, reason} = error ->
        Logger.error("Failed to retrieve order status",
          user_id: user_id,
          symbol: symbol,
          order_id: order_id,
          reason: inspect(reason)
        )

        error
    end
  end
end
