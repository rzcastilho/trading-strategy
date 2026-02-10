defmodule TradingStrategy.Backtesting do
  @moduledoc """
  Context module for backtesting operations.

  Implements the BacktestAPI contract for running backtests,
  tracking progress, and retrieving results.
  """

  @behaviour TradingStrategy.Contracts.BacktestAPI

  alias TradingStrategy.Backtesting.Engine
  alias TradingStrategy.{Strategies, MarketData, Repo}
  alias TradingStrategy.Backtesting.{TradingSession, ProgressTracker, ConcurrencyManager, Supervisor}
  require Logger

  import Ecto.Query

  @doc """
  Creates a backtest session without starting it.

  ## Examples

      iex> config = %{
      ...>   strategy_id: "550e8400-...",
      ...>   trading_pair: "BTC/USD",
      ...>   start_time: ~U[2023-01-01 00:00:00Z],
      ...>   end_time: ~U[2024-12-31 23:59:59Z],
      ...>   initial_capital: Decimal.new("10000"),
      ...>   timeframe: "1h"
      ...> }
      iex> create_backtest(config)
      {:ok, session}
  """
  def create_backtest(config) do
    with {:ok, strategy} <- load_strategy(config.strategy_id),
         :ok <- validate_date_range(config.start_time, config.end_time) do
      # Create backtest session record in pending state
      session_params = %{
        strategy_id: config.strategy_id,
        mode: "backtest",
        status: "pending",
        initial_capital: config.initial_capital,
        current_capital: config.initial_capital,
        config: %{
          trading_pair: config.trading_pair,
          start_time: config.start_time,
          end_time: config.end_time,
          initial_capital: config.initial_capital,
          timeframe: Map.get(config, :timeframe, "1h"),
          commission_rate: Map.get(config, :commission_rate, Decimal.new("0.001")),
          slippage_bps: Map.get(config, :slippage_bps, 5)
        },
        metadata: %{}
      }

      %TradingSession{}
      |> TradingSession.changeset(session_params)
      |> Repo.insert()
    else
      {:error, :strategy_not_found} -> {:error, :strategy_not_found}
      {:error, :invalid_date_range} -> {:error, :invalid_date_range}
      error -> error
    end
  end

  @doc """
  Starts a backtest session by requesting a concurrency slot.
  If no slot is available, the session is queued.

  ## Parameters
    - session_id: UUID of the trading session to start

  ## Returns
    - `{:ok, session}` with updated status (running or queued)
    - `{:error, reason}` if session not found or cannot be started
  """
  def start_backtest(session_id) when is_binary(session_id) do
    case Repo.get(TradingSession, session_id) do
      nil ->
        {:error, :not_found}

      %{status: "running"} = session ->
        {:ok, session}

      %{status: "queued"} = session ->
        {:ok, session}

      session ->
        # Request concurrency slot
        case ConcurrencyManager.request_slot(session_id) do
          {:ok, :granted} ->
            # Slot available - start backtest immediately
            session = session
              |> TradingSession.changeset(%{
                status: "running",
                started_at: DateTime.utc_now()
              })
              |> Repo.update!()

            # Launch backtest via supervisor
            launch_backtest_task(session)

            {:ok, session}

          {:ok, {:queued, position}} ->
            # No slot available - queue the backtest
            session = session
              |> TradingSession.changeset(%{
                status: "queued",
                queued_at: DateTime.utc_now(),
                metadata: Map.merge(session.metadata || %{}, %{
                  queue_position: position,
                  queued_at: DateTime.utc_now()
                })
              })
              |> Repo.update!()

            {:ok, session}

          {:error, :already_running} ->
            {:error, :already_running}
        end
    end
  end

  @doc """
  Starts a backtest for a given strategy and historical date range.
  (Legacy function - creates and starts in one step for backward compatibility)

  This function now delegates to the new create_backtest + start_backtest(session_id) approach
  which uses supervised tasks and concurrency management.

  ## Examples

      iex> config = %{
      ...>   strategy_id: "550e8400-...",
      ...>   trading_pair: "BTC/USD",
      ...>   start_date: ~U[2023-01-01 00:00:00Z],
      ...>   end_date: ~U[2024-12-31 23:59:59Z],
      ...>   initial_capital: Decimal.new("10000"),
      ...>   commission_rate: Decimal.new("0.001"),
      ...>   slippage_bps: 5,
      ...>   data_source: "binance"
      ...> }
      iex> start_backtest(config)
      {:ok, backtest_id}
  """
  @impl true
  def start_backtest(config) when is_map(config) do
    # Convert legacy config format to new format
    normalized_config = %{
      strategy_id: config.strategy_id,
      trading_pair: config.trading_pair,
      start_time: config[:start_date] || config[:start_time],
      end_time: config[:end_date] || config[:end_time],
      initial_capital: config.initial_capital,
      timeframe: Map.get(config, :timeframe, "1h"),
      commission_rate: Map.get(config, :commission_rate, Decimal.new("0.001")),
      slippage_bps: Map.get(config, :slippage_bps, 5)
    }

    # Validate data availability before creating session
    with {:ok, _data_quality} <- validate_data_availability(normalized_config),
         {:ok, session} <- create_backtest(normalized_config),
         {:ok, started_session} <- start_backtest(session.id) do
      {:ok, started_session.id}
    else
      {:error, :no_data_available} -> {:error, :insufficient_data}
      error -> error
    end
  end

  @doc """
  Retrieves the current progress of a running backtest.
  """
  @impl true
  def get_backtest_progress(backtest_id) do
    case Repo.get(TradingSession, backtest_id) do
      nil ->
        {:error, :not_found}

      session ->
        # If session is completed or failed, return final progress
        if session.status in ["completed", "failed", "cancelled", "stopped"] do
          {:ok, get_final_progress(session)}
        else
          # For running/pending sessions, check ProgressTracker
          {:ok, get_running_progress(session, backtest_id)}
        end
    end
  end

  @doc """
  Retrieves the complete results of a finished backtest.
  """
  @impl true
  def get_backtest_result(backtest_id) do
    case Repo.get(TradingSession, backtest_id) do
      nil ->
        {:error, :not_found}

      %{status: "running"} ->
        {:error, :still_running}

      session ->
        # Load associated positions (with trades) and metrics
        session =
          session
          |> Repo.preload([:performance_metrics, positions: :trades])

        result = build_backtest_result(session)
        {:ok, result}
    end
  end

  @doc """
  Cancels a running or queued backtest.

  For running backtests, marks the session as "cancelled" which signals the
  backtest engine to stop gracefully. For queued backtests, removes from queue
  and releases the concurrency slot.
  """
  @impl true
  def cancel_backtest(backtest_id) do
    case Repo.get(TradingSession, backtest_id) do
      nil ->
        {:error, :not_found}

      %{status: "completed"} ->
        {:error, :already_completed}

      %{status: "failed"} ->
        {:error, :already_completed}

      %{status: "cancelled"} ->
        {:error, :already_completed}

      %{status: "queued"} = session ->
        # For queued backtests, just update status
        # The concurrency manager will handle cleanup
        session
        |> TradingSession.changeset(%{
          status: "cancelled",
          ended_at: DateTime.utc_now(),
          metadata: Map.merge(session.metadata || %{}, %{
            cancelled_at: DateTime.utc_now(),
            cancellation_reason: "user_requested"
          })
        })
        |> Repo.update()

        :ok

      session ->
        # For running backtests, mark as cancelled
        # The engine should check session status periodically and stop gracefully
        session
        |> TradingSession.changeset(%{
          status: "cancelled",
          ended_at: DateTime.utc_now(),
          metadata: Map.merge(session.metadata || %{}, %{
            cancelled_at: DateTime.utc_now(),
            cancellation_reason: "user_requested"
          })
        })
        |> Repo.update()

        # Release concurrency slot if session was running
        if session.status == "running" do
          ConcurrencyManager.release_slot(backtest_id)
        end

        :ok
    end
  end

  @doc """
  Lists all backtests, optionally filtered by strategy or status.
  """
  @impl true
  def list_backtests(opts \\ []) do
    query =
      from s in TradingSession,
        where: s.mode == "backtest",
        order_by: [desc: s.started_at]

    query = apply_filters(query, opts)

    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)

    sessions =
      query
      |> limit(^limit)
      |> offset(^offset)
      |> Repo.all()

    summaries = Enum.map(sessions, &build_summary/1)

    {:ok, summaries}
  end

  @doc """
  Calculates performance metrics for a set of trades.
  """
  @impl true
  def calculate_metrics(trades, initial_capital, final_equity) do
    if length(trades) < 2 do
      {:error, :insufficient_trades}
    else
      # Build equity history from trades
      equity_history = build_equity_history_from_trades(trades, initial_capital)

      # Calculate metrics (safely convert initial_capital)
      initial_cap_float =
        case initial_capital do
          %Decimal{} = d -> Decimal.to_float(d)
          n when is_number(n) -> n / 1.0
          _ -> 10000.0
        end

      metrics =
        TradingStrategy.Backtesting.MetricsCalculator.calculate_metrics(
          trades,
          equity_history,
          initial_cap_float
        )

      # Convert to contract format
      contract_metrics = %{
        total_return: Decimal.from_float(metrics.total_return),
        total_return_abs: Decimal.from_float(metrics.total_return_abs),
        win_rate: Decimal.from_float(metrics.win_rate),
        max_drawdown: Decimal.from_float(metrics.max_drawdown),
        sharpe_ratio: Decimal.from_float(metrics.sharpe_ratio),
        trade_count: metrics.trade_count,
        winning_trades: metrics.winning_trades,
        losing_trades: metrics.losing_trades,
        average_trade_duration: metrics.average_trade_duration_minutes * 60,
        max_consecutive_wins: metrics.max_consecutive_wins,
        max_consecutive_losses: metrics.max_consecutive_losses,
        average_win: Decimal.from_float(metrics.average_win),
        average_loss: Decimal.from_float(metrics.average_loss),
        profit_factor: Decimal.from_float(metrics.profit_factor)
      }

      {:ok, contract_metrics}
    end
  end

  @doc """
  Validates historical data quality before running backtest.
  """
  @impl true
  def validate_data_quality(trading_pair, start_date, end_date, timeframe, data_source) do
    MarketData.validate_data_quality(
      trading_pair,
      timeframe,
      start_time: start_date,
      end_time: end_date
    )
  end

  # Private Functions

  defp load_strategy(strategy_id) do
    case Strategies.get_strategy_admin(strategy_id) do
      nil -> {:error, :strategy_not_found}
      strategy -> {:ok, strategy}
    end
  end

  defp validate_date_range(start_date, end_date) do
    if DateTime.compare(start_date, end_date) == :lt do
      :ok
    else
      {:error, :invalid_date_range}
    end
  end

  defp validate_data_availability(config) do
    exchange = Map.get(config, :exchange, "binance")

    with {:ok, strategy} <- load_strategy(config.strategy_id),
         {:ok, strategy_map} <- parse_strategy_content(strategy.content),
         {:ok, min_bars_required} <- get_strategy_min_bars(strategy_map),
         {:ok, data} <- fetch_historical_data(config, exchange) do
      # Validate we have enough bars for strategy indicators
      data_count = length(data)

      cond do
        data_count == 0 ->
          {:error, :no_data_available}

        data_count < min_bars_required ->
          Logger.warning(
            "Insufficient data: #{data_count} bars available, #{min_bars_required} required for strategy indicators"
          )

          {:error,
           {:insufficient_data,
            "Need at least #{min_bars_required} bars, but only #{data_count} available"}}

        true ->
          {:ok, %{completeness_percentage: Decimal.new("100"), bars_available: data_count}}
      end
    else
      {:error, :strategy_not_found} -> {:error, :strategy_not_found}
      {:error, _} -> {:error, :no_data_available}
    end
  end

  defp parse_strategy_content(content) do
    case YamlElixir.read_from_string(content) do
      {:ok, strategy_map} -> {:ok, strategy_map}
      {:error, reason} -> {:error, {:invalid_strategy, reason}}
    end
  end

  defp get_strategy_min_bars(strategy_map) do
    alias TradingStrategy.Strategies.IndicatorEngine

    case IndicatorEngine.get_minimum_bars_required(strategy_map) do
      {:ok, min_bars} -> {:ok, min_bars}
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch_historical_data(config, exchange) do
    # Support both old field names (start_date/end_date) and new ones (start_time/end_time)
    start_time = config[:start_time] || config[:start_date]
    end_time = config[:end_time] || config[:end_date]
    timeframe = config[:timeframe] || "1h"

    case MarketData.get_historical_data(
           config.trading_pair,
           timeframe,
           start_time: start_time,
           end_time: end_time,
           exchange: exchange
         ) do
      {:ok, data} -> {:ok, data}
      {:error, reason} -> {:error, reason}
    end
  end

  defp run_backtest_task(session_id, strategy, config) do
    try do
      Logger.info("Running backtest for session #{session_id}")

      # Parse strategy content to map for engine
      {:ok, strategy_map} = YamlElixir.read_from_string(strategy.content)

      # Convert config to engine format (support both old and new field names)
      start_time = config[:start_time] || config[:start_date]
      end_time = config[:end_time] || config[:end_date]

      # Safely convert config values to float
      initial_capital_float =
        case config.initial_capital do
          %Decimal{} = d -> Decimal.to_float(d)
          n when is_number(n) -> n / 1.0
          _ -> 10000.0
        end

      commission_rate_float =
        case config.commission_rate do
          %Decimal{} = d -> Decimal.to_float(d)
          n when is_number(n) -> n / 1.0
          _ -> 0.001
        end

      engine_opts = [
        session_id: session_id,
        trading_pair: config.trading_pair,
        start_time: start_time,
        end_time: end_time,
        initial_capital: initial_capital_float,
        commission_rate: commission_rate_float,
        slippage_bps: config.slippage_bps,
        timeframe: config[:timeframe] || "1h",
        exchange: Map.get(config, :exchange, "binance")
      ]

      # Run backtest engine
      case Engine.run_backtest(strategy_map, engine_opts) do
        {:ok, result} ->
          # Store results
          save_backtest_results(session_id, result)
          update_session_status(session_id, "completed")
          Logger.info("Backtest #{session_id} completed successfully")

        {:error, reason} ->
          Logger.error("Backtest #{session_id} failed: #{inspect(reason)}")
          update_session_status(session_id, "failed")
      end
    rescue
      error ->
        Logger.error("Backtest #{session_id} crashed: #{inspect(error)}")
        update_session_status(session_id, "failed")
    end
  end

  defp save_backtest_results(session_id, result) do
    # Get the session to access strategy_id
    session = Repo.get(TradingSession, session_id)

    # Save trades by creating positions first
    # Group trades into position pairs (entry/exit)
    trades_with_positions = pair_trades_into_positions(result.trades)

    Enum.each(trades_with_positions, fn {position_trades, position_data} ->
      # Create position
      position_params = %{
        trading_session_id: session_id,
        strategy_id: session.strategy_id,
        symbol: result.config.trading_pair,
        side: position_data.side,
        quantity: Decimal.from_float(position_data.quantity),
        entry_price: Decimal.from_float(position_data.entry_price),
        exit_price: position_data.exit_price && Decimal.from_float(position_data.exit_price),
        opened_at: position_data.opened_at,
        closed_at: position_data.closed_at,
        status: position_data.status,
        realized_pnl: Decimal.from_float(Map.get(position_data, :pnl, 0.0)),
        fees: Decimal.from_float(Map.get(position_data, :fees, 0.0))
      }

      {:ok, position} =
        %TradingStrategy.Orders.Position{}
        |> TradingStrategy.Orders.Position.changeset(position_params)
        |> Repo.insert()

      # Create trades for this position
      Enum.each(position_trades, fn trade ->
        trade_params = %{
          position_id: position.id,
          side: trade.side,
          quantity: Decimal.from_float(trade.executed_quantity || 1.0),
          price: Decimal.from_float(trade.executed_price || 0.0),
          fee: Decimal.from_float(Map.get(trade, :fees, 0.0)),
          timestamp: trade.timestamp,
          exchange: "backtest",
          status: "filled",
          # T070: Save trade-level PnL and duration
          pnl: Decimal.from_float(Map.get(trade, :pnl, 0.0)),
          duration_seconds: Map.get(trade, :duration_seconds),
          entry_price: trade[:entry_price] && Decimal.from_float(trade.entry_price),
          exit_price: trade[:exit_price] && Decimal.from_float(trade.exit_price)
        }

        %TradingStrategy.Orders.Trade{}
        |> TradingStrategy.Orders.Trade.changeset(trade_params)
        |> Repo.insert()
      end)
    end)

    # Save performance metrics with equity curve
    # Helper to safely convert metrics to Decimal (handles nil for 0-trade backtests)
    safe_decimal = fn
      nil -> Decimal.new("0")
      val when is_number(val) -> Decimal.from_float(val / 1.0)
      val -> Decimal.new("0")
    end

    metrics_params = %{
      trading_session_id: session_id,
      total_return: safe_decimal.(result.metrics.total_return_abs),
      total_return_pct: safe_decimal.(result.metrics.total_return),
      # Convert percentage to decimal (handle nil for 0 trades)
      win_rate: if(result.metrics.win_rate, do: Decimal.from_float(result.metrics.win_rate / 100.0), else: Decimal.new("0")),
      max_drawdown: safe_decimal.(result.metrics.max_drawdown),
      max_drawdown_pct: if(result.metrics.max_drawdown, do: Decimal.from_float(abs(result.metrics.max_drawdown) / 100.0), else: Decimal.new("0")),
      sharpe_ratio: safe_decimal.(result.metrics.sharpe_ratio),
      total_trades: result.metrics.trade_count || 0,
      winning_trades: result.metrics.winning_trades || 0,
      losing_trades: result.metrics.losing_trades || 0,
      avg_win: safe_decimal.(result.metrics.average_win),
      avg_loss: safe_decimal.(result.metrics.average_loss),
      profit_factor: safe_decimal.(result.metrics.profit_factor),
      calculated_at: DateTime.utc_now(),
      # Add equity curve and metadata from result
      equity_curve: Map.get(result.metrics, :equity_curve, []),
      equity_curve_metadata: Map.get(result.metrics, :equity_curve_metadata, %{})
    }

    %TradingStrategy.Backtesting.PerformanceMetrics{}
    |> TradingStrategy.Backtesting.PerformanceMetrics.changeset(metrics_params)
    |> Repo.insert()
  end

  defp update_session_status(session_id, status) do
    case Repo.get(TradingSession, session_id) do
      nil ->
        :ok

      session ->
        session
        |> TradingSession.changeset(%{status: status})
        |> Repo.update()
    end
  end

  defp get_running_progress(session, backtest_id) do
    base_progress =
      # Try to get progress from ProgressTracker
      case ProgressTracker.get(backtest_id) do
        {:ok, progress} ->
          %{
            backtest_id: backtest_id,
            status: String.to_atom(session.status),
            progress_percentage: progress.percentage,
            bars_processed: progress.bars_processed,
            total_bars: progress.total_bars,
            estimated_time_remaining_ms: nil,
            current_timestamp: nil
          }

        {:error, :not_found} ->
          # Fallback if progress tracking not initialized yet
          %{
            backtest_id: backtest_id,
            status: String.to_atom(session.status),
            progress_percentage: 0,
            bars_processed: 0,
            total_bars: 0,
            estimated_time_remaining_ms: nil,
            current_timestamp: nil
          }
      end

    # Add queue information if queued
    if session.status == "queued" do
      queue_position = get_in(session.metadata, ["queue_position"]) || get_in(session.metadata, [:queue_position])
      Map.put(base_progress, :queue_position, queue_position)
    else
      base_progress
    end
  end

  defp get_final_progress(session) do
    %{
      backtest_id: session.id,
      status: String.to_atom(session.status),
      progress_percentage: 100,
      bars_processed: 0,
      total_bars: 0,
      estimated_time_remaining_ms: 0,
      current_timestamp: session.ended_at
    }
  end

  defp build_backtest_result(session) do
    # Extract all trades from all positions
    all_trades =
      session.positions
      |> Enum.flat_map(fn position -> position.trades end)

    trades =
      Enum.map(all_trades, fn trade ->
        %{
          timestamp: trade.timestamp,
          side: String.to_atom(trade.side),
          price: trade.price,
          quantity: trade.quantity,
          fees: trade.fee || Decimal.new("0"),
          # T071: Include trade-level PnL and analytics
          pnl: trade.pnl || Decimal.new("0"),
          duration_seconds: trade.duration_seconds,
          entry_price: trade.entry_price,
          exit_price: trade.exit_price,
          # Default signal type (could be enhanced from metadata)
          signal_type: :entry
        }
      end)

    metrics =
      if length(session.performance_metrics) > 0 do
        m = List.first(session.performance_metrics)

        %{
          total_return: m.total_return_pct,
          total_return_abs: m.total_return,
          # Convert to percentage
          win_rate: Decimal.mult(m.win_rate || Decimal.new("0"), Decimal.new("100")),
          max_drawdown:
            (m.max_drawdown_pct && Decimal.mult(m.max_drawdown_pct, Decimal.new("100"))) ||
              Decimal.new("0"),
          sharpe_ratio: m.sharpe_ratio,
          trade_count: m.total_trades,
          winning_trades: m.winning_trades,
          losing_trades: m.losing_trades,
          # Not stored in schema
          average_trade_duration: 0,
          # Not stored in schema
          max_consecutive_wins: 0,
          # Not stored in schema
          max_consecutive_losses: 0,
          average_win: m.avg_win,
          average_loss: m.avg_loss,
          profit_factor: m.profit_factor,
          # Include equity curve metadata
          equity_curve_metadata: m.equity_curve_metadata || %{}
        }
      else
        %{}
      end

    # Extract equity curve from performance metrics
    equity_curve =
      if length(session.performance_metrics) > 0 do
        m = List.first(session.performance_metrics)
        m.equity_curve || []
      else
        []
      end

    # Extract configuration from session.config (stored as JSONB)
    # Fall back to generating from session fields if not present
    config =
      if session.config && map_size(session.config) > 0 do
        %{
          trading_pair: Map.get(session.config, "trading_pair") || Map.get(session.config, :trading_pair) || "BTC/USD",
          start_time: Map.get(session.config, "start_time") || Map.get(session.config, :start_time) || session.started_at,
          end_time: Map.get(session.config, "end_time") || Map.get(session.config, :end_time) || session.ended_at,
          initial_capital: session.initial_capital,
          timeframe: Map.get(session.config, "timeframe") || Map.get(session.config, :timeframe) || "1h"
        }
      else
        %{
          trading_pair: "BTC/USD",
          start_time: session.started_at,
          end_time: session.ended_at,
          initial_capital: session.initial_capital,
          timeframe: "1h"
        }
      end

    %{
      backtest_id: session.id,
      strategy_id: session.strategy_id,
      config: config,
      performance_metrics: metrics,
      trades: trades,
      equity_curve: equity_curve,  # Now populated from database
      started_at: session.started_at,
      completed_at: session.ended_at,
      data_quality_warnings: []
    }
  end

  defp build_summary(session) do
    %{
      backtest_id: session.id,
      strategy_id: session.strategy_id,
      started_at: session.started_at,
      completed_at: session.ended_at,
      status: String.to_atom(session.status)
    }
  end

  defp apply_filters(query, opts) do
    query
    |> filter_by_strategy(Keyword.get(opts, :strategy_id))
    |> filter_by_status(Keyword.get(opts, :status))
  end

  defp filter_by_strategy(query, nil), do: query

  defp filter_by_strategy(query, strategy_id) do
    from s in query, where: s.strategy_id == ^strategy_id
  end

  defp filter_by_status(query, nil), do: query

  defp filter_by_status(query, status) do
    status_str = Atom.to_string(status)
    from s in query, where: s.status == ^status_str
  end

  defp pair_trades_into_positions(trades) do
    # For now, create one position per trade
    # In a more sophisticated implementation, we would pair entry/exit trades
    Enum.map(trades, fn trade ->
      position_side =
        case trade.side do
          "buy" -> "long"
          "sell" -> "short"
          _ -> "long"
        end

      position_data = %{
        side: position_side,
        quantity: trade.executed_quantity || 1.0,
        entry_price: trade.executed_price || 0.0,
        exit_price: nil,
        opened_at: trade.timestamp,
        closed_at: nil,
        status: "open",
        pnl: Map.get(trade, :pnl, 0.0),
        fees: Map.get(trade, :fees, 0.0)
      }

      {[trade], position_data}
    end)
  end

  defp build_equity_history_from_trades(trades, initial_capital) do
    # Build simple equity history from trades
    # Safely convert initial_capital to float
    initial_value =
      case initial_capital do
        %Decimal{} = d -> Decimal.to_float(d)
        n when is_number(n) -> n / 1.0
        _ -> 10000.0
      end

    trades
    |> Enum.reduce([{DateTime.utc_now(), initial_value}], fn trade, acc ->
      {_last_ts, last_equity} = List.first(acc)

      # Safely get and convert PnL
      pnl =
        case Map.get(trade, :pnl, 0) do
          %Decimal{} = d -> Decimal.to_float(d)
          n when is_number(n) -> n / 1.0
          nil -> 0.0
          _ -> 0.0
        end

      new_equity = last_equity + pnl
      [{trade.timestamp, new_equity} | acc]
    end)
    |> Enum.reverse()
  end

  # New functions for Phase 5 (US3)

  defp launch_backtest_task(session) do
    # Check if we're in test mode where backtests should not actually execute
    test_mode = Application.get_env(:trading_strategy, :backtest_test_mode, false)

    if test_mode do
      # In test mode, just keep the session running without executing
      # Tests can manually complete/fail sessions as needed
      Logger.debug("Test mode: Backtest #{session.id} marked as running without execution")
      :ok
    else
      # Normal mode: actually execute the backtest
      execute_real_backtest(session)
    end
  end

  defp execute_real_backtest(session) do
    # Load strategy
    {:ok, strategy} = load_strategy(session.strategy_id)

    # Extract config
    config = session.config

    # Create backtest function
    backtest_fn = fn ->
      try do
        Logger.info("Running backtest for session #{session.id}")

        # Parse strategy content
        {:ok, strategy_map} = YamlElixir.read_from_string(strategy.content)

        # Convert config to engine format
        commission_rate =
          case config["commission_rate"] || config[:commission_rate] do
            nil -> 0.001
            %Decimal{} = d -> Decimal.to_float(d)
            n when is_number(n) -> n / 1.0
            _ -> 0.001
          end

        # Safely convert initial_capital to float
        initial_capital =
          case session.initial_capital do
            %Decimal{} = d -> Decimal.to_float(d)
            n when is_number(n) -> n / 1.0
            nil -> 10000.0
            _ -> 10000.0
          end

        engine_opts = [
          session_id: session.id,
          trading_pair: config["trading_pair"] || config[:trading_pair],
          start_time: parse_datetime(config["start_time"] || config[:start_time]),
          end_time: parse_datetime(config["end_time"] || config[:end_time]),
          initial_capital: initial_capital,
          commission_rate: commission_rate,
          slippage_bps: config["slippage_bps"] || config[:slippage_bps] || 5,
          timeframe: config["timeframe"] || config[:timeframe] || "1h",
          exchange: config["exchange"] || config[:exchange] || "binance"
        ]

        # Run backtest engine
        case Engine.run_backtest(strategy_map, engine_opts) do
          {:ok, result} ->
            # Finalize with results
            finalize_backtest(session.id, result)
            Logger.info("Backtest #{session.id} completed successfully")

          {:error, reason} ->
            Logger.error("Backtest #{session.id} failed: #{inspect(reason)}")
            mark_as_failed(session.id, "execution_error", "Backtest execution failed: #{inspect(reason)}")
        end
      rescue
        error ->
          Logger.error("Backtest #{session.id} crashed: #{inspect(error)}\n#{Exception.format_stacktrace()}")
          mark_as_failed(session.id, "crash", "Backtest crashed: #{inspect(error)}")
      end
    end

    # Start via supervisor
    case Supervisor.start_backtest_task(session.id, backtest_fn) do
      {:ok, _pid} ->
        Logger.info("Backtest task started for session #{session.id}")
        :ok

      {:error, reason} ->
        Logger.error("Failed to start backtest task: #{inspect(reason)}")
        mark_as_failed(session.id, "supervisor_error", "Failed to start: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Finalizes a backtest by saving results and releasing the concurrency slot.

  ## Parameters
    - session_id: UUID of the trading session
    - result: Backtest result map from Engine
  """
  def finalize_backtest(session_id, result) do
    # Save results
    save_backtest_results(session_id, result)

    # Update session status
    update_session_status(session_id, "completed")

    # Release concurrency slot
    ConcurrencyManager.release_slot(session_id)

    {:ok, :finalized}
  end

  @doc """
  Marks a backtest session as failed and releases the concurrency slot.

  ## Parameters
    - session_id: UUID of the trading session
    - error_type: Type of error (e.g., "application_restart", "execution_error")
    - error_message: Detailed error message
  """
  def mark_as_failed(session_id, error_type, error_message) do
    case Repo.get(TradingSession, session_id) do
      nil ->
        {:error, :not_found}

      session ->
        # Preserve checkpoint data if it exists
        updated_metadata = Map.merge(session.metadata || %{}, %{
          "error_type" => error_type,
          "error_message" => error_message,
          "partial_data_saved" => true,
          "failed_at" => DateTime.to_iso8601(DateTime.utc_now())
        })

        updated_session = session
          |> TradingSession.changeset(%{
            status: "error",
            ended_at: DateTime.utc_now(),
            metadata: updated_metadata
          })
          |> Repo.update!()

        # Release concurrency slot
        ConcurrencyManager.release_slot(session_id)

        {:ok, updated_session}
    end
  end

  @doc """
  Detects and marks stale "running" sessions on application restart.
  Should be called during application startup.
  """
  def detect_and_mark_stale_sessions do
    # Find all sessions with "running" status
    stale_sessions =
      from(s in TradingSession,
        where: s.status == "running" and s.mode == "backtest"
      )
      |> Repo.all()

    # Mark each as failed
    Enum.each(stale_sessions, fn session ->
      checkpoint_info =
        if checkpoint = session.metadata["checkpoint"] || session.metadata[:checkpoint] do
          bars = checkpoint["bars_processed"] || checkpoint[:bars_processed] || 0
          total = checkpoint["total_bars"] || checkpoint[:total_bars] || 0
          percentage = if total > 0, do: Float.round(bars / total * 100, 1), else: 0
          " at #{percentage}% completion (#{bars}/#{total} bars)"
        else
          ""
        end

      mark_as_failed(
        session.id,
        "application_restart",
        "Backtest interrupted by application restart#{checkpoint_info}"
      )

      Logger.warning("Marked stale backtest session #{session.id} as failed (was running before restart)")
    end)

    {:ok, length(stale_sessions)}
  end

  @doc """
  Starts a queued backtest that has been dequeued by the ConcurrencyManager.
  Called internally when a slot becomes available.
  """
  def start_queued_backtest(session_id) do
    case Repo.get(TradingSession, session_id) do
      nil ->
        Logger.error("Cannot start queued backtest: session #{session_id} not found")
        {:error, :not_found}

      session ->
        # Update status to running
        updated_session = session
          |> TradingSession.changeset(%{
            status: "running",
            started_at: DateTime.utc_now()
          })
          |> Repo.update!()

        # Launch the backtest
        launch_backtest_task(updated_session)

        {:ok, updated_session}
    end
  end

  defp parse_datetime(%DateTime{} = dt), do: dt
  defp parse_datetime(iso_string) when is_binary(iso_string) do
    case DateTime.from_iso8601(iso_string) do
      {:ok, dt, _offset} -> dt
      _ -> DateTime.utc_now()
    end
  end
  defp parse_datetime(_), do: DateTime.utc_now()

  @doc """
  Validates data integrity by checking that position realized_pnl equals sum of trade PnLs.

  This function performs a consistency check to ensure that the aggregate PnL at the
  position level matches the sum of individual trade PnLs. This is critical for data
  integrity and accurate performance reporting.

  ## Parameters
    - `position_id`: UUID of the position to validate

  ## Returns
    - `{:ok, :valid}` if position PnL matches sum of trade PnLs (within tolerance)
    - `{:error, {:mismatch, details}}` if there's a discrepancy
    - `{:error, :position_not_found}` if position doesn't exist

  ## Examples

      iex> validate_position_trade_pnl_consistency(position_id)
      {:ok, :valid}

      iex> validate_position_trade_pnl_consistency(bad_position_id)
      {:error, {:mismatch, %{position_pnl: 100.0, trades_pnl_sum: 95.5, difference: 4.5}}}
  """
  @spec validate_position_trade_pnl_consistency(String.t()) ::
          {:ok, :valid} | {:error, {:mismatch, map()}} | {:error, :position_not_found}
  def validate_position_trade_pnl_consistency(position_id) do
    # T073: Data integrity check
    position =
      from(p in TradingStrategy.Orders.Position,
        where: p.id == ^position_id and p.status == "closed",
        preload: [:trades]
      )
      |> Repo.one()

    case position do
      nil ->
        {:error, :position_not_found}

      position ->
        # Calculate sum of trade PnLs
        trades_pnl_sum =
          position.trades
          |> Enum.map(& &1.pnl)
          |> Enum.reduce(Decimal.new("0"), &Decimal.add/2)

        # Compare with position realized_pnl
        position_pnl = position.realized_pnl || Decimal.new("0")
        difference = Decimal.abs(Decimal.sub(position_pnl, trades_pnl_sum))

        # Allow for small floating-point precision errors (0.01 tolerance)
        tolerance = Decimal.new("0.01")

        if Decimal.compare(difference, tolerance) == :lt do
          {:ok, :valid}
        else
          {:error,
           {:mismatch,
            %{
              position_pnl: Decimal.to_float(position_pnl),
              trades_pnl_sum: Decimal.to_float(trades_pnl_sum),
              difference: Decimal.to_float(difference)
            }}}
        end
    end
  end

  @doc """
  Validates data integrity for all positions in a trading session.

  ## Parameters
    - `session_id`: UUID of the trading session

  ## Returns
    - `{:ok, results}` with a list of validation results for each position
    - `{:error, reason}` if session not found
  """
  @spec validate_session_data_integrity(String.t()) :: {:ok, list(map())} | {:error, term()}
  def validate_session_data_integrity(session_id) do
    # T073: Validate all positions in a session
    session =
      from(s in TradingSession,
        where: s.id == ^session_id,
        preload: [positions: :trades]
      )
      |> Repo.one()

    case session do
      nil ->
        {:error, :session_not_found}

      session ->
        results =
          Enum.map(session.positions, fn position ->
            case validate_position_trade_pnl_consistency(position.id) do
              {:ok, :valid} ->
                %{position_id: position.id, status: :valid}

              {:error, {:mismatch, details}} ->
                %{position_id: position.id, status: :mismatch, details: details}

              {:error, reason} ->
                %{position_id: position.id, status: :error, reason: reason}
            end
          end)

        {:ok, results}
    end
  end
end
