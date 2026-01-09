defmodule TradingStrategy.Orders.OrderTracker do
  @moduledoc """
  Order status tracker monitoring fills and partial fills.

  This GenServer tracks the status of orders placed on exchanges,
  polling for updates and notifying subscribers of status changes.
  """

  use GenServer
  require Logger

  alias TradingStrategy.Exchanges.Exchange

  @type order_id :: String.t()
  @type user_id :: String.t()
  @type order_status :: :pending | :open | :filled | :partially_filled | :cancelled | :rejected

  @type tracked_order :: %{
          internal_order_id: String.t(),
          exchange_order_id: String.t(),
          user_id: user_id(),
          symbol: String.t(),
          side: :buy | :sell,
          type: :market | :limit | :stop_loss,
          quantity: Decimal.t(),
          filled_quantity: Decimal.t(),
          price: Decimal.t() | nil,
          status: order_status(),
          signal_type: :entry | :exit | :stop,
          created_at: DateTime.t(),
          updated_at: DateTime.t(),
          subscribers: [pid()]
        }

  # Poll every 5 seconds
  @poll_interval :timer.seconds(5)

  # Client API

  @doc """
  Start the order tracker.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, opts ++ [name: __MODULE__])
  end

  @doc """
  Track a new order.

  ## Parameters
  - `order`: Order details to track
  - `subscriber`: Optional PID to notify of status changes

  ## Returns
  - `{:ok, internal_order_id}` - Unique ID for tracking this order

  ## Examples
      iex> OrderTracker.track_order(%{
      ...>   exchange_order_id: "12345",
      ...>   user_id: "user_123",
      ...>   symbol: "BTCUSDT",
      ...>   side: :buy,
      ...>   type: :market,
      ...>   quantity: Decimal.new("0.001"),
      ...>   price: nil,
      ...>   signal_type: :entry
      ...> }, self())
      {:ok, "order_abc123"}
  """
  @spec track_order(map(), pid() | nil) :: {:ok, String.t()}
  def track_order(order, subscriber \\ nil) do
    GenServer.call(__MODULE__, {:track_order, order, subscriber})
  end

  @doc """
  Stop tracking an order.

  ## Parameters
  - `internal_order_id`: Internal order ID

  ## Examples
      iex> OrderTracker.untrack_order("order_abc123")
      :ok
  """
  @spec untrack_order(String.t()) :: :ok
  def untrack_order(internal_order_id) do
    GenServer.call(__MODULE__, {:untrack_order, internal_order_id})
  end

  @doc """
  Get current status of a tracked order.

  ## Parameters
  - `internal_order_id`: Internal order ID

  ## Returns
  - `{:ok, order_status}` if order found
  - `{:error, :not_found}` if order not being tracked

  ## Examples
      iex> OrderTracker.get_status("order_abc123")
      {:ok, %{status: :filled, filled_quantity: Decimal.new("0.001"), ...}}
  """
  @spec get_status(String.t()) :: {:ok, tracked_order()} | {:error, :not_found}
  def get_status(internal_order_id) do
    GenServer.call(__MODULE__, {:get_status, internal_order_id})
  end

  @doc """
  Get all tracked orders for a user.

  ## Parameters
  - `user_id`: User identifier

  ## Returns
  - List of tracked orders for the user
  """
  @spec get_user_orders(user_id()) :: [tracked_order()]
  def get_user_orders(user_id) do
    GenServer.call(__MODULE__, {:get_user_orders, user_id})
  end

  @doc """
  Subscribe to order status updates.

  ## Parameters
  - `internal_order_id`: Internal order ID to subscribe to
  - `subscriber`: PID to receive updates (defaults to caller)

  ## Returns
  - `:ok` if subscribed
  - `{:error, :not_found}` if order not being tracked
  """
  @spec subscribe(String.t(), pid()) :: :ok | {:error, :not_found}
  def subscribe(internal_order_id, subscriber \\ nil) do
    pid = subscriber || self()
    GenServer.call(__MODULE__, {:subscribe, internal_order_id, pid})
  end

  @doc """
  Force an immediate poll for order status.

  ## Parameters
  - `internal_order_id`: Internal order ID to poll

  ## Returns
  - `{:ok, updated_status}` if poll successful
  - `{:error, reason}` if poll failed
  """
  @spec poll_now(String.t()) :: {:ok, tracked_order()} | {:error, term()}
  def poll_now(internal_order_id) do
    GenServer.call(__MODULE__, {:poll_now, internal_order_id})
  end

  # Server Callbacks

  @impl true
  def init(:ok) do
    Logger.info("Starting Order Tracker")

    # Schedule periodic polling
    schedule_poll()

    {:ok, %{orders: %{}}}
  end

  @impl true
  def handle_call({:track_order, order, subscriber}, _from, state) do
    internal_order_id = generate_order_id()

    tracked_order = %{
      internal_order_id: internal_order_id,
      exchange_order_id: order[:exchange_order_id] || order["orderId"],
      user_id: order[:user_id],
      symbol: order[:symbol],
      side: order[:side],
      type: order[:type],
      quantity: order[:quantity],
      filled_quantity: order[:filled_quantity] || Decimal.new("0"),
      price: order[:price],
      status: parse_status(order[:status] || :pending),
      signal_type: order[:signal_type],
      created_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now(),
      subscribers: if(subscriber, do: [subscriber], else: [])
    }

    Logger.info("Tracking new order",
      internal_order_id: internal_order_id,
      exchange_order_id: tracked_order.exchange_order_id,
      user_id: tracked_order.user_id,
      symbol: tracked_order.symbol
    )

    new_state = put_in(state, [:orders, internal_order_id], tracked_order)

    {:reply, {:ok, internal_order_id}, new_state}
  end

  @impl true
  def handle_call({:untrack_order, internal_order_id}, _from, state) do
    Logger.info("Untracking order", internal_order_id: internal_order_id)

    {_value, new_orders} = Map.pop(state.orders, internal_order_id)
    new_state = %{state | orders: new_orders}

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:get_status, internal_order_id}, _from, state) do
    case Map.get(state.orders, internal_order_id) do
      nil -> {:reply, {:error, :not_found}, state}
      order -> {:reply, {:ok, order}, state}
    end
  end

  @impl true
  def handle_call({:get_user_orders, user_id}, _from, state) do
    orders =
      state.orders
      |> Map.values()
      |> Enum.filter(fn order -> order.user_id == user_id end)

    {:reply, orders, state}
  end

  @impl true
  def handle_call({:subscribe, internal_order_id, subscriber}, _from, state) do
    case Map.get(state.orders, internal_order_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      order ->
        updated_order = %{order | subscribers: [subscriber | order.subscribers] |> Enum.uniq()}
        new_state = put_in(state, [:orders, internal_order_id], updated_order)

        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call({:poll_now, internal_order_id}, _from, state) do
    case Map.get(state.orders, internal_order_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      order ->
        case poll_order_status(order) do
          {:ok, updated_order} ->
            new_state = put_in(state, [:orders, internal_order_id], updated_order)
            {:reply, {:ok, updated_order}, new_state}

          {:error, reason} = error ->
            {:reply, error, state}
        end
    end
  end

  @impl true
  def handle_info(:poll_orders, state) do
    # Poll all active orders
    new_orders =
      Map.new(state.orders, fn {id, order} ->
        if order_active?(order) do
          case poll_order_status(order) do
            {:ok, updated_order} -> {id, updated_order}
            {:error, _reason} -> {id, order}
          end
        else
          {id, order}
        end
      end)

    new_state = %{state | orders: new_orders}

    # Schedule next poll
    schedule_poll()

    {:noreply, new_state}
  end

  # Private Functions

  defp generate_order_id do
    "order_" <> (:crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower))
  end

  defp parse_status(:pending), do: :pending
  defp parse_status(:open), do: :open
  defp parse_status(:filled), do: :filled
  defp parse_status(:partially_filled), do: :partially_filled
  defp parse_status(:cancelled), do: :cancelled
  defp parse_status(:rejected), do: :rejected
  defp parse_status("NEW"), do: :open
  defp parse_status("PARTIALLY_FILLED"), do: :partially_filled
  defp parse_status("FILLED"), do: :filled
  defp parse_status("CANCELED"), do: :cancelled
  defp parse_status("REJECTED"), do: :rejected
  defp parse_status(_), do: :pending

  defp order_active?(order) do
    order.status in [:pending, :open, :partially_filled]
  end

  defp poll_order_status(order) do
    Logger.debug("Polling order status",
      internal_order_id: order.internal_order_id,
      exchange_order_id: order.exchange_order_id
    )

    case Exchange.get_order_status(order.user_id, order.symbol, order.exchange_order_id) do
      {:ok, status_response} ->
        old_status = order.status
        new_status = parse_status(status_response[:status] || status_response["status"])

        new_filled_qty =
          status_response[:filled_quantity] || status_response["executedQty"] ||
            order.filled_quantity

        updated_order = %{
          order
          | status: new_status,
            filled_quantity: new_filled_qty,
            updated_at: DateTime.utc_now()
        }

        # Notify subscribers if status changed
        if old_status != new_status do
          Logger.info("Order status changed",
            internal_order_id: order.internal_order_id,
            old_status: old_status,
            new_status: new_status
          )

          notify_subscribers(updated_order, old_status, new_status)
        end

        {:ok, updated_order}

      {:error, reason} ->
        Logger.warning("Failed to poll order status",
          internal_order_id: order.internal_order_id,
          reason: inspect(reason)
        )

        {:error, reason}
    end
  end

  defp notify_subscribers(order, old_status, new_status) do
    Enum.each(order.subscribers, fn pid ->
      send(pid, {:order_status_changed, order.internal_order_id, old_status, new_status, order})
    end)
  end

  defp schedule_poll do
    Process.send_after(self(), :poll_orders, @poll_interval)
  end
end
