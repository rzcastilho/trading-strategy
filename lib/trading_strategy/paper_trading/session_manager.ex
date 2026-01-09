defmodule TradingStrategy.PaperTrading.SessionManager do
  @moduledoc """
  Manages paper trading sessions with real-time market data.

  Coordinates between:
  - Real-time indicator engine (calculates indicators on new data)
  - Real-time signal detector (evaluates entry/exit/stop conditions)
  - Paper executor (simulates trades)
  - Position tracker (tracks positions and P&L)
  - Session persister (saves state to database)

  Subscribes to Phoenix.PubSub for real-time market data updates and
  maintains session state with automatic persistence.
  """

  use GenServer
  require Logger

  alias TradingStrategy.PaperTrading.{PositionTracker, PaperExecutor, SessionPersister}
  alias TradingStrategy.Strategies.{RealtimeIndicatorEngine, RealtimeSignalDetector}
  alias TradingStrategy.MarketData.Cache
  alias TradingStrategy.Repo
  alias TradingStrategy.Strategies.Strategy

  @pubsub TradingStrategy.PubSub

  defstruct [
    :session_id,
    :strategy_id,
    :strategy,
    :trading_pair,
    :data_source,
    :status,
    :started_at,
    :position_tracker,
    :indicator_engine,
    :signal_detector,
    :trades,
    :last_market_price,
    :last_update_at,
    :config
  ]

  @type status :: :active | :paused | :stopped

  # Client API

  @doc """
  Starts a new paper trading session.

  ## Parameters
    - `session_config`: Session configuration
      - `:session_id` - Unique session identifier (required)
      - `:strategy_id` - Strategy UUID (required)
      - `:trading_pair` - Trading pair symbol (required)
      - `:initial_capital` - Starting capital (required)
      - `:data_source` - Exchange name (required)
      - `:position_sizing` - :percentage or :fixed_amount (default: :percentage)
      - `:position_size_pct` - Position size percentage (default: 0.1)

  ## Returns
    - `{:ok, pid}` - Session started
    - `{:error, reason}` - Failed to start
  """
  def start_link(session_config) do
    session_id = Keyword.fetch!(session_config, :session_id)
    GenServer.start_link(__MODULE__, session_config, name: via_tuple(session_id))
  end

  @doc """
  Gets the current status of a paper trading session.

  ## Parameters
    - `session_id`: Session UUID

  ## Returns
    - `{:ok, status}` - Session status
    - `{:error, :not_found}` - Session doesn't exist
  """
  def get_status(session_id) do
    case GenServer.whereis(via_tuple(session_id)) do
      nil -> {:error, :not_found}
      pid -> GenServer.call(pid, :get_status)
    end
  end

  @doc """
  Pauses a paper trading session.

  Stops processing market data updates but maintains positions.
  """
  def pause(session_id) do
    call_session(session_id, :pause)
  end

  @doc """
  Resumes a paused paper trading session.

  Reconnects to market data feed and continues processing.
  """
  def resume(session_id) do
    call_session(session_id, :resume)
  end

  @doc """
  Stops a paper trading session.

  Closes all open positions at current market price and archives session.
  """
  def stop(session_id) do
    call_session(session_id, :stop)
  end

  @doc """
  Gets the trade history for a session.

  ## Parameters
    - `session_id`: Session UUID
    - `opts`: Options
      - `:limit` - Max trades to return (default: 100)
      - `:offset` - Offset for pagination (default: 0)
  """
  def get_trades(session_id, opts \\ []) do
    call_session(session_id, {:get_trades, opts})
  end

  @doc """
  Gets current performance metrics for a session.
  """
  def get_metrics(session_id) do
    call_session(session_id, :get_metrics)
  end

  # Server Callbacks

  @impl true
  def init(session_config) do
    session_id = Keyword.fetch!(session_config, :session_id)
    strategy_id = Keyword.fetch!(session_config, :strategy_id)
    trading_pair = Keyword.fetch!(session_config, :trading_pair)
    initial_capital = Keyword.fetch!(session_config, :initial_capital)
    data_source = Keyword.fetch!(session_config, :data_source)

    # Load strategy from database
    case Repo.get(Strategy, strategy_id) do
      nil ->
        {:stop, {:error, :strategy_not_found}}

      strategy_record ->
        strategy = strategy_record.definition

        # Initialize position tracker
        position_tracker =
          PositionTracker.init(
            initial_capital,
            position_sizing: Keyword.get(session_config, :position_sizing, :percentage),
            position_size_pct: Keyword.get(session_config, :position_size_pct, 0.1)
          )

        # Start indicator engine
        {:ok, indicator_engine} =
          RealtimeIndicatorEngine.start_link(
            strategy: strategy,
            symbol: trading_pair,
            timeframe: "1m"
          )

        # Subscribe to indicator updates
        RealtimeIndicatorEngine.subscribe(indicator_engine)

        # Start signal detector
        {:ok, signal_detector} =
          RealtimeSignalDetector.start_link(
            strategy: strategy,
            symbol: trading_pair
          )

        # Subscribe to signal notifications
        RealtimeSignalDetector.subscribe(signal_detector)

        state = %__MODULE__{
          session_id: session_id,
          strategy_id: strategy_id,
          strategy: strategy,
          trading_pair: trading_pair,
          data_source: data_source,
          status: :active,
          started_at: DateTime.utc_now(),
          position_tracker: position_tracker,
          indicator_engine: indicator_engine,
          signal_detector: signal_detector,
          trades: [],
          last_market_price: nil,
          last_update_at: nil,
          config: Map.new(session_config)
        }

        # Create session in database
        session_data = %{
          session_id: session_id,
          strategy_id: strategy_id,
          initial_capital: initial_capital,
          config: %{
            trading_pair: trading_pair,
            data_source: data_source,
            position_sizing: Keyword.get(session_config, :position_sizing, :percentage)
          }
        }

        case SessionPersister.create_session(session_data) do
          {:ok, _} ->
            # Schedule periodic persistence
            SessionPersister.schedule_periodic_persist(session_id, fn ->
              build_persist_state(state)
            end)

            # Subscribe to market data
            subscribe_to_market_data(trading_pair)

            # Try to load historical candles for initial indicators
            load_initial_candles(state)

            Logger.info(
              "[SessionManager] Started session #{session_id} for #{trading_pair} " <>
                "with capital=#{initial_capital}"
            )

            {:ok, state}

          {:error, reason} ->
            {:stop, {:error, reason}}
        end
    end
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    status = build_status_response(state)
    {:reply, {:ok, status}, state}
  end

  @impl true
  def handle_call(:pause, _from, state) do
    case state.status do
      :active ->
        # Unsubscribe from market data
        unsubscribe_from_market_data(state.trading_pair)

        new_state = %{state | status: :paused}

        # Persist state change
        persist_state(new_state)

        Logger.info("[SessionManager] Paused session #{state.session_id}")

        {:reply, :ok, new_state}

      :paused ->
        {:reply, {:error, :already_paused}, state}

      :stopped ->
        {:reply, {:error, :already_stopped}, state}
    end
  end

  @impl true
  def handle_call(:resume, _from, state) do
    case state.status do
      :paused ->
        # Resubscribe to market data
        subscribe_to_market_data(state.trading_pair)

        new_state = %{state | status: :active}

        # Persist state change
        persist_state(new_state)

        Logger.info("[SessionManager] Resumed session #{state.session_id}")

        {:reply, :ok, new_state}

      :active ->
        {:reply, {:error, :not_paused}, state}

      :stopped ->
        {:reply, {:error, :already_stopped}, state}
    end
  end

  @impl true
  def handle_call(:stop, _from, state) do
    case state.status do
      :stopped ->
        {:reply, {:error, :already_stopped}, state}

      _ ->
        # Close all open positions at current market price
        {new_state, closed_positions} = close_all_positions(state)

        # Mark as stopped
        final_state = %{new_state | status: :stopped}

        # Unsubscribe from market data
        unsubscribe_from_market_data(state.trading_pair)

        # Cancel periodic persistence
        SessionPersister.cancel_periodic_persist(state.session_id)

        # Persist final state
        final_state_data = build_persist_state(final_state)

        SessionPersister.stop_session(state.session_id, final_state_data)

        Logger.info(
          "[SessionManager] Stopped session #{state.session_id}, " <>
            "closed #{length(closed_positions)} positions"
        )

        # Build final results
        results = build_final_results(final_state)

        {:stop, :normal, {:ok, results}, final_state}
    end
  end

  @impl true
  def handle_call({:get_trades, opts}, _from, state) do
    limit = Keyword.get(opts, :limit, 100)
    offset = Keyword.get(opts, :offset, 0)

    trades =
      state.trades
      |> Enum.reverse()
      |> Enum.drop(offset)
      |> Enum.take(limit)

    {:reply, {:ok, trades}, state}
  end

  @impl true
  def handle_call(:get_metrics, _from, state) do
    metrics = calculate_metrics(state)
    {:reply, {:ok, metrics}, state}
  end

  @impl true
  def handle_info({:indicator_update, symbol, indicator_values}, state) do
    if state.status == :active and symbol == state.trading_pair do
      # Get current market data for evaluation
      case Cache.get_latest(symbol) do
        {:ok, {_timestamp, ticker_data}} ->
          current_bar = build_current_bar(ticker_data, symbol)

          # Evaluate signals with updated indicators
          case RealtimeSignalDetector.evaluate(
                 state.signal_detector,
                 indicator_values,
                 current_bar
               ) do
            {:ok, _signals} ->
              # Signal detector will notify us via :signal_detected if conditions met
              {:noreply, state}

            {:error, reason} ->
              Logger.warning("[SessionManager] Signal evaluation failed: #{inspect(reason)}")

              {:noreply, state}
          end

        {:error, :not_found} ->
          Logger.debug("[SessionManager] No market data available yet for #{symbol}")

          {:noreply, state}
      end
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:signal_detected, signal_type, signal_data}, state) do
    if state.status == :active do
      Logger.info(
        "[SessionManager] #{signal_type} signal detected for #{state.trading_pair} " <>
          "at price #{signal_data.price}"
      )

      # Execute trade based on signal
      new_state = execute_signal(state, signal_type, signal_data)

      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:market_data, symbol, market_data}, state) do
    if state.status == :active and symbol == state.trading_pair do
      # Update indicator engine with new price/candle
      price = extract_price(market_data)

      if price do
        RealtimeIndicatorEngine.update_price(state.indicator_engine, price)

        # Update position tracker with current prices
        new_tracker =
          PositionTracker.update_unrealized_pnl(state.position_tracker, %{
            symbol => price
          })

        new_state = %{
          state
          | position_tracker: new_tracker,
            last_market_price: price,
            last_update_at: DateTime.utc_now()
        }

        {:noreply, new_state}
      else
        {:noreply, state}
      end
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Private Functions

  defp via_tuple(session_id) do
    {:via, Registry, {TradingStrategy.PaperTrading.SessionRegistry, session_id}}
  end

  defp call_session(session_id, message) do
    case GenServer.whereis(via_tuple(session_id)) do
      nil -> {:error, :not_found}
      pid -> GenServer.call(pid, message)
    end
  end

  defp subscribe_to_market_data(symbol) do
    Phoenix.PubSub.subscribe(@pubsub, "ticker:#{symbol}")
    Phoenix.PubSub.subscribe(@pubsub, "market_data:#{symbol}")
    Logger.debug("[SessionManager] Subscribed to market data for #{symbol}")
  end

  defp unsubscribe_from_market_data(symbol) do
    Phoenix.PubSub.unsubscribe(@pubsub, "ticker:#{symbol}")
    Phoenix.PubSub.unsubscribe(@pubsub, "market_data:#{symbol}")
    Logger.debug("[SessionManager] Unsubscribed from market data for #{symbol}")
  end

  defp load_initial_candles(state) do
    # Try to load recent candles from cache
    candles = Cache.get_candles(state.trading_pair, "1m", 500)

    if length(candles) > 0 do
      RealtimeIndicatorEngine.preload_history(state.indicator_engine, candles)

      Logger.info(
        "[SessionManager] Preloaded #{length(candles)} candles for #{state.trading_pair}"
      )
    end
  end

  defp build_current_bar(ticker_data, symbol) do
    price = extract_price(ticker_data)

    %{
      symbol: symbol,
      timestamp: DateTime.utc_now(),
      open: price,
      high: price,
      low: price,
      close: price,
      volume: Map.get(ticker_data, :volume, 0.0)
    }
  end

  defp extract_price(market_data) when is_map(market_data) do
    cond do
      Map.has_key?(market_data, :price) -> market_data.price
      Map.has_key?(market_data, "price") -> market_data["price"]
      Map.has_key?(market_data, :close) -> market_data.close
      Map.has_key?(market_data, "close") -> market_data["close"]
      true -> nil
    end
    |> to_float()
  end

  defp extract_price(_), do: nil

  defp to_float(nil), do: nil
  defp to_float(value) when is_float(value), do: value
  defp to_float(value) when is_integer(value), do: value / 1.0
  defp to_float(value) when is_binary(value), do: String.to_float(value)
  defp to_float(%Decimal{} = d), do: Decimal.to_float(d)
  defp to_float(_), do: nil

  defp execute_signal(state, :entry, signal_data) do
    # Check if we already have open positions
    if PositionTracker.has_open_positions?(state.position_tracker) do
      Logger.info("[SessionManager] Ignoring entry signal, position already open")
      state
    else
      # Execute entry trade
      trade_params = %{
        symbol: state.trading_pair,
        side: :buy,
        quantity: calculate_entry_quantity(state, signal_data.price),
        signal_type: :entry
      }

      case PaperExecutor.execute_trade(
             trade_params,
             signal_data.price,
             session_id: state.session_id
           ) do
        {:ok, executed_trade} ->
          # Open position in tracker
          case PositionTracker.open_position(
                 state.position_tracker,
                 state.trading_pair,
                 :long,
                 executed_trade.net_price,
                 DateTime.utc_now(),
                 quantity: executed_trade.quantity
               ) do
            {:ok, new_tracker, _position} ->
              new_trades = [executed_trade | state.trades]

              %{state | position_tracker: new_tracker, trades: new_trades}

            {:error, reason} ->
              Logger.error("[SessionManager] Failed to open position: #{inspect(reason)}")

              state
          end

        {:error, reason} ->
          Logger.error("[SessionManager] Trade execution failed: #{inspect(reason)}")
          state
      end
    end
  end

  defp execute_signal(state, signal_type, signal_data)
       when signal_type in [:exit, :stop] do
    # Close all positions for this symbol
    open_positions = PositionTracker.get_open_positions(state.position_tracker)

    if Enum.empty?(open_positions) do
      Logger.info("[SessionManager] Ignoring #{signal_type} signal, no open positions")
      state
    else
      # Execute exit trades for all positions
      {new_tracker, executed_trades} =
        Enum.reduce(open_positions, {state.position_tracker, []}, fn position,
                                                                     {tracker_acc, trades_acc} ->
          trade_params = %{
            symbol: state.trading_pair,
            side: :sell,
            quantity: position.quantity,
            signal_type: signal_type
          }

          case PaperExecutor.execute_trade(
                 trade_params,
                 signal_data.price,
                 session_id: state.session_id
               ) do
            {:ok, executed_trade} ->
              # Close position in tracker
              case PositionTracker.close_position(
                     tracker_acc,
                     position.position_id,
                     executed_trade.net_price,
                     DateTime.utc_now()
                   ) do
                {:ok, updated_tracker, _closed_position} ->
                  {updated_tracker, [executed_trade | trades_acc]}

                {:error, _reason} ->
                  {tracker_acc, trades_acc}
              end

            {:error, _reason} ->
              {tracker_acc, trades_acc}
          end
        end)

      new_trades = Enum.reverse(executed_trades) ++ state.trades

      %{state | position_tracker: new_tracker, trades: new_trades}
    end
  end

  defp calculate_entry_quantity(state, _price) do
    # Position sizing is handled by PositionTracker
    # This is a placeholder that won't be used since we pass quantity: in options
    0.1
  end

  defp close_all_positions(state) do
    open_positions = PositionTracker.get_open_positions(state.position_tracker)

    if Enum.empty?(open_positions) do
      {state, []}
    else
      current_price = state.last_market_price || 0.0

      case PositionTracker.close_positions_for_symbol(
             state.position_tracker,
             state.trading_pair,
             current_price,
             DateTime.utc_now()
           ) do
        {:ok, new_tracker, closed_positions} ->
          {%{state | position_tracker: new_tracker}, closed_positions}

        {:error, _reason} ->
          {state, []}
      end
    end
  end

  defp build_status_response(state) do
    %{
      session_id: state.session_id,
      status: state.status,
      started_at: state.started_at,
      current_equity: PositionTracker.calculate_total_equity(state.position_tracker),
      unrealized_pnl: PositionTracker.get_total_unrealized_pnl(state.position_tracker),
      realized_pnl: PositionTracker.get_total_realized_pnl(state.position_tracker),
      open_positions: build_position_summaries(state),
      trades_count: length(state.trades),
      last_market_price: state.last_market_price,
      last_updated_at: state.last_update_at || state.started_at
    }
  end

  defp build_position_summaries(state) do
    open_positions = PositionTracker.get_open_positions(state.position_tracker)

    Enum.map(open_positions, fn position ->
      duration = DateTime.diff(DateTime.utc_now(), position.entry_timestamp, :second)

      %{
        trading_pair: position.symbol,
        side: position.side,
        entry_price: position.entry_price,
        quantity: position.quantity,
        current_price: state.last_market_price || position.entry_price,
        unrealized_pnl: position.unrealized_pnl,
        duration_seconds: duration
      }
    end)
  end

  defp build_persist_state(state) do
    %{
      status: state.status,
      current_capital: PositionTracker.calculate_total_equity(state.position_tracker),
      position_tracker: state.position_tracker,
      trades_count: length(state.trades),
      last_market_price: state.last_market_price,
      last_signal_timestamp: state.last_update_at
    }
  end

  defp persist_state(state) do
    state_data = build_persist_state(state)
    SessionPersister.update_session(state.session_id, state_data)
  end

  defp build_final_results(state) do
    %{
      session_id: state.session_id,
      duration_seconds: DateTime.diff(DateTime.utc_now(), state.started_at, :second),
      final_equity: PositionTracker.calculate_total_equity(state.position_tracker),
      total_return:
        PositionTracker.calculate_total_equity(state.position_tracker) -
          state.position_tracker.initial_capital,
      trades: Enum.reverse(state.trades),
      performance_metrics: calculate_metrics(state),
      max_drawdown_reached: 0.0
    }
  end

  defp calculate_metrics(state) do
    closed_positions = PositionTracker.get_closed_positions(state.position_tracker)

    winning_trades =
      Enum.filter(closed_positions, fn pos -> pos.realized_pnl > 0 end)

    losing_trades =
      Enum.filter(closed_positions, fn pos -> pos.realized_pnl <= 0 end)

    total_trades = length(closed_positions)

    %{
      total_trades: total_trades,
      winning_trades: length(winning_trades),
      losing_trades: length(losing_trades),
      win_rate: if(total_trades > 0, do: length(winning_trades) / total_trades, else: 0.0),
      total_return: PositionTracker.get_total_realized_pnl(state.position_tracker),
      avg_win:
        if(length(winning_trades) > 0,
          do:
            Enum.sum(Enum.map(winning_trades, & &1.realized_pnl)) /
              length(winning_trades),
          else: 0.0
        ),
      avg_loss:
        if(length(losing_trades) > 0,
          do:
            Enum.sum(Enum.map(losing_trades, & &1.realized_pnl)) /
              length(losing_trades),
          else: 0.0
        ),
      current_equity: PositionTracker.calculate_total_equity(state.position_tracker),
      initial_capital: state.position_tracker.initial_capital
    }
  end
end
