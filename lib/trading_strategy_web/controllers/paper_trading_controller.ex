defmodule TradingStrategyWeb.PaperTradingController do
  @moduledoc """
  Controller for paper trading session management.

  Provides REST API endpoints for:
  - Starting/stopping paper trading sessions
  - Pausing/resuming sessions
  - Querying session status and metrics
  - Retrieving trade history
  - Listing all sessions

  All endpoints return JSON and delegate to TradingStrategy.PaperTrading context.
  """

  use TradingStrategyWeb, :controller

  alias TradingStrategy.PaperTrading

  action_fallback TradingStrategyWeb.FallbackController

  @doc """
  Starts a new paper trading session.

  POST /api/paper_trading/sessions

  Expected JSON body:
  {
    "session": {
      "strategy_id": "uuid-here",
      "trading_pair": "BTC/USD",
      "initial_capital": "10000.00",
      "data_source": "binance",
      "position_sizing": "percentage",
      "position_size_pct": 0.1
    }
  }

  Returns:
  - 201 Created with session details on success
  - 400 Bad Request if missing required fields
  - 404 Not Found if strategy_id doesn't exist
  - 422 Unprocessable Entity if validation fails
  """
  def create(conn, %{"session" => session_params}) do
    config = build_session_config(session_params)

    case PaperTrading.start_paper_session(config) do
      {:ok, session_id} ->
        # Fetch the newly created session status
        {:ok, status} = PaperTrading.get_paper_session_status(session_id)

        conn
        |> put_status(:created)
        |> put_resp_header("location", ~p"/api/paper_trading/sessions/#{session_id}")
        |> render(:show, session: status)

      {:error, :strategy_not_found} ->
        {:error, :not_found}

      {:error, :data_feed_unavailable} ->
        {:error, :data_feed_unavailable}

      {:error, :invalid_trading_pair} ->
        {:error, :invalid_trading_pair}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def create(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing required 'session' field in request body"})
  end

  @doc """
  Lists all paper trading sessions with optional filters.

  GET /api/paper_trading/sessions?strategy_id=uuid&status=active&limit=10&offset=0

  Query parameters:
  - strategy_id: Filter by strategy UUID (optional)
  - status: Filter by status (active, paused, stopped) (optional)
  - limit: Maximum results (default: 50)
  - offset: Pagination offset (default: 0)

  Returns:
  - 200 OK with list of session summaries
  """
  def index(conn, params) do
    opts = build_list_opts(params)
    {:ok, sessions} = PaperTrading.list_paper_sessions(opts)

    render(conn, :index, sessions: sessions)
  end

  @doc """
  Gets the status of a specific paper trading session.

  GET /api/paper_trading/sessions/:id

  Returns:
  - 200 OK with session status
  - 404 Not Found if session doesn't exist
  """
  def show(conn, %{"id" => session_id}) do
    case PaperTrading.get_paper_session_status(session_id) do
      {:ok, status} ->
        render(conn, :show, session: status)

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  @doc """
  Pauses an active paper trading session.

  POST /api/paper_trading/sessions/:id/pause

  Returns:
  - 200 OK if successfully paused
  - 404 Not Found if session doesn't exist
  - 422 Unprocessable Entity if already paused or stopped
  """
  def pause(conn, %{"id" => session_id}) do
    case PaperTrading.pause_paper_session(session_id) do
      :ok ->
        {:ok, status} = PaperTrading.get_paper_session_status(session_id)
        render(conn, :show, session: status)

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, :already_paused} ->
        {:error, :already_paused}

      {:error, :already_stopped} ->
        {:error, :already_stopped}
    end
  end

  @doc """
  Resumes a paused paper trading session.

  POST /api/paper_trading/sessions/:id/resume

  Returns:
  - 200 OK if successfully resumed
  - 404 Not Found if session doesn't exist
  - 422 Unprocessable Entity if not paused
  - 503 Service Unavailable if data feed unavailable
  """
  def resume(conn, %{"id" => session_id}) do
    case PaperTrading.resume_paper_session(session_id) do
      :ok ->
        {:ok, status} = PaperTrading.get_paper_session_status(session_id)
        render(conn, :show, session: status)

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, :not_paused} ->
        {:error, :not_paused}

      {:error, :data_feed_unavailable} ->
        {:error, :data_feed_unavailable}
    end
  end

  @doc """
  Stops a paper trading session and closes all positions.

  DELETE /api/paper_trading/sessions/:id

  Returns:
  - 200 OK with final session results
  - 404 Not Found if session doesn't exist
  - 422 Unprocessable Entity if already stopped
  """
  def delete(conn, %{"id" => session_id}) do
    case PaperTrading.stop_paper_session(session_id) do
      {:ok, results} ->
        render(conn, :results, results: results)

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, :already_stopped} ->
        {:error, :already_stopped}
    end
  end

  @doc """
  Gets the trade history for a paper trading session.

  GET /api/paper_trading/sessions/:id/trades?limit=100&offset=0&since=2025-12-01T00:00:00Z

  Query parameters:
  - limit: Maximum results (default: 100)
  - offset: Pagination offset (default: 0)
  - since: ISO8601 datetime (optional)

  Returns:
  - 200 OK with list of trades
  - 404 Not Found if session doesn't exist
  """
  def trades(conn, %{"id" => session_id} = params) do
    opts = build_trades_opts(params)

    case PaperTrading.get_paper_session_trades(session_id, opts) do
      {:ok, trades} ->
        render(conn, :trades, trades: trades)

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  @doc """
  Gets performance metrics for a paper trading session.

  GET /api/paper_trading/sessions/:id/metrics

  Returns:
  - 200 OK with performance metrics
  - 404 Not Found if session doesn't exist
  """
  def metrics(conn, %{"id" => session_id}) do
    case PaperTrading.get_paper_session_metrics(session_id) do
      {:ok, metrics} ->
        render(conn, :metrics, metrics: metrics)

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  # Private helper functions

  defp build_session_config(params) do
    %{
      strategy_id: params["strategy_id"],
      trading_pair: params["trading_pair"],
      initial_capital: parse_decimal(params["initial_capital"]),
      data_source: params["data_source"] || "binance",
      position_sizing: parse_atom(params["position_sizing"], :percentage),
      position_size_pct: params["position_size_pct"],
      position_size_fixed: parse_decimal(params["position_size_fixed"]),
      slippage_bps: params["slippage_bps"],
      commission_rate: params["commission_rate"]
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp build_list_opts(params) do
    [
      strategy_id: params["strategy_id"],
      status: parse_atom(params["status"]),
      limit: parse_int(params["limit"], 50),
      offset: parse_int(params["offset"], 0)
    ]
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
  end

  defp build_trades_opts(params) do
    [
      limit: parse_int(params["limit"], 100),
      offset: parse_int(params["offset"], 0),
      since: parse_datetime(params["since"])
    ]
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
  end

  defp parse_decimal(nil), do: nil

  defp parse_decimal(value) when is_binary(value) do
    Decimal.new(value)
  end

  defp parse_decimal(%Decimal{} = value), do: value
  defp parse_decimal(value) when is_number(value), do: Decimal.from_float(value)
  defp parse_decimal(_), do: nil

  defp parse_atom(nil), do: nil
  defp parse_atom(nil, default), do: default

  defp parse_atom(value, _default \\ nil) when is_binary(value) do
    String.to_existing_atom(value)
  rescue
    ArgumentError -> nil
  end

  defp parse_atom(value, _default) when is_atom(value), do: value
  defp parse_atom(_, default), do: default

  defp parse_int(nil, default), do: default

  defp parse_int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> default
    end
  end

  defp parse_int(value, _default) when is_integer(value), do: value
  defp parse_int(_, default), do: default

  defp parse_datetime(nil), do: nil

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      {:error, _} -> nil
    end
  end

  defp parse_datetime(%DateTime{} = value), do: value
  defp parse_datetime(_), do: nil
end
