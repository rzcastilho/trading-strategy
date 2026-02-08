defmodule TradingStrategy.BacktestingTest do
  use TradingStrategy.DataCase, async: false

  alias TradingStrategy.Backtesting
  alias TradingStrategy.Backtesting.{TradingSession, PerformanceMetrics}
  alias TradingStrategy.Repo
  import TradingStrategy.BacktestHelpers

  describe "backtest result with equity curve" do
    setup do
      # Create a test strategy first
      strategy_id = Ecto.UUID.generate()

      {:ok, _} = Repo.insert(%TradingStrategy.Strategies.Strategy{
        id: strategy_id,
        name: "Test Strategy",
        description: "For testing",
        version: 1,
        status: "active",
        format: "yaml",
        content: "indicators: []",
        trading_pair: "BTC/USD",
        timeframe: "1h"
      })

      {:ok, strategy_id: strategy_id}
    end

    test "get_backtest_result includes equity curve from performance_metrics", %{strategy_id: strategy_id} do
      # Create a trading session directly
      {:ok, session} = %TradingSession{}
        |> TradingSession.changeset(%{
          strategy_id: strategy_id,
          mode: "backtest",
          status: "completed",
          initial_capital: Decimal.new("10000.00"),
          current_capital: Decimal.new("10450.00"),
          started_at: ~U[2024-01-01 00:00:00Z],
          ended_at: ~U[2024-01-02 00:00:00Z],
          config: %{
            "trading_pair" => "BTC/USD",
            "start_time" => ~U[2024-01-01 00:00:00Z],
            "end_time" => ~U[2024-01-02 00:00:00Z],
            "timeframe" => "1h"
          }
        })
        |> Repo.insert()
      session_id = session.id

      # Create performance metrics with equity curve
      equity_curve = [
        %{"timestamp" => "2024-01-01T00:00:00Z", "value" => 10000.0},
        %{"timestamp" => "2024-01-01T06:00:00Z", "value" => 10150.5},
        %{"timestamp" => "2024-01-01T12:00:00Z", "value" => 10120.25},
        %{"timestamp" => "2024-01-01T18:00:00Z", "value" => 10300.0},
        %{"timestamp" => "2024-01-02T00:00:00Z", "value" => 10450.0}
      ]

      equity_curve_metadata = %{
        sampled: false,
        sample_rate: 1,
        original_length: 5,
        trade_points_included: 2
      }

      # Create performance metrics with equity curve
      {:ok, _metrics} = %PerformanceMetrics{}
        |> PerformanceMetrics.changeset(%{
          trading_session_id: session_id,
          total_return: Decimal.new("450.00"),
          total_return_pct: Decimal.new("4.5"),
          sharpe_ratio: Decimal.new("1.5"),
          max_drawdown: Decimal.new("30.25"),
          max_drawdown_pct: Decimal.new("0.3"),
          win_rate: Decimal.new("0.75"),
          profit_factor: Decimal.new("2.5"),
          total_trades: 4,
          winning_trades: 3,
          losing_trades: 1,
          avg_win: Decimal.new("100.00"),
          avg_loss: Decimal.new("30.00"),
          calculated_at: DateTime.utc_now(),
          equity_curve: equity_curve,
          equity_curve_metadata: equity_curve_metadata
        })
        |> Repo.insert()

      # Get backtest result
      assert {:ok, result} = Backtesting.get_backtest_result(session_id)

      # Verify equity curve is included
      assert Map.has_key?(result, :equity_curve)
      assert is_list(result.equity_curve)
      assert length(result.equity_curve) == 5

      # Verify equity curve format
      assert Enum.all?(result.equity_curve, fn point ->
        Map.has_key?(point, "timestamp") and Map.has_key?(point, "value")
      end)

      # Verify first and last values match initial and final capital
      assert hd(result.equity_curve)["value"] == 10000.0
      assert List.last(result.equity_curve)["value"] == 10450.0

      # Verify configuration is complete
      assert Map.has_key?(result, :config)
      assert result.config[:trading_pair] == "BTC/USD" or result.config.trading_pair == "BTC/USD"
      assert Decimal.eq?(result.config[:initial_capital] || result.config.initial_capital, Decimal.new("10000.00"))
    end

    test "backtest result with sampled equity curve (>1000 points)", %{strategy_id: strategy_id} do
      # Create a trading session directly
      {:ok, session} = %TradingSession{}
        |> TradingSession.changeset(%{
          strategy_id: strategy_id,
          mode: "backtest",
          status: "completed",
          initial_capital: Decimal.new("10000.00"),
          current_capital: Decimal.new("12500.00"),
          started_at: ~U[2024-01-01 00:00:00Z],
          ended_at: ~U[2024-01-07 00:00:00Z],
          config: %{
            "trading_pair" => "BTC/USD",
            "start_time" => ~U[2024-01-01 00:00:00Z],
            "end_time" => ~U[2024-01-07 00:00:00Z],
            "timeframe" => "1m"
          }
        })
        |> Repo.insert()

      session_id = session.id

      # Create large equity curve (simulating 5000 points)
      large_curve = Enum.map(1..5000, fn i ->
        timestamp = DateTime.add(~U[2024-01-01 00:00:00Z], i * 60, :second)
        value = 10000.0 + i * 0.5
        %{
          "timestamp" => DateTime.to_iso8601(timestamp),
          "value" => value
        }
      end)

      equity_curve_metadata = %{
        sampled: true,
        sample_rate: 5,  # Every 5th point included
        original_length: 5000,
        trade_points_included: 20
      }

      # Sample down to 1000 points
      sampled_curve = Enum.take_every(large_curve, 5) |> Enum.take(1000)

      # Create performance metrics
      {:ok, _metrics} = %PerformanceMetrics{}
        |> PerformanceMetrics.changeset(%{
          trading_session_id: session_id,
          total_return: Decimal.new("2500.00"),
          total_return_pct: Decimal.new("25.0"),
          total_trades: 20,
          winning_trades: 15,
          losing_trades: 5,
          avg_win: Decimal.new("200.00"),
          avg_loss: Decimal.new("50.00"),
          calculated_at: DateTime.utc_now(),
          equity_curve: sampled_curve,
          equity_curve_metadata: equity_curve_metadata
        })
        |> Repo.insert()

      # Get result
      assert {:ok, result} = Backtesting.get_backtest_result(session_id)

      # Verify equity curve is sampled to max 1000 points
      assert length(result.equity_curve) <= 1000

      # Verify metadata indicates sampling (keys are strings in JSONB)
      assert result.performance_metrics.equity_curve_metadata["sampled"] == true or
             result.performance_metrics.equity_curve_metadata[:sampled] == true
      assert result.performance_metrics.equity_curve_metadata["original_length"] == 5000 or
             result.performance_metrics.equity_curve_metadata[:original_length] == 5000
    end
  end

  describe "concurrent backtest limiting" do
    setup do
      # Reset ConcurrencyManager state before each test
      TradingStrategy.Backtesting.ConcurrencyManager.reset()

      # Create a test strategy with valid content
      {:ok, strategy} = create_test_strategy()

      # Enable test mode to prevent actual backtest execution
      original_test_mode = Application.get_env(:trading_strategy, :backtest_test_mode)
      Application.put_env(:trading_strategy, :backtest_test_mode, true)

      on_exit(fn ->
        # Restore original test mode setting
        if original_test_mode do
          Application.put_env(:trading_strategy, :backtest_test_mode, original_test_mode)
        else
          Application.delete_env(:trading_strategy, :backtest_test_mode)
        end
      end)

      {:ok, strategy_id: strategy.id}
    end

    test "queues backtest when max concurrent limit reached", %{strategy_id: strategy_id} do
      # Get current max_concurrent setting
      max_concurrent = Application.get_env(:trading_strategy, :max_concurrent_backtests, 5)

      # Start enough backtests to fill all slots
      running_sessions = for _ <- 1..max_concurrent do
        {:ok, session} = Backtesting.create_backtest(%{
          strategy_id: strategy_id,
          trading_pair: "BTC/USD",
          start_time: ~U[2024-01-01 00:00:00Z],
          end_time: ~U[2024-01-02 00:00:00Z],
          initial_capital: Decimal.new("10000.00"),
          timeframe: "1h"
        })

        # Start the backtest
        {:ok, started_session} = Backtesting.start_backtest(session.id)
        started_session
      end

      # Verify all are running
      assert Enum.all?(running_sessions, fn s -> s.status == "running" end)

      # Try to start one more backtest - should be queued
      {:ok, queued_session} = Backtesting.create_backtest(%{
        strategy_id: strategy_id,
        trading_pair: "BTC/USD",
        start_time: ~U[2024-01-01 00:00:00Z],
        end_time: ~U[2024-01-02 00:00:00Z],
        initial_capital: Decimal.new("10000.00"),
        timeframe: "1h"
      })

      {:ok, queued_result} = Backtesting.start_backtest(queued_session.id)

      # Verify it was queued
      assert queued_result.status == "queued"
      assert not is_nil(queued_result.queued_at)
      assert queued_result.metadata["queue_position"] > 0 or queued_result.metadata[:queue_position] > 0
    end

    test "starts queued backtest when slot becomes available", %{strategy_id: strategy_id} do
      max_concurrent = Application.get_env(:trading_strategy, :max_concurrent_backtests, 5)

      # Fill all slots
      running_sessions = for _ <- 1..max_concurrent do
        {:ok, session} = Backtesting.create_backtest(%{
          strategy_id: strategy_id,
          trading_pair: "BTC/USD",
          start_time: ~U[2024-01-01 00:00:00Z],
          end_time: ~U[2024-01-02 00:00:00Z],
          initial_capital: Decimal.new("10000.00"),
          timeframe: "1h"
        })

        {:ok, started_session} = Backtesting.start_backtest(session.id)
        started_session
      end

      # Queue one
      {:ok, queued_session} = Backtesting.create_backtest(%{
        strategy_id: strategy_id,
        trading_pair: "BTC/USD",
        start_time: ~U[2024-01-01 00:00:00Z],
        end_time: ~U[2024-01-02 00:00:00Z],
        initial_capital: Decimal.new("10000.00"),
        timeframe: "1h"
      })

      {:ok, queued_result} = Backtesting.start_backtest(queued_session.id)
      assert queued_result.status == "queued"

      # Complete one of the running backtests to free a slot
      first_session = hd(running_sessions)

      # Create minimal result for finalize_backtest
      minimal_result = %{
        trades: [],
        metrics: %{
          total_return: 0.0,
          total_return_abs: 0.0,
          win_rate: 0.0,
          max_drawdown: 0.0,
          sharpe_ratio: 0.0,
          trade_count: 0,
          winning_trades: 0,
          losing_trades: 0,
          average_win: 0.0,
          average_loss: 0.0,
          profit_factor: 0.0,
          average_trade_duration_minutes: 0,
          max_consecutive_wins: 0,
          max_consecutive_losses: 0,
          equity_curve: [],
          equity_curve_metadata: %{}
        },
        config: %{
          trading_pair: "BTC/USD",
          start_time: ~U[2024-01-01 00:00:00Z],
          end_time: ~U[2024-01-02 00:00:00Z]
        }
      }

      Backtesting.finalize_backtest(first_session.id, minimal_result)

      # Wait for queue processing
      Process.sleep(200)

      # Verify queued backtest started
      refreshed_session = Repo.get(TradingSession, queued_session.id)
      assert refreshed_session.status == "running"
    end

    test "multiple queued backtests start in FIFO order", %{strategy_id: strategy_id} do
      max_concurrent = Application.get_env(:trading_strategy, :max_concurrent_backtests, 5)

      # Fill all slots
      running_sessions = for _ <- 1..max_concurrent do
        {:ok, session} = Backtesting.create_backtest(%{
          strategy_id: strategy_id,
          trading_pair: "BTC/USD",
          start_time: ~U[2024-01-01 00:00:00Z],
          end_time: ~U[2024-01-02 00:00:00Z],
          initial_capital: Decimal.new("10000.00"),
          timeframe: "1h"
        })

        {:ok, started_session} = Backtesting.start_backtest(session.id)
        started_session
      end

      # Queue multiple backtests
      queued_ids = for i <- 1..3 do
        {:ok, session} = Backtesting.create_backtest(%{
          strategy_id: strategy_id,
          trading_pair: "BTC/USD",
          start_time: ~U[2024-01-01 00:00:00Z],
          end_time: ~U[2024-01-02 00:00:00Z],
          initial_capital: Decimal.new("10000.00"),
          timeframe: "1h"
        })

        {:ok, queued} = Backtesting.start_backtest(session.id)
        assert queued.status == "queued"
        # Check queue position in metadata (handle both string and atom keys)
        queue_pos = queued.metadata["queue_position"] || queued.metadata[:queue_position]
        assert queue_pos == i, "Expected queue position #{i}, got #{inspect(queue_pos)}"

        session.id
      end

      # Create minimal result for finalize_backtest
      minimal_result = %{
        trades: [],
        metrics: %{
          total_return: 0.0,
          total_return_abs: 0.0,
          win_rate: 0.0,
          max_drawdown: 0.0,
          sharpe_ratio: 0.0,
          trade_count: 0,
          winning_trades: 0,
          losing_trades: 0,
          average_win: 0.0,
          average_loss: 0.0,
          profit_factor: 0.0,
          average_trade_duration_minutes: 0,
          max_consecutive_wins: 0,
          max_consecutive_losses: 0,
          equity_curve: [],
          equity_curve_metadata: %{}
        },
        config: %{
          trading_pair: "BTC/USD",
          start_time: ~U[2024-01-01 00:00:00Z],
          end_time: ~U[2024-01-02 00:00:00Z]
        }
      }

      # Release slots one by one
      for {running_session, expected_queued_id} <- Enum.zip(running_sessions, queued_ids) do
        Backtesting.finalize_backtest(running_session.id, minimal_result)

        Process.sleep(200)

        # Verify correct queued backtest started (FIFO)
        started_session = Repo.get(TradingSession, expected_queued_id)
        assert started_session.status == "running",
          "Expected session #{expected_queued_id} to be running, got #{started_session.status}"
      end
    end
  end

  describe "restart detection and state recovery" do
    setup do
      # Reset ConcurrencyManager state before each test
      TradingStrategy.Backtesting.ConcurrencyManager.reset()

      # Create a test strategy with valid content
      {:ok, strategy} = create_test_strategy(%{
        name: "Test Strategy",
        description: "For restart testing"
      })

      {:ok, strategy_id: strategy.id}
    end

    test "detects stale running sessions on application start", %{strategy_id: strategy_id} do
      # Create sessions with "running" status (simulating crash scenario)
      stale_sessions = for _ <- 1..3 do
        {:ok, session} = %TradingSession{}
          |> TradingSession.changeset(%{
            strategy_id: strategy_id,
            mode: "backtest",
            status: "running",  # Stale status
            initial_capital: Decimal.new("10000.00"),
            current_capital: Decimal.new("10000.00"),
            started_at: DateTime.utc_now() |> DateTime.add(-3600, :second),  # Started 1 hour ago
            config: %{
              "trading_pair" => "BTC/USD",
              "start_time" => ~U[2024-01-01 00:00:00Z],
              "end_time" => ~U[2024-01-02 00:00:00Z],
              "timeframe" => "1h"
            },
            metadata: %{
              checkpoint: %{
                bar_index: 500,
                bars_processed: 500,
                total_bars: 1000,
                last_equity: Decimal.new("10050.00"),
                checkpointed_at: DateTime.utc_now() |> DateTime.add(-1800, :second)
              }
            }
          })
          |> Repo.insert()

        session
      end

      # Create a completed session (should not be affected)
      {:ok, completed_session} = %TradingSession{}
        |> TradingSession.changeset(%{
          strategy_id: strategy_id,
          mode: "backtest",
          status: "completed",
          initial_capital: Decimal.new("10000.00"),
          current_capital: Decimal.new("10500.00"),
          started_at: DateTime.utc_now() |> DateTime.add(-7200, :second),
          ended_at: DateTime.utc_now() |> DateTime.add(-3600, :second),
          config: %{
            "trading_pair" => "BTC/USD",
            "start_time" => ~U[2024-01-01 00:00:00Z],
            "end_time" => ~U[2024-01-02 00:00:00Z],
            "timeframe" => "1h"
          }
        })
        |> Repo.insert()

      # Call the restart detection function
      Backtesting.detect_and_mark_stale_sessions()

      # Verify stale sessions were marked as error
      for session <- stale_sessions do
        refreshed = Repo.get(TradingSession, session.id)
        assert refreshed.status == "error"
        assert refreshed.metadata["error_type"] == "application_restart"
        assert not is_nil(refreshed.metadata["error_message"])
        assert refreshed.metadata["partial_data_saved"] == true
      end

      # Verify completed session was not affected
      refreshed_completed = Repo.get(TradingSession, completed_session.id)
      assert refreshed_completed.status == "completed"
    end

    test "preserves checkpoint data when marking session as failed", %{strategy_id: strategy_id} do
      checkpoint_data = %{
        bar_index: 2500,
        bars_processed: 2500,
        total_bars: 5000,
        last_equity: Decimal.new("10750.00"),
        completed_trades: 15,
        checkpointed_at: DateTime.utc_now() |> DateTime.add(-900, :second)
      }

      {:ok, session} = %TradingSession{}
        |> TradingSession.changeset(%{
          strategy_id: strategy_id,
          mode: "backtest",
          status: "running",
          initial_capital: Decimal.new("10000.00"),
          current_capital: Decimal.new("10750.00"),
          started_at: DateTime.utc_now() |> DateTime.add(-1800, :second),
          config: %{
            "trading_pair" => "BTC/USD",
            "start_time" => ~U[2024-01-01 00:00:00Z],
            "end_time" => ~U[2024-01-03 00:00:00Z],
            "timeframe" => "1h"
          },
          metadata: %{checkpoint: checkpoint_data}
        })
        |> Repo.insert()

      # Mark as failed
      {:ok, failed_session} = Backtesting.mark_as_failed(
        session.id,
        "application_restart",
        "Backtest interrupted by application restart at 50% completion"
      )

      # Verify checkpoint data is preserved
      assert failed_session.status == "error"

      # Convert checkpoint data to strings for comparison (database stores as strings)
      expected_checkpoint = %{
        "bar_index" => checkpoint_data.bar_index,
        "bars_processed" => checkpoint_data.bars_processed,
        "total_bars" => checkpoint_data.total_bars,
        "last_equity" => Decimal.to_string(checkpoint_data.last_equity),
        "completed_trades" => checkpoint_data.completed_trades,
        "checkpointed_at" => DateTime.to_iso8601(checkpoint_data.checkpointed_at)
      }

      assert failed_session.metadata["checkpoint"] == expected_checkpoint
      assert failed_session.metadata["error_type"] == "application_restart"
      assert failed_session.metadata["partial_data_saved"] == true
    end

    test "completed sessions are not affected by restart detection", %{strategy_id: strategy_id} do
      # Create multiple sessions with different statuses
      {:ok, completed1} = %TradingSession{}
        |> TradingSession.changeset(%{
          strategy_id: strategy_id,
          mode: "backtest",
          status: "completed",
          initial_capital: Decimal.new("10000.00"),
          current_capital: Decimal.new("10500.00"),
          started_at: DateTime.utc_now() |> DateTime.add(-7200, :second),
          ended_at: DateTime.utc_now() |> DateTime.add(-3600, :second),
          config: %{"trading_pair" => "BTC/USD"}
        })
        |> Repo.insert()

      {:ok, stopped} = %TradingSession{}
        |> TradingSession.changeset(%{
          strategy_id: strategy_id,
          mode: "backtest",
          status: "stopped",
          initial_capital: Decimal.new("10000.00"),
          current_capital: Decimal.new("10200.00"),
          started_at: DateTime.utc_now() |> DateTime.add(-5400, :second),
          ended_at: DateTime.utc_now() |> DateTime.add(-3000, :second),
          config: %{"trading_pair" => "BTC/USD"}
        })
        |> Repo.insert()

      {:ok, error} = %TradingSession{}
        |> TradingSession.changeset(%{
          strategy_id: strategy_id,
          mode: "backtest",
          status: "error",
          initial_capital: Decimal.new("10000.00"),
          current_capital: Decimal.new("10000.00"),
          started_at: DateTime.utc_now() |> DateTime.add(-3600, :second),
          ended_at: DateTime.utc_now() |> DateTime.add(-1800, :second),
          config: %{"trading_pair" => "BTC/USD"},
          metadata: %{"error_type" => "data_validation"}
        })
        |> Repo.insert()

      # Run restart detection
      Backtesting.detect_and_mark_stale_sessions()

      # Verify all terminal states are preserved
      assert Repo.get(TradingSession, completed1.id).status == "completed"
      assert Repo.get(TradingSession, stopped.id).status == "stopped"

      error_session = Repo.get(TradingSession, error.id)
      assert error_session.status == "error"
      assert error_session.metadata["error_type"] == "data_validation"
    end
  end
end
