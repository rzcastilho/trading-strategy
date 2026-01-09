defmodule TradingStrategyWeb.PaperTradingJSON do
  @moduledoc """
  JSON rendering for paper trading resources.

  Handles serialization of paper trading sessions, trades, and metrics,
  including proper Decimal type conversion to strings for JSON compatibility.
  """

  @doc """
  Renders a list of paper trading sessions.
  """
  def index(%{sessions: sessions}) do
    %{data: for(session <- sessions, do: session_summary(session))}
  end

  @doc """
  Renders a single paper trading session status.
  """
  def show(%{session: session}) do
    %{data: session_data(session)}
  end

  @doc """
  Renders final session results after stopping.
  """
  def results(%{results: results}) do
    %{data: session_results(results)}
  end

  @doc """
  Renders a list of trades.
  """
  def trades(%{trades: trades}) do
    %{data: for(trade <- trades, do: trade_data(trade))}
  end

  @doc """
  Renders performance metrics.
  """
  def metrics(%{metrics: metrics}) do
    %{data: metrics_data(metrics)}
  end

  # Private rendering functions

  defp session_summary(session) do
    %{
      session_id: session.session_id,
      strategy_id: session[:strategy_id],
      trading_pair: session[:trading_pair],
      status: session[:status],
      started_at: format_datetime(session[:started_at]),
      current_equity: format_decimal(session[:current_equity]),
      realized_pnl: format_decimal(session[:realized_pnl]),
      unrealized_pnl: format_decimal(session[:unrealized_pnl]),
      trades_count: session[:trades_count] || 0,
      last_updated_at: format_datetime(session[:last_updated_at])
    }
  end

  defp session_data(session) do
    %{
      session_id: session.session_id,
      status: session.status,
      started_at: format_datetime(session.started_at),
      stopped_at: format_datetime(Map.get(session, :stopped_at)),
      current_equity: format_decimal(session.current_equity),
      unrealized_pnl: format_decimal(session.unrealized_pnl),
      realized_pnl: format_decimal(session.realized_pnl),
      open_positions: Enum.map(session.open_positions, &position_data/1),
      trades_count: session.trades_count,
      last_market_price: format_decimal(session.last_market_price),
      last_updated_at: format_datetime(session.last_updated_at)
    }
  end

  defp session_results(results) do
    %{
      session_id: results.session_id,
      duration_seconds: results[:duration_seconds],
      final_equity: format_decimal(results[:final_equity]),
      total_return: format_decimal(results[:total_return]),
      trades: Enum.map(results[:trades] || [], &trade_data/1),
      performance_metrics: metrics_data(results[:performance_metrics] || %{}),
      max_drawdown_reached: format_decimal(results[:max_drawdown_reached])
    }
  end

  defp position_data(position) do
    %{
      trading_pair: position[:trading_pair] || position["trading_pair"],
      side: position[:side] || position["side"],
      entry_price: format_decimal(position[:entry_price] || position["entry_price"]),
      quantity: format_decimal(position[:quantity] || position["quantity"]),
      current_price: format_decimal(position[:current_price] || position["current_price"]),
      unrealized_pnl: format_decimal(position[:unrealized_pnl] || position["unrealized_pnl"]),
      duration_seconds: position[:duration_seconds] || position["duration_seconds"]
    }
  end

  defp trade_data(trade) do
    %{
      trade_id: trade[:trade_id] || trade["trade_id"],
      session_id: trade[:session_id] || trade["session_id"],
      timestamp: format_datetime(trade[:timestamp] || trade["timestamp"]),
      trading_pair: trade[:trading_pair] || trade["trading_pair"],
      side: trade[:side] || trade["side"],
      quantity: format_decimal(trade[:quantity] || trade["quantity"]),
      price: format_decimal(trade[:price] || trade["price"]),
      signal_type: trade[:signal_type] || trade["signal_type"],
      pnl: format_decimal(trade[:pnl] || trade["pnl"])
    }
  end

  defp metrics_data(metrics) when is_map(metrics) do
    metrics
    |> Enum.map(fn {key, value} ->
      {key, format_metric_value(value)}
    end)
    |> Map.new()
  end

  defp metrics_data(_), do: %{}

  defp format_metric_value(%Decimal{} = value), do: Decimal.to_string(value)
  defp format_metric_value(value) when is_list(value), do: Enum.map(value, &format_metric_value/1)
  defp format_metric_value(value) when is_map(value), do: metrics_data(value)
  defp format_metric_value(value), do: value

  # Utility functions for formatting

  defp format_decimal(nil), do: nil
  defp format_decimal(%Decimal{} = decimal), do: Decimal.to_string(decimal)
  defp format_decimal(value) when is_number(value), do: to_string(value)
  defp format_decimal(value), do: value

  defp format_datetime(nil), do: nil
  defp format_datetime(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp format_datetime(value), do: value
end
