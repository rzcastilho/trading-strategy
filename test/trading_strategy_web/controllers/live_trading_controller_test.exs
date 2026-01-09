defmodule TradingStrategyWeb.LiveTradingControllerTest do
  use TradingStrategyWeb.ConnCase, async: false

  import Mox

  alias TradingStrategy.LiveTrading

  setup :verify_on_exit!

  describe "POST /api/live_trading/sessions" do
    test "creates a live trading session successfully", %{conn: conn} do
      session_params = %{
        "strategy_id" => "550e8400-e29b-41d4-a716-446655440000",
        "trading_pair" => "BTC/USDT",
        "allocated_capital" => "5000.00",
        "exchange" => "binance",
        "mode" => "testnet",
        "api_credentials" => %{
          "api_key" => "test_key",
          "api_secret" => "test_secret"
        },
        "position_sizing" => "percentage",
        "risk_limits" => %{
          "max_position_size_pct" => "0.25",
          "max_daily_loss_pct" => "0.03",
          "max_drawdown_pct" => "0.15",
          "max_concurrent_positions" => 3
        }
      }

      # Mock the LiveTrading module
      expect(LiveTradingMock, :start_live_session, fn _config ->
        {:ok, "session_abc123"}
      end)

      conn = post(conn, "/api/live_trading/sessions", session_params)

      assert %{
               "session_id" => "session_abc123",
               "status" => "created",
               "message" => _
             } = json_response(conn, 201)
    end

    test "returns error for missing required parameters", %{conn: conn} do
      incomplete_params = %{
        "trading_pair" => "BTC/USDT"
        # Missing strategy_id, allocated_capital, etc.
      }

      conn = post(conn, "/api/live_trading/sessions", incomplete_params)

      assert json_response(conn, 422)
    end

    test "returns error for invalid strategy_id", %{conn: conn} do
      session_params = %{
        "strategy_id" => "invalid-uuid",
        "trading_pair" => "BTC/USDT",
        "allocated_capital" => "5000.00",
        "exchange" => "binance"
      }

      expect(LiveTradingMock, :start_live_session, fn _config ->
        {:error, :invalid_strategy}
      end)

      conn = post(conn, "/api/live_trading/sessions", session_params)

      assert json_response(conn, 422)
    end
  end

  describe "GET /api/live_trading/sessions/:id" do
    test "returns session status for existing session", %{conn: conn} do
      session_id = "session_abc123"

      expect(LiveTradingMock, :get_live_session_status, fn ^session_id ->
        {:ok,
         %{
           status: :active,
           connectivity_status: :connected,
           current_equity: Decimal.new("5250.00"),
           open_positions: [
             %{
               symbol: "BTCUSDT",
               side: :long,
               quantity: Decimal.new("0.1"),
               entry_price: Decimal.new("50000"),
               current_price: Decimal.new("51000"),
               unrealized_pnl: Decimal.new("100.00")
             }
           ],
           risk_limits_status: %{
             position_size_utilization_pct: Decimal.new("20"),
             daily_loss_used_pct: Decimal.new("0"),
             drawdown_from_peak_pct: Decimal.new("0"),
             can_open_new_position: true
           }
         }}
      end)

      conn = get(conn, "/api/live_trading/sessions/#{session_id}")

      response = json_response(conn, 200)
      assert response["status"] == "active"
      assert response["connectivity_status"] == "connected"
      assert length(response["open_positions"]) == 1
    end

    test "returns 404 for non-existent session", %{conn: conn} do
      session_id = "nonexistent_session"

      expect(LiveTradingMock, :get_live_session_status, fn ^session_id ->
        {:error, :session_not_found}
      end)

      conn = get(conn, "/api/live_trading/sessions/#{session_id}")

      assert json_response(conn, 404)
    end
  end

  describe "DELETE /api/live_trading/sessions/:id" do
    test "stops a live trading session successfully", %{conn: conn} do
      session_id = "session_abc123"

      expect(LiveTradingMock, :stop_live_session, fn ^session_id ->
        {:ok,
         %{
           final_equity: Decimal.new("5250.00"),
           # 5% return
           total_return: Decimal.new("0.05"),
           trades_count: 15,
           winning_trades: 9,
           losing_trades: 6
         }}
      end)

      conn = delete(conn, "/api/live_trading/sessions/#{session_id}")

      response = json_response(conn, 200)
      assert response["message"] == "Live trading session stopped"
      assert response["final_results"]["trades_count"] == 15
    end

    test "returns error when stopping non-existent session", %{conn: conn} do
      session_id = "nonexistent_session"

      expect(LiveTradingMock, :stop_live_session, fn ^session_id ->
        {:error, :session_not_found}
      end)

      conn = delete(conn, "/api/live_trading/sessions/#{session_id}")

      assert json_response(conn, 404)
    end
  end

  describe "POST /api/live_trading/sessions/:id/emergency_stop" do
    test "executes emergency stop successfully", %{conn: conn} do
      session_id = "session_abc123"

      expect(LiveTradingMock, :emergency_stop, fn ^session_id ->
        {:ok,
         %{
           orders_cancelled: 3,
           positions_closed: 2,
           message: "Emergency stop executed"
         }}
      end)

      conn = post(conn, "/api/live_trading/sessions/#{session_id}/emergency_stop")

      response = json_response(conn, 200)
      assert response["orders_cancelled"] == 3
      assert response["positions_closed"] == 2
    end
  end

  describe "POST /api/live_trading/sessions/:id/pause" do
    test "pauses a live trading session", %{conn: conn} do
      session_id = "session_abc123"

      expect(LiveTradingMock, :pause_live_session, fn ^session_id ->
        :ok
      end)

      conn = post(conn, "/api/live_trading/sessions/#{session_id}/pause")

      response = json_response(conn, 200)
      assert response["message"] == "Live trading session paused"
      assert response["session_id"] == session_id
    end
  end

  describe "POST /api/live_trading/sessions/:id/resume" do
    test "resumes a paused live trading session", %{conn: conn} do
      session_id = "session_abc123"

      expect(LiveTradingMock, :resume_live_session, fn ^session_id ->
        :ok
      end)

      conn = post(conn, "/api/live_trading/sessions/#{session_id}/resume")

      response = json_response(conn, 200)
      assert response["message"] == "Live trading session resumed"
      assert response["session_id"] == session_id
    end
  end

  describe "integration scenarios" do
    test "complete lifecycle: create -> status -> pause -> resume -> stop", %{conn: conn} do
      # Create session
      session_params = %{
        "strategy_id" => "550e8400-e29b-41d4-a716-446655440000",
        "trading_pair" => "BTC/USDT",
        "allocated_capital" => "5000.00",
        "exchange" => "binance",
        "mode" => "testnet",
        "api_credentials" => %{
          "api_key" => "test_key",
          "api_secret" => "test_secret"
        }
      }

      expect(LiveTradingMock, :start_live_session, fn _config ->
        {:ok, "session_lifecycle_test"}
      end)

      conn = post(conn, "/api/live_trading/sessions", session_params)
      create_response = json_response(conn, 201)
      session_id = create_response["session_id"]

      # Get status
      expect(LiveTradingMock, :get_live_session_status, fn ^session_id ->
        {:ok, %{status: :active, connectivity_status: :connected}}
      end)

      conn = get(conn, "/api/live_trading/sessions/#{session_id}")
      status_response = json_response(conn, 200)
      assert status_response["status"] == "active"

      # Pause
      expect(LiveTradingMock, :pause_live_session, fn ^session_id -> :ok end)
      conn = post(conn, "/api/live_trading/sessions/#{session_id}/pause")
      assert json_response(conn, 200)

      # Resume
      expect(LiveTradingMock, :resume_live_session, fn ^session_id -> :ok end)
      conn = post(conn, "/api/live_trading/sessions/#{session_id}/resume")
      assert json_response(conn, 200)

      # Stop
      expect(LiveTradingMock, :stop_live_session, fn ^session_id ->
        {:ok, %{final_equity: Decimal.new("5100"), trades_count: 5}}
      end)

      conn = delete(conn, "/api/live_trading/sessions/#{session_id}")
      stop_response = json_response(conn, 200)
      assert stop_response["message"] == "Live trading session stopped"
    end
  end
end
