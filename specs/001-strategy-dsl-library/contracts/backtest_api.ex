# Backtesting API Contract
#
# This module defines the Elixir behaviour contract for backtesting operations.
# Covers FR-007 through FR-011 (Backtesting requirements)

defmodule TradingStrategy.Contracts.BacktestAPI do
  @moduledoc """
  Contract for executing backtests and calculating performance metrics.

  Backtests simulate strategy performance against historical market data (FR-007)
  with realistic trading costs (FR-011) and robust error handling (FR-009).
  """

  alias TradingStrategy.Contracts.StrategyAPI

  @type backtest_id :: String.t()
  @type strategy_id :: StrategyAPI.strategy_id()

  @type backtest_config :: %{
    strategy_id: strategy_id(),
    trading_pair: String.t(),
    start_date: DateTime.t(),
    end_date: DateTime.t(),
    initial_capital: Decimal.t(),
    position_sizing: atom(),  # :percentage | :fixed_amount
    commission_rate: Decimal.t(),  # e.g., 0.001 for 0.1%
    slippage_bps: integer(),  # Basis points (e.g., 5 = 0.05%)
    data_source: String.t()  # Exchange name
  }

  @type backtest_result :: %{
    backtest_id: backtest_id(),
    strategy_id: strategy_id(),
    config: backtest_config(),
    performance_metrics: performance_metrics(),
    trades: [trade_record()],
    equity_curve: [equity_snapshot()],
    started_at: DateTime.t(),
    completed_at: DateTime.t(),
    data_quality_warnings: [String.t()]
  }

  @type performance_metrics :: %{
    total_return: Decimal.t(),
    total_return_abs: Decimal.t(),
    win_rate: Decimal.t(),
    max_drawdown: Decimal.t(),
    sharpe_ratio: Decimal.t(),
    trade_count: integer(),
    winning_trades: integer(),
    losing_trades: integer(),
    average_trade_duration: integer(),  # Seconds
    max_consecutive_wins: integer(),
    max_consecutive_losses: integer(),
    average_win: Decimal.t(),
    average_loss: Decimal.t(),
    profit_factor: Decimal.t()
  }

  @type trade_record :: %{
    timestamp: DateTime.t(),
    side: :buy | :sell,
    price: Decimal.t(),
    quantity: Decimal.t(),
    fees: Decimal.t(),
    pnl: Decimal.t(),
    signal_type: :entry | :exit | :stop
  }

  @type equity_snapshot :: %{
    timestamp: DateTime.t(),
    equity: Decimal.t(),
    cash: Decimal.t(),
    positions_value: Decimal.t()
  }

  @type backtest_progress :: %{
    backtest_id: backtest_id(),
    status: :running | :completed | :failed,
    progress_percentage: integer(),  # 0-100
    bars_processed: integer(),
    total_bars: integer(),
    estimated_time_remaining_ms: integer() | nil,
    current_timestamp: DateTime.t() | nil
  }

  @doc """
  Starts a backtest for a given strategy and historical date range.

  Fetches historical OHLCV data (FR-007), applies strategy logic,
  and simulates trade execution with realistic costs (FR-011).

  ## Parameters
  - `config`: Backtest configuration map

  ## Returns
  - `{:ok, backtest_id}` with unique identifier for tracking progress
  - `{:error, :strategy_not_found}` if strategy_id invalid
  - `{:error, :insufficient_data}` if historical data unavailable
  - `{:error, :invalid_date_range}` if start_date >= end_date

  ## Examples
      iex> start_backtest(%{
        strategy_id: "550e8400-...",
        trading_pair: "BTC/USD",
        start_date: ~U[2023-01-01 00:00:00Z],
        end_date: ~U[2024-12-31 23:59:59Z],
        initial_capital: Decimal.new("10000"),
        commission_rate: Decimal.new("0.001"),
        slippage_bps: 5,
        data_source: "binance"
      })
      {:ok, "backtest_abc123"}

  ## Notes
  - Backtests run asynchronously in background process
  - Use `get_backtest_progress/1` to monitor execution
  - Results available via `get_backtest_result/1` when complete
  """
  @callback start_backtest(config :: backtest_config()) ::
    {:ok, backtest_id()} | {:error, :strategy_not_found | :insufficient_data | :invalid_date_range}

  @doc """
  Retrieves the current progress of a running backtest.

  Implements FR-009 requirement for progress tracking during backtesting.

  ## Parameters
  - `backtest_id`: UUID of the backtest

  ## Returns
  - `{:ok, progress}` with current status and progress percentage
  - `{:error, :not_found}` if backtest_id doesn't exist

  ## Examples
      iex> get_backtest_progress("backtest_abc123")
      {:ok, %{
        backtest_id: "backtest_abc123",
        status: :running,
        progress_percentage: 45,
        bars_processed: 6570,
        total_bars: 14600,
        estimated_time_remaining_ms: 12000,
        current_timestamp: ~U[2023-06-15 00:00:00Z]
      }}
  """
  @callback get_backtest_progress(backtest_id :: backtest_id()) ::
    {:ok, backtest_progress()} | {:error, :not_found}

  @doc """
  Retrieves the complete results of a finished backtest.

  Returns performance metrics (FR-008), trade history, and equity curve.

  ## Parameters
  - `backtest_id`: UUID of the backtest

  ## Returns
  - `{:ok, result}` with full backtest results
  - `{:error, :not_found}` if backtest_id doesn't exist
  - `{:error, :still_running}` if backtest hasn't completed

  ## Examples
      iex> get_backtest_result("backtest_abc123")
      {:ok, %{
        backtest_id: "backtest_abc123",
        performance_metrics: %{
          total_return: Decimal.new("0.342"),  # 34.2%
          sharpe_ratio: Decimal.new("1.8"),
          max_drawdown: Decimal.new("0.12"),
          win_rate: Decimal.new("0.58"),
          trade_count: 156,
          ...
        },
        trades: [...],
        equity_curve: [...],
        data_quality_warnings: [
          "Missing data for 2023-07-04 00:00:00 UTC (holiday)",
          "Volume spike detected on 2023-11-12 (possible outlier)"
        ]
      }}
  """
  @callback get_backtest_result(backtest_id :: backtest_id()) ::
    {:ok, backtest_result()} | {:error, :not_found | :still_running}

  @doc """
  Cancels a running backtest.

  ## Parameters
  - `backtest_id`: UUID of the backtest to cancel

  ## Returns
  - `:ok` if successfully cancelled
  - `{:error, :not_found}` if backtest doesn't exist
  - `{:error, :already_completed}` if backtest finished

  ## Notes
  - Partial results may be available via `get_backtest_result/1`
  - Cancelled backtests remain queryable for analysis
  """
  @callback cancel_backtest(backtest_id :: backtest_id()) ::
    :ok | {:error, :not_found | :already_completed}

  @doc """
  Lists all backtests, optionally filtered by strategy or status.

  ## Parameters
  - `opts`: Keyword list of filters
    - `strategy_id`: Filter by strategy UUID (optional)
    - `status`: `:running` | `:completed` | `:failed` (optional)
    - `limit`: Integer (default 50)
    - `offset`: Integer (default 0)
    - `order_by`: `:created_at` | `:completed_at` (default :created_at)

  ## Returns
  - `{:ok, [backtest_summary, ...]}` list of backtest summaries

  ## Examples
      iex> list_backtests(strategy_id: "550e8400-...", status: :completed, limit: 10)
      {:ok, [
        %{backtest_id: "abc", started_at: ~U[...], status: :completed},
        ...
      ]}
  """
  @callback list_backtests(opts :: keyword()) ::
    {:ok, [map()]}

  @doc """
  Calculates performance metrics for a set of trades.

  Implements FR-008 metric calculations (Sharpe ratio, max drawdown, etc.).

  ## Parameters
  - `trades`: List of trade records
  - `initial_capital`: Starting capital amount
  - `final_equity`: Ending equity value

  ## Returns
  - `{:ok, metrics}` with calculated performance metrics
  - `{:error, :insufficient_trades}` if < 2 trades (can't compute statistics)

  ## Notes
  - Sharpe ratio assumes risk-free rate = 0 for crypto
  - Max drawdown computed from equity curve
  - Win rate = winning_trades / total_trades
  """
  @callback calculate_metrics(
    trades :: [trade_record()],
    initial_capital :: Decimal.t(),
    final_equity :: Decimal.t()
  ) :: {:ok, performance_metrics()} | {:error, :insufficient_trades}

  @doc """
  Validates historical data quality before running backtest.

  Implements FR-009 requirement for graceful handling of missing/incomplete data.

  ## Parameters
  - `trading_pair`: Symbol to validate
  - `start_date`: Beginning of date range
  - `end_date`: End of date range
  - `timeframe`: Candlestick interval (e.g., "1h", "1d")
  - `data_source`: Exchange name

  ## Returns
  - `{:ok, quality_report}` with data completeness statistics
  - `{:error, :no_data_available}` if no data exists for range

  ## Example Return
      {:ok, %{
        total_bars_expected: 8760,  # Hours in year
        total_bars_available: 8650,
        missing_bars: 110,
        missing_bar_timestamps: [~U[2023-01-15 03:00:00Z], ...],
        completeness_percentage: Decimal.new("98.7"),
        quality_warnings: [
          "Data gap of 12 hours on 2023-01-15",
          "Volume = 0 for 5 bars (possible exchange downtime)"
        ]
      }}
  """
  @callback validate_data_quality(
    trading_pair :: String.t(),
    start_date :: DateTime.t(),
    end_date :: DateTime.t(),
    timeframe :: String.t(),
    data_source :: String.t()
  ) :: {:ok, map()} | {:error, :no_data_available}
end
