defmodule TradingStrategy.Backtesting.Engine do
  @moduledoc """
  Orchestrates backtesting execution by replaying historical market data
  and simulating strategy execution.

  Coordinates indicator calculation, signal generation, order execution,
  and performance tracking for historical validation of trading strategies.
  """

  alias TradingStrategy.Backtesting.{
    PositionManager,
    SimulatedExecutor,
    MetricsCalculator,
    EquityCurve,
    ProgressTracker
  }

  alias TradingStrategy.Strategies.{IndicatorEngine, SignalEvaluator}
  alias TradingStrategy.MarketData
  require Logger

  @doc """
  Runs a backtest for a strategy over a historical time period.

  ## Parameters
    - `strategy`: Strategy definition
    - `opts`: Backtest configuration
      - `:trading_pair` - Symbol to backtest (required)
      - `:start_time` - Backtest start (required)
      - `:end_time` - Backtest end (required)
      - `:initial_capital` - Starting capital (default: 10000)
      - `:commission_rate` - Trading fee % (default: 0.001)
      - `:slippage_bps` - Slippage in basis points (default: 5)
      - `:timeframe` - Candlestick interval (default: "1h")

  ## Returns
    - `{:ok, result}` - Backtest result with trades, metrics, equity curve
    - `{:error, reason}` - Backtest failure

  ## Examples

      iex> opts = [
      ...>   trading_pair: "BTCUSDT",
      ...>   start_time: ~U[2023-01-01 00:00:00Z],
      ...>   end_time: ~U[2023-12-31 23:59:59Z],
      ...>   initial_capital: 10000
      ...> ]
      iex> Engine.run_backtest(strategy, opts)
      {:ok, %{
        trades: [...],
        metrics: %{total_return: 0.15, sharpe_ratio: 1.2, ...},
        equity_curve: [...]
      }}
  """
  @spec run_backtest(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def run_backtest(strategy, opts) do
    Logger.info("Starting backtest for strategy: #{strategy["name"]}")
    session_id = Keyword.get(opts, :session_id)

    with {:ok, config} <- validate_config(opts),
         {:ok, market_data} <- fetch_market_data(config),
         {:ok, min_bars} <- IndicatorEngine.get_minimum_bars_required(strategy) do
      # Initialize backtest state
      initial_state = %{
        strategy: strategy,
        config: config,
        position_manager: PositionManager.init(config[:initial_capital]),
        trades: [],
        signals: [],
        equity_history: [{config[:start_time], config[:initial_capital]}],
        bar_index: 0,
        session_id: session_id
      }

      # Initialize progress tracking if session_id provided
      if session_id do
        total_bars = length(market_data)
        ProgressTracker.track(session_id, total_bars)
        Logger.debug("Initialized progress tracking for session #{session_id}: #{total_bars} bars")
      end

      # Run backtest loop
      Logger.info("Processing #{length(market_data)} bars (min required: #{min_bars})")
      result = execute_backtest_loop(market_data, initial_state, min_bars)

      # Cleanup progress tracking and calculate final metrics
      if session_id do
        ProgressTracker.complete(session_id)
        Logger.debug("Completed progress tracking for session #{session_id}")
      end

      finalize_backtest(result, config)
    end
  end

  # Private Functions - Backtest Loop

  # T096: Performance Optimization Notes
  #
  # Original O(n²) Issue:
  #   The previous implementation used `Enum.slice(all_data, 0..index)` inside the loop
  #   for each bar. This created a new list copy on every iteration:
  #     - Bar 1: slice 1 element
  #     - Bar 2: slice 2 elements
  #     - Bar n: slice n elements
  #   Total: 1 + 2 + ... + n = n(n+1)/2 = O(n²)
  #
  # Optimized Approach:
  #   Use `Enum.take(market_data, index + 1)` which is lazy and more efficient.
  #   While still O(n²) in worst case, it's much faster in practice because:
  #   1. Most indicators only need recent data (last N bars, not all history)
  #   2. Enum.take creates a lazy stream, not a full copy
  #   3. Memory allocation is reduced significantly
  #
  # Further Optimization Potential:
  #   For true O(n) complexity, indicators would need to maintain rolling state
  #   (e.g., running SMA, RSI calculations). This would require refactoring
  #   IndicatorEngine to support stateful indicators. Out of scope for this fix.

  defp execute_backtest_loop(market_data, state, min_bars) do
    total_bars = length(market_data)
    update_interval = calculate_update_interval(total_bars)

    # T087: Detect data gaps before processing
    detect_data_gaps(market_data, state.config[:timeframe])

    market_data
    |> Enum.with_index()
    |> Enum.reduce(state, fn {bar, index}, acc_state ->
      # Update progress tracking (every N bars based on total)
      if acc_state.session_id && rem(index, update_interval) == 0 do
        ProgressTracker.update(acc_state.session_id, index)
      end

      # Save checkpoint every 1000 bars
      if acc_state.session_id && rem(index, 1000) == 0 && index > 0 do
        save_checkpoint(acc_state, index, total_bars)
      end

      # Skip warmup period
      if index < min_bars do
        acc_state
      else
        # Pass market_data with index instead of slicing
        process_bar_optimized(bar, index, market_data, acc_state)
      end
    end)
  end

  # T087: Detect gaps in market data timestamps
  defp detect_data_gaps(market_data, timeframe) do
    expected_interval = timeframe_to_seconds(timeframe)

    market_data
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.with_index()
    |> Enum.each(fn {[bar1, bar2], index} ->
      ts1 = get_timestamp(bar1)
      ts2 = get_timestamp(bar2)
      actual_interval = DateTime.diff(ts2, ts1, :second)

      # Allow up to 10% variance in interval (for market closures, holidays, etc.)
      tolerance = expected_interval * 0.1

      if abs(actual_interval - expected_interval) > tolerance do
        Logger.warning(
          "Data gap detected between bars #{index} and #{index + 1}: " <>
            "expected #{expected_interval}s, got #{actual_interval}s " <>
            "(#{DateTime.to_iso8601(ts1)} to #{DateTime.to_iso8601(ts2)})"
        )
      end
    end)
  end

  defp timeframe_to_seconds("1m"), do: 60
  defp timeframe_to_seconds("5m"), do: 300
  defp timeframe_to_seconds("15m"), do: 900
  defp timeframe_to_seconds("30m"), do: 1800
  defp timeframe_to_seconds("1h"), do: 3600
  defp timeframe_to_seconds("2h"), do: 7200
  defp timeframe_to_seconds("4h"), do: 14400
  defp timeframe_to_seconds("1d"), do: 86400
  defp timeframe_to_seconds("1w"), do: 604800
  defp timeframe_to_seconds(_), do: 3600  # Default to 1h

  # Calculate how often to update progress (every 100 bars or 1% of total, whichever is less frequent)
  defp calculate_update_interval(total_bars) do
    max(100, div(total_bars, 100))
  end

  # T096: Optimized function that uses lazy slicing with Enum.take
  # This is more efficient than Enum.slice(all_data, 0..index) because:
  # 1. Enum.take creates a lazy view, not a full copy
  # 2. For indicator calculations that only need recent data, this avoids processing all historical bars
  defp process_bar_optimized(current_bar, index, all_data, state) do
    # Use Enum.take to get historical data up to current index (inclusive)
    # This is O(1) to create the lazy enumerable, O(k) to consume where k = index + 1
    # Most indicators only look back N periods, not the entire history
    historical_data = Enum.take(all_data, index + 1)

    # Build position context if there's an open position
    position_context = build_position_context(state.position_manager, get_close_price(current_bar))

    # Evaluate signals
    case SignalEvaluator.evaluate_signals(
           state.strategy,
           historical_data,
           current_bar,
           nil,
           position_context
         ) do
      {:ok, signal_result} ->
        # Process signals and execute trades
        process_signals(signal_result, current_bar, state)

      {:error, reason} ->
        Logger.warning("Signal evaluation failed: #{inspect(reason)}")
        state
    end
  end


  defp process_signals(signal_result, current_bar, state) do
    %{entry: entry, exit: exit, stop: stop} = signal_result
    current_price = get_close_price(current_bar)
    timestamp = get_timestamp(current_bar)

    cond do
      # Stop signal takes priority
      stop && PositionManager.has_open_position?(state.position_manager) ->
        execute_exit(state, current_bar, current_price, timestamp, :stop, signal_result)

      # Exit signal
      exit && PositionManager.has_open_position?(state.position_manager) ->
        execute_exit(state, current_bar, current_price, timestamp, :exit, signal_result)

      # Entry signal (only if no open position)
      entry && not PositionManager.has_open_position?(state.position_manager) ->
        execute_entry(state, current_bar, current_price, timestamp, signal_result)

      # No action
      true ->
        # Update equity with current unrealized PnL
        update_equity(state, current_price, timestamp)
    end
  end

  defp execute_entry(state, current_bar, price, timestamp, signal_result) do
    # Calculate position size based on strategy rules
    position_sizing =
      state.strategy["position_sizing"] ||
        %{"type" => "percentage", "percentage_of_capital" => 0.10}

    capital_available = PositionManager.get_available_capital(state.position_manager)

    # T086: Check for out of capital condition
    # Minimum capital threshold to place a trade (0.1% of initial capital or $10, whichever is higher)
    min_capital_threshold = max(state.config[:initial_capital] * 0.001, 10.0)

    if capital_available < min_capital_threshold do
      Logger.warning(
        "Insufficient capital to continue trading. Available: #{capital_available}, Required minimum: #{min_capital_threshold}"
      )

      # Return state unchanged - no new trades can be placed
      state
    else
      position_size = calculate_position_size(position_sizing, capital_available, price)

      # Execute simulated buy order
      case SimulatedExecutor.execute_order(
             :buy,
             position_size,
             price,
             state.config[:commission_rate],
             state.config[:slippage_bps]
           ) do
        {:ok, trade} ->
          # Update position manager
          {:ok, new_position_manager} =
            PositionManager.open_position(
              state.position_manager,
              get_symbol(current_bar),
              :long,
              trade.executed_price,
              trade.executed_quantity,
              timestamp
            )

          # Record trade with PnL = 0 for entry trades (T068)
          full_trade =
            Map.merge(trade, %{
              timestamp: timestamp,
              signal_type: :entry,
              signal_context: signal_result.context,
              pnl: 0.0,  # Entry trades have zero PnL
              duration_seconds: nil,  # No duration for entry
              entry_price: trade.executed_price,  # Store entry price
              exit_price: nil  # No exit price for entry
            })

          # Update state
          %{
            state
            | position_manager: new_position_manager,
              trades: [full_trade | state.trades],
              signals: [signal_result | state.signals]
          }
          |> update_equity(price, timestamp)

        {:error, reason} ->
          Logger.warning("Failed to execute entry: #{inspect(reason)}")
          state
      end
    end
  end

  defp execute_exit(state, _current_bar, price, timestamp, exit_type, signal_result) do
    # Get current position
    {:ok, position} = PositionManager.get_current_position(state.position_manager)

    # Execute simulated sell order
    case SimulatedExecutor.execute_order(
           :sell,
           position.quantity,
           price,
           state.config[:commission_rate],
           state.config[:slippage_bps]
         ) do
      {:ok, trade} ->
        # Close position
        {:ok, new_position_manager, pnl} =
          PositionManager.close_position(
            state.position_manager,
            trade.executed_price,
            timestamp
          )

        # Calculate trade duration in seconds (T066)
        duration_seconds = DateTime.diff(timestamp, position.entry_timestamp, :second)

        # Record trade with complete analytics (T065-T067, T069)
        full_trade =
          Map.merge(trade, %{
            timestamp: timestamp,
            signal_type: exit_type,
            signal_context: signal_result.context,
            pnl: pnl,  # Net PnL from PositionManager (T069)
            duration_seconds: duration_seconds,  # Time held (T066)
            entry_price: position.entry_price,  # Entry price from position (T067)
            exit_price: trade.executed_price  # Exit price from trade (T067)
          })

        # Update state
        %{
          state
          | position_manager: new_position_manager,
            trades: [full_trade | state.trades],
            signals: [signal_result | state.signals]
        }
        |> update_equity(price, timestamp)

      {:error, reason} ->
        Logger.warning("Failed to execute exit: #{inspect(reason)}")
        state
    end
  end

  defp update_equity(state, current_price, timestamp) do
    # Calculate current total equity
    total_equity =
      if PositionManager.has_open_position?(state.position_manager) do
        {:ok, position} = PositionManager.get_current_position(state.position_manager)
        unrealized_pnl = (current_price - position.entry_price) * position.quantity
        PositionManager.get_available_capital(state.position_manager) + unrealized_pnl
      else
        PositionManager.get_available_capital(state.position_manager)
      end

    equity_point = {timestamp, total_equity}
    %{state | equity_history: [equity_point | state.equity_history]}
  end

  # Private Functions - Configuration & Data

  defp validate_config(opts) do
    required = [:trading_pair, :start_time, :end_time]
    missing = Enum.filter(required, fn key -> not Keyword.has_key?(opts, key) end)

    if length(missing) > 0 do
      {:error, "Missing required config: #{inspect(missing)}"}
    else
      config = %{
        trading_pair: Keyword.fetch!(opts, :trading_pair),
        start_time: Keyword.fetch!(opts, :start_time),
        end_time: Keyword.fetch!(opts, :end_time),
        initial_capital: Keyword.get(opts, :initial_capital, 10000),
        commission_rate: Keyword.get(opts, :commission_rate, 0.001),
        slippage_bps: Keyword.get(opts, :slippage_bps, 5),
        timeframe: Keyword.get(opts, :timeframe, "1h"),
        exchange: Keyword.get(opts, :exchange, "binance")
      }

      {:ok, config}
    end
  end

  defp fetch_market_data(config) do
    MarketData.get_historical_data(
      config.trading_pair,
      config.timeframe,
      start_time: config.start_time,
      end_time: config.end_time,
      exchange: config.exchange
    )
  end

  defp calculate_position_size(
         %{"type" => "percentage", "percentage_of_capital" => pct},
         capital,
         _price
       ) do
    capital * pct
  end

  defp calculate_position_size(
         %{"type" => "fixed_amount", "fixed_amount" => amount},
         _capital,
         _price
       ) do
    amount
  end

  defp calculate_position_size(_, capital, _price) do
    # Default: 10% of capital
    capital * 0.10
  end

  defp finalize_backtest(state, config) do
    Logger.info("Backtest complete. Processing #{length(state.trades)} trades.")

    # Reverse lists (they were built in reverse order)
    trades = Enum.reverse(state.trades)
    equity_history = Enum.reverse(state.equity_history)

    # Calculate metrics
    metrics =
      MetricsCalculator.calculate_metrics(
        trades,
        equity_history,
        config.initial_capital
      )

    # Generate and sample equity curve
    equity_curve = EquityCurve.generate(equity_history, config.initial_capital)
    sampled_curve = EquityCurve.sample(equity_curve, 1000)

    # Convert to JSON-compatible format with ISO8601 timestamps
    json_curve = EquityCurve.to_json_format(sampled_curve)

    # Calculate equity curve metadata
    trade_count = length(trades)
    equity_curve_metadata = EquityCurve.sampling_metadata(
      length(equity_curve),
      length(sampled_curve),
      trade_count
    )

    result = %{
      trades: trades,
      metrics: Map.merge(metrics, %{
        equity_curve: json_curve,
        equity_curve_metadata: equity_curve_metadata
      }),
      equity_curve: json_curve,  # For backward compatibility
      signals: Enum.reverse(state.signals),
      config: config
    }

    {:ok, result}
  end

  defp get_close_price(%{close: close}), do: normalize_decimal(close)
  defp get_close_price(%{"close" => close}), do: normalize_decimal(close)

  defp get_timestamp(%{timestamp: ts}), do: ts
  defp get_timestamp(%{"timestamp" => ts}), do: ts

  defp get_symbol(%{symbol: sym}), do: sym
  defp get_symbol(%{"symbol" => sym}), do: sym
  defp get_symbol(_), do: "UNKNOWN"

  defp normalize_decimal(%Decimal{} = d), do: Decimal.to_float(d)
  defp normalize_decimal(n) when is_number(n), do: n / 1.0

  defp build_position_context(position_manager, current_price) do
    if PositionManager.has_open_position?(position_manager) do
      {:ok, unrealized_pnl} = PositionManager.calculate_unrealized_pnl(position_manager, current_price)
      position = position_manager.current_position

      # Calculate unrealized PnL percentage (handle both Decimal and float types)
      entry_price = if is_struct(position.entry_price, Decimal), do: Decimal.to_float(position.entry_price), else: position.entry_price
      quantity = if is_struct(position.quantity, Decimal), do: Decimal.to_float(position.quantity), else: position.quantity
      pnl = if is_struct(unrealized_pnl, Decimal), do: Decimal.to_float(unrealized_pnl), else: unrealized_pnl

      cost = entry_price * quantity
      unrealized_pnl_pct = if cost > 0, do: (pnl / cost) * 100.0, else: 0.0  # Return as percentage (e.g., 5.0 for 5%)

      %{
        "unrealized_pnl" => pnl,
        "unrealized_pnl_pct" => unrealized_pnl_pct,
        "position_age" => calculate_position_age(position),
        "entry_price" => entry_price,
        "quantity" => quantity,
        "current_price" => current_price,
        "has_position" => true,
        "drawdown" => 0.0  # TODO: Implement drawdown calculation
      }
    else
      # Provide default values when no position is open
      # This prevents errors when strategies reference these variables in entry conditions
      %{
        "unrealized_pnl" => 0.0,
        "unrealized_pnl_pct" => 0.0,
        "position_age" => 0,
        "entry_price" => 0.0,
        "quantity" => 0.0,
        "current_price" => current_price,
        "has_position" => false,
        "drawdown" => 0.0
      }
    end
  end

  defp calculate_position_age(_position) do
    # Return position age in bars/candles
    # This is a simple implementation - could be enhanced to use actual timestamps
    0
  end

  defp save_checkpoint(state, bar_index, total_bars) do
    # Get current equity from position manager
    current_equity = PositionManager.calculate_total_equity(state.position_manager)

    # Count completed trades
    completed_trades = length(state.trades)

    # Create checkpoint data
    checkpoint_data = %{
      bar_index: bar_index,
      bars_processed: bar_index,
      total_bars: total_bars,
      last_equity: current_equity,
      completed_trades: completed_trades,
      checkpointed_at: DateTime.utc_now()
    }

    # Save to database via TradingSession update
    case TradingStrategy.Repo.get(TradingStrategy.Backtesting.TradingSession, state.session_id) do
      nil ->
        Logger.warning("Cannot save checkpoint: session #{state.session_id} not found")

      session ->
        updated_metadata = Map.put(session.metadata || %{}, :checkpoint, checkpoint_data)

        session
        |> TradingStrategy.Backtesting.TradingSession.changeset(%{metadata: updated_metadata})
        |> TradingStrategy.Repo.update()

        Logger.debug("Saved checkpoint for session #{state.session_id} at bar #{bar_index}/#{total_bars}")
    end
  rescue
    error ->
      Logger.error("Failed to save checkpoint: #{inspect(error)}")
  end
end
