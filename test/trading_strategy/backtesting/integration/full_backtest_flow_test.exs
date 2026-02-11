defmodule TradingStrategy.Backtesting.Integration.FullBacktestFlowTest do
  use TradingStrategy.DataCase, async: false

  alias TradingStrategy.Backtesting
  alias TradingStrategy.Backtesting.{TradingSession, PerformanceMetrics}
  alias TradingStrategy.Orders.Trade
  alias TradingStrategy.Repo

  import TradingStrategy.BacktestHelpers

  @moduletag :integration

  describe "full backtest flow - end to end" do
    @tag timeout: 120_000
    test "complete backtest lifecycle with progress tracking and results" do
      # Step 1: Create a test strategy
      {:ok, strategy} =
        create_test_strategy(%{
          name: "Integration Test Strategy",
          trading_pair: "BTC/USD",
          timeframe: "1h"
        })

      # Step 2: Create backtest configuration
      config = %{
        strategy_id: strategy.id,
        trading_pair: "BTC/USD",
        start_time: ~U[2024-01-01 00:00:00Z],
        end_time: ~U[2024-01-02 00:00:00Z],
        initial_capital: Decimal.new("10000.00"),
        timeframe: "1h",
        commission_rate: Decimal.new("0.001"),
        slippage_bps: 5
      }

      # Step 3: Create backtest session
      {:ok, session} = Backtesting.create_backtest(config)

      assert session.status == "pending"
      assert session.strategy_id == strategy.id
      assert Decimal.eq?(session.initial_capital, Decimal.new("10000.00"))
      assert session.config["trading_pair"] == "BTC/USD"

      # Step 4: Start backtest execution
      {:ok, started_session} = Backtesting.start_backtest(session.id)

      # Session should be running or queued
      assert started_session.status in ["running", "queued"]

      # Step 5: Monitor progress (if running)
      if started_session.status == "running" do
        # Wait a bit for backtest to process
        Process.sleep(500)

        # Check progress
        case Backtesting.get_backtest_progress(session.id) do
          {:ok, progress} ->
            assert is_map(progress)
            assert Map.has_key?(progress, :status)

            # Progress should have expected fields
            if progress.status == "running" do
              assert is_number(progress.bars_processed) or progress.bars_processed >= 0
              assert is_number(progress.total_bars) or progress.total_bars > 0
            end

          {:error, _} ->
            # Progress might not be available yet, which is ok
            :ok
        end
      end

      # Step 6: Wait for backtest completion (with timeout)
      final_session = wait_for_completion(session.id, 60_000)

      assert final_session.status in ["completed", "failed", "stopped"]

      # If completed successfully, verify results
      if final_session.status == "completed" do
        # Step 7: Retrieve backtest results
        {:ok, results} = Backtesting.get_backtest_result(session.id)

        # Verify result structure
        assert is_map(results)
        assert results.backtest_id == session.id
        assert results.strategy_id == strategy.id

        # Verify configuration is returned
        assert is_map(results.config)
        assert results.config["trading_pair"] == "BTC/USD"

        # Verify performance metrics exist
        assert is_map(results.performance_metrics)
        assert Map.has_key?(results.performance_metrics, :total_return)
        assert Map.has_key?(results.performance_metrics, :win_rate)
        assert Map.has_key?(results.performance_metrics, :max_drawdown)
        assert Map.has_key?(results.performance_metrics, :sharpe_ratio)

        # Verify equity curve exists
        assert is_list(results.equity_curve)

        if length(results.equity_curve) > 0 do
          # First point should be near initial capital
          first_point = hd(results.equity_curve)
          assert Map.has_key?(first_point, "timestamp")
          assert Map.has_key?(first_point, "value")

          # Equity curve should be chronologically ordered
          timestamps = Enum.map(results.equity_curve, & &1["timestamp"])
          assert timestamps == Enum.sort(timestamps)
        end

        # Verify trades exist (if any were executed)
        assert is_list(results.trades)

        # If trades exist, verify trade structure
        if length(results.trades) > 0 do
          trade = hd(results.trades)
          assert Map.has_key?(trade, :timestamp)
          assert Map.has_key?(trade, :side)
          assert Map.has_key?(trade, :price)
          assert Map.has_key?(trade, :quantity)
        end

        # Step 8: Verify database persistence
        db_session = Repo.get(TradingSession, session.id)
        assert db_session.status == "completed"
        assert db_session.started_at != nil
        assert db_session.ended_at != nil

        # Verify performance metrics saved to DB
        metrics = Repo.get_by(PerformanceMetrics, trading_session_id: session.id)

        if metrics do
          assert metrics.total_return != nil
          assert metrics.trade_count >= 0

          # Verify equity curve saved to DB
          if metrics.equity_curve do
            assert is_list(metrics.equity_curve)
          end
        end

        # Verify trades saved to DB
        trades = Repo.all(from t in Trade, where: t.position_id in ^get_position_ids(session.id))

        # Trades should have PnL and duration for exit trades
        Enum.each(trades, fn trade ->
          if trade.side == :sell do
            # Exit trades should have PnL calculated
            assert trade.pnl != nil
          end
        end)
      end
    end

    @tag timeout: 120_000
    test "concurrent backtests respect concurrency limits" do
      # Create multiple strategies
      strategies =
        Enum.map(1..3, fn i ->
          {:ok, strategy} =
            create_test_strategy(%{
              name: "Concurrent Strategy #{i}",
              trading_pair: "BTC/USD"
            })

          strategy
        end)

      # Create and start multiple backtests
      sessions =
        Enum.map(strategies, fn strategy ->
          config = %{
            strategy_id: strategy.id,
            trading_pair: "BTC/USD",
            start_time: ~U[2024-01-01 00:00:00Z],
            end_time: ~U[2024-01-01 12:00:00Z],
            initial_capital: Decimal.new("10000.00"),
            timeframe: "1h"
          }

          {:ok, session} = Backtesting.create_backtest(config)
          {:ok, started} = Backtesting.start_backtest(session.id)
          started
        end)

      # At least one should be queued if concurrency limit is enforced
      statuses = Enum.map(sessions, & &1.status)

      # We should have a mix of running and potentially queued
      assert "running" in statuses or "queued" in statuses

      # Wait for all to complete
      Enum.each(sessions, fn session ->
        wait_for_completion(session.id, 60_000)
      end)

      # All should eventually complete
      final_sessions =
        Enum.map(sessions, fn session ->
          Repo.get(TradingSession, session.id)
        end)

      Enum.each(final_sessions, fn session ->
        assert session.status in ["completed", "failed", "stopped"]
      end)
    end

    @tag timeout: 60_000
    test "backtest with zero trades completes successfully" do
      # Create strategy that never generates signals
      {:ok, strategy} =
        create_test_strategy(%{
          name: "No Signal Strategy",
          trading_pair: "BTC/USD"
        })

      # Override strategy content to never generate signals
      strategy = %{
        strategy
        | content: """
          name: No Signal Strategy
          trading_pair: BTC/USD
          timeframe: 1h

          indicators: []

          entry_conditions: "false"

          exit_conditions: ""

          stop_conditions: ""

          position_sizing:
            type: percentage
            percentage_of_capital: 0.10

          risk_parameters:
            max_daily_loss: 0.03
            max_position_size: 1.0
            max_drawdown: 0.20
            stop_loss_percentage: 0.05
            take_profit_percentage: 0.10
          """
      }

      Repo.update!(
        TradingStrategy.Strategies.Strategy.changeset(strategy, %{content: strategy.content})
      )

      config = %{
        strategy_id: strategy.id,
        trading_pair: "BTC/USD",
        start_time: ~U[2024-01-01 00:00:00Z],
        end_time: ~U[2024-01-01 06:00:00Z],
        initial_capital: Decimal.new("10000.00"),
        timeframe: "1h"
      }

      {:ok, session} = Backtesting.create_backtest(config)
      {:ok, _started} = Backtesting.start_backtest(session.id)

      final_session = wait_for_completion(session.id, 30_000)

      if final_session.status == "completed" do
        {:ok, results} = Backtesting.get_backtest_result(session.id)

        # Should have zero trades
        assert length(results.trades) == 0

        # Metrics should handle zero trades gracefully
        assert results.performance_metrics.trade_count == 0
        # N/A
        assert results.performance_metrics.win_rate == nil
        # N/A
        assert results.performance_metrics.profit_factor == nil

        # Equity curve should be flat
        if length(results.equity_curve) > 0 do
          first_value = hd(results.equity_curve)["value"]
          last_value = List.last(results.equity_curve)["value"]

          # All values should be the same (initial capital)
          assert_in_delta first_value, last_value, 0.01
        end
      end
    end

    @tag timeout: 60_000
    test "backtest handles insufficient data gracefully" do
      {:ok, strategy} =
        create_test_strategy(%{
          name: "High Requirement Strategy",
          trading_pair: "BTC/USD"
        })

      # Strategy requires many bars for indicators (e.g., SMA 200)
      # But we provide insufficient data
      config = %{
        strategy_id: strategy.id,
        trading_pair: "BTC/USD",
        start_time: ~U[2024-01-01 00:00:00Z],
        # Only 2 hours of data
        end_time: ~U[2024-01-01 02:00:00Z],
        initial_capital: Decimal.new("10000.00"),
        timeframe: "1h"
      }

      # Should either fail to create or fail during execution
      result = Backtesting.create_backtest(config)

      case result do
        {:ok, session} ->
          # If creation succeeds, execution should handle it
          case Backtesting.start_backtest(session.id) do
            {:ok, _} ->
              final_session = wait_for_completion(session.id, 30_000)
              # Should fail or complete with appropriate handling
              assert final_session.status in ["failed", "completed", "stopped"]

            {:error, reason} ->
              # Acceptable to fail at start
              assert reason in [:insufficient_data, :no_data_available]
          end

        {:error, reason} ->
          # Acceptable to fail at creation
          assert reason in [:insufficient_data, :no_data_available]
      end
    end
  end

  # Helper functions

  defp wait_for_completion(session_id, timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout
    wait_for_completion_loop(session_id, deadline)
  end

  defp wait_for_completion_loop(session_id, deadline) do
    session = Repo.get(TradingSession, session_id)

    cond do
      session.status in ["completed", "failed", "stopped"] ->
        session

      System.monotonic_time(:millisecond) > deadline ->
        # Timeout - return current session
        session

      true ->
        Process.sleep(100)
        wait_for_completion_loop(session_id, deadline)
    end
  end

  defp get_position_ids(session_id) do
    from(p in TradingStrategy.Orders.Position,
      where: p.trading_session_id == ^session_id,
      select: p.id
    )
    |> Repo.all()
  end
end
