defmodule TradingStrategy.Backtesting do
  @moduledoc """
  Context module for backtesting operations.

  Implements the BacktestAPI contract for running backtests,
  tracking progress, and retrieving results.
  """

  @behaviour TradingStrategy.Contracts.BacktestAPI

  alias TradingStrategy.Backtesting.Engine
  alias TradingStrategy.{Strategies, MarketData, Repo}
  alias TradingStrategy.Backtesting.TradingSession
  require Logger

  import Ecto.Query

  @doc """
  Starts a backtest for a given strategy and historical date range.

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
  def start_backtest(config) do
    with {:ok, strategy} <- load_strategy(config.strategy_id),
         :ok <- validate_date_range(config.start_date, config.end_date),
         {:ok, _data_quality} <- validate_data_availability(config) do
      # Create backtest session record
      session_params = %{
        strategy_id: config.strategy_id,
        mode: "backtest",
        status: "running",
        started_at: config.start_date,
        ended_at: config.end_date,
        initial_capital: config.initial_capital,
        current_capital: config.initial_capital
      }

      {:ok, session} =
        %TradingSession{}
        |> TradingSession.changeset(session_params)
        |> Repo.insert()

      # Run backtest asynchronously
      task =
        Task.async(fn ->
          run_backtest_task(session.id, strategy, config)
        end)

      # Store task reference for tracking
      Process.put({:backtest_task, session.id}, task)

      {:ok, session.id}
    else
      {:error, :strategy_not_found} -> {:error, :strategy_not_found}
      {:error, :invalid_date_range} -> {:error, :invalid_date_range}
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
        # Check if task is still running
        task = Process.get({:backtest_task, backtest_id})

        progress =
          if task && Process.alive?(task.pid) do
            # Still running - check progress from task state
            get_running_progress(session, backtest_id)
          else
            # Completed or failed
            get_final_progress(session)
          end

        {:ok, progress}
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
  Cancels a running backtest.
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

      session ->
        # Stop the task if running
        task = Process.get({:backtest_task, backtest_id})

        if task && Process.alive?(task.pid) do
          Task.shutdown(task, :brutal_kill)
        end

        # Update session status
        session
        |> TradingSession.changeset(%{status: "cancelled"})
        |> Repo.update()

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
        order_by: [desc: s.start_time]

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

      # Calculate metrics
      metrics =
        TradingStrategy.Backtesting.MetricsCalculator.calculate_metrics(
          trades,
          equity_history,
          Decimal.to_float(initial_capital)
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
    case Strategies.get_strategy(strategy_id) do
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

    case MarketData.get_historical_data(
           config.trading_pair,
           # Default timeframe
           "1h",
           start_time: config.start_date,
           end_time: config.end_date,
           exchange: exchange
         ) do
      {:ok, []} -> {:error, :no_data_available}
      {:ok, _data} -> {:ok, %{completeness_percentage: Decimal.new("100")}}
      {:error, _} -> {:error, :no_data_available}
    end
  end

  defp run_backtest_task(session_id, strategy, config) do
    try do
      Logger.info("Running backtest for session #{session_id}")

      # Parse strategy content to map for engine
      {:ok, strategy_map} = YamlElixir.read_from_string(strategy.content)

      # Convert config to engine format
      engine_opts = [
        trading_pair: config.trading_pair,
        start_time: config.start_date,
        end_time: config.end_date,
        initial_capital: Decimal.to_float(config.initial_capital),
        commission_rate: Decimal.to_float(config.commission_rate),
        slippage_bps: config.slippage_bps,
        timeframe: "1h",
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
          status: "filled"
        }

        %TradingStrategy.Orders.Trade{}
        |> TradingStrategy.Orders.Trade.changeset(trade_params)
        |> Repo.insert()
      end)
    end)

    # Save performance metrics
    metrics_params = %{
      trading_session_id: session_id,
      total_return: Decimal.from_float(result.metrics.total_return_abs),
      total_return_pct: Decimal.from_float(result.metrics.total_return),
      # Convert percentage to decimal
      win_rate: Decimal.from_float(result.metrics.win_rate / 100.0),
      max_drawdown: Decimal.from_float(abs(result.metrics.max_drawdown)),
      max_drawdown_pct: Decimal.from_float(abs(result.metrics.max_drawdown) / 100.0),
      sharpe_ratio: Decimal.from_float(result.metrics.sharpe_ratio),
      total_trades: result.metrics.trade_count,
      winning_trades: result.metrics.winning_trades,
      losing_trades: result.metrics.losing_trades,
      avg_win: Decimal.from_float(result.metrics.average_win),
      avg_loss: Decimal.from_float(abs(result.metrics.average_loss)),
      profit_factor: Decimal.from_float(result.metrics.profit_factor),
      calculated_at: DateTime.utc_now()
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
    # For now, return basic progress
    # TODO: Implement progress tracking in Engine
    %{
      backtest_id: backtest_id,
      status: String.to_atom(session.status),
      # Placeholder
      progress_percentage: 50,
      bars_processed: 0,
      total_bars: 0,
      estimated_time_remaining_ms: nil,
      current_timestamp: nil
    }
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
          # PNL is at position level, not trade level
          pnl: Decimal.new("0"),
          # Default signal type
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
          profit_factor: m.profit_factor
        }
      else
        %{}
      end

    %{
      backtest_id: session.id,
      strategy_id: session.strategy_id,
      config: %{
        # TODO: Store in session
        trading_pair: "BTC/USD",
        start_date: session.started_at,
        end_date: session.ended_at,
        initial_capital: session.initial_capital
      },
      performance_metrics: metrics,
      trades: trades,
      # TODO: Generate from trades
      equity_curve: [],
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
    trades
    |> Enum.reduce([{DateTime.utc_now(), Decimal.to_float(initial_capital)}], fn trade, acc ->
      {last_ts, last_equity} = List.first(acc)
      pnl = Map.get(trade, :pnl, Decimal.new("0")) |> Decimal.to_float()
      new_equity = last_equity + pnl
      [{trade.timestamp, new_equity} | acc]
    end)
    |> Enum.reverse()
  end
end
