defmodule TradingStrategy.Orders.LiveExecutor do
  @moduledoc """
  Live order executor placing real orders via exchange adapter.

  This module handles the execution of orders on live exchanges with:
  - Order validation before submission
  - Risk management checks
  - Retry logic for transient failures
  - Audit logging
  """

  require Logger

  alias TradingStrategy.Exchanges.{Exchange, OrderAdapter, RetryHandler}
  alias TradingStrategy.Orders.OrderValidator
  alias TradingStrategy.Risk.RiskManager

  @type order_params :: %{
          user_id: String.t(),
          symbol: String.t(),
          side: :buy | :sell,
          type: :market | :limit | :stop_loss,
          quantity: Decimal.t(),
          price: Decimal.t() | nil,
          signal_type: :entry | :exit | :stop
        }

  @type execution_context :: %{
          balances: [map()],
          portfolio_state: map(),
          risk_limits: map() | nil,
          symbol_info: map() | nil
        }

  @doc """
  Execute a live order on the exchange.

  ## Parameters
  - `order_params`: Order parameters
  - `context`: Execution context with balances and portfolio state (optional)

  ## Returns
  - `{:ok, order_response}` if order executed successfully
  - `{:error, reason}` if execution failed

  ## Examples
      iex> LiveExecutor.execute_order(%{
      ...>   user_id: "user_123",
      ...>   symbol: "BTCUSDT",
      ...>   side: :buy,
      ...>   type: :market,
      ...>   quantity: Decimal.new("0.001"),
      ...>   price: nil,
      ...>   signal_type: :entry
      ...> }, context)
      {:ok, %{order_id: "12345", status: "FILLED", ...}}
  """
  @spec execute_order(order_params(), execution_context() | nil) ::
          {:ok, map()} | {:error, atom() | String.t()}
  def execute_order(order_params, context \\ nil) do
    Logger.info("Executing live order",
      user_id: order_params.user_id,
      symbol: order_params.symbol,
      side: order_params.side,
      type: order_params.type,
      quantity: Decimal.to_string(order_params.quantity),
      signal_type: order_params.signal_type
    )

    with :ok <- validate_order_params(order_params),
         :ok <- validate_order_with_context(order_params, context),
         :ok <- check_risk_limits(order_params, context),
         {:ok, response} <- place_order_with_retry(order_params) do
      Logger.info("Order executed successfully",
        user_id: order_params.user_id,
        order_id: response[:exchange_order_id],
        status: response[:status]
      )

      {:ok, response}
    else
      {:error, reason} = error ->
        Logger.error("Order execution failed",
          user_id: order_params.user_id,
          symbol: order_params.symbol,
          reason: inspect(reason)
        )

        error
    end
  end

  @doc """
  Execute multiple orders in batch.

  ## Parameters
  - `orders`: List of order parameters
  - `context`: Execution context (optional)

  ## Returns
  - `{:ok, results}` - List of {:ok, response} or {:error, reason} tuples
  """
  @spec execute_batch([order_params()], execution_context() | nil) ::
          {:ok, [{:ok, map()} | {:error, term()}]}
  def execute_batch(orders, context \\ nil) do
    Logger.info("Executing batch of orders", count: length(orders))

    results =
      Enum.map(orders, fn order ->
        execute_order(order, context)
      end)

    {:ok, results}
  end

  @doc """
  Cancel an order on the exchange.

  ## Parameters
  - `user_id`: User identifier
  - `symbol`: Trading pair
  - `order_id`: Exchange order ID to cancel

  ## Returns
  - `{:ok, cancel_response}` if cancelled successfully
  - `{:error, reason}` if cancellation failed
  """
  @spec cancel_order(String.t(), String.t(), String.t()) ::
          {:ok, map()} | {:error, term()}
  def cancel_order(user_id, symbol, order_id) do
    Logger.info("Cancelling order",
      user_id: user_id,
      symbol: symbol,
      order_id: order_id
    )

    RetryHandler.with_retry(
      fn ->
        Exchange.cancel_order(user_id, symbol, order_id)
      end,
      max_attempts: 3
    )
  end

  @doc """
  Get current status of an order.

  ## Parameters
  - `user_id`: User identifier
  - `symbol`: Trading pair
  - `order_id`: Exchange order ID

  ## Returns
  - `{:ok, order_status}` if status retrieved
  - `{:error, reason}` if retrieval failed
  """
  @spec get_order_status(String.t(), String.t(), String.t()) ::
          {:ok, map()} | {:error, term()}
  def get_order_status(user_id, symbol, order_id) do
    Logger.debug("Fetching order status",
      user_id: user_id,
      symbol: symbol,
      order_id: order_id
    )

    RetryHandler.with_retry(fn ->
      Exchange.get_order_status(user_id, symbol, order_id)
    end)
  end

  # Private Functions

  defp validate_order_params(params) do
    required_fields = [:user_id, :symbol, :side, :type, :quantity, :signal_type]

    missing =
      Enum.filter(required_fields, fn field ->
        not Map.has_key?(params, field) or is_nil(Map.get(params, field))
      end)

    if Enum.empty?(missing) do
      :ok
    else
      Logger.error("Missing required order parameters", missing: missing)
      {:error, :missing_parameters}
    end
  end

  defp validate_order_with_context(_order_params, nil), do: :ok

  defp validate_order_with_context(order_params, context) do
    # Create order structure for validator
    order = %{
      symbol: order_params.symbol,
      side: order_params.side,
      type: order_params.type,
      quantity: order_params.quantity,
      price: order_params.price
    }

    balances = context[:balances] || []
    symbol_info = context[:symbol_info]

    OrderValidator.validate_order(order, balances, symbol_info)
  end

  defp check_risk_limits(_order_params, nil), do: :ok

  defp check_risk_limits(order_params, context) do
    portfolio_state = context[:portfolio_state]
    risk_limits = context[:risk_limits]

    if portfolio_state && risk_limits do
      # Create proposed trade structure
      proposed_trade = %{
        side: order_params.side,
        quantity: order_params.quantity,
        price: order_params.price,
        symbol: order_params.symbol
      }

      case RiskManager.check_trade(proposed_trade, portfolio_state, risk_limits) do
        {:ok, :allowed} -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      :ok
    end
  end

  defp place_order_with_retry(order_params) do
    # Build internal order structure
    internal_order = %{
      trading_pair: normalize_trading_pair(order_params.symbol),
      side: order_params.side,
      type: order_params.type,
      quantity: order_params.quantity,
      price: order_params.price,
      signal_type: order_params.signal_type
    }

    # Place order with retry logic
    RetryHandler.with_retry(
      fn ->
        case OrderAdapter.place_order(order_params.user_id, internal_order) do
          {:ok, exchange_response} ->
            # Translate response to internal format
            {:ok, OrderAdapter.translate_response(exchange_response)}

          {:error, _reason} = error ->
            error
        end
      end,
      max_attempts: 3,
      base_delay: 1000
    )
  end

  defp normalize_trading_pair(symbol) do
    # Convert "BTCUSDT" to "BTC/USDT" for internal representation
    # This is a simple heuristic - in production, you might want a more robust solution
    quote_currencies = ["USDT", "BUSD", "USD", "BTC", "ETH", "BNB"]

    Enum.find_value(quote_currencies, symbol, fn quote ->
      if String.ends_with?(symbol, quote) do
        base = String.replace_suffix(symbol, quote, "")
        "#{base}/#{quote}"
      end
    end)
  end
end
