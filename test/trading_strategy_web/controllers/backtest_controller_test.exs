defmodule TradingStrategyWeb.BacktestControllerTest do
  @moduledoc """
  Integration tests for BacktestController.

  Tests the HTTP API for backtest operations, including:
  - Creating backtests
  - Retrieving progress
  - Retrieving results
  - Listing backtests
  - Cancelling backtests
  """
  use TradingStrategyWeb.ConnCase

  alias TradingStrategy.{Backtesting, Strategies, Repo}
  alias TradingStrategy.Backtesting.{TradingSession, ProgressTracker}

  @valid_strategy_yaml """
  name: Test Strategy
  trading_pair: BTC/USD
  timeframe: 1h
  indicators:
    - type: rsi
      name: rsi_14
      parameters:
        period: 14
  entry_conditions: "rsi_14 < 30"
  exit_conditions: "rsi_14 > 70"
  stop_conditions: "rsi_14 < 25"
  position_sizing:
    type: percentage
    percentage_of_capital: 0.10
    max_position_size: 0.25
  risk_parameters:
    max_daily_loss: 0.03
    max_drawdown: 0.15
  """

  setup %{conn: conn} do
    # Create a test strategy
    {:ok, strategy} =
      Strategies.create_strategy(%{
        "name" => "Test RSI Strategy",
        "description" => "Test strategy for integration tests",
        "format" => "yaml",
        "content" => @valid_strategy_yaml,
        "trading_pair" => "BTC/USD",
        "timeframe" => "1h"
      })

    conn = put_req_header(conn, "accept", "application/json")
    {:ok, conn: conn, strategy: strategy}
  end

  describe "POST /api/backtests" do
    test "creates a new backtest and returns backtest_id", %{conn: conn, strategy: strategy} do
      params = %{
        "strategy_id" => strategy.id,
        "trading_pair" => "BTC/USD",
        "start_date" => "2023-01-01T00:00:00Z",
        "end_date" => "2023-01-31T23:59:59Z",
        "initial_capital" => "10000",
        "commission_rate" => "0.001",
        "slippage_bps" => 5
      }

      conn = post(conn, ~p"/api/backtests", params)

      assert %{"backtest_id" => backtest_id, "status" => "running"} = json_response(conn, 202)
      assert is_binary(backtest_id)

      # Verify session was created in database
      session = Repo.get(TradingSession, backtest_id)
      assert session != nil
      assert session.status == "running"
    end

    test "returns error for missing required fields", %{conn: conn} do
      params = %{
        "trading_pair" => "BTC/USD"
        # Missing strategy_id, start_date, end_date
      }

      conn = post(conn, ~p"/api/backtests", params)

      assert conn.status == 400
    end

    test "returns error for non-existent strategy", %{conn: conn} do
      params = %{
        "strategy_id" => Ecto.UUID.generate(),
        "trading_pair" => "BTC/USD",
        "start_date" => "2023-01-01T00:00:00Z",
        "end_date" => "2023-01-31T23:59:59Z"
      }

      conn = post(conn, ~p"/api/backtests", params)

      assert conn.status in [404, 422]
    end
  end

  describe "GET /api/backtests/:id/progress" do
    test "returns accurate progress for running backtest", %{conn: conn} do
      # Create a mock session
      session = insert_test_session()

      # Simulate progress tracking
      ProgressTracker.track(session.id, 5000)
      Process.sleep(10)
      ProgressTracker.update(session.id, 2500)

      conn = get(conn, ~p"/api/backtests/#{session.id}/progress")

      assert response = json_response(conn, 200)
      assert response["backtest_id"] == session.id
      assert response["status"] == "running"
      assert response["bars_processed"] == 2500
      assert response["total_bars"] == 5000
      assert response["progress_percentage"] == 50.0
    end

    test "returns progress from ProgressTracker for active backtest", %{conn: conn} do
      session = insert_test_session()

      # Initialize tracking with specific values
      ProgressTracker.track(session.id, 10_000)
      Process.sleep(10)
      ProgressTracker.update(session.id, 3_750)

      conn = get(conn, ~p"/api/backtests/#{session.id}/progress")

      assert response = json_response(conn, 200)
      assert response["bars_processed"] == 3_750
      assert response["total_bars"] == 10_000
      assert response["progress_percentage"] == 37.5
    end

    test "returns 100% progress for completed backtest", %{conn: conn} do
      session = insert_test_session(%{status: "completed"})

      conn = get(conn, ~p"/api/backtests/#{session.id}/progress")

      assert response = json_response(conn, 200)
      assert response["status"] == "completed"
      assert response["progress_percentage"] == 100
    end

    test "returns error for non-existent backtest", %{conn: conn} do
      conn = get(conn, ~p"/api/backtests/#{Ecto.UUID.generate()}/progress")

      assert conn.status == 404
    end

    test "handles backtest with no progress tracking data", %{conn: conn} do
      # Session exists but no progress tracking initialized
      session = insert_test_session()

      conn = get(conn, ~p"/api/backtests/#{session.id}/progress")

      # Should return some default progress, not crash
      assert response = json_response(conn, 200)
      assert response["backtest_id"] == session.id
    end
  end

  describe "GET /api/backtests/:id" do
    test "returns complete results for finished backtest", %{conn: conn, strategy: strategy} do
      session = insert_test_session(%{status: "completed", strategy_id: strategy.id})

      # Insert mock performance metrics
      insert_test_metrics(session.id)

      conn = get(conn, ~p"/api/backtests/#{session.id}")

      assert response = json_response(conn, 200)
      assert response["backtest_id"] == session.id
      assert response["strategy_id"] == strategy.id
      assert is_map(response["performance_metrics"])
      assert is_list(response["trades"])
      assert is_list(response["equity_curve"])
    end

    test "returns error when backtest is still running", %{conn: conn} do
      session = insert_test_session(%{status: "running"})

      conn = get(conn, ~p"/api/backtests/#{session.id}")

      assert response = json_response(conn, 202)
      assert response["error"] == "Backtest is still running"
    end

    test "returns error for non-existent backtest", %{conn: conn} do
      conn = get(conn, ~p"/api/backtests/#{Ecto.UUID.generate()}")

      assert conn.status == 404
    end
  end

  describe "GET /api/backtests" do
    test "lists all backtests", %{conn: conn, strategy: strategy} do
      # Create multiple test sessions
      session1 = insert_test_session(%{strategy_id: strategy.id, status: "completed"})
      session2 = insert_test_session(%{strategy_id: strategy.id, status: "running"})

      conn = get(conn, ~p"/api/backtests")

      assert response = json_response(conn, 200)
      assert is_list(response["backtests"])
      assert length(response["backtests"]) >= 2

      backtest_ids = Enum.map(response["backtests"], & &1["backtest_id"])
      assert session1.id in backtest_ids
      assert session2.id in backtest_ids
    end

    test "filters backtests by strategy_id", %{conn: conn, strategy: strategy} do
      # Create sessions for this strategy
      session1 = insert_test_session(%{strategy_id: strategy.id})

      # Create another strategy and session
      {:ok, other_strategy} =
        Strategies.create_strategy(%{
          "name" => "Other Strategy",
          "format" => "yaml",
          "content" => @valid_strategy_yaml,
          "trading_pair" => "ETH/USD",
          "timeframe" => "1h"
        })

      _session2 = insert_test_session(%{strategy_id: other_strategy.id})

      conn = get(conn, ~p"/api/backtests?strategy_id=#{strategy.id}")

      assert response = json_response(conn, 200)
      backtest_ids = Enum.map(response["backtests"], & &1["backtest_id"])
      assert session1.id in backtest_ids

      # All returned backtests should belong to the filtered strategy
      Enum.each(response["backtests"], fn backtest ->
        assert backtest["strategy_id"] == strategy.id
      end)
    end

    test "filters backtests by status", %{conn: conn, strategy: strategy} do
      _session_running = insert_test_session(%{strategy_id: strategy.id, status: "running"})
      session_completed = insert_test_session(%{strategy_id: strategy.id, status: "completed"})

      conn = get(conn, ~p"/api/backtests?status=completed")

      assert response = json_response(conn, 200)
      backtest_ids = Enum.map(response["backtests"], & &1["backtest_id"])
      assert session_completed.id in backtest_ids

      # All returned backtests should have 'completed' status
      Enum.each(response["backtests"], fn backtest ->
        assert backtest["status"] == "completed"
      end)
    end

    test "respects limit parameter", %{conn: conn, strategy: strategy} do
      # Create 5 sessions
      for _i <- 1..5 do
        insert_test_session(%{strategy_id: strategy.id})
      end

      conn = get(conn, ~p"/api/backtests?limit=2")

      assert response = json_response(conn, 200)
      assert length(response["backtests"]) == 2
    end
  end

  describe "DELETE /api/backtests/:id" do
    test "cancels a running backtest", %{conn: conn} do
      session = insert_test_session(%{status: "running"})

      conn = delete(conn, ~p"/api/backtests/#{session.id}")

      assert response = json_response(conn, 200)
      assert response["message"] == "Backtest cancelled successfully"

      # Verify status updated in database
      updated_session = Repo.get(TradingSession, session.id)
      assert updated_session.status == "cancelled"
    end

    test "returns error for already completed backtest", %{conn: conn} do
      session = insert_test_session(%{status: "completed"})

      conn = delete(conn, ~p"/api/backtests/#{session.id}")

      assert response = json_response(conn, 422)
      assert response["error"] == "Backtest already completed"
    end

    test "returns error for non-existent backtest", %{conn: conn} do
      conn = delete(conn, ~p"/api/backtests/#{Ecto.UUID.generate()}")

      assert conn.status == 404
    end
  end

  # Helper Functions

  defp insert_test_session(attrs \\ %{}) do
    # Create a test strategy if strategy_id not provided
    strategy_id = Map.get(attrs, :strategy_id) || create_test_strategy().id

    default_attrs = %{
      strategy_id: strategy_id,
      mode: "backtest",
      status: "running",
      started_at: ~U[2023-01-01 00:00:00Z],
      ended_at: ~U[2023-01-31 23:59:59Z],
      initial_capital: Decimal.new("10000"),
      current_capital: Decimal.new("10000")
    }

    merged_attrs = Map.merge(default_attrs, attrs)

    %TradingSession{}
    |> TradingSession.changeset(merged_attrs)
    |> Repo.insert!()
  end

  defp create_test_strategy do
    {:ok, strategy} =
      Strategies.create_strategy(%{
        "name" => "Helper Test Strategy",
        "description" => "Auto-generated test strategy",
        "format" => "yaml",
        "content" => @valid_strategy_yaml,
        "trading_pair" => "BTC/USD",
        "timeframe" => "1h"
      })

    strategy
  end

  defp insert_test_metrics(session_id) do
    %TradingStrategy.Backtesting.PerformanceMetrics{}
    |> TradingStrategy.Backtesting.PerformanceMetrics.changeset(%{
      trading_session_id: session_id,
      total_return: Decimal.new("1500"),
      total_return_pct: Decimal.new("0.15"),
      win_rate: Decimal.new("0.60"),
      max_drawdown: Decimal.new("500"),
      max_drawdown_pct: Decimal.new("0.05"),
      sharpe_ratio: Decimal.new("1.8"),
      total_trades: 20,
      winning_trades: 12,
      losing_trades: 8,
      avg_win: Decimal.new("200"),
      avg_loss: Decimal.new("100"),
      profit_factor: Decimal.new("1.5"),
      calculated_at: DateTime.utc_now()
    })
    |> Repo.insert!()
  end
end
