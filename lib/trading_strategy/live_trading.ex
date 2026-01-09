defmodule TradingStrategy.LiveTrading do
  @moduledoc """
  Live trading context module providing public API for live trading operations.

  This is the main entry point for live trading functionality, implementing
  the contract defined in contracts/live_trading_api.ex.

  WARNING: This module places REAL ORDERS on cryptocurrency exchanges.
  Use with extreme caution and only with funds you can afford to lose.
  """

  require Logger

  alias TradingStrategy.LiveTrading.SessionManager
  alias TradingStrategy.Orders.{LiveExecutor, OrderTracker}

  @behaviour TradingStrategy.Contracts.LiveTradingAPI

  @type session_id :: String.t()
  @type strategy_id :: String.t()
  @type order_id :: String.t()

  @doc """
  Start a new live trading session.

  Implements FR-017 (connect to exchange) and FR-018 (authenticate with credentials).

  ## Examples
      iex> LiveTrading.start_live_session(%{
      ...>   strategy_id: "550e8400-...",
      ...>   trading_pair: "BTC/USDT",
      ...>   allocated_capital: Decimal.new("5000"),
      ...>   exchange: "binance",
      ...>   api_credentials: %{api_key: "...", api_secret: "...", passphrase: nil},
      ...>   position_sizing: :percentage,
      ...>   risk_limits: %{max_position_size_pct: Decimal.new("0.25"), ...}
      ...> })
      {:ok, "live_session_abc123"}
  """
  @impl true
  def start_live_session(config) do
    # Generate unique session ID
    session_id = generate_session_id()

    # Normalize trading pair format (BTC/USDT -> BTCUSDT for exchanges)
    trading_pair = normalize_trading_pair(config.trading_pair)

    # Build session configuration
    session_config = [
      session_id: session_id,
      strategy_id: config.strategy_id,
      trading_pair: trading_pair,
      allocated_capital: config.allocated_capital,
      exchange: config.exchange,
      api_credentials: config.api_credentials,
      position_sizing: config[:position_sizing] || :percentage,
      risk_limits: config[:risk_limits] || default_risk_limits()
    ]

    # Start session under supervisor
    case DynamicSupervisor.start_child(
           TradingStrategy.LiveTrading.SessionSupervisor,
           {SessionManager, session_config}
         ) do
      {:ok, _pid} ->
        Logger.info("Live trading session started", session_id: session_id)
        {:ok, session_id}

      {:error, :strategy_not_found} ->
        {:error, :strategy_not_found}

      {:error, :exchange_connection_failed} ->
        {:error, :exchange_unavailable}

      {:error, reason} ->
        Logger.error("Failed to start live trading session", reason: inspect(reason))
        {:error, :exchange_unavailable}
    end
  end

  @impl true
  def get_live_session_status(session_id) do
    case SessionManager.get_status(session_id) do
      {:ok, status} -> {:ok, status}
      {:error, :not_found} -> {:error, :not_found}
    end
  end

  @impl true
  def place_order(session_id, order_type, side, quantity, price, signal_type) do
    order_params = %{
      type: order_type,
      side: side,
      quantity: quantity,
      price: price,
      signal_type: signal_type,
      # Get from session state
      symbol: get_session_symbol(session_id)
    }

    case SessionManager.place_order(session_id, order_params) do
      {:ok, order_id} -> {:ok, order_id}
      {:error, :session_not_active} -> {:error, :session_not_found}
      {:error, :max_position_size_exceeded} -> {:error, :risk_limits_exceeded}
      {:error, :daily_loss_limit_hit} -> {:error, :risk_limits_exceeded}
      {:error, :max_drawdown_exceeded} -> {:error, :risk_limits_exceeded}
      {:error, :max_concurrent_positions} -> {:error, :risk_limits_exceeded}
      {:error, :insufficient_balance} -> {:error, :insufficient_balance}
      {:error, :rate_limited} -> {:error, :rate_limited}
      {:error, _reason} -> {:error, :exchange_error}
    end
  end

  @impl true
  def cancel_order(session_id, order_id) do
    # Get order details from tracker
    case OrderTracker.get_status(order_id) do
      {:ok, order} ->
        case LiveExecutor.cancel_order(order.user_id, order.symbol, order.exchange_order_id) do
          {:ok, _response} -> :ok
          {:error, :already_filled} -> {:error, :already_filled}
          {:error, _reason} -> {:error, :exchange_error}
        end

      {:error, :not_found} ->
        {:error, :order_not_found}
    end
  end

  @impl true
  def get_order_status(session_id, order_id) do
    case OrderTracker.get_status(order_id) do
      {:ok, order} ->
        status = %{
          order_id: order.internal_order_id,
          exchange_order_id: order.exchange_order_id,
          type: order.type,
          side: order.side,
          status: order.status,
          quantity: order.quantity,
          filled_quantity: order.filled_quantity,
          price: order.price,
          timestamp: order.created_at,
          signal_type: order.signal_type
        }

        {:ok, status}

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  @impl true
  def monitor_and_exit_positions(session_id) do
    # This is called automatically by the session manager
    # Return empty list for now (positions are monitored internally)
    {:ok, []}
  end

  @impl true
  def pause_live_session(session_id) do
    case SessionManager.pause(session_id) do
      :ok -> :ok
      {:error, :not_found} -> {:error, :not_found}
      {:error, :not_active} -> {:error, :already_paused}
    end
  end

  @impl true
  def resume_live_session(session_id) do
    case SessionManager.resume(session_id) do
      :ok -> :ok
      {:error, :not_found} -> {:error, :not_found}
      {:error, :not_paused} -> {:error, :not_paused}
      {:error, :exchange_unavailable} -> {:error, :exchange_unavailable}
    end
  end

  @impl true
  def stop_live_session(session_id) do
    case SessionManager.stop(session_id) do
      {:ok, final_results} -> {:ok, final_results}
      {:error, :not_found} -> {:error, :not_found}
    end
  end

  @impl true
  def handle_connectivity_failure(session_id, failure_reason) do
    Logger.error("CONNECTIVITY FAILURE",
      session_id: session_id,
      reason: failure_reason
    )

    # Pause trading
    pause_live_session(session_id)

    # Attempt reconnection (handled by ReconnectionHandler)
    # The session will automatically resume when connectivity is restored

    :ok
  end

  @impl true
  def check_risk_limits(session_id, proposed_trade) do
    case SessionManager.get_status(session_id) do
      {:ok, status} ->
        # Build portfolio state from status
        portfolio_state = %{
          current_equity: status.current_equity,
          # TODO: Track actual peak
          peak_equity: status.current_equity,
          # TODO: Track daily starting
          daily_starting_equity: status.current_equity,
          open_positions: status.open_positions,
          # TODO: Track daily P&L
          realized_pnl_today: Decimal.new("0")
        }

        # Get risk limits from session
        # TODO: Get actual limits
        risk_limits = status.risk_limits_status

        # Check risk
        alias TradingStrategy.Risk.RiskManager
        RiskManager.check_trade(proposed_trade, portfolio_state, nil)

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  @impl true
  def get_live_session_trades(session_id, opts \\ []) do
    # TODO: Implement trade history retrieval
    # For now, return empty list
    {:ok, []}
  end

  @impl true
  def list_live_sessions(opts \\ []) do
    # TODO: Implement session listing
    # This would require tracking all active sessions
    {:ok, []}
  end

  # Public helper functions

  @doc """
  Execute emergency stop for a session.

  Cancels all orders within 1 second as per requirements.
  """
  def emergency_stop(session_id) do
    case SessionManager.emergency_stop(session_id) do
      {:ok, result} -> {:ok, result}
      {:error, :not_found} -> {:error, :not_found}
    end
  end

  # Private Functions

  defp generate_session_id do
    "live_session_" <> (:crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower))
  end

  defp normalize_trading_pair(trading_pair) do
    # Convert "BTC/USDT" to "BTCUSDT" for exchange APIs
    String.replace(trading_pair, "/", "")
  end

  defp default_risk_limits do
    alias TradingStrategy.Risk.RiskManager
    RiskManager.default_risk_limits()
  end

  defp get_session_symbol(session_id) do
    # Get trading pair from session
    case SessionManager.get_status(session_id) do
      {:ok, status} ->
        # TODO: Extract symbol from status
        # Placeholder
        "BTCUSDT"

      {:error, _} ->
        # Placeholder
        "BTCUSDT"
    end
  end
end
