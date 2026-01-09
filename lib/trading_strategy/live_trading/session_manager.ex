defmodule TradingStrategy.LiveTrading.SessionManager do
  @moduledoc """
  Live trading session manager coordinating real-time execution.

  Manages live trading sessions with real money on exchanges, coordinating:
  - Exchange connection and authentication
  - Real-time market data processing
  - Order execution via LiveExecutor
  - Position tracking and risk management
  - Balance monitoring
  - Emergency stop procedures
  - Connectivity monitoring and reconnection
  """

  use GenServer
  require Logger

  alias TradingStrategy.{Repo, Strategies}
  alias TradingStrategy.Exchanges.{Exchange, Credentials, HealthMonitor}
  alias TradingStrategy.Orders.{LiveExecutor, OrderTracker}
  alias TradingStrategy.Risk.{RiskManager, PositionSizer}

  alias TradingStrategy.LiveTrading.{
    BalanceMonitor,
    EmergencyStop,
    ConnectivityMonitor,
    ReconnectionHandler,
    AuditLogger
  }

  alias TradingStrategy.Strategies.{RealtimeIndicatorEngine, RealtimeSignalDetector}
  alias TradingStrategy.MarketData.Cache

  @pubsub TradingStrategy.PubSub

  defstruct [
    :session_id,
    :user_id,
    :strategy_id,
    :strategy,
    :trading_pair,
    :exchange,
    :status,
    :started_at,
    :allocated_capital,
    :current_equity,
    :peak_equity,
    :daily_starting_equity,
    :realized_pnl_today,
    :risk_limits,
    :position_sizing_method,
    :open_positions,
    :pending_orders,
    :trades_count,
    :indicator_engine,
    :signal_detector,
    :last_market_price,
    :last_update_at,
    :connectivity_status
  ]

  @type status :: :active | :paused | :stopped | :error
  @type connectivity_status :: :connected | :disconnected | :degraded

  # Client API

  @doc """
  Start a new live trading session.

  ## Parameters
  - `session_config`: Session configuration (keyword list)
    - `:session_id` - Unique session identifier (required)
    - `:strategy_id` - Strategy UUID (required)
    - `:trading_pair` - Trading pair symbol (required)
    - `:allocated_capital` - Capital allocated for trading (required)
    - `:exchange` - Exchange name (required, e.g., "binance")
    - `:api_credentials` - API credentials map (required)
    - `:position_sizing` - Sizing method (default: :percentage)
    - `:risk_limits` - Risk limits map (optional, uses defaults)

  ## Returns
  - `{:ok, pid}` - Session started successfully
  - `{:error, reason}` - Failed to start session
  """
  def start_link(session_config) do
    session_id = Keyword.fetch!(session_config, :session_id)
    GenServer.start_link(__MODULE__, session_config, name: via_tuple(session_id))
  end

  @doc """
  Get current status of a live trading session.
  """
  def get_status(session_id) do
    call_session(session_id, :get_status)
  end

  @doc """
  Pause a live trading session.
  """
  def pause(session_id) do
    call_session(session_id, :pause)
  end

  @doc """
  Resume a paused live trading session.
  """
  def resume(session_id) do
    call_session(session_id, :resume)
  end

  @doc """
  Stop a live trading session and close all positions.
  """
  def stop(session_id) do
    call_session(session_id, :stop)
  end

  @doc """
  Execute emergency stop for a session.
  """
  def emergency_stop(session_id) do
    call_session(session_id, :emergency_stop)
  end

  @doc """
  Place an order in a live session.
  """
  def place_order(session_id, order_params) do
    call_session(session_id, {:place_order, order_params})
  end

  # Server Callbacks

  @impl true
  def init(config) do
    session_id = Keyword.fetch!(config, :session_id)
    strategy_id = Keyword.fetch!(config, :strategy_id)
    trading_pair = Keyword.fetch!(config, :trading_pair)
    allocated_capital = Keyword.fetch!(config, :allocated_capital)
    exchange = Keyword.fetch!(config, :exchange)
    api_credentials = Keyword.fetch!(config, :api_credentials)
    position_sizing = Keyword.get(config, :position_sizing, :percentage)
    risk_limits = Keyword.get(config, :risk_limits, RiskManager.default_risk_limits())

    Logger.info("Starting live trading session",
      session_id: session_id,
      strategy_id: strategy_id,
      trading_pair: trading_pair,
      exchange: exchange
    )

    # Load strategy
    case Repo.get(Strategies.Strategy, strategy_id) do
      nil ->
        {:stop, :strategy_not_found}

      strategy ->
        # Generate user_id for exchange connection
        user_id = "live_#{session_id}"

        # Store credentials (never persisted to database)
        :ok = Credentials.store(user_id, api_credentials)

        # Connect to exchange
        case Exchange.connect_user(user_id, api_credentials.api_key, api_credentials.api_secret) do
          {:ok, _user_pid} ->
            # Register with monitoring systems
            :ok = HealthMonitor.register_user(user_id)
            :ok = BalanceMonitor.monitor_user(user_id)
            :ok = ConnectivityMonitor.monitor_user(user_id)

            # Get initial balance
            {:ok, balances} = Exchange.get_balance(user_id)

            # Initialize state
            state = %__MODULE__{
              session_id: session_id,
              user_id: user_id,
              strategy_id: strategy_id,
              strategy: strategy,
              trading_pair: trading_pair,
              exchange: exchange,
              status: :active,
              started_at: DateTime.utc_now(),
              allocated_capital: allocated_capital,
              current_equity: allocated_capital,
              peak_equity: allocated_capital,
              daily_starting_equity: allocated_capital,
              realized_pnl_today: Decimal.new("0"),
              risk_limits: risk_limits,
              position_sizing_method: position_sizing,
              open_positions: [],
              pending_orders: [],
              trades_count: 0,
              indicator_engine: nil,
              signal_detector: nil,
              last_market_price: nil,
              last_update_at: DateTime.utc_now(),
              connectivity_status: :connected
            }

            # Initialize real-time components
            state = initialize_realtime_components(state)

            # Subscribe to market data
            topic = "market_data:#{exchange}:#{trading_pair}"
            Phoenix.PubSub.subscribe(@pubsub, topic)

            # Log session start
            AuditLogger.log_session_event(user_id, session_id, :session_started, %{
              strategy_id: strategy_id,
              trading_pair: trading_pair,
              allocated_capital: Decimal.to_string(allocated_capital)
            })

            {:ok, state}

          {:error, reason} ->
            Logger.error("Failed to connect to exchange",
              session_id: session_id,
              reason: inspect(reason)
            )

            {:stop, :exchange_connection_failed}
        end
    end
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    status = build_status_response(state)
    {:reply, {:ok, status}, state}
  end

  @impl true
  def handle_call(:pause, _from, %{status: :active} = state) do
    Logger.info("Pausing live trading session", session_id: state.session_id)

    AuditLogger.log_session_event(state.user_id, state.session_id, :session_paused, %{})

    {:reply, :ok, %{state | status: :paused}}
  end

  @impl true
  def handle_call(:pause, _from, state) do
    {:reply, {:error, :not_active}, state}
  end

  @impl true
  def handle_call(:resume, _from, %{status: :paused} = state) do
    Logger.info("Resuming live trading session", session_id: state.session_id)

    # Check connectivity before resuming
    case ConnectivityMonitor.get_status(state.user_id) do
      {:ok, :connected} ->
        AuditLogger.log_session_event(state.user_id, state.session_id, :session_resumed, %{})
        {:reply, :ok, %{state | status: :active}}

      {:ok, status} ->
        Logger.warning("Cannot resume - connectivity status is #{status}")
        {:reply, {:error, :exchange_unavailable}, state}

      {:error, _} ->
        {:reply, {:error, :exchange_unavailable}, state}
    end
  end

  @impl true
  def handle_call(:resume, _from, state) do
    {:reply, {:error, :not_paused}, state}
  end

  @impl true
  def handle_call(:stop, _from, state) do
    Logger.info("Stopping live trading session", session_id: state.session_id)

    # Close all positions at market price
    final_results = close_all_positions(state)

    # Cleanup
    cleanup_session(state)

    AuditLogger.log_session_event(
      state.user_id,
      state.session_id,
      :session_stopped,
      final_results
    )

    {:stop, :normal, {:ok, final_results}, %{state | status: :stopped}}
  end

  @impl true
  def handle_call(:emergency_stop, _from, state) do
    Logger.error("EMERGENCY STOP TRIGGERED", session_id: state.session_id)

    # Execute emergency stop
    {:ok, stop_result} = EmergencyStop.execute(state.user_id)

    AuditLogger.log_emergency_stop(state.user_id, state.session_id, stop_result)

    # Cleanup
    cleanup_session(state)

    {:stop, :normal, {:ok, stop_result}, %{state | status: :stopped}}
  end

  @impl true
  def handle_call({:place_order, order_params}, _from, %{status: :active} = state) do
    # Build execution context
    {:ok, balances} = Exchange.get_balance(state.user_id)

    context = %{
      balances: balances,
      portfolio_state: build_portfolio_state(state),
      risk_limits: state.risk_limits,
      # Could be fetched from exchange
      symbol_info: nil
    }

    # Execute order
    full_order_params = Map.merge(order_params, %{user_id: state.user_id})

    case LiveExecutor.execute_order(full_order_params, context) do
      {:ok, response} ->
        # Track the order
        {:ok, internal_order_id} = OrderTracker.track_order(response, self())

        # Log to audit
        correlation_id =
          AuditLogger.log_order_placement(
            state.user_id,
            state.session_id,
            order_params,
            :success
          )

        # Update state
        new_state = %{
          state
          | pending_orders: [response | state.pending_orders],
            trades_count: state.trades_count + 1
        }

        {:reply, {:ok, internal_order_id}, new_state}

      {:error, reason} = error ->
        # Log failure
        AuditLogger.log_order_placement(
          state.user_id,
          state.session_id,
          order_params,
          :failure,
          reason
        )

        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:place_order, _order_params}, _from, state) do
    {:reply, {:error, :session_not_active}, state}
  end

  @impl true
  def handle_info({:market_data_update, _exchange, _pair, tick_data}, %{status: :active} = state) do
    # Process market data update
    new_state = process_market_update(state, tick_data)
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:market_data_update, _, _, _}, state) do
    # Ignore market updates when not active
    {:noreply, state}
  end

  @impl true
  def handle_info({:order_status_changed, order_id, old_status, new_status, order}, state) do
    Logger.info("Order status changed",
      order_id: order_id,
      old_status: old_status,
      new_status: new_status
    )

    # Update state based on order status
    new_state = handle_order_status_change(state, order, new_status)

    {:noreply, new_state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("Live trading session terminating",
      session_id: state.session_id,
      reason: inspect(reason)
    )

    cleanup_session(state)
    :ok
  end

  # Private Functions

  defp via_tuple(session_id) do
    {:via, Registry, {TradingStrategy.LiveTrading.SessionRegistry, session_id}}
  end

  defp call_session(session_id, message) do
    case GenServer.whereis(via_tuple(session_id)) do
      nil -> {:error, :not_found}
      pid -> GenServer.call(pid, message)
    end
  end

  defp initialize_realtime_components(state) do
    # Initialize indicator engine
    indicator_engine = RealtimeIndicatorEngine.new(state.strategy)

    # Initialize signal detector
    signal_detector = RealtimeSignalDetector.new(state.strategy)

    %{state | indicator_engine: indicator_engine, signal_detector: signal_detector}
  end

  defp process_market_update(state, tick_data) do
    price = tick_data[:price] || tick_data["price"]

    # Update indicators
    {updated_engine, indicator_values} =
      RealtimeIndicatorEngine.update(
        state.indicator_engine,
        tick_data
      )

    # Check for signals
    {updated_detector, signals} =
      RealtimeSignalDetector.evaluate(
        state.signal_detector,
        indicator_values,
        tick_data
      )

    # Process signals and execute trades if needed
    new_state = %{
      state
      | indicator_engine: updated_engine,
        signal_detector: updated_detector,
        last_market_price: price,
        last_update_at: DateTime.utc_now()
    }

    # Execute signals (if any)
    execute_signals(new_state, signals)
  end

  defp execute_signals(state, []), do: state

  defp execute_signals(state, signals) do
    # Process each signal
    Enum.reduce(signals, state, fn signal, acc_state ->
      process_signal(acc_state, signal)
    end)
  end

  defp process_signal(state, _signal) do
    # TODO: Implement signal processing logic
    # This would involve creating orders based on signals
    # For now, just return state unchanged
    state
  end

  defp handle_order_status_change(state, order, :filled) do
    # Update positions when order is filled
    # TODO: Implement position tracking
    state
  end

  defp handle_order_status_change(state, _order, _status) do
    state
  end

  defp build_portfolio_state(state) do
    %{
      current_equity: state.current_equity,
      peak_equity: state.peak_equity,
      daily_starting_equity: state.daily_starting_equity,
      open_positions: state.open_positions,
      realized_pnl_today: state.realized_pnl_today
    }
  end

  defp build_status_response(state) do
    risk_metrics =
      RiskManager.calculate_risk_metrics(
        build_portfolio_state(state),
        state.risk_limits
      )

    %{
      session_id: state.session_id,
      status: state.status,
      started_at: state.started_at,
      exchange: state.exchange,
      current_equity: state.current_equity,
      # TODO: Calculate from open positions
      unrealized_pnl: Decimal.new("0"),
      realized_pnl: state.realized_pnl_today,
      open_positions: state.open_positions,
      pending_orders: state.pending_orders,
      trades_count: state.trades_count,
      risk_limits_status: risk_metrics,
      last_updated_at: state.last_update_at,
      connectivity_status: state.connectivity_status
    }
  end

  defp close_all_positions(state) do
    # TODO: Implement position closing logic
    %{
      final_equity: state.current_equity,
      total_pnl: Decimal.sub(state.current_equity, state.allocated_capital),
      trades_count: state.trades_count
    }
  end

  defp cleanup_session(state) do
    # Unsubscribe from market data
    topic = "market_data:#{state.exchange}:#{state.trading_pair}"
    Phoenix.PubSub.unsubscribe(@pubsub, topic)

    # Unregister from monitoring systems
    HealthMonitor.unregister_user(state.user_id)
    BalanceMonitor.stop_monitoring(state.user_id)
    ConnectivityMonitor.stop_monitoring(state.user_id)

    # Clear credentials from memory
    Credentials.delete(state.user_id)
  end
end
