defmodule TradingStrategy.LiveTrading.EmergencyStop do
  @moduledoc """
  Emergency stop mechanism canceling all orders on critical errors.

  This module provides a panic button to immediately cancel all open orders
  and halt trading when critical errors are detected. Must complete within 1 second.
  """

  require Logger

  alias TradingStrategy.Exchanges.Exchange

  @type user_id :: String.t()
  @type emergency_result :: %{
          cancelled_orders: [String.t()],
          failed_cancellations: [String.t()],
          duration_ms: non_neg_integer()
        }

  @cancellation_timeout :timer.seconds(1)

  @doc """
  Execute emergency stop for a user, cancelling all orders.

  This function must complete within 1 second as per requirements.
  Cancellation requests are sent in parallel to minimize latency.

  ## Parameters
  - `user_id`: User identifier
  - `symbol`: Trading pair (optional, nil cancels all symbols)

  ## Returns
  - `{:ok, result}` with cancellation summary
  - `{:error, reason}` if emergency stop failed

  ## Examples
      iex> EmergencyStop.execute("user_123", "BTCUSDT")
      {:ok, %{cancelled_orders: ["12345", "67890"], failed_cancellations: [], duration_ms: 234}}
  """
  @spec execute(user_id(), String.t() | nil) :: {:ok, emergency_result()} | {:error, term()}
  def execute(user_id, symbol \\ nil) do
    start_time = System.monotonic_time(:millisecond)

    Logger.error("EMERGENCY STOP TRIGGERED",
      user_id: user_id,
      symbol: symbol || "ALL"
    )

    # Get all open orders
    case get_open_orders(user_id, symbol) do
      {:ok, orders} ->
        if Enum.empty?(orders) do
          Logger.info("No open orders to cancel", user_id: user_id)

          {:ok,
           %{
             cancelled_orders: [],
             failed_cancellations: [],
             duration_ms: System.monotonic_time(:millisecond) - start_time
           }}
        else
          # Cancel all orders in parallel with timeout
          result = cancel_orders_parallel(user_id, orders, @cancellation_timeout)

          duration_ms = System.monotonic_time(:millisecond) - start_time

          Logger.error("Emergency stop completed",
            user_id: user_id,
            total_orders: length(orders),
            cancelled: length(result.cancelled_orders),
            failed: length(result.failed_cancellations),
            duration_ms: duration_ms
          )

          {:ok, Map.put(result, :duration_ms, duration_ms)}
        end

      {:error, reason} = error ->
        Logger.error("Failed to get open orders during emergency stop",
          user_id: user_id,
          reason: inspect(reason)
        )

        error
    end
  end

  @doc """
  Check if user has any open orders.

  ## Parameters
  - `user_id`: User identifier

  ## Returns
  - `true` if user has open orders
  - `false` if no open orders
  """
  @spec has_open_orders?(user_id()) :: boolean()
  def has_open_orders?(user_id) do
    case get_open_orders(user_id, nil) do
      {:ok, orders} -> not Enum.empty?(orders)
      {:error, _} -> false
    end
  end

  # Private Functions

  defp get_open_orders(user_id, symbol) do
    Exchange.get_open_orders(user_id, symbol)
  end

  defp cancel_orders_parallel(user_id, orders, timeout) do
    # Create tasks for each cancellation
    tasks =
      Enum.map(orders, fn order ->
        Task.async(fn ->
          cancel_single_order(user_id, order)
        end)
      end)

    # Wait for all tasks with timeout
    results = Task.yield_many(tasks, timeout)

    # Separate successful and failed cancellations
    Enum.reduce(results, %{cancelled_orders: [], failed_cancellations: []}, fn
      {task, {:ok, {:ok, order_id}}}, acc ->
        %{acc | cancelled_orders: [order_id | acc.cancelled_orders]}

      {task, {:ok, {:error, order_id}}}, acc ->
        %{acc | failed_cancellations: [order_id | acc.failed_cancellations]}

      {task, nil}, acc ->
        # Task timed out
        Task.shutdown(task, :brutal_kill)
        order_id = extract_order_id_from_task(task)
        %{acc | failed_cancellations: [order_id | acc.failed_cancellations]}
    end)
  end

  defp cancel_single_order(user_id, order) do
    symbol = order[:symbol] || order["symbol"]
    order_id = order[:order_id] || order["orderId"]

    Logger.debug("Cancelling order",
      user_id: user_id,
      symbol: symbol,
      order_id: order_id
    )

    case Exchange.cancel_order(user_id, symbol, order_id) do
      {:ok, _response} ->
        {:ok, order_id}

      {:error, reason} ->
        Logger.warning("Failed to cancel order",
          user_id: user_id,
          order_id: order_id,
          reason: inspect(reason)
        )

        {:error, order_id}
    end
  end

  defp extract_order_id_from_task(_task) do
    # In a timeout scenario, we don't have the order_id easily accessible
    # This is a placeholder - in production, you might structure this differently
    "unknown"
  end
end
