defmodule TradingStrategy.Telemetry do
  @moduledoc """
  Telemetry metrics configuration for the Trading Strategy application.

  Tracks key performance indicators including:
  - Order placement latency
  - Signal detection frequency
  - Backtest processing duration
  - Strategy execution performance
  - Database query times
  - Exchange API response times
  """

  use Supervisor
  import Telemetry.Metrics

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [
      # Telemetry poller for periodic measurements
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc """
  Returns telemetry metrics for monitoring.
  """
  def metrics do
    [
      # Phoenix Metrics
      summary("phoenix.endpoint.stop.duration",
        unit: {:native, :millisecond},
        tags: [:route]
      ),
      summary("phoenix.router_dispatch.stop.duration",
        unit: {:native, :millisecond},
        tags: [:route]
      ),

      # Database Metrics
      summary("trading_strategy.repo.query.total_time",
        unit: {:native, :millisecond},
        description: "Total time spent executing DB queries",
        tags: [:source, :command]
      ),
      counter("trading_strategy.repo.query.count",
        description: "Total number of DB queries executed",
        tags: [:source, :command]
      ),

      # Trading Strategy Metrics
      counter("trading_strategy.signal.detected.count",
        description: "Number of trading signals detected",
        tags: [:strategy_id, :signal_type, :trading_pair]
      ),
      summary("trading_strategy.signal.evaluation.duration",
        unit: {:native, :millisecond},
        description: "Time to evaluate strategy conditions",
        tags: [:strategy_id]
      ),
      distribution("trading_strategy.signal.evaluation.duration",
        unit: {:native, :millisecond},
        description: "Distribution of signal evaluation times",
        buckets: [10, 25, 50, 100, 250, 500],
        tags: [:strategy_id]
      ),

      # Order Execution Metrics
      counter("trading_strategy.order.placed.count",
        description: "Number of orders placed",
        tags: [:mode, :trading_pair, :side, :order_type]
      ),
      summary("trading_strategy.order.placement.latency",
        unit: {:native, :millisecond},
        description: "Time from signal to order placement",
        tags: [:mode, :exchange]
      ),
      distribution("trading_strategy.order.placement.latency",
        unit: {:native, :millisecond},
        description: "Distribution of order placement latencies",
        buckets: [10, 25, 50, 100, 250, 500, 1000],
        tags: [:mode, :exchange]
      ),
      summary("trading_strategy.order.slippage",
        unit: :native,
        description: "Price slippage on order execution",
        tags: [:mode, :trading_pair]
      ),

      # Backtest Metrics
      counter("trading_strategy.backtest.started.count",
        description: "Number of backtests started",
        tags: [:strategy_id]
      ),
      counter("trading_strategy.backtest.completed.count",
        description: "Number of backtests completed",
        tags: [:strategy_id, :status]
      ),
      summary("trading_strategy.backtest.duration",
        unit: {:native, :millisecond},
        description: "Total backtest processing time",
        tags: [:strategy_id]
      ),
      summary("trading_strategy.backtest.bars_processed",
        unit: :unit,
        description: "Number of bars processed in backtest",
        tags: [:strategy_id, :timeframe]
      ),

      # Paper Trading Metrics
      counter("trading_strategy.paper_trading.session.started.count",
        description: "Number of paper trading sessions started",
        tags: [:strategy_id]
      ),
      counter("trading_strategy.paper_trading.trade.executed.count",
        description: "Number of simulated trades executed",
        tags: [:strategy_id, :trading_pair]
      ),
      summary("trading_strategy.paper_trading.position.duration",
        unit: {:native, :millisecond},
        description: "Duration of positions held",
        tags: [:strategy_id, :trading_pair]
      ),

      # Live Trading Metrics
      counter("trading_strategy.live_trading.session.started.count",
        description: "Number of live trading sessions started",
        tags: [:strategy_id, :exchange]
      ),
      counter("trading_strategy.live_trading.trade.executed.count",
        description: "Number of real trades executed",
        tags: [:strategy_id, :trading_pair, :exchange]
      ),
      counter("trading_strategy.live_trading.risk_limit.hit.count",
        description: "Number of times risk limits prevented trades",
        tags: [:strategy_id, :limit_type]
      ),
      counter("trading_strategy.live_trading.emergency_stop.count",
        description: "Number of emergency stops triggered",
        tags: [:strategy_id, :reason]
      ),

      # Indicator Calculation Metrics
      summary("trading_strategy.indicator.calculation.duration",
        unit: {:native, :millisecond},
        description: "Time to calculate indicator values",
        tags: [:indicator_type, :period]
      ),
      counter("trading_strategy.indicator.cache.hit.count",
        description: "Number of indicator cache hits",
        tags: [:indicator_type]
      ),
      counter("trading_strategy.indicator.cache.miss.count",
        description: "Number of indicator cache misses",
        tags: [:indicator_type]
      ),

      # Market Data Metrics
      counter("trading_strategy.market_data.stream.received.count",
        description: "Number of market data updates received",
        tags: [:source, :trading_pair, :data_type]
      ),
      summary("trading_strategy.market_data.stream.latency",
        unit: {:native, :millisecond},
        description: "Latency from exchange timestamp to processing",
        tags: [:source, :trading_pair]
      ),
      counter("trading_strategy.market_data.stream.reconnect.count",
        description: "Number of stream reconnections",
        tags: [:source, :trading_pair, :reason]
      ),

      # Exchange API Metrics
      summary("trading_strategy.exchange.api.request.duration",
        unit: {:native, :millisecond},
        description: "Exchange API request duration",
        tags: [:exchange, :endpoint, :method]
      ),
      counter("trading_strategy.exchange.api.error.count",
        description: "Number of exchange API errors",
        tags: [:exchange, :endpoint, :error_type]
      ),
      counter("trading_strategy.exchange.rate_limit.hit.count",
        description: "Number of times rate limits were hit",
        tags: [:exchange, :endpoint]
      ),
      summary("trading_strategy.exchange.circuit_breaker.open.duration",
        unit: {:native, :millisecond},
        description: "Duration circuit breaker stayed open",
        tags: [:exchange]
      ),

      # VM Metrics
      summary("vm.memory.total", unit: {:byte, :megabyte}),
      summary("vm.total_run_queue_lengths.total"),
      summary("vm.total_run_queue_lengths.cpu"),
      summary("vm.total_run_queue_lengths.io")
    ]
  end

  defp periodic_measurements do
    [
      # A module, function and arguments to be invoked periodically.
      # This function must call :telemetry.execute/3 and a metric must be added above.
      # {TradingStrategyWeb, :count_users, []}
    ]
  end

  @doc """
  Emits a telemetry event for signal detection.
  """
  def signal_detected(strategy_id, signal_type, trading_pair, metadata \\ %{}) do
    :telemetry.execute(
      [:trading_strategy, :signal, :detected],
      %{count: 1},
      Map.merge(metadata, %{
        strategy_id: strategy_id,
        signal_type: signal_type,
        trading_pair: trading_pair
      })
    )
  end

  @doc """
  Measures the duration of signal evaluation.
  """
  def measure_signal_evaluation(strategy_id, fun) when is_function(fun, 0) do
    start_time = System.monotonic_time()
    result = fun.()
    duration = System.monotonic_time() - start_time

    :telemetry.execute(
      [:trading_strategy, :signal, :evaluation],
      %{duration: duration},
      %{strategy_id: strategy_id}
    )

    result
  end

  @doc """
  Emits a telemetry event for order placement.
  """
  def order_placed(mode, trading_pair, side, order_type, latency_ms, metadata \\ %{}) do
    :telemetry.execute(
      [:trading_strategy, :order, :placed],
      %{count: 1, latency: latency_ms * 1_000_000},
      Map.merge(metadata, %{
        mode: mode,
        trading_pair: trading_pair,
        side: side,
        order_type: order_type
      })
    )
  end

  @doc """
  Emits a telemetry event for backtest completion.
  """
  def backtest_completed(strategy_id, status, duration_ms, bars_processed, metadata \\ %{}) do
    :telemetry.execute(
      [:trading_strategy, :backtest, :completed],
      %{count: 1, duration: duration_ms * 1_000_000, bars_processed: bars_processed},
      Map.merge(metadata, %{strategy_id: strategy_id, status: status})
    )
  end

  @doc """
  Emits a telemetry event for risk limit being hit.
  """
  def risk_limit_hit(strategy_id, limit_type, metadata \\ %{}) do
    :telemetry.execute(
      [:trading_strategy, :live_trading, :risk_limit, :hit],
      %{count: 1},
      Map.merge(metadata, %{strategy_id: strategy_id, limit_type: limit_type})
    )
  end

  @doc """
  Emits a telemetry event for emergency stop.
  """
  def emergency_stop(strategy_id, reason, metadata \\ %{}) do
    :telemetry.execute(
      [:trading_strategy, :live_trading, :emergency_stop],
      %{count: 1},
      Map.merge(metadata, %{strategy_id: strategy_id, reason: reason})
    )
  end

  @doc """
  Measures the duration of indicator calculation.
  """
  def measure_indicator_calculation(indicator_type, period, fun) when is_function(fun, 0) do
    start_time = System.monotonic_time()
    result = fun.()
    duration = System.monotonic_time() - start_time

    :telemetry.execute(
      [:trading_strategy, :indicator, :calculation],
      %{duration: duration},
      %{indicator_type: indicator_type, period: period}
    )

    result
  end

  @doc """
  Emits telemetry event for market data stream received.
  """
  def market_data_received(source, trading_pair, data_type, latency_ms, metadata \\ %{}) do
    :telemetry.execute(
      [:trading_strategy, :market_data, :stream, :received],
      %{count: 1, latency: latency_ms * 1_000_000},
      Map.merge(metadata, %{
        source: source,
        trading_pair: trading_pair,
        data_type: data_type
      })
    )
  end
end
