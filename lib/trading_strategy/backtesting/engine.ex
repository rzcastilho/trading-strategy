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
    EquityCurve
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
        bar_index: 0
      }

      # Run backtest loop
      Logger.info("Processing #{length(market_data)} bars (min required: #{min_bars})")
      result = execute_backtest_loop(market_data, initial_state, min_bars)

      # Calculate final metrics
      finalize_backtest(result, config)
    end
  end

  # Private Functions - Backtest Loop

  defp execute_backtest_loop(market_data, state, min_bars) do
    market_data
    |> Enum.with_index()
    |> Enum.reduce(state, fn {bar, index}, acc_state ->
      # Skip warmup period
      if index < min_bars do
        acc_state
      else
        process_bar(bar, index, market_data, acc_state)
      end
    end)
  end

  defp process_bar(current_bar, index, all_data, state) do
    # Get historical data up to current bar for indicator calculation
    historical_data = Enum.slice(all_data, 0..index)

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
        Logger.warning("Signal evaluation failed at bar #{index}: #{inspect(reason)}")
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

        # Record trade
        full_trade =
          Map.merge(trade, %{
            timestamp: timestamp,
            signal_type: :entry,
            signal_context: signal_result.context
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

  defp execute_exit(state, current_bar, price, timestamp, exit_type, signal_result) do
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

        # Record trade
        full_trade =
          Map.merge(trade, %{
            timestamp: timestamp,
            signal_type: exit_type,
            signal_context: signal_result.context,
            pnl: pnl
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

    # Generate equity curve
    equity_curve = EquityCurve.generate(equity_history)

    result = %{
      trades: trades,
      metrics: metrics,
      equity_curve: equity_curve,
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

      # Calculate unrealized PnL percentage
      cost = position.entry_price * position.quantity
      unrealized_pnl_pct = if cost > 0, do: unrealized_pnl / cost, else: 0.0

      %{
        "unrealized_pnl" => unrealized_pnl,
        "unrealized_pnl_pct" => unrealized_pnl_pct,
        "position_age" => calculate_position_age(position),
        "drawdown" => 0.0  # TODO: Implement drawdown calculation
      }
    else
      %{}
    end
  end

  defp calculate_position_age(position) do
    # Return position age in bars/candles
    # This is a simple implementation - could be enhanced to use actual timestamps
    0
  end
end
