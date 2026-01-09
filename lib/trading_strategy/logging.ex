defmodule TradingStrategy.Logging do
  @moduledoc """
  Structured logging utilities for the Trading Strategy application.

  Provides consistent logging patterns with metadata for:
  - Correlation IDs
  - Trading decisions (signals, conditions, actions)
  - Error context
  - Performance tracking

  Follows Constitution Principle IV: Observability & Auditability
  FR-028: All trading decisions must be logged
  FR-030: Error handling must log context
  """

  require Logger

  @doc """
  Logs a trading signal detection with full context.

  ## Examples

      iex> log_signal_detected(:entry, "BTC/USD", "rsi_14 < 30", %{rsi_14: 28.5}, "strategy-123", "session-456")
      :ok
  """
  def log_signal_detected(
        signal_type,
        trading_pair,
        conditions_met,
        indicator_values,
        strategy_id,
        session_id
      ) do
    Logger.info("Signal detected",
      event: :signal_detected,
      signal_type: signal_type,
      trading_pair: trading_pair,
      conditions_met: conditions_met,
      indicator_values: indicator_values,
      strategy_id: strategy_id,
      session_id: session_id,
      timestamp: DateTime.utc_now()
    )
  end

  @doc """
  Logs order placement with correlation ID.
  """
  def log_order_placed(mode, trading_pair, side, order_type, quantity, price, metadata \\ %{}) do
    Logger.info("Order placed",
      event: :order_placed,
      mode: mode,
      trading_pair: trading_pair,
      side: side,
      order_type: order_type,
      quantity: to_string(quantity),
      price: to_string(price),
      correlation_id: Map.get(metadata, :correlation_id),
      strategy_id: Map.get(metadata, :strategy_id),
      session_id: Map.get(metadata, :session_id),
      exchange_order_id: Map.get(metadata, :exchange_order_id),
      timestamp: DateTime.utc_now()
    )
  end

  @doc """
  Logs order execution (fill) with slippage tracking.
  """
  def log_order_filled(order_id, expected_price, actual_price, slippage, metadata \\ %{}) do
    Logger.info("Order filled",
      event: :order_filled,
      order_id: order_id,
      expected_price: to_string(expected_price),
      actual_price: to_string(actual_price),
      slippage_bps: to_string(slippage),
      correlation_id: Map.get(metadata, :correlation_id),
      exchange_order_id: Map.get(metadata, :exchange_order_id),
      timestamp: DateTime.utc_now()
    )
  end

  @doc """
  Logs position open event.
  """
  def log_position_opened(position_id, trading_pair, side, entry_price, quantity, metadata \\ %{}) do
    Logger.info("Position opened",
      event: :position_opened,
      position_id: position_id,
      trading_pair: trading_pair,
      side: side,
      entry_price: to_string(entry_price),
      quantity: to_string(quantity),
      strategy_id: Map.get(metadata, :strategy_id),
      session_id: Map.get(metadata, :session_id),
      correlation_id: Map.get(metadata, :correlation_id),
      timestamp: DateTime.utc_now()
    )
  end

  @doc """
  Logs position close event with P&L.
  """
  def log_position_closed(position_id, exit_price, realized_pnl, duration_ms, metadata \\ %{}) do
    Logger.info("Position closed",
      event: :position_closed,
      position_id: position_id,
      exit_price: to_string(exit_price),
      realized_pnl: to_string(realized_pnl),
      duration_ms: duration_ms,
      strategy_id: Map.get(metadata, :strategy_id),
      session_id: Map.get(metadata, :session_id),
      correlation_id: Map.get(metadata, :correlation_id),
      timestamp: DateTime.utc_now()
    )
  end

  @doc """
  Logs risk limit enforcement event.
  """
  def log_risk_limit_hit(limit_type, current_value, limit_value, action_taken, metadata \\ %{}) do
    Logger.warning("Risk limit hit",
      event: :risk_limit_hit,
      limit_type: limit_type,
      current_value: to_string(current_value),
      limit_value: to_string(limit_value),
      action_taken: action_taken,
      strategy_id: Map.get(metadata, :strategy_id),
      session_id: Map.get(metadata, :session_id),
      timestamp: DateTime.utc_now()
    )
  end

  @doc """
  Logs emergency stop event with reason.
  """
  def log_emergency_stop(reason, positions_closed, metadata \\ %{}) do
    Logger.error("Emergency stop triggered",
      event: :emergency_stop,
      reason: reason,
      positions_closed: positions_closed,
      strategy_id: Map.get(metadata, :strategy_id),
      session_id: Map.get(metadata, :session_id),
      timestamp: DateTime.utc_now()
    )
  end

  @doc """
  Logs backtest start event.
  """
  def log_backtest_started(backtest_id, strategy_id, start_date, end_date, metadata \\ %{}) do
    Logger.info("Backtest started",
      event: :backtest_started,
      backtest_id: backtest_id,
      strategy_id: strategy_id,
      start_date: to_string(start_date),
      end_date: to_string(end_date),
      initial_capital: Map.get(metadata, :initial_capital),
      timestamp: DateTime.utc_now()
    )
  end

  @doc """
  Logs backtest completion with performance metrics.
  """
  def log_backtest_completed(backtest_id, status, duration_ms, metrics, metadata \\ %{}) do
    Logger.info("Backtest completed",
      event: :backtest_completed,
      backtest_id: backtest_id,
      status: status,
      duration_ms: duration_ms,
      total_return: Map.get(metrics, :total_return),
      sharpe_ratio: Map.get(metrics, :sharpe_ratio),
      max_drawdown: Map.get(metrics, :max_drawdown),
      win_rate: Map.get(metrics, :win_rate),
      trade_count: Map.get(metrics, :trade_count),
      timestamp: DateTime.utc_now()
    )
  end

  @doc """
  Logs paper trading session start.
  """
  def log_paper_session_started(session_id, strategy_id, initial_capital, metadata \\ %{}) do
    Logger.info("Paper trading session started",
      event: :paper_session_started,
      session_id: session_id,
      strategy_id: strategy_id,
      initial_capital: to_string(initial_capital),
      trading_pair: Map.get(metadata, :trading_pair),
      data_source: Map.get(metadata, :data_source),
      timestamp: DateTime.utc_now()
    )
  end

  @doc """
  Logs live trading session start.
  """
  def log_live_session_started(
        session_id,
        strategy_id,
        allocated_capital,
        exchange,
        metadata \\ %{}
      ) do
    Logger.info("Live trading session started",
      event: :live_session_started,
      session_id: session_id,
      strategy_id: strategy_id,
      allocated_capital: to_string(allocated_capital),
      exchange: exchange,
      trading_pair: Map.get(metadata, :trading_pair),
      timestamp: DateTime.utc_now()
    )
  end

  @doc """
  Logs market data stream connection event.
  """
  def log_stream_connected(source, trading_pair, stream_type, metadata \\ %{}) do
    Logger.info("Market data stream connected",
      event: :stream_connected,
      source: source,
      trading_pair: trading_pair,
      stream_type: stream_type,
      session_id: Map.get(metadata, :session_id),
      timestamp: DateTime.utc_now()
    )
  end

  @doc """
  Logs market data stream disconnection.
  """
  def log_stream_disconnected(source, trading_pair, reason, metadata \\ %{}) do
    Logger.warning("Market data stream disconnected",
      event: :stream_disconnected,
      source: source,
      trading_pair: trading_pair,
      reason: reason,
      session_id: Map.get(metadata, :session_id),
      reconnect_attempt: Map.get(metadata, :reconnect_attempt),
      timestamp: DateTime.utc_now()
    )
  end

  @doc """
  Logs exchange API error with retry context.
  """
  def log_exchange_error(exchange, endpoint, error_type, error_details, metadata \\ %{}) do
    Logger.error("Exchange API error",
      event: :exchange_error,
      exchange: exchange,
      endpoint: endpoint,
      error_type: error_type,
      error_details: error_details,
      retry_attempt: Map.get(metadata, :retry_attempt),
      will_retry: Map.get(metadata, :will_retry),
      backoff_ms: Map.get(metadata, :backoff_ms),
      correlation_id: Map.get(metadata, :correlation_id),
      timestamp: DateTime.utc_now()
    )
  end

  @doc """
  Logs rate limit hit event.
  """
  def log_rate_limit_hit(exchange, endpoint, queue_depth, metadata \\ %{}) do
    Logger.warning("Rate limit hit",
      event: :rate_limit_hit,
      exchange: exchange,
      endpoint: endpoint,
      queue_depth: queue_depth,
      backoff_ms: Map.get(metadata, :backoff_ms),
      timestamp: DateTime.utc_now()
    )
  end

  @doc """
  Logs circuit breaker state change.
  """
  def log_circuit_breaker_state_change(exchange, old_state, new_state, reason, metadata \\ %{}) do
    log_level = if new_state == :open, do: :error, else: :info

    Logger.log(log_level, "Circuit breaker state changed",
      event: :circuit_breaker_state_change,
      exchange: exchange,
      old_state: old_state,
      new_state: new_state,
      reason: reason,
      failure_count: Map.get(metadata, :failure_count),
      timestamp: DateTime.utc_now()
    )
  end

  @doc """
  Logs indicator calculation with performance tracking.
  """
  def log_indicator_calculated(indicator_type, period, calculation_time_ms, metadata \\ %{}) do
    Logger.debug("Indicator calculated",
      event: :indicator_calculated,
      indicator_type: indicator_type,
      period: period,
      calculation_time_ms: calculation_time_ms,
      cache_hit: Map.get(metadata, :cache_hit, false),
      data_points: Map.get(metadata, :data_points),
      timestamp: DateTime.utc_now()
    )
  end

  @doc """
  Logs strategy validation result.
  """
  def log_strategy_validation(strategy_id, validation_result, errors \\ []) do
    log_level = if validation_result == :ok, do: :info, else: :warning

    Logger.log(log_level, "Strategy validation",
      event: :strategy_validation,
      strategy_id: strategy_id,
      validation_result: validation_result,
      errors: errors,
      timestamp: DateTime.utc_now()
    )
  end

  @doc """
  Logs session state persistence event.
  """
  def log_session_snapshot_saved(session_id, mode, snapshot_size, metadata \\ %{}) do
    Logger.debug("Session snapshot saved",
      event: :session_snapshot_saved,
      session_id: session_id,
      mode: mode,
      snapshot_size_bytes: snapshot_size,
      positions_count: Map.get(metadata, :positions_count),
      timestamp: DateTime.utc_now()
    )
  end

  @doc """
  Logs critical error with full context.
  """
  def log_critical_error(module, function, error, stacktrace, metadata \\ %{}) do
    Logger.error("Critical error",
      event: :critical_error,
      module: module,
      function: function,
      error: inspect(error),
      stacktrace: inspect(stacktrace),
      correlation_id: Map.get(metadata, :correlation_id),
      session_id: Map.get(metadata, :session_id),
      strategy_id: Map.get(metadata, :strategy_id),
      timestamp: DateTime.utc_now()
    )
  end

  @doc """
  Generates a correlation ID for request tracing.
  """
  def generate_correlation_id do
    UUID.uuid4()
  end

  @doc """
  Adds correlation ID to Logger metadata for automatic inclusion in all logs.
  """
  def put_correlation_id(correlation_id) do
    Logger.metadata(correlation_id: correlation_id)
  end

  @doc """
  Executes a function with correlation ID context.
  """
  def with_correlation_id(fun) when is_function(fun, 0) do
    correlation_id = generate_correlation_id()
    put_correlation_id(correlation_id)

    try do
      fun.()
    after
      Logger.metadata(correlation_id: nil)
    end
  end

  @doc """
  Formats decimal values for logging.
  """
  def format_decimal(nil), do: nil
  def format_decimal(value) when is_binary(value), do: value

  def format_decimal(value) do
    if Decimal.is_decimal(value) do
      Decimal.to_string(value, :normal)
    else
      to_string(value)
    end
  end
end
