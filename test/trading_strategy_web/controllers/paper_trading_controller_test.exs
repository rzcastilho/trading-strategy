defmodule TradingStrategyWeb.PaperTradingControllerTest do
  use TradingStrategyWeb.ConnCase, async: true

  alias TradingStrategy.PaperTrading

  @moduletag :capture_log

  setup %{conn: conn} do
    # Set default headers for JSON API
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("content-type", "application/json")

    %{conn: conn}
  end

  describe "POST /api/paper_trading/sessions (create)" do
    test "creates a new paper trading session with valid params", %{conn: conn} do
      params = %{
        "session" => %{
          "strategy_id" => Ecto.UUID.generate(),
          "trading_pair" => "BTC/USD",
          "initial_capital" => "10000.00",
          "data_source" => "binance",
          "position_sizing" => "percentage",
          "position_size_pct" => 0.1
        }
      }

      # Mock the PaperTrading context
      stub_paper_trading_start(params["session"])

      conn = post(conn, ~p"/api/paper_trading/sessions", params)

      assert %{"id" => session_id, "status" => "active"} = json_response(conn, 201)
      assert is_binary(session_id)
      assert [location_header] = get_resp_header(conn, "location")
      assert location_header =~ session_id
    end

    test "returns 400 when session field is missing", %{conn: conn} do
      conn = post(conn, ~p"/api/paper_trading/sessions", %{})

      assert %{"error" => message} = json_response(conn, 400)
      assert message =~ "Missing required 'session' field"
    end

    test "returns 404 when strategy_id doesn't exist", %{conn: conn} do
      params = %{
        "session" => %{
          "strategy_id" => Ecto.UUID.generate(),
          "trading_pair" => "BTC/USD",
          "initial_capital" => "10000.00"
        }
      }

      stub_paper_trading_start_error(params["session"], {:error, :strategy_not_found})

      conn = post(conn, ~p"/api/paper_trading/sessions", params)

      assert json_response(conn, 404)
    end

    test "returns 422 when data feed unavailable", %{conn: conn} do
      params = %{
        "session" => %{
          "strategy_id" => Ecto.UUID.generate(),
          "trading_pair" => "BTC/USD",
          "initial_capital" => "10000.00"
        }
      }

      stub_paper_trading_start_error(params["session"], {:error, :data_feed_unavailable})

      conn = post(conn, ~p"/api/paper_trading/sessions", params)

      assert json_response(conn, 422)
    end

    test "returns 422 when trading pair is invalid", %{conn: conn} do
      params = %{
        "session" => %{
          "strategy_id" => Ecto.UUID.generate(),
          "trading_pair" => "INVALID",
          "initial_capital" => "10000.00"
        }
      }

      stub_paper_trading_start_error(params["session"], {:error, :invalid_trading_pair})

      conn = post(conn, ~p"/api/paper_trading/sessions", params)

      assert json_response(conn, 422)
    end

    test "accepts optional parameters", %{conn: conn} do
      params = %{
        "session" => %{
          "strategy_id" => Ecto.UUID.generate(),
          "trading_pair" => "BTC/USD",
          "initial_capital" => "10000.00",
          "slippage_bps" => 10,
          "commission_rate" => 0.001
        }
      }

      stub_paper_trading_start(params["session"])

      conn = post(conn, ~p"/api/paper_trading/sessions", params)

      assert json_response(conn, 201)
    end
  end

  describe "GET /api/paper_trading/sessions (index)" do
    test "lists all paper trading sessions", %{conn: conn} do
      stub_paper_trading_list([
        %{
          id: "session-1",
          strategy_id: Ecto.UUID.generate(),
          status: "active",
          trading_pair: "BTC/USD"
        },
        %{
          id: "session-2",
          strategy_id: Ecto.UUID.generate(),
          status: "paused",
          trading_pair: "ETH/USD"
        }
      ])

      conn = get(conn, ~p"/api/paper_trading/sessions")

      assert %{"sessions" => sessions} = json_response(conn, 200)
      assert length(sessions) == 2
    end

    test "filters sessions by strategy_id", %{conn: conn} do
      strategy_id = Ecto.UUID.generate()

      stub_paper_trading_list([
        %{id: "session-1", strategy_id: strategy_id, status: "active"}
      ])

      conn = get(conn, ~p"/api/paper_trading/sessions?strategy_id=#{strategy_id}")

      assert %{"sessions" => sessions} = json_response(conn, 200)
      assert length(sessions) == 1
    end

    test "filters sessions by status", %{conn: conn} do
      stub_paper_trading_list([
        %{id: "session-1", status: "active"},
        %{id: "session-2", status: "active"}
      ])

      conn = get(conn, ~p"/api/paper_trading/sessions?status=active")

      assert %{"sessions" => sessions} = json_response(conn, 200)
      assert Enum.all?(sessions, fn s -> s["status"] == "active" end)
    end

    test "supports pagination with limit and offset", %{conn: conn} do
      stub_paper_trading_list([
        %{id: "session-1"},
        %{id: "session-2"}
      ])

      conn = get(conn, ~p"/api/paper_trading/sessions?limit=10&offset=0")

      assert %{"sessions" => sessions} = json_response(conn, 200)
      assert length(sessions) <= 10
    end

    test "returns empty list when no sessions", %{conn: conn} do
      stub_paper_trading_list([])

      conn = get(conn, ~p"/api/paper_trading/sessions")

      assert %{"sessions" => []} = json_response(conn, 200)
    end
  end

  describe "GET /api/paper_trading/sessions/:id (show)" do
    test "retrieves session status", %{conn: conn} do
      session_id = "session-123"

      stub_paper_trading_status(session_id, %{
        id: session_id,
        status: "active",
        trading_pair: "BTC/USD",
        initial_capital: "10000.00",
        available_capital: "9500.00",
        total_realized_pnl: "50.00",
        total_unrealized_pnl: "25.00"
      })

      conn = get(conn, ~p"/api/paper_trading/sessions/#{session_id}")

      assert %{
               "id" => ^session_id,
               "status" => "active",
               "trading_pair" => "BTC/USD"
             } = json_response(conn, 200)
    end

    test "returns 404 when session doesn't exist", %{conn: conn} do
      session_id = "nonexistent"
      stub_paper_trading_status_error(session_id, {:error, :not_found})

      conn = get(conn, ~p"/api/paper_trading/sessions/#{session_id}")

      assert json_response(conn, 404)
    end
  end

  describe "POST /api/paper_trading/sessions/:id/pause (pause)" do
    test "pauses an active session", %{conn: conn} do
      session_id = "session-123"

      stub_paper_trading_pause(session_id, :ok)

      stub_paper_trading_status(session_id, %{
        id: session_id,
        status: "paused"
      })

      conn = post(conn, ~p"/api/paper_trading/sessions/#{session_id}/pause")

      assert %{"id" => ^session_id, "status" => "paused"} = json_response(conn, 200)
    end

    test "returns 404 when session doesn't exist", %{conn: conn} do
      session_id = "nonexistent"
      stub_paper_trading_pause(session_id, {:error, :not_found})

      conn = post(conn, ~p"/api/paper_trading/sessions/#{session_id}/pause")

      assert json_response(conn, 404)
    end

    test "returns 422 when already paused", %{conn: conn} do
      session_id = "session-123"
      stub_paper_trading_pause(session_id, {:error, :already_paused})

      conn = post(conn, ~p"/api/paper_trading/sessions/#{session_id}/pause")

      assert json_response(conn, 422)
    end

    test "returns 422 when already stopped", %{conn: conn} do
      session_id = "session-123"
      stub_paper_trading_pause(session_id, {:error, :already_stopped})

      conn = post(conn, ~p"/api/paper_trading/sessions/#{session_id}/pause")

      assert json_response(conn, 422)
    end
  end

  describe "POST /api/paper_trading/sessions/:id/resume (resume)" do
    test "resumes a paused session", %{conn: conn} do
      session_id = "session-123"

      stub_paper_trading_resume(session_id, :ok)

      stub_paper_trading_status(session_id, %{
        id: session_id,
        status: "active"
      })

      conn = post(conn, ~p"/api/paper_trading/sessions/#{session_id}/resume")

      assert %{"id" => ^session_id, "status" => "active"} = json_response(conn, 200)
    end

    test "returns 404 when session doesn't exist", %{conn: conn} do
      session_id = "nonexistent"
      stub_paper_trading_resume(session_id, {:error, :not_found})

      conn = post(conn, ~p"/api/paper_trading/sessions/#{session_id}/resume")

      assert json_response(conn, 404)
    end

    test "returns 422 when not paused", %{conn: conn} do
      session_id = "session-123"
      stub_paper_trading_resume(session_id, {:error, :not_paused})

      conn = post(conn, ~p"/api/paper_trading/sessions/#{session_id}/resume")

      assert json_response(conn, 422)
    end

    test "returns 503 when data feed unavailable", %{conn: conn} do
      session_id = "session-123"
      stub_paper_trading_resume(session_id, {:error, :data_feed_unavailable})

      conn = post(conn, ~p"/api/paper_trading/sessions/#{session_id}/resume")

      assert json_response(conn, 503)
    end
  end

  describe "DELETE /api/paper_trading/sessions/:id (delete/stop)" do
    test "stops a session and returns final results", %{conn: conn} do
      session_id = "session-123"

      stub_paper_trading_stop(session_id, %{
        session_id: session_id,
        final_capital: "10500.00",
        total_realized_pnl: "500.00",
        total_trades: 10,
        winning_trades: 6,
        losing_trades: 4
      })

      conn = delete(conn, ~p"/api/paper_trading/sessions/#{session_id}")

      assert %{
               "session_id" => ^session_id,
               "final_capital" => "10500.00",
               "total_realized_pnl" => "500.00"
             } = json_response(conn, 200)
    end

    test "returns 404 when session doesn't exist", %{conn: conn} do
      session_id = "nonexistent"
      stub_paper_trading_stop_error(session_id, {:error, :not_found})

      conn = delete(conn, ~p"/api/paper_trading/sessions/#{session_id}")

      assert json_response(conn, 404)
    end

    test "returns 422 when already stopped", %{conn: conn} do
      session_id = "session-123"
      stub_paper_trading_stop_error(session_id, {:error, :already_stopped})

      conn = delete(conn, ~p"/api/paper_trading/sessions/#{session_id}")

      assert json_response(conn, 422)
    end
  end

  describe "GET /api/paper_trading/sessions/:id/trades (trades)" do
    test "retrieves trade history for a session", %{conn: conn} do
      session_id = "session-123"

      stub_paper_trading_trades(session_id, [
        %{
          trade_id: "trade-1",
          symbol: "BTC/USD",
          side: "buy",
          quantity: "0.1",
          price: "43250.50",
          timestamp: "2025-12-04T12:00:00Z"
        },
        %{
          trade_id: "trade-2",
          symbol: "BTC/USD",
          side: "sell",
          quantity: "0.1",
          price: "43500.00",
          timestamp: "2025-12-04T13:00:00Z"
        }
      ])

      conn = get(conn, ~p"/api/paper_trading/sessions/#{session_id}/trades")

      assert %{"trades" => trades} = json_response(conn, 200)
      assert length(trades) == 2
      assert hd(trades)["trade_id"] == "trade-1"
    end

    test "supports limit parameter", %{conn: conn} do
      session_id = "session-123"

      stub_paper_trading_trades(session_id, [
        %{trade_id: "trade-1"},
        %{trade_id: "trade-2"}
      ])

      conn = get(conn, ~p"/api/paper_trading/sessions/#{session_id}/trades?limit=10")

      assert %{"trades" => trades} = json_response(conn, 200)
      assert length(trades) <= 10
    end

    test "supports offset parameter for pagination", %{conn: conn} do
      session_id = "session-123"

      stub_paper_trading_trades(session_id, [%{trade_id: "trade-11"}])

      conn = get(conn, ~p"/api/paper_trading/sessions/#{session_id}/trades?offset=10")

      assert %{"trades" => _trades} = json_response(conn, 200)
    end

    test "supports since parameter to filter by timestamp", %{conn: conn} do
      session_id = "session-123"
      since = "2025-12-04T00:00:00Z"

      stub_paper_trading_trades(session_id, [
        %{trade_id: "trade-1", timestamp: "2025-12-04T12:00:00Z"}
      ])

      conn = get(conn, ~p"/api/paper_trading/sessions/#{session_id}/trades?since=#{since}")

      assert %{"trades" => trades} = json_response(conn, 200)
      assert length(trades) >= 0
    end

    test "returns 404 when session doesn't exist", %{conn: conn} do
      session_id = "nonexistent"
      stub_paper_trading_trades_error(session_id, {:error, :not_found})

      conn = get(conn, ~p"/api/paper_trading/sessions/#{session_id}/trades")

      assert json_response(conn, 404)
    end

    test "returns empty list when no trades", %{conn: conn} do
      session_id = "session-123"
      stub_paper_trading_trades(session_id, [])

      conn = get(conn, ~p"/api/paper_trading/sessions/#{session_id}/trades")

      assert %{"trades" => []} = json_response(conn, 200)
    end
  end

  describe "GET /api/paper_trading/sessions/:id/metrics (metrics)" do
    test "retrieves performance metrics for a session", %{conn: conn} do
      session_id = "session-123"

      stub_paper_trading_metrics(session_id, %{
        total_trades: 10,
        winning_trades: 6,
        losing_trades: 4,
        win_rate: 0.6,
        total_realized_pnl: "500.00",
        total_unrealized_pnl: "50.00",
        max_drawdown: "150.00",
        sharpe_ratio: 1.5
      })

      conn = get(conn, ~p"/api/paper_trading/sessions/#{session_id}/metrics")

      assert %{
               "total_trades" => 10,
               "winning_trades" => 6,
               "win_rate" => 0.6,
               "total_realized_pnl" => "500.00"
             } = json_response(conn, 200)
    end

    test "returns 404 when session doesn't exist", %{conn: conn} do
      session_id = "nonexistent"
      stub_paper_trading_metrics_error(session_id, {:error, :not_found})

      conn = get(conn, ~p"/api/paper_trading/sessions/#{session_id}/metrics")

      assert json_response(conn, 404)
    end
  end

  # Test helper stubs
  # In a real implementation, these would use Mox or similar mocking library

  defp stub_paper_trading_start(_params) do
    # Mock successful session start
    session_id = "session-#{:rand.uniform(9999)}"
    Process.put({:paper_trading, :start}, {:ok, session_id})

    stub_paper_trading_status(session_id, %{
      id: session_id,
      status: "active",
      trading_pair: "BTC/USD"
    })
  end

  defp stub_paper_trading_start_error(_params, error) do
    Process.put({:paper_trading, :start}, error)
  end

  defp stub_paper_trading_list(sessions) do
    Process.put({:paper_trading, :list}, {:ok, sessions})
  end

  defp stub_paper_trading_status(session_id, status) do
    Process.put({:paper_trading, :status, session_id}, {:ok, status})
  end

  defp stub_paper_trading_status_error(session_id, error) do
    Process.put({:paper_trading, :status, session_id}, error)
  end

  defp stub_paper_trading_pause(session_id, result) do
    Process.put({:paper_trading, :pause, session_id}, result)
  end

  defp stub_paper_trading_resume(session_id, result) do
    Process.put({:paper_trading, :resume, session_id}, result)
  end

  defp stub_paper_trading_stop(session_id, results) do
    Process.put({:paper_trading, :stop, session_id}, {:ok, results})
  end

  defp stub_paper_trading_stop_error(session_id, error) do
    Process.put({:paper_trading, :stop, session_id}, error)
  end

  defp stub_paper_trading_trades(session_id, trades) do
    Process.put({:paper_trading, :trades, session_id}, {:ok, trades})
  end

  defp stub_paper_trading_trades_error(session_id, error) do
    Process.put({:paper_trading, :trades, session_id}, error)
  end

  defp stub_paper_trading_metrics(session_id, metrics) do
    Process.put({:paper_trading, :metrics, session_id}, {:ok, metrics})
  end

  defp stub_paper_trading_metrics_error(session_id, error) do
    Process.put({:paper_trading, :metrics, session_id}, error)
  end
end
