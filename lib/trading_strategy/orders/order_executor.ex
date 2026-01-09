defmodule TradingStrategy.Orders.OrderExecutor do
  @moduledoc """
  Behaviour for executing orders on exchanges.

  This behaviour defines the contract for order execution engines that
  place and manage orders on cryptocurrency exchanges.
  """

  @doc """
  Places an order on the exchange.

  ## Parameters
    - order_params: map() - Order parameters (symbol, side, quantity, price, etc.)
    - config: map() - Exchange configuration (API keys, exchange name, etc.)

  ## Returns
    - {:ok, trade} - The executed trade
    - {:error, reason} - If order placement fails
  """
  @callback place_order(order_params :: map(), config :: map()) ::
              {:ok, struct()} | {:error, term()}

  @doc """
  Cancels an existing order on the exchange.

  ## Parameters
    - order_id: String.t() - The order ID to cancel

  ## Returns
    - {:ok, cancelled_order} - The cancelled order
    - {:error, reason} - If order cancellation fails
  """
  @callback cancel_order(order_id :: String.t()) ::
              {:ok, map()} | {:error, term()}
end
