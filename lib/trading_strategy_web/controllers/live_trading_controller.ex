defmodule TradingStrategyWeb.LiveTradingController do
  use TradingStrategyWeb, :controller

  alias TradingStrategy.LiveTrading

  action_fallback TradingStrategyWeb.FallbackController

  @doc """
  Create a new live trading session.

  POST /api/live_trading/sessions

  Request body:
  ```json
  {
    "strategy_id": "uuid",
    "trading_pair": "BTC/USDT",
    "allocated_capital": "5000.00",
    "exchange": "binance",
    "mode": "testnet",
    "api_credentials": {
      "api_key": "...",
      "api_secret": "...",
      "passphrase": null
    },
    "position_sizing": "percentage",
    "risk_limits": {
      "max_position_size_pct": "0.25",
      "max_daily_loss_pct": "0.03",
      "max_drawdown_pct": "0.15",
      "max_concurrent_positions": 3
    }
  }
  ```
  """
  def create(conn, params) do
    with {:ok, config} <- build_session_config(params),
         {:ok, session_id} <- LiveTrading.start_live_session(config) do
      conn
      |> put_status(:created)
      |> json(%{
        session_id: session_id,
        status: "created",
        message: "Live trading session started successfully"
      })
    end
  end

  @doc """
  Get live trading session status.

  GET /api/live_trading/sessions/:id
  """
  def show(conn, %{"id" => session_id}) do
    with {:ok, status} <- LiveTrading.get_live_session_status(session_id) do
      json(conn, format_session_status(status))
    end
  end

  @doc """
  Stop a live trading session.

  DELETE /api/live_trading/sessions/:id
  """
  def delete(conn, %{"id" => session_id}) do
    with {:ok, final_results} <- LiveTrading.stop_live_session(session_id) do
      json(conn, %{
        message: "Live trading session stopped",
        final_results: final_results
      })
    end
  end

  @doc """
  Pause a live trading session.

  POST /api/live_trading/sessions/:id/pause
  """
  def pause(conn, %{"id" => session_id}) do
    with :ok <- LiveTrading.pause_live_session(session_id) do
      json(conn, %{
        message: "Live trading session paused",
        session_id: session_id
      })
    end
  end

  @doc """
  Resume a paused live trading session.

  POST /api/live_trading/sessions/:id/resume
  """
  def resume(conn, %{"id" => session_id}) do
    with :ok <- LiveTrading.resume_live_session(session_id) do
      json(conn, %{
        message: "Live trading session resumed",
        session_id: session_id
      })
    end
  end

  @doc """
  Execute emergency stop for a session.

  POST /api/live_trading/sessions/:id/emergency_stop
  """
  def emergency_stop(conn, %{"id" => session_id}) do
    with {:ok, result} <- LiveTrading.emergency_stop(session_id) do
      json(conn, %{
        message: "Emergency stop executed",
        session_id: session_id,
        cancelled_orders: result.cancelled_orders,
        failed_cancellations: result.failed_cancellations,
        duration_ms: result.duration_ms
      })
    end
  end

  @doc """
  Place an order in a live trading session.

  POST /api/live_trading/sessions/:id/orders

  Request body:
  ```json
  {
    "order_type": "market",
    "side": "buy",
    "quantity": "0.001",
    "price": null,
    "signal_type": "entry"
  }
  ```
  """
  def place_order(conn, %{"id" => session_id} = params) do
    with {:ok, order_params} <- parse_order_params(params),
         {:ok, order_id} <-
           LiveTrading.place_order(
             session_id,
             order_params.order_type,
             order_params.side,
             order_params.quantity,
             order_params.price,
             order_params.signal_type
           ) do
      conn
      |> put_status(:created)
      |> json(%{
        order_id: order_id,
        message: "Order placed successfully"
      })
    end
  end

  @doc """
  Get order status.

  GET /api/live_trading/sessions/:id/orders/:order_id
  """
  def get_order(conn, %{"id" => session_id, "order_id" => order_id}) do
    with {:ok, order_status} <- LiveTrading.get_order_status(session_id, order_id) do
      json(conn, format_order_status(order_status))
    end
  end

  @doc """
  Cancel an order.

  DELETE /api/live_trading/sessions/:id/orders/:order_id
  """
  def cancel_order(conn, %{"id" => session_id, "order_id" => order_id}) do
    with :ok <- LiveTrading.cancel_order(session_id, order_id) do
      json(conn, %{
        message: "Order cancelled successfully",
        order_id: order_id
      })
    end
  end

  @doc """
  List all live trading sessions.

  GET /api/live_trading/sessions
  """
  def index(conn, params) do
    opts = build_list_opts(params)

    with {:ok, sessions} <- LiveTrading.list_live_sessions(opts) do
      json(conn, %{sessions: sessions})
    end
  end

  # Private Functions

  defp build_session_config(params) do
    try do
      config = %{
        strategy_id: params["strategy_id"],
        trading_pair: params["trading_pair"],
        allocated_capital: Decimal.new(params["allocated_capital"]),
        exchange: params["exchange"],
        api_credentials: %{
          api_key: params["api_credentials"]["api_key"],
          api_secret: params["api_credentials"]["api_secret"],
          passphrase: params["api_credentials"]["passphrase"]
        },
        position_sizing: parse_position_sizing(params["position_sizing"]),
        risk_limits: parse_risk_limits(params["risk_limits"])
      }

      {:ok, config}
    rescue
      _ -> {:error, :invalid_parameters}
    end
  end

  defp parse_position_sizing(nil), do: :percentage
  defp parse_position_sizing("percentage"), do: :percentage
  defp parse_position_sizing("fixed"), do: :fixed
  defp parse_position_sizing("risk_based"), do: :risk_based
  defp parse_position_sizing("kelly"), do: :kelly
  defp parse_position_sizing(:percentage), do: :percentage
  defp parse_position_sizing(:fixed), do: :fixed
  defp parse_position_sizing(:risk_based), do: :risk_based
  defp parse_position_sizing(:kelly), do: :kelly

  defp parse_risk_limits(nil) do
    alias TradingStrategy.Risk.RiskManager
    RiskManager.default_risk_limits()
  end

  defp parse_risk_limits(limits) when is_map(limits) do
    %{
      max_position_size_pct: Decimal.new(limits["max_position_size_pct"] || "0.25"),
      max_daily_loss_pct: Decimal.new(limits["max_daily_loss_pct"] || "0.03"),
      max_drawdown_pct: Decimal.new(limits["max_drawdown_pct"] || "0.15"),
      max_concurrent_positions: limits["max_concurrent_positions"] || 3
    }
  end

  defp parse_order_params(params) do
    try do
      order_params = %{
        order_type: String.to_existing_atom(params["order_type"]),
        side: String.to_existing_atom(params["side"]),
        quantity: Decimal.new(params["quantity"]),
        price: if(params["price"], do: Decimal.new(params["price"]), else: nil),
        signal_type: String.to_existing_atom(params["signal_type"] || "entry")
      }

      {:ok, order_params}
    rescue
      _ -> {:error, :invalid_order_parameters}
    end
  end

  defp format_session_status(status) do
    %{
      session_id: status.session_id,
      status: status.status,
      started_at: DateTime.to_iso8601(status.started_at),
      exchange: status.exchange,
      current_equity: Decimal.to_string(status.current_equity),
      unrealized_pnl: Decimal.to_string(status.unrealized_pnl),
      realized_pnl: Decimal.to_string(status.realized_pnl),
      open_positions: format_positions(status.open_positions),
      pending_orders: format_orders(status.pending_orders),
      trades_count: status.trades_count,
      risk_limits_status: format_risk_status(status.risk_limits_status),
      last_updated_at: DateTime.to_iso8601(status.last_updated_at),
      connectivity_status: status.connectivity_status
    }
  end

  defp format_positions([]), do: []

  defp format_positions(positions) do
    Enum.map(positions, fn position ->
      %{
        position_id: position[:position_id],
        trading_pair: position[:trading_pair],
        side: position[:side],
        entry_price: Decimal.to_string(position[:entry_price]),
        quantity: Decimal.to_string(position[:quantity]),
        current_price: Decimal.to_string(position[:current_price]),
        unrealized_pnl: Decimal.to_string(position[:unrealized_pnl])
      }
    end)
  end

  defp format_orders([]), do: []

  defp format_orders(orders) do
    Enum.map(orders, fn order ->
      %{
        order_id: order[:order_id],
        exchange_order_id: order[:exchange_order_id],
        type: order[:type],
        side: order[:side],
        status: order[:status],
        quantity: if(order[:quantity], do: Decimal.to_string(order[:quantity]), else: nil),
        price: if(order[:price], do: Decimal.to_string(order[:price]), else: nil)
      }
    end)
  end

  defp format_risk_status(risk_status) do
    %{
      position_size_utilization_pct: Decimal.to_string(risk_status.position_size_utilization_pct),
      daily_loss_used_pct: Decimal.to_string(risk_status.daily_loss_used_pct),
      drawdown_from_peak_pct: Decimal.to_string(risk_status.drawdown_from_peak_pct),
      concurrent_positions: risk_status.concurrent_positions,
      can_open_new_position: risk_status.can_open_new_position
    }
  end

  defp format_order_status(order) do
    %{
      order_id: order.order_id,
      exchange_order_id: order.exchange_order_id,
      type: order.type,
      side: order.side,
      status: order.status,
      quantity: Decimal.to_string(order.quantity),
      filled_quantity: Decimal.to_string(order.filled_quantity),
      price: if(order.price, do: Decimal.to_string(order.price), else: nil),
      timestamp: DateTime.to_iso8601(order.timestamp),
      signal_type: order.signal_type
    }
  end

  defp build_list_opts(params) do
    []
    |> maybe_add_opt(:strategy_id, params["strategy_id"])
    |> maybe_add_opt(:status, params["status"])
    |> maybe_add_opt(:exchange, params["exchange"])
    |> maybe_add_opt(:limit, params["limit"])
  end

  defp maybe_add_opt(opts, _key, nil), do: opts
  defp maybe_add_opt(opts, key, value), do: Keyword.put(opts, key, value)
end
