defmodule TradingStrategyWeb.TradingChannel do
  @moduledoc """
  Phoenix Channel for real-time paper trading updates.

  Clients can join "trading:SESSION_ID" topics to receive live updates about:
  - Position changes
  - New trade executions
  - P&L updates (realized and unrealized)
  - Session status changes (active, paused, stopped)
  - Market price updates

  ## Usage

  Client-side JavaScript example:
  ```javascript
  let socket = new Socket("/socket", {params: {token: window.userToken}})
  socket.connect()

  let channel = socket.channel("trading:paper_abc123", {})
  channel.join()
    .receive("ok", resp => { console.log("Joined successfully", resp) })
    .receive("error", resp => { console.log("Unable to join", resp) })

  channel.on("position_update", payload => {
    console.log("Position updated:", payload)
  })

  channel.on("new_trade", payload => {
    console.log("New trade:", payload)
  })

  channel.on("pnl_update", payload => {
    console.log("P&L updated:", payload)
  })

  channel.on("status_change", payload => {
    console.log("Status changed:", payload)
  })
  ```

  ## Events Broadcast

  - `position_update`: When a position is opened, modified, or closed
  - `new_trade`: When a trade is executed
  - `pnl_update`: When P&L values change
  - `status_change`: When session status changes
  - `market_update`: Periodic market price updates
  """

  use TradingStrategyWeb, :channel

  require Logger

  alias TradingStrategy.PaperTrading

  @doc """
  Authorizes socket to join the trading channel.

  Only allows joining if:
  1. Session ID is valid
  2. Session exists (active, paused, or stopped)

  Topic format: "trading:SESSION_ID"
  """
  def join("trading:" <> session_id, _payload, socket) do
    case PaperTrading.get_paper_session_status(session_id) do
      {:ok, session_status} ->
        # Subscribe to PubSub for this session
        Phoenix.PubSub.subscribe(
          TradingStrategy.PubSub,
          "paper_trading:#{session_id}"
        )

        Logger.info("[TradingChannel] Client joined trading:#{session_id}")

        # Send initial session state
        {:ok, %{session: format_session_status(session_status)},
         assign(socket, :session_id, session_id)}

      {:error, :not_found} ->
        Logger.warning("[TradingChannel] Attempted to join non-existent session: #{session_id}")
        {:error, %{reason: "session_not_found"}}
    end
  end

  def join(topic, _payload, _socket) do
    Logger.warning("[TradingChannel] Invalid topic format: #{topic}")
    {:error, %{reason: "invalid_topic"}}
  end

  @doc """
  Handles client ping to check if channel is still alive.
  """
  def handle_in("ping", _payload, socket) do
    {:reply, {:ok, %{status: "pong"}}, socket}
  end

  @doc """
  Handles request for current session status.
  """
  def handle_in("get_status", _payload, socket) do
    session_id = socket.assigns.session_id

    case PaperTrading.get_paper_session_status(session_id) do
      {:ok, session_status} ->
        {:reply, {:ok, format_session_status(session_status)}, socket}

      {:error, :not_found} ->
        {:reply, {:error, %{reason: "session_not_found"}}, socket}
    end
  end

  @doc """
  Handles request for recent trades.
  """
  def handle_in("get_trades", %{"limit" => limit}, socket) do
    session_id = socket.assigns.session_id

    case PaperTrading.get_paper_session_trades(session_id, limit: limit) do
      {:ok, trades} ->
        {:reply, {:ok, %{trades: format_trades(trades)}}, socket}

      {:error, :not_found} ->
        {:reply, {:error, %{reason: "session_not_found"}}, socket}
    end
  end

  def handle_in("get_trades", _payload, socket) do
    handle_in("get_trades", %{"limit" => 20}, socket)
  end

  @doc """
  Handles unknown messages gracefully.
  """
  def handle_in(event, _payload, socket) do
    Logger.warning("[TradingChannel] Unknown event: #{event}")
    {:reply, {:error, %{reason: "unknown_event"}}, socket}
  end

  # PubSub message handlers - these broadcast to all clients in the channel

  @doc """
  Handles position update events from PubSub.
  """
  def handle_info({:position_update, position}, socket) do
    push(socket, "position_update", %{
      position: format_position(position),
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    })

    {:noreply, socket}
  end

  @doc """
  Handles new trade events from PubSub.
  """
  def handle_info({:new_trade, trade}, socket) do
    push(socket, "new_trade", %{
      trade: format_trade(trade),
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    })

    {:noreply, socket}
  end

  @doc """
  Handles P&L update events from PubSub.
  """
  def handle_info({:pnl_update, pnl_data}, socket) do
    push(socket, "pnl_update", %{
      unrealized_pnl: format_decimal(pnl_data.unrealized_pnl),
      realized_pnl: format_decimal(pnl_data.realized_pnl),
      current_equity: format_decimal(pnl_data.current_equity),
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    })

    {:noreply, socket}
  end

  @doc """
  Handles status change events from PubSub.
  """
  def handle_info({:status_change, new_status}, socket) do
    push(socket, "status_change", %{
      status: new_status,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    })

    {:noreply, socket}
  end

  @doc """
  Handles market price update events from PubSub.
  """
  def handle_info({:market_update, market_data}, socket) do
    push(socket, "market_update", %{
      price: format_decimal(market_data.price),
      timestamp: market_data.timestamp |> DateTime.to_iso8601()
    })

    {:noreply, socket}
  end

  @doc """
  Handles session stopped events from PubSub.
  """
  def handle_info({:session_stopped, results}, socket) do
    push(socket, "session_stopped", %{
      final_equity: format_decimal(results.final_equity),
      total_return: format_decimal(results.total_return),
      trades_count: length(results.trades || []),
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    })

    {:noreply, socket}
  end

  @doc """
  Catches any other PubSub messages and logs them.
  """
  def handle_info(msg, socket) do
    Logger.debug("[TradingChannel] Unhandled message: #{inspect(msg)}")
    {:noreply, socket}
  end

  # Private formatting helpers

  defp format_session_status(status) do
    %{
      session_id: status.session_id,
      status: status.status,
      started_at: format_datetime(status.started_at),
      current_equity: format_decimal(status.current_equity),
      unrealized_pnl: format_decimal(status.unrealized_pnl),
      realized_pnl: format_decimal(status.realized_pnl),
      open_positions: Enum.map(status.open_positions, &format_position/1),
      trades_count: status.trades_count,
      last_market_price: format_decimal(status.last_market_price),
      last_updated_at: format_datetime(status.last_updated_at)
    }
  end

  defp format_position(position) when is_map(position) do
    %{
      trading_pair: position[:trading_pair] || position["trading_pair"],
      side: position[:side] || position["side"],
      entry_price: format_decimal(position[:entry_price] || position["entry_price"]),
      quantity: format_decimal(position[:quantity] || position["quantity"]),
      current_price: format_decimal(position[:current_price] || position["current_price"]),
      unrealized_pnl: format_decimal(position[:unrealized_pnl] || position["unrealized_pnl"]),
      duration_seconds: position[:duration_seconds] || position["duration_seconds"]
    }
  end

  defp format_trades(trades) when is_list(trades) do
    Enum.map(trades, &format_trade/1)
  end

  defp format_trade(trade) when is_map(trade) do
    %{
      trade_id: trade[:trade_id] || trade["trade_id"],
      timestamp: format_datetime(trade[:timestamp] || trade["timestamp"]),
      trading_pair: trade[:trading_pair] || trade["trading_pair"],
      side: trade[:side] || trade["side"],
      quantity: format_decimal(trade[:quantity] || trade["quantity"]),
      price: format_decimal(trade[:price] || trade["price"]),
      signal_type: trade[:signal_type] || trade["signal_type"],
      pnl: format_decimal(trade[:pnl] || trade["pnl"])
    }
  end

  defp format_decimal(nil), do: nil
  defp format_decimal(%Decimal{} = decimal), do: Decimal.to_string(decimal)
  defp format_decimal(value) when is_number(value), do: to_string(value)
  defp format_decimal(value), do: value

  defp format_datetime(nil), do: nil
  defp format_datetime(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp format_datetime(value), do: value
end
