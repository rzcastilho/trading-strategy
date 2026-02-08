defmodule TradingStrategyWeb.BacktestController do
  @moduledoc """
  Controller for backtesting operations.

  Handles creating, retrieving, and managing backtests.
  """

  use TradingStrategyWeb, :controller

  alias TradingStrategy.Backtesting
  require Logger

  action_fallback TradingStrategyWeb.FallbackController

  @doc """
  Creates and starts a new backtest.

  ## Request Body
      {
        "strategy_id": "550e8400-...",
        "trading_pair": "BTC/USD",
        "start_date": "2023-01-01T00:00:00Z",
        "end_date": "2024-12-31T23:59:59Z",
        "initial_capital": "10000",
        "commission_rate": "0.001",
        "slippage_bps": 5,
        "data_source": "binance"
      }

  ## Response
      {
        "backtest_id": "abc123...",
        "status": "running"
      }
  """
  def create(conn, params) do
    with {:ok, config} <- parse_backtest_config(params),
         {:ok, backtest_id} <- Backtesting.start_backtest(config) do
      conn
      |> put_status(:accepted)
      |> json(%{
        backtest_id: backtest_id,
        status: "running",
        message: "Backtest started successfully"
      })
    end
  end

  @doc """
  Retrieves the progress of a running backtest.

  ## Path Parameters
    - id: Backtest UUID

  ## Response
      {
        "backtest_id": "abc123...",
        "status": "running",
        "progress_percentage": 45,
        "bars_processed": 6570,
        "total_bars": 14600,
        "estimated_time_remaining_ms": 12000
      }
  """
  def show_progress(conn, %{"backtest_id" => backtest_id}) do
    case Backtesting.get_backtest_progress(backtest_id) do
      {:ok, progress} ->
        json(conn, format_progress(progress))

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  @doc """
  Retrieves the complete results of a finished backtest.

  ## Path Parameters
    - id: Backtest UUID

  ## Response
      {
        "backtest_id": "abc123...",
        "strategy_id": "550e8400-...",
        "performance_metrics": {
          "total_return": "0.342",
          "sharpe_ratio": "1.8",
          "max_drawdown": "0.12",
          ...
        },
        "trades": [...],
        "equity_curve": [...]
      }
  """
  def show(conn, %{"id" => backtest_id}) do
    case Backtesting.get_backtest_result(backtest_id) do
      {:ok, result} ->
        json(conn, format_result(result))

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, :still_running} ->
        conn
        |> put_status(:accepted)
        |> json(%{
          error: "Backtest is still running",
          message: "Use GET /api/backtests/:id/progress to check status"
        })
    end
  end

  @doc """
  Lists all backtests with optional filtering.

  ## Query Parameters
    - strategy_id: Filter by strategy UUID (optional)
    - status: Filter by status (running, completed, failed) (optional)
    - limit: Number of results (default: 50)
    - offset: Pagination offset (default: 0)

  ## Response
      {
        "backtests": [
          {
            "backtest_id": "abc123...",
            "strategy_id": "550e8400-...",
            "started_at": "2023-01-01T00:00:00Z",
            "status": "completed"
          },
          ...
        ]
      }
  """
  def index(conn, params) do
    opts = build_list_opts(params)

    case Backtesting.list_backtests(opts) do
      {:ok, backtests} ->
        json(conn, %{backtests: format_backtest_list(backtests)})
    end
  end

  @doc """
  Cancels a running backtest.

  ## Path Parameters
    - id: Backtest UUID

  ## Response
      {
        "message": "Backtest cancelled successfully"
      }
  """
  def delete(conn, %{"id" => backtest_id}) do
    case Backtesting.cancel_backtest(backtest_id) do
      :ok ->
        json(conn, %{message: "Backtest cancelled successfully"})

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, :already_completed} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Backtest already completed"})
    end
  end

  @doc """
  Validates data quality for a backtest configuration.

  ## Request Body
      {
        "trading_pair": "BTC/USD",
        "start_date": "2023-01-01T00:00:00Z",
        "end_date": "2024-12-31T23:59:59Z",
        "timeframe": "1h",
        "data_source": "binance"
      }

  ## Response
      {
        "total_bars_expected": 8760,
        "total_bars_available": 8650,
        "completeness_percentage": "98.7",
        "quality_warnings": [...]
      }
  """
  def validate_data(conn, params) do
    with {:ok, config} <- parse_validation_config(params) do
      case Backtesting.validate_data_quality(
             config.trading_pair,
             config.start_date,
             config.end_date,
             config.timeframe,
             config.data_source
           ) do
        {:ok, quality_report} ->
          json(conn, quality_report)

        {:error, :no_data_available} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "No data available for the specified date range"})
      end
    end
  end

  # Private Functions

  defp parse_backtest_config(params) do
    required_fields = ["strategy_id", "trading_pair", "start_date", "end_date"]
    missing = Enum.filter(required_fields, fn field -> not Map.has_key?(params, field) end)

    if length(missing) > 0 do
      {:error, {:bad_request, "Missing required fields: #{Enum.join(missing, ", ")}"}}
    else
      config = %{
        strategy_id: params["strategy_id"],
        trading_pair: params["trading_pair"],
        start_date: parse_datetime(params["start_date"]),
        end_date: parse_datetime(params["end_date"]),
        initial_capital: parse_decimal(params["initial_capital"], "10000"),
        commission_rate: parse_decimal(params["commission_rate"], "0.001"),
        slippage_bps: parse_integer(params["slippage_bps"], 5),
        data_source: params["data_source"] || "binance",
        position_sizing: String.to_atom(params["position_sizing"] || "percentage")
      }

      {:ok, config}
    end
  end

  defp parse_validation_config(params) do
    required_fields = ["trading_pair", "start_date", "end_date"]
    missing = Enum.filter(required_fields, fn field -> not Map.has_key?(params, field) end)

    if length(missing) > 0 do
      {:error, {:bad_request, "Missing required fields: #{Enum.join(missing, ", ")}"}}
    else
      config = %{
        trading_pair: params["trading_pair"],
        start_date: parse_datetime(params["start_date"]),
        end_date: parse_datetime(params["end_date"]),
        timeframe: params["timeframe"] || "1h",
        data_source: params["data_source"] || "binance"
      }

      {:ok, config}
    end
  end

  defp build_list_opts(params) do
    []
    |> add_opt_if_present(:strategy_id, params["strategy_id"])
    |> add_opt_if_present(:status, parse_status(params["status"]))
    |> add_opt_if_present(:limit, parse_integer(params["limit"], 50))
    |> add_opt_if_present(:offset, parse_integer(params["offset"], 0))
  end

  defp add_opt_if_present(opts, _key, nil), do: opts
  defp add_opt_if_present(opts, key, value), do: Keyword.put(opts, key, value)

  defp parse_datetime(nil), do: nil

  defp parse_datetime(string) when is_binary(string) do
    case DateTime.from_iso8601(string) do
      {:ok, datetime, _offset} -> datetime
      {:error, _} -> nil
    end
  end

  defp parse_datetime(datetime), do: datetime

  defp parse_decimal(nil, default), do: Decimal.new(default)
  defp parse_decimal(value, _default) when is_binary(value), do: Decimal.new(value)
  defp parse_decimal(value, _default) when is_number(value), do: Decimal.from_float(value / 1.0)
  defp parse_decimal(%Decimal{} = value, _default), do: value

  defp parse_integer(nil, default), do: default
  defp parse_integer(value, _default) when is_integer(value), do: value

  defp parse_integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> default
    end
  end

  defp parse_status(nil), do: nil
  defp parse_status(status) when is_binary(status), do: String.to_atom(status)
  defp parse_status(status) when is_atom(status), do: status

  defp format_progress(progress) do
    %{
      backtest_id: progress.backtest_id,
      status: Atom.to_string(progress.status),
      progress_percentage: progress.progress_percentage,
      bars_processed: progress.bars_processed,
      total_bars: progress.total_bars,
      estimated_time_remaining_ms: progress.estimated_time_remaining_ms,
      current_timestamp: progress.current_timestamp
    }
  end

  defp format_result(result) do
    %{
      backtest_id: result.backtest_id,
      strategy_id: result.strategy_id,
      config: format_config(result.config),
      performance_metrics: format_metrics(result.performance_metrics),
      trades: format_trades(result.trades),
      equity_curve: format_equity_curve(result.equity_curve),
      started_at: result.started_at,
      completed_at: result.completed_at,
      data_quality_warnings: result.data_quality_warnings
    }
  end

  defp format_config(config) do
    %{
      trading_pair: config.trading_pair,
      start_time: config.start_time || config[:start_date],
      end_time: config.end_time || config[:end_date],
      initial_capital: Decimal.to_string(config.initial_capital),
      timeframe: config[:timeframe] || "1h"
    }
  end

  defp format_metrics(metrics) when is_map(metrics) do
    %{
      total_return: Decimal.to_string(Map.get(metrics, :total_return, Decimal.new("0"))),
      total_return_abs: Decimal.to_string(Map.get(metrics, :total_return_abs, Decimal.new("0"))),
      win_rate: Decimal.to_string(Map.get(metrics, :win_rate, Decimal.new("0"))),
      max_drawdown: Decimal.to_string(Map.get(metrics, :max_drawdown, Decimal.new("0"))),
      sharpe_ratio: Decimal.to_string(Map.get(metrics, :sharpe_ratio, Decimal.new("0"))),
      trade_count: Map.get(metrics, :trade_count, 0),
      winning_trades: Map.get(metrics, :winning_trades, 0),
      losing_trades: Map.get(metrics, :losing_trades, 0),
      average_trade_duration: Map.get(metrics, :average_trade_duration, 0),
      max_consecutive_wins: Map.get(metrics, :max_consecutive_wins, 0),
      max_consecutive_losses: Map.get(metrics, :max_consecutive_losses, 0),
      average_win: Decimal.to_string(Map.get(metrics, :average_win, Decimal.new("0"))),
      average_loss: Decimal.to_string(Map.get(metrics, :average_loss, Decimal.new("0"))),
      profit_factor: Decimal.to_string(Map.get(metrics, :profit_factor, Decimal.new("0")))
    }
  end

  defp format_metrics(_), do: %{}

  defp format_trades(trades) when is_list(trades) do
    Enum.map(trades, fn trade ->
      %{
        timestamp: trade.timestamp,
        side: Atom.to_string(trade.side),
        price: Decimal.to_string(trade.price),
        quantity: Decimal.to_string(trade.quantity),
        fees: Decimal.to_string(trade.fees),
        pnl: Decimal.to_string(trade.pnl),
        signal_type: Atom.to_string(trade.signal_type)
      }
    end)
  end

  defp format_trades(_), do: []

  defp format_equity_curve(curve) when is_list(curve) do
    # Equity curve is already in JSON format from EquityCurve.to_json_format/1
    # Just return it as-is if it has the correct format
    if Enum.all?(curve, &is_map/1) and
       Enum.all?(curve, fn point -> Map.has_key?(point, "timestamp") and Map.has_key?(point, "value") end) do
      curve
    else
      # Legacy format - convert to new format
      Enum.map(curve, fn point ->
        %{
          timestamp: point.timestamp,
          equity: Decimal.to_string(point.equity),
          cash: Decimal.to_string(point.cash),
          positions_value: Decimal.to_string(point.positions_value)
        }
      end)
    end
  end

  defp format_equity_curve(_), do: []

  defp format_backtest_list(backtests) do
    Enum.map(backtests, fn backtest ->
      %{
        backtest_id: backtest.backtest_id,
        strategy_id: backtest.strategy_id,
        started_at: backtest.started_at,
        completed_at: backtest.completed_at,
        status: Atom.to_string(backtest.status)
      }
    end)
  end
end
