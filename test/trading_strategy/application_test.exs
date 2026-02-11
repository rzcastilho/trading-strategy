defmodule TradingStrategy.ApplicationTest do
  use TradingStrategy.DataCase, async: false

  alias TradingStrategy.Backtesting
  alias TradingStrategy.Backtesting.TradingSession
  alias TradingStrategy.Repo

  describe "restart handling with stale sessions" do
    setup do
      # Clean up any existing sessions
      Repo.delete_all(TradingSession)
      :ok
    end

    test "marks running sessions as failed after application restart" do
      # Create a session that was "running" before restart
      stale_session =
        insert(:trading_session, %{
          status: "running",
          strategy_id: "test_strategy",
          mode: "backtest",
          initial_capital: Decimal.new("10000"),
          config: %{
            trading_pair: "BTC/USD",
            start_time: ~U[2024-01-01 00:00:00Z],
            end_time: ~U[2024-01-31 23:59:59Z],
            timeframe: "1h"
          },
          metadata: %{
            checkpoint: %{
              bar_index: 500,
              bars_processed: 500,
              total_bars: 1000
            }
          },
          # Simulate that this session was updated more than 5 minutes ago
          updated_at: DateTime.add(DateTime.utc_now(), -10, :minute)
        })

      # Create a recently updated running session (should not be marked as failed)
      recent_session =
        insert(:trading_session, %{
          status: "running",
          strategy_id: "test_strategy",
          mode: "backtest",
          initial_capital: Decimal.new("10000"),
          config: %{
            trading_pair: "ETH/USD",
            start_time: ~U[2024-01-01 00:00:00Z],
            end_time: ~U[2024-01-31 23:59:59Z],
            timeframe: "1h"
          },
          updated_at: DateTime.utc_now()
        })

      # Create a completed session (should not be affected)
      completed_session =
        insert(:trading_session, %{
          status: "completed",
          strategy_id: "test_strategy",
          mode: "backtest",
          initial_capital: Decimal.new("10000"),
          config: %{
            trading_pair: "SOL/USD",
            start_time: ~U[2024-01-01 00:00:00Z],
            end_time: ~U[2024-01-31 23:59:59Z],
            timeframe: "1h"
          },
          updated_at: DateTime.add(DateTime.utc_now(), -10, :minute)
        })

      # Simulate restart detection by calling the private function
      # (In real app, this is called automatically in Application.start/2)
      TradingStrategy.Application.handle_stale_sessions()

      # Verify stale running session is now marked as failed
      reloaded_stale = Repo.get!(TradingSession, stale_session.id)
      assert reloaded_stale.status == "error"
      assert reloaded_stale.metadata["error_type"] == "application_restart"
      assert reloaded_stale.metadata["error_message"] =~ "interrupted by application restart"
      assert reloaded_stale.metadata["partial_data_saved"] == true

      # Verify recent running session is NOT marked as failed
      reloaded_recent = Repo.get!(TradingSession, recent_session.id)
      assert reloaded_recent.status == "running"

      # Verify completed session is unchanged
      reloaded_completed = Repo.get!(TradingSession, completed_session.id)
      assert reloaded_completed.status == "completed"
    end

    test "preserves checkpoint data when marking session as failed" do
      # Create a running session with checkpoint data
      session_with_checkpoint =
        insert(:trading_session, %{
          status: "running",
          strategy_id: "test_strategy",
          mode: "backtest",
          initial_capital: Decimal.new("10000"),
          config: %{
            trading_pair: "BTC/USD",
            start_time: ~U[2024-01-01 00:00:00Z],
            end_time: ~U[2024-01-31 23:59:59Z],
            timeframe: "1h"
          },
          metadata: %{
            checkpoint: %{
              bar_index: 750,
              bars_processed: 750,
              total_bars: 1000,
              last_equity: 10500.0,
              completed_trades: 15
            },
            execution_started_at: ~U[2024-01-15 10:00:00Z]
          },
          updated_at: DateTime.add(DateTime.utc_now(), -10, :minute)
        })

      # Handle stale sessions
      TradingStrategy.Application.handle_stale_sessions()

      # Verify checkpoint data is preserved
      reloaded = Repo.get!(TradingSession, session_with_checkpoint.id)
      assert reloaded.status == "error"
      assert reloaded.metadata["checkpoint"]["bar_index"] == 750
      assert reloaded.metadata["checkpoint"]["bars_processed"] == 750
      assert reloaded.metadata["checkpoint"]["completed_trades"] == 15
      assert reloaded.metadata["checkpoint"]["last_equity"] == 10500.0
    end

    test "handles multiple stale sessions in a single restart" do
      # Create multiple stale running sessions
      sessions =
        for i <- 1..5 do
          insert(:trading_session, %{
            status: "running",
            strategy_id: "test_strategy_#{i}",
            mode: "backtest",
            initial_capital: Decimal.new("10000"),
            config: %{
              trading_pair: "BTC/USD",
              start_time: ~U[2024-01-01 00:00:00Z],
              end_time: ~U[2024-01-31 23:59:59Z],
              timeframe: "1h"
            },
            updated_at: DateTime.add(DateTime.utc_now(), -10, :minute)
          })
        end

      # Handle stale sessions
      TradingStrategy.Application.handle_stale_sessions()

      # Verify all sessions are marked as failed
      Enum.each(sessions, fn session ->
        reloaded = Repo.get!(TradingSession, session.id)
        assert reloaded.status == "error"
        assert reloaded.metadata["error_type"] == "application_restart"
      end)
    end

    test "does not mark queued sessions as failed" do
      # Create a queued session (not yet running)
      queued_session =
        insert(:trading_session, %{
          status: "queued",
          strategy_id: "test_strategy",
          mode: "backtest",
          initial_capital: Decimal.new("10000"),
          config: %{
            trading_pair: "BTC/USD",
            start_time: ~U[2024-01-01 00:00:00Z],
            end_time: ~U[2024-01-31 23:59:59Z],
            timeframe: "1h"
          },
          queued_at: DateTime.add(DateTime.utc_now(), -10, :minute),
          updated_at: DateTime.add(DateTime.utc_now(), -10, :minute)
        })

      # Handle stale sessions
      TradingStrategy.Application.handle_stale_sessions()

      # Verify queued session is NOT marked as failed
      reloaded = Repo.get!(TradingSession, queued_session.id)
      assert reloaded.status == "queued"
    end

    test "does not mark pending sessions as failed" do
      # Create a pending session
      pending_session =
        insert(:trading_session, %{
          status: "pending",
          strategy_id: "test_strategy",
          mode: "backtest",
          initial_capital: Decimal.new("10000"),
          config: %{
            trading_pair: "BTC/USD",
            start_time: ~U[2024-01-01 00:00:00Z],
            end_time: ~U[2024-01-31 23:59:59Z],
            timeframe: "1h"
          },
          updated_at: DateTime.add(DateTime.utc_now(), -10, :minute)
        })

      # Handle stale sessions
      TradingStrategy.Application.handle_stale_sessions()

      # Verify pending session is NOT marked as failed
      reloaded = Repo.get!(TradingSession, pending_session.id)
      assert reloaded.status == "pending"
    end

    test "logs warning for each stale session found" do
      # Create a stale running session
      stale_session =
        insert(:trading_session, %{
          status: "running",
          strategy_id: "test_strategy",
          mode: "backtest",
          initial_capital: Decimal.new("10000"),
          config: %{
            trading_pair: "BTC/USD",
            start_time: ~U[2024-01-01 00:00:00Z],
            end_time: ~U[2024-01-31 23:59:59Z],
            timeframe: "1h"
          },
          updated_at: DateTime.add(DateTime.utc_now(), -10, :minute)
        })

      # Capture logs
      log =
        capture_log(fn ->
          TradingStrategy.Application.handle_stale_sessions()
        end)

      # Verify warning was logged
      assert log =~ "Marking interrupted backtest as failed"
      assert log =~ stale_session.id
    end

    test "handles empty database gracefully" do
      # Delete all sessions
      Repo.delete_all(TradingSession)

      # Should not raise error
      assert :ok = TradingStrategy.Application.handle_stale_sessions()
    end

    test "cutoff time is 5 minutes" do
      # Create session updated exactly 5 minutes ago (should NOT be marked as stale)
      edge_session =
        insert(:trading_session, %{
          status: "running",
          strategy_id: "test_strategy",
          mode: "backtest",
          initial_capital: Decimal.new("10000"),
          config: %{
            trading_pair: "BTC/USD",
            start_time: ~U[2024-01-01 00:00:00Z],
            end_time: ~U[2024-01-31 23:59:59Z],
            timeframe: "1h"
          },
          updated_at: DateTime.add(DateTime.utc_now(), -5, :minute)
        })

      # Create session updated 6 minutes ago (should be marked as stale)
      stale_session =
        insert(:trading_session, %{
          status: "running",
          strategy_id: "test_strategy",
          mode: "backtest",
          initial_capital: Decimal.new("10000"),
          config: %{
            trading_pair: "ETH/USD",
            start_time: ~U[2024-01-01 00:00:00Z],
            end_time: ~U[2024-01-31 23:59:59Z],
            timeframe: "1h"
          },
          updated_at: DateTime.add(DateTime.utc_now(), -6, :minute)
        })

      # Handle stale sessions
      TradingStrategy.Application.handle_stale_sessions()

      # Verify edge case (5 minutes) is still running
      reloaded_edge = Repo.get!(TradingSession, edge_session.id)
      assert reloaded_edge.status == "running"

      # Verify 6 minutes is marked as failed
      reloaded_stale = Repo.get!(TradingSession, stale_session.id)
      assert reloaded_stale.status == "error"
    end
  end

  describe "integration with Backtesting context" do
    test "mark_as_failed/2 function sets correct error metadata" do
      session =
        insert(:trading_session, %{
          status: "running",
          strategy_id: "test_strategy",
          mode: "backtest",
          initial_capital: Decimal.new("10000"),
          config: %{
            trading_pair: "BTC/USD",
            start_time: ~U[2024-01-01 00:00:00Z],
            end_time: ~U[2024-01-31 23:59:59Z],
            timeframe: "1h"
          }
        })

      error_info = %{
        error_type: "test_error",
        error_message: "Test error message",
        partial_data_saved: true
      }

      {:ok, updated_session} = Backtesting.mark_as_failed(session.id, error_info)

      assert updated_session.status == "error"
      assert updated_session.metadata["error_type"] == "test_error"
      assert updated_session.metadata["error_message"] == "Test error message"
      assert updated_session.metadata["partial_data_saved"] == true
    end

    test "mark_as_failed/2 preserves existing metadata" do
      session =
        insert(:trading_session, %{
          status: "running",
          strategy_id: "test_strategy",
          mode: "backtest",
          initial_capital: Decimal.new("10000"),
          config: %{
            trading_pair: "BTC/USD",
            start_time: ~U[2024-01-01 00:00:00Z],
            end_time: ~U[2024-01-31 23:59:59Z],
            timeframe: "1h"
          },
          metadata: %{
            checkpoint: %{
              bar_index: 500
            },
            custom_field: "preserved"
          }
        })

      error_info = %{
        error_type: "restart",
        error_message: "Application restarted"
      }

      {:ok, updated_session} = Backtesting.mark_as_failed(session.id, error_info)

      # Verify error info is added
      assert updated_session.metadata["error_type"] == "restart"

      # Verify existing metadata is preserved
      assert updated_session.metadata["checkpoint"]["bar_index"] == 500
      assert updated_session.metadata["custom_field"] == "preserved"
    end
  end
end
