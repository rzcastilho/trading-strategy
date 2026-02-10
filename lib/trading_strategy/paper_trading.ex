defmodule TradingStrategy.PaperTrading do
  @moduledoc """
  Context module for paper trading operations.

  Provides high-level API for managing paper trading sessions, implementing
  the PaperTradingAPI contract defined in contracts/paper_trading_api.ex.

  ## Responsibilities
  - Start/stop/pause/resume paper trading sessions
  - Query session status and performance metrics
  - Retrieve trade history
  - List active sessions
  - Restore sessions after restart

  ## Architecture
  - Uses DynamicSupervisor for session process management
  - SessionManager processes are registered in Registry
  - SessionPersister handles database persistence
  - Delegates to SessionManager for actual execution

  ## Usage

  ```elixir
  # Start a paper trading session
  {:ok, session_id} = PaperTrading.start_paper_session(%{
    strategy_id: "550e8400-...",
    trading_pair: "BTC/USD",
    initial_capital: Decimal.new("10000"),
    data_source: "binance",
    position_sizing: :percentage
  })

  # Get session status
  {:ok, status} = PaperTrading.get_paper_session_status(session_id)

  # Stop session
  {:ok, results} = PaperTrading.stop_paper_session(session_id)
  ```
  """

  require Logger

  alias TradingStrategy.PaperTrading.SessionManager
  alias TradingStrategy.PaperTrading.SessionPersister
  alias TradingStrategy.PaperTrading.SessionSupervisor
  alias TradingStrategy.Strategies

  @type session_id :: String.t()
  @type strategy_id :: String.t()

  @type paper_session_config :: %{
          strategy_id: strategy_id(),
          trading_pair: String.t(),
          initial_capital: Decimal.t(),
          data_source: String.t(),
          position_sizing: :percentage | :fixed_amount,
          position_size_pct: float() | nil,
          position_size_fixed: Decimal.t() | nil
        }

  @type session_status :: %{
          session_id: session_id(),
          status: :active | :paused | :stopped,
          started_at: DateTime.t(),
          current_equity: Decimal.t(),
          unrealized_pnl: Decimal.t(),
          realized_pnl: Decimal.t(),
          open_positions: [map()],
          trades_count: integer(),
          last_market_price: Decimal.t(),
          last_updated_at: DateTime.t()
        }

  @doc """
  Starts a new paper trading session.

  Connects to live market data feed and begins monitoring for signal conditions.
  All trades are simulated (no real orders placed).

  ## Parameters
  - `config`: Paper session configuration map (see `paper_session_config` type)

  ## Returns
  - `{:ok, session_id}` with unique session identifier
  - `{:error, :strategy_not_found}` if strategy_id invalid
  - `{:error, :data_feed_unavailable}` if cannot connect to exchange
  - `{:error, :invalid_trading_pair}` if pair not supported

  ## Examples
      iex> start_paper_session(%{
      ...>   strategy_id: "550e8400-...",
      ...>   trading_pair: "BTC/USD",
      ...>   initial_capital: Decimal.new("10000"),
      ...>   data_source: "binance",
      ...>   position_sizing: :percentage,
      ...>   position_size_pct: 0.1
      ...> })
      {:ok, "session_abc123"}
  """
  @spec start_paper_session(paper_session_config()) ::
          {:ok, session_id()} | {:error, atom()}
  def start_paper_session(config) do
    with {:ok, strategy} <- validate_strategy(config.strategy_id),
         {:ok, session_id} <- generate_session_id(),
         {:ok, session_config} <- build_session_config(session_id, config, strategy) do
      # Start session manager under DynamicSupervisor
      case SessionSupervisor.start_session(session_config) do
        {:ok, _pid} ->
          Logger.info("[PaperTrading] Started paper session: #{session_id}")
          {:ok, session_id}

        {:error, reason} = error ->
          Logger.error("[PaperTrading] Failed to start session: #{inspect(reason)}")
          error
      end
    end
  end

  @doc """
  Retrieves current status of an active paper trading session.

  ## Parameters
  - `session_id`: UUID of the paper session

  ## Returns
  - `{:ok, status}` with real-time session state
  - `{:error, :not_found}` if session doesn't exist
  """
  @spec get_paper_session_status(session_id()) ::
          {:ok, session_status()} | {:error, :not_found}
  def get_paper_session_status(session_id) do
    case find_session_process(session_id) do
      {:ok, pid} ->
        SessionManager.get_status(pid)

      {:error, :not_found} ->
        # Check if session exists in database but not running
        case SessionPersister.get_session(session_id) do
          {:ok, session_data} ->
            {:ok, build_stopped_status(session_data)}

          {:error, :not_found} ->
            {:error, :not_found}
        end
    end
  end

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
  """
  @spec pause_paper_session(session_id()) ::
          :ok | {:error, :not_found | :already_paused | :already_stopped}
  def pause_paper_session(session_id) do
    with {:ok, pid} <- find_session_process(session_id) do
      SessionManager.pause(pid)
    end
  end

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
  @spec resume_paper_session(session_id()) ::
          :ok | {:error, :not_found | :not_paused | :data_feed_unavailable}
  def resume_paper_session(session_id) do
    with {:ok, pid} <- find_session_process(session_id) do
      SessionManager.resume(pid)
    end
  end

  @doc """
  Stops a paper trading session and closes all open positions at market price.

  Session cannot be restarted after stopping - use pause/resume for temporary suspension.

  ## Parameters
  - `session_id`: UUID of the session to stop

  ## Returns
  - `{:ok, final_results}` with session summary and performance metrics
  - `{:error, :not_found}` if session doesn't exist
  - `{:error, :already_stopped}` if session already terminated
  """
  @spec stop_paper_session(session_id()) ::
          {:ok, map()} | {:error, :not_found | :already_stopped}
  def stop_paper_session(session_id) do
    with {:ok, pid} <- find_session_process(session_id),
         {:ok, results} <- SessionManager.stop(pid) do
      # Terminate the session process
      SessionSupervisor.stop_session(session_id)

      {:ok, results}
    end
  end

  @doc """
  Retrieves the trade history for a paper trading session.

  ## Parameters
  - `session_id`: UUID of the session
  - `opts`: Keyword list of filters
    - `limit`: Integer (default 100)
    - `offset`: Integer (default 0)
    - `since`: DateTime (only trades after this time)

  ## Returns
  - `{:ok, trades}` with list of simulated trade records
  - `{:error, :not_found}` if session doesn't exist
  """
  @spec get_paper_session_trades(session_id(), keyword()) ::
          {:ok, [map()]} | {:error, :not_found}
  def get_paper_session_trades(session_id, opts \\ []) do
    with {:ok, pid} <- find_session_process(session_id) do
      SessionManager.get_trades(pid, opts)
    else
      {:error, :not_found} ->
        # Try loading from database if session not running
        SessionPersister.get_session_trades(session_id, opts)
    end
  end

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
  @spec list_paper_sessions(keyword()) :: {:ok, [map()]}
  def list_paper_sessions(opts \\ []) do
    SessionPersister.list_sessions(opts)
  end

  @doc """
  Restores a paper trading session from persisted state after application restart.

  Automatically called on application startup for all :active sessions.

  ## Parameters
  - `session_id`: UUID of the session to restore

  ## Returns
  - `{:ok, session_id}` if successfully restored and resumed
  - `{:error, :not_found}` if no persisted state exists
  - `{:error, :data_feed_unavailable}` if cannot reconnect to exchange
  - `{:error, :corrupted_state}` if persisted state is invalid
  """
  @spec restore_paper_session(session_id()) ::
          {:ok, session_id()} | {:error, :not_found | :data_feed_unavailable | :corrupted_state}
  def restore_paper_session(session_id) do
    with {:ok, session_data} <- SessionPersister.get_session(session_id),
         strategy when not is_nil(strategy) <- Strategies.get_strategy_admin(session_data.strategy_id),
         {:ok, session_config} <- build_restore_config(session_id, session_data, strategy) do
      case SessionSupervisor.start_session(session_config) do
        {:ok, _pid} ->
          Logger.info("[PaperTrading] Restored paper session: #{session_id}")
          {:ok, session_id}

        {:error, reason} = error ->
          Logger.error("[PaperTrading] Failed to restore session: #{inspect(reason)}")
          error
      end
    end
  end

  @doc """
  Restores all active paper trading sessions on application startup.

  Called by the application supervisor during startup.

  ## Returns
  - `{:ok, restored_count}` with number of sessions restored
  """
  @spec restore_all_active_sessions() :: {:ok, integer()}
  def restore_all_active_sessions do
    {:ok, sessions} = list_paper_sessions(status: :active)

    restored_count =
      sessions
      |> Enum.map(fn session -> restore_paper_session(session.session_id) end)
      |> Enum.count(fn
        {:ok, _} -> true
        {:error, _} -> false
      end)

    Logger.info("[PaperTrading] Restored #{restored_count} active sessions")

    {:ok, restored_count}
  end

  @doc """
  Retrieves performance metrics for a paper trading session.

  ## Parameters
  - `session_id`: UUID of the session

  ## Returns
  - `{:ok, metrics}` with current performance statistics
  - `{:error, :not_found}` if session doesn't exist
  """
  @spec get_paper_session_metrics(session_id()) ::
          {:ok, map()} | {:error, :not_found}
  def get_paper_session_metrics(session_id) do
    with {:ok, pid} <- find_session_process(session_id) do
      SessionManager.get_metrics(pid)
    else
      {:error, :not_found} ->
        # Try loading from database if session not running
        SessionPersister.get_session_metrics(session_id)
    end
  end

  # Private Functions

  defp validate_strategy(strategy_id) do
    case Strategies.get_strategy_admin(strategy_id) do
      nil ->
        {:error, :strategy_not_found}

      strategy ->
        {:ok, strategy}
    end
  end

  defp generate_session_id do
    session_id = "paper_" <> UUID.uuid4()
    {:ok, session_id}
  end

  defp build_session_config(session_id, config, strategy) do
    session_config = %{
      session_id: session_id,
      strategy_id: config.strategy_id,
      strategy: strategy,
      trading_pair: config.trading_pair,
      initial_capital: config.initial_capital,
      current_capital: config.initial_capital,
      data_source: config.data_source,
      position_sizing: config.position_sizing,
      position_size_pct: Map.get(config, :position_size_pct, 0.1),
      position_size_fixed: Map.get(config, :position_size_fixed),
      # 0.1%
      slippage_bps: Map.get(config, :slippage_bps, 10),
      # 0.1%
      commission_rate: Map.get(config, :commission_rate, 0.001),
      restore: false
    }

    {:ok, session_config}
  end

  defp build_restore_config(session_id, session_data, strategy) do
    session_config = %{
      session_id: session_id,
      strategy_id: session_data.strategy_id,
      strategy: strategy,
      trading_pair: session_data.trading_pair,
      initial_capital: session_data.initial_capital,
      current_capital: session_data.current_capital,
      data_source: session_data.data_source || "binance",
      position_sizing: session_data.position_sizing || :percentage,
      position_size_pct: session_data.position_size_pct || 0.1,
      position_size_fixed: session_data.position_size_fixed,
      slippage_bps: session_data.slippage_bps || 10,
      commission_rate: session_data.commission_rate || 0.001,
      restore: true,
      persisted_state: session_data.state
    }

    {:ok, session_config}
  end

  defp find_session_process(session_id) do
    case Registry.lookup(TradingStrategy.PaperTrading.SessionRegistry, session_id) do
      [{pid, _}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end

  defp build_stopped_status(session_data) do
    %{
      session_id: session_data.session_id,
      status: :stopped,
      started_at: session_data.started_at,
      stopped_at: session_data.stopped_at,
      current_equity: session_data.current_capital,
      unrealized_pnl: Decimal.new("0"),
      realized_pnl: session_data.realized_pnl || Decimal.new("0"),
      open_positions: [],
      trades_count: session_data.trades_count || 0,
      last_market_price: Decimal.new("0"),
      last_updated_at: session_data.updated_at || session_data.stopped_at
    }
  end
end
