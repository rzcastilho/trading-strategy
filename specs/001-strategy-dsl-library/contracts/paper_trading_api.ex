# Paper Trading API Contract
#
# This module defines the Elixir behaviour contract for paper trading operations.
# Covers FR-012 through FR-016 (Paper Trading requirements)

defmodule TradingStrategy.Contracts.PaperTradingAPI do
  @moduledoc """
  Contract for real-time paper trading (simulated trading with live data).

  Paper trading connects to live market data feeds (FR-012) but simulates
  trade execution without placing real orders (FR-013), enabling strategy
  validation in real-time conditions before risking capital.
  """

  alias TradingStrategy.Contracts.StrategyAPI

  @type session_id :: String.t()
  @type strategy_id :: StrategyAPI.strategy_id()

  @type paper_session_config :: %{
    strategy_id: strategy_id(),
    trading_pair: String.t(),
    initial_capital: Decimal.t(),
    data_source: String.t(),  # Exchange name
    position_sizing: atom()  # :percentage | :fixed_amount
  }

  @type session_status :: %{
    session_id: session_id(),
    status: :active | :paused | :stopped,
    started_at: DateTime.t(),
    current_equity: Decimal.t(),
    unrealized_pnl: Decimal.t(),
    realized_pnl: Decimal.t(),
    open_positions: [position_summary()],
    trades_count: integer(),
    last_market_price: Decimal.t(),
    last_updated_at: DateTime.t()
  }

  @type position_summary :: %{
    trading_pair: String.t(),
    side: :long | :short,
    entry_price: Decimal.t(),
    quantity: Decimal.t(),
    current_price: Decimal.t(),
    unrealized_pnl: Decimal.t(),
    duration_seconds: integer()
  }

  @type simulated_trade :: %{
    trade_id: String.t(),
    session_id: session_id(),
    timestamp: DateTime.t(),
    trading_pair: String.t(),
    side: :buy | :sell,
    quantity: Decimal.t(),
    price: Decimal.t(),
    signal_type: :entry | :exit | :stop,
    pnl: Decimal.t() | nil  # nil for entry, Decimal for exit/stop
  }

  @type session_results :: %{
    session_id: session_id(),
    duration_seconds: integer(),
    final_equity: Decimal.t(),
    total_return: Decimal.t(),
    trades: [simulated_trade()],
    performance_metrics: map(),  # Same structure as backtest metrics
    max_drawdown_reached: Decimal.t()
  }

  @doc """
  Starts a new paper trading session.

  Connects to live market data feed (FR-012) and begins monitoring for
  signal conditions. All trades are simulated (FR-013).

  ## Parameters
  - `config`: Paper session configuration map

  ## Returns
  - `{:ok, session_id}` with unique session identifier
  - `{:error, :strategy_not_found}` if strategy_id invalid
  - `{:error, :data_feed_unavailable}` if cannot connect to exchange
  - `{:error, :invalid_trading_pair}` if pair not supported by exchange

  ## Examples
      iex> start_paper_session(%{
        strategy_id: "550e8400-...",
        trading_pair: "BTC/USD",
        initial_capital: Decimal.new("10000"),
        data_source: "binance",
        position_sizing: :percentage
      })
      {:ok, "session_abc123"}

  ## Notes
  - Session runs indefinitely until stopped
  - State persisted across application restarts (FR-016)
  - All trades logged with timestamps and P&L (FR-014)
  """
  @callback start_paper_session(config :: paper_session_config()) ::
    {:ok, session_id()} | {:error, :strategy_not_found | :data_feed_unavailable | :invalid_trading_pair}

  @doc """
  Retrieves current status of an active paper trading session.

  Implements FR-015 requirement for tracking simulated portfolio state.

  ## Parameters
  - `session_id`: UUID of the paper session

  ## Returns
  - `{:ok, status}` with real-time session state
  - `{:error, :not_found}` if session doesn't exist

  ## Examples
      iex> get_paper_session_status("session_abc123")
      {:ok, %{
        session_id: "session_abc123",
        status: :active,
        started_at: ~U[2025-12-04 10:00:00Z],
        current_equity: Decimal.new("10450.23"),
        unrealized_pnl: Decimal.new("120.50"),
        realized_pnl: Decimal.new("329.73"),
        open_positions: [
          %{
            trading_pair: "BTC/USD",
            side: :long,
            entry_price: Decimal.new("42150.00"),
            quantity: Decimal.new("0.1"),
            current_price: Decimal.new("43200.00"),
            unrealized_pnl: Decimal.new("105.00"),
            duration_seconds: 7200
          }
        ],
        trades_count: 8,
        last_market_price: Decimal.new("43200.00"),
        last_updated_at: ~U[2025-12-04 12:34:56Z]
      }}
  """
  @callback get_paper_session_status(session_id :: session_id()) ::
    {:ok, session_status()} | {:error, :not_found}

  @doc """
  Pauses an active paper trading session.

  Stops monitoring for signals but maintains current positions.
  Can be resumed later with `resume_paper_session/1`.

  ## Parameters
  - `session_id`: UUID of the session to pause

  ## Returns
  - `:ok` if successfully paused
  - `{:error, :not_found}` if session doesn't exist
  - `{:error, :already_paused}` if session already paused
  - `{:error, :already_stopped}` if session terminated

  ## Notes
  - Paused sessions do not process new market data
  - Open positions remain tracked but no actions taken
  - Resume to continue strategy execution
  """
  @callback pause_paper_session(session_id :: session_id()) ::
    :ok | {:error, :not_found | :already_paused | :already_stopped}

  @doc """
  Resumes a paused paper trading session.

  Reconnects to market data feed and continues monitoring for signals.

  ## Parameters
  - `session_id`: UUID of the session to resume

  ## Returns
  - `:ok` if successfully resumed
  - `{:error, :not_found}` if session doesn't exist
  - `{:error, :not_paused}` if session not currently paused
  - `{:error, :data_feed_unavailable}` if cannot reconnect to exchange
  """
  @callback resume_paper_session(session_id :: session_id()) ::
    :ok | {:error, :not_found | :not_paused | :data_feed_unavailable}

  @doc """
  Stops a paper trading session and closes all open positions at market price.

  Session cannot be restarted after stopping - use pause/resume for temporary suspension.

  ## Parameters
  - `session_id`: UUID of the session to stop

  ## Returns
  - `{:ok, final_results}` with session summary and performance metrics
  - `{:error, :not_found}` if session doesn't exist
  - `{:error, :already_stopped}` if session already terminated

  ## Notes
  - All open positions closed at current market price (simulated instant fill)
  - Final P&L calculated and metrics computed
  - Session state archived for historical analysis
  """
  @callback stop_paper_session(session_id :: session_id()) ::
    {:ok, session_results()} | {:error, :not_found | :already_stopped}

  @doc """
  Retrieves the trade history for a paper trading session.

  Implements FR-014 requirement for logging all simulated trades.

  ## Parameters
  - `session_id`: UUID of the session
  - `opts`: Keyword list of filters
    - `limit`: Integer (default 100)
    - `offset`: Integer (default 0)
    - `since`: DateTime (only trades after this time)

  ## Returns
  - `{:ok, trades}` with list of simulated trade records
  - `{:error, :not_found}` if session doesn't exist

  ## Examples
      iex> get_paper_session_trades("session_abc123", limit: 5)
      {:ok, [
        %{
          trade_id: "trade_001",
          timestamp: ~U[2025-12-04 10:15:30Z],
          side: :buy,
          quantity: Decimal.new("0.1"),
          price: Decimal.new("42150.00"),
          signal_type: :entry,
          pnl: nil
        },
        %{
          trade_id: "trade_002",
          timestamp: ~U[2025-12-04 11:45:12Z],
          side: :sell,
          quantity: Decimal.new("0.1"),
          price: Decimal.new("42680.00"),
          signal_type: :exit,
          pnl: Decimal.new("53.00")  # After fees
        },
        ...
      ]}
  """
  @callback get_paper_session_trades(session_id :: session_id(), opts :: keyword()) ::
    {:ok, [simulated_trade()]} | {:error, :not_found}

  @doc """
  Lists all paper trading sessions, optionally filtered.

  ## Parameters
  - `opts`: Keyword list of filters
    - `strategy_id`: Filter by strategy UUID (optional)
    - `status`: `:active` | `:paused` | `:stopped` (optional)
    - `limit`: Integer (default 50)
    - `offset`: Integer (default 0)

  ## Returns
  - `{:ok, [session_summary, ...]}` list of session summaries
  """
  @callback list_paper_sessions(opts :: keyword()) ::
    {:ok, [map()]}

  @doc """
  Restores a paper trading session from persisted state after application restart.

  Implements FR-016 requirement for session persistence across restarts.

  ## Parameters
  - `session_id`: UUID of the session to restore

  ## Returns
  - `{:ok, session_id}` if successfully restored and resumed
  - `{:error, :not_found}` if no persisted state exists
  - `{:error, :data_feed_unavailable}` if cannot reconnect to exchange
  - `{:error, :corrupted_state}` if persisted state is invalid

  ## Notes
  - Automatically called on application startup for all :active sessions
  - Reconnects to market data feed
  - Loads last snapshot + replays delta trades
  - Continues from recovered state
  """
  @callback restore_paper_session(session_id :: session_id()) ::
    {:ok, session_id()} | {:error, :not_found | :data_feed_unavailable | :corrupted_state}

  @doc """
  Retrieves performance metrics for a paper trading session.

  ## Parameters
  - `session_id`: UUID of the session

  ## Returns
  - `{:ok, metrics}` with current performance statistics
  - `{:error, :not_found}` if session doesn't exist

  ## Notes
  - Metrics calculated in real-time from trade history
  - For stopped sessions, returns final metrics
  - For active sessions, includes unrealized P&L in calculations
  """
  @callback get_paper_session_metrics(session_id :: session_id()) ::
    {:ok, map()} | {:error, :not_found}
end
