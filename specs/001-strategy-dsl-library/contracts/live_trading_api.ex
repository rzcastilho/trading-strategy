# Live Trading API Contract
#
# This module defines the Elixir behaviour contract for live trading operations.
# Covers FR-017 through FR-023 (Live Trading requirements)

defmodule TradingStrategy.Contracts.LiveTradingAPI do
  @moduledoc """
  Contract for automated live trading with real capital.

  WARNING: Live trading places REAL ORDERS on cryptocurrency exchanges.
  All functions in this module execute actual trades that can result in
  financial gain or loss. Use with extreme caution.

  Implements real-time order placement (FR-017, FR-019), position monitoring
  (FR-020), risk management (FR-021), connectivity handling (FR-022),
  and rate limiting (FR-023).
  """

  alias TradingStrategy.Contracts.StrategyAPI

  @type session_id :: String.t()
  @type strategy_id :: StrategyAPI.strategy_id()
  @type order_id :: String.t()

  @type live_session_config :: %{
    strategy_id: strategy_id(),
    trading_pair: String.t(),
    allocated_capital: Decimal.t(),
    exchange: String.t(),  # "binance", "coinbase", "kraken"
    api_credentials: api_credentials(),  # Runtime-provided, not persisted
    position_sizing: atom(),
    risk_limits: risk_limits()
  }

  @type api_credentials :: %{
    api_key: String.t(),
    api_secret: String.t(),
    passphrase: String.t() | nil  # Required for some exchanges (Coinbase)
  }

  @type risk_limits :: %{
    max_position_size_pct: Decimal.t(),  # % of portfolio
    max_daily_loss_pct: Decimal.t(),
    max_drawdown_pct: Decimal.t(),
    max_concurrent_positions: integer()
  }

  @type live_session_status :: %{
    session_id: session_id(),
    status: :active | :paused | :stopped | :error,
    started_at: DateTime.t(),
    exchange: String.t(),
    current_equity: Decimal.t(),
    unrealized_pnl: Decimal.t(),
    realized_pnl: Decimal.t(),
    open_positions: [live_position()],
    pending_orders: [order_status()],
    trades_count: integer(),
    risk_limits_status: risk_limits_status(),
    last_updated_at: DateTime.t(),
    connectivity_status: :connected | :disconnected | :degraded
  }

  @type live_position :: %{
    position_id: String.t(),
    trading_pair: String.t(),
    side: :long | :short,
    entry_price: Decimal.t(),
    quantity: Decimal.t(),
    current_price: Decimal.t(),
    unrealized_pnl: Decimal.t(),
    stop_loss_order_id: String.t() | nil,
    take_profit_order_id: String.t() | nil
  }

  @type order_status :: %{
    order_id: String.t(),
    exchange_order_id: String.t(),
    type: :market | :limit | :stop_loss | :take_profit,
    side: :buy | :sell,
    status: :pending | :open | :filled | :partially_filled | :cancelled | :rejected,
    quantity: Decimal.t(),
    filled_quantity: Decimal.t(),
    price: Decimal.t() | nil,  # nil for market orders
    timestamp: DateTime.t(),
    signal_type: :entry | :exit | :stop
  }

  @type risk_limits_status :: %{
    position_size_utilization_pct: Decimal.t(),
    daily_loss_used_pct: Decimal.t(),
    drawdown_from_peak_pct: Decimal.t(),
    concurrent_positions: integer(),
    can_open_new_position: boolean()
  }

  @doc """
  Starts a new live trading session with real exchange API credentials.

  Implements FR-017 (connect to exchange) and FR-018 (authenticate with credentials).

  ## Parameters
  - `config`: Live session configuration with API credentials

  ## Returns
  - `{:ok, session_id}` if successfully connected and authenticated
  - `{:error, :strategy_not_found}` if strategy_id invalid
  - `{:error, :authentication_failed}` if API credentials rejected
  - `{:error, :exchange_unavailable}` if cannot connect to exchange
  - `{:error, :insufficient_funds}` if account balance < allocated_capital

  ## Security Notes (FR-018)
  - API credentials provided at runtime, NEVER persisted to database
  - Credentials stored in GenServer state only (memory-only)
  - Session termination clears credentials from memory

  ## Examples
      iex> start_live_session(%{
        strategy_id: "550e8400-...",
        trading_pair: "BTC/USD",
        allocated_capital: Decimal.new("5000"),
        exchange: "binance",
        api_credentials: %{
          api_key: "...",
          api_secret: "...",
          passphrase: nil
        },
        position_sizing: :percentage,
        risk_limits: %{
          max_position_size_pct: Decimal.new("0.25"),
          max_daily_loss_pct: Decimal.new("0.03"),
          max_drawdown_pct: Decimal.new("0.15"),
          max_concurrent_positions: 3
        }
      })
      {:ok, "live_session_abc123"}
  """
  @callback start_live_session(config :: live_session_config()) ::
    {:ok, session_id()} |
    {:error, :strategy_not_found | :authentication_failed | :exchange_unavailable | :insufficient_funds}

  @doc """
  Retrieves current status of a live trading session.

  ## Parameters
  - `session_id`: UUID of the live session

  ## Returns
  - `{:ok, status}` with real-time session state
  - `{:error, :not_found}` if session doesn't exist

  ## Notes
  - Includes connectivity status (FR-022)
  - Shows risk limits utilization (FR-021)
  - Lists pending orders and open positions (FR-020)
  """
  @callback get_live_session_status(session_id :: session_id()) ::
    {:ok, live_session_status()} | {:error, :not_found}

  @doc """
  Places a market or limit order on the exchange.

  Implements FR-019 (place orders based on signal type and configuration).

  ## Parameters
  - `session_id`: UUID of the live session
  - `order_type`: `:market` or `:limit`
  - `side`: `:buy` or `:sell`
  - `quantity`: Amount to trade (in base currency)
  - `price`: Limit price (required if order_type = :limit, nil for market)
  - `signal_type`: `:entry`, `:exit`, or `:stop`

  ## Returns
  - `{:ok, order_id}` with internal order ID
  - `{:error, :session_not_found}` if session doesn't exist
  - `{:error, :risk_limits_exceeded}` if order would violate risk limits (FR-021)
  - `{:error, :insufficient_balance}` if account lacks funds
  - `{:error, :rate_limited}` if exchange API rate limit hit (FR-023)
  - `{:error, :exchange_error}` with error details from exchange

  ## Rate Limiting (FR-023)
  - Requests queued when rate limit approached
  - Exponential backoff retry (1s, 2s, 4s, 8s)
  - Stop-loss orders prioritized in queue

  ## Examples
      iex> place_order("live_session_abc123", :market, :buy, Decimal.new("0.1"), nil, :entry)
      {:ok, "order_123"}

      iex> place_order("live_session_abc123", :limit, :sell, Decimal.new("0.1"), Decimal.new("44000"), :exit)
      {:ok, "order_124"}
  """
  @callback place_order(
    session_id :: session_id(),
    order_type :: :market | :limit,
    side :: :buy | :sell,
    quantity :: Decimal.t(),
    price :: Decimal.t() | nil,
    signal_type :: :entry | :exit | :stop
  ) :: {:ok, order_id()} |
       {:error, :session_not_found | :risk_limits_exceeded | :insufficient_balance |
                :rate_limited | :exchange_error}

  @doc """
  Cancels an open or pending order.

  ## Parameters
  - `session_id`: UUID of the live session
  - `order_id`: Internal order ID returned by place_order

  ## Returns
  - `:ok` if successfully cancelled
  - `{:error, :order_not_found}` if order doesn't exist
  - `{:error, :already_filled}` if order already executed
  - `{:error, :exchange_error}` if cancellation fails on exchange
  """
  @callback cancel_order(session_id :: session_id(), order_id :: order_id()) ::
    :ok | {:error, :order_not_found | :already_filled | :exchange_error}

  @doc """
  Retrieves the current status of an order.

  ## Parameters
  - `session_id`: UUID of the live session
  - `order_id`: Internal order ID

  ## Returns
  - `{:ok, order_status}` with current order state
  - `{:error, :not_found}` if order doesn't exist

  ## Notes
  - Status polled from exchange API
  - Updates cached locally for performance
  """
  @callback get_order_status(session_id :: session_id(), order_id :: order_id()) ::
    {:ok, order_status()} | {:error, :not_found}

  @doc """
  Monitors open positions and executes exit orders when conditions met.

  Implements FR-020 (monitor positions and execute exit/stop orders).

  This is called automatically by the session GenServer on every market data update.

  ## Parameters
  - `session_id`: UUID of the live session

  ## Returns
  - `{:ok, actions_taken}` with list of exit orders placed
  - `{:error, :session_not_found}` if session doesn't exist

  ## Notes
  - Evaluates exit_conditions and stop_conditions from strategy definition
  - Places market orders immediately when stop-loss triggered
  - Logs all exit decisions (FR-028)
  """
  @callback monitor_and_exit_positions(session_id :: session_id()) ::
    {:ok, [order_id()]} | {:error, :session_not_found}

  @doc """
  Pauses a live trading session.

  Stops monitoring for new signals but maintains open positions.
  Does NOT close positions - use stop_live_session to exit all positions.

  ## Parameters
  - `session_id`: UUID of the session to pause

  ## Returns
  - `:ok` if successfully paused
  - `{:error, :not_found}` if session doesn't exist
  - `{:error, :already_paused}` if already paused
  """
  @callback pause_live_session(session_id :: session_id()) ::
    :ok | {:error, :not_found | :already_paused}

  @doc """
  Resumes a paused live trading session.

  ## Parameters
  - `session_id`: UUID of the session to resume

  ## Returns
  - `:ok` if successfully resumed
  - `{:error, :not_found}` if session doesn't exist
  - `{:error, :not_paused}` if not currently paused
  - `{:error, :exchange_unavailable}` if cannot reconnect (FR-022)
  """
  @callback resume_live_session(session_id :: session_id()) ::
    :ok | {:error, :not_found | :not_paused | :exchange_unavailable}

  @doc """
  Stops a live trading session and closes all open positions at market price.

  ## Parameters
  - `session_id`: UUID of the session to stop

  ## Returns
  - `{:ok, final_results}` with session summary
  - `{:error, :not_found}` if session doesn't exist

  ## Notes
  - All open positions closed via market orders
  - Pending orders cancelled
  - API credentials cleared from memory
  - Session cannot be restarted
  """
  @callback stop_live_session(session_id :: session_id()) ::
    {:ok, map()} | {:error, :not_found}

  @doc """
  Handles exchange connectivity failures by pausing trading and alerting.

  Implements FR-022 (handle connectivity failures, pause trading, log alerts).

  ## Parameters
  - `session_id`: UUID of the live session
  - `failure_reason`: Atom describing failure type

  ## Returns
  - `:ok` after handling failure

  ## Actions Taken
  - Pauses session (no new positions opened)
  - Logs critical alert to console/terminal (FR-022)
  - Attempts reconnection with exponential backoff
  - Resumes session when connectivity restored

  ## Example Failure Reasons
  - `:websocket_disconnected`
  - `:api_timeout`
  - `:authentication_expired`
  - `:exchange_maintenance`
  """
  @callback handle_connectivity_failure(
    session_id :: session_id(),
    failure_reason :: atom()
  ) :: :ok

  @doc """
  Checks if a proposed trade would violate risk limits.

  Implements FR-021 (enforce portfolio-level risk limits).

  ## Parameters
  - `session_id`: UUID of the live session
  - `proposed_trade`: Map with trade details (side, quantity, price)

  ## Returns
  - `{:ok, :allowed}` if trade permitted
  - `{:error, :max_position_size_exceeded}` if trade too large
  - `{:error, :daily_loss_limit_hit}` if daily loss limit reached
  - `{:error, :max_drawdown_exceeded}` if drawdown threshold hit
  - `{:error, :max_concurrent_positions}` if too many open positions

  ## Notes
  - Called before place_order to prevent risk limit violations
  - Evaluates both current state and proposed trade impact
  """
  @callback check_risk_limits(
    session_id :: session_id(),
    proposed_trade :: map()
  ) :: {:ok, :allowed} |
       {:error, :max_position_size_exceeded | :daily_loss_limit_hit |
                :max_drawdown_exceeded | :max_concurrent_positions}

  @doc """
  Retrieves the trade history for a live trading session.

  ## Parameters
  - `session_id`: UUID of the session
  - `opts`: Keyword list of filters
    - `limit`: Integer (default 100)
    - `offset`: Integer (default 0)
    - `since`: DateTime (only trades after this time)

  ## Returns
  - `{:ok, trades}` with list of executed trades
  - `{:error, :not_found}` if session doesn't exist

  ## Notes
  - Includes exchange_order_id for reconciliation
  - Shows actual execution price and slippage
  """
  @callback get_live_session_trades(session_id :: session_id(), opts :: keyword()) ::
    {:ok, [map()]} | {:error, :not_found}

  @doc """
  Lists all live trading sessions.

  ## Parameters
  - `opts`: Keyword list of filters
    - `strategy_id`: Filter by strategy (optional)
    - `status`: Filter by status (optional)
    - `exchange`: Filter by exchange (optional)
    - `limit`: Integer (default 50)

  ## Returns
  - `{:ok, [session_summary, ...]}` list of sessions

  ## Security Notes
  - API credentials NEVER included in response
  - Only metadata returned (session_id, status, exchange name)
  """
  @callback list_live_sessions(opts :: keyword()) ::
    {:ok, [map()]}
end
