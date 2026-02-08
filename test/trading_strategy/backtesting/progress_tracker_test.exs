defmodule TradingStrategy.Backtesting.ProgressTrackerTest do
  @moduledoc """
  Unit tests for ProgressTracker GenServer.

  Tests the core functionality of progress tracking with ETS:
  - Initializing tracking for new backtests
  - Fast ETS updates during execution
  - Accurate progress retrieval
  - Cleanup after completion
  - Stale record cleanup
  """
  use ExUnit.Case, async: true

  alias TradingStrategy.Backtesting.ProgressTracker

  setup do
    session_id = Ecto.UUID.generate()
    {:ok, session_id: session_id}
  end

  describe "track/2" do
    test "initializes progress tracking for new backtest", %{session_id: session_id} do
      ProgressTracker.track(session_id, 1000)

      # Give the GenServer a moment to process the cast
      Process.sleep(10)

      assert {:ok, progress} = ProgressTracker.get(session_id)
      assert progress.bars_processed == 0
      assert progress.total_bars == 1000
      assert progress.percentage == 0.0
      assert is_integer(progress.updated_at)
    end

    test "allows tracking multiple sessions simultaneously" do
      session1 = Ecto.UUID.generate()
      session2 = Ecto.UUID.generate()

      ProgressTracker.track(session1, 500)
      ProgressTracker.track(session2, 1000)

      Process.sleep(10)

      assert {:ok, progress1} = ProgressTracker.get(session1)
      assert {:ok, progress2} = ProgressTracker.get(session2)

      assert progress1.total_bars == 500
      assert progress2.total_bars == 1000
    end
  end

  describe "update/2" do
    test "updates bars processed and recalculates percentage", %{session_id: session_id} do
      ProgressTracker.track(session_id, 1000)
      Process.sleep(10)

      # Update to 25%
      ProgressTracker.update(session_id, 250)
      assert {:ok, progress} = ProgressTracker.get(session_id)
      assert progress.bars_processed == 250
      assert progress.percentage == 25.0

      # Update to 50%
      ProgressTracker.update(session_id, 500)
      assert {:ok, progress} = ProgressTracker.get(session_id)
      assert progress.bars_processed == 500
      assert progress.percentage == 50.0

      # Update to 100%
      ProgressTracker.update(session_id, 1000)
      assert {:ok, progress} = ProgressTracker.get(session_id)
      assert progress.bars_processed == 1000
      assert progress.percentage == 100.0
    end

    test "handles non-existent session gracefully", %{session_id: session_id} do
      # Should not crash, just log warning
      assert :ok = ProgressTracker.update(session_id, 100)
    end

    test "updates timestamp on each update", %{session_id: session_id} do
      ProgressTracker.track(session_id, 1000)
      Process.sleep(10)

      {:ok, progress1} = ProgressTracker.get(session_id)
      timestamp1 = progress1.updated_at

      Process.sleep(10)

      ProgressTracker.update(session_id, 500)
      {:ok, progress2} = ProgressTracker.get(session_id)
      timestamp2 = progress2.updated_at

      assert timestamp2 > timestamp1
    end
  end

  describe "get/1" do
    test "returns accurate progress data", %{session_id: session_id} do
      ProgressTracker.track(session_id, 2000)
      Process.sleep(10)

      ProgressTracker.update(session_id, 600)

      assert {:ok, progress} = ProgressTracker.get(session_id)
      assert progress.bars_processed == 600
      assert progress.total_bars == 2000
      assert progress.percentage == 30.0
      assert is_integer(progress.updated_at)
    end

    test "returns error for unknown session" do
      unknown_id = Ecto.UUID.generate()
      assert {:error, :not_found} = ProgressTracker.get(unknown_id)
    end

    test "handles edge case of zero total bars", %{session_id: session_id} do
      ProgressTracker.track(session_id, 0)
      Process.sleep(10)

      assert {:ok, progress} = ProgressTracker.get(session_id)
      assert progress.percentage == 0.0
    end
  end

  describe "complete/1" do
    test "removes progress record after backtest completion", %{session_id: session_id} do
      ProgressTracker.track(session_id, 1000)
      Process.sleep(10)

      assert {:ok, _progress} = ProgressTracker.get(session_id)

      ProgressTracker.complete(session_id)

      assert {:error, :not_found} = ProgressTracker.get(session_id)
    end

    test "handles completing non-existent session gracefully", %{session_id: session_id} do
      # Should not crash
      assert :ok = ProgressTracker.complete(session_id)
    end
  end

  describe "accuracy scenarios" do
    test "calculates percentage with high precision for large datasets", %{
      session_id: session_id
    } do
      # Test with 50,000 bars (typical year of hourly data)
      total_bars = 50_000
      ProgressTracker.track(session_id, total_bars)
      Process.sleep(10)

      # Process 1/3
      bars_at_third = div(total_bars, 3)
      ProgressTracker.update(session_id, bars_at_third)

      {:ok, progress} = ProgressTracker.get(session_id)
      # Should be close to 33.33%
      assert_in_delta progress.percentage, 33.33, 0.01
    end

    test "handles rapid consecutive updates", %{session_id: session_id} do
      ProgressTracker.track(session_id, 10_000)
      Process.sleep(10)

      # Simulate rapid updates (every 100 bars)
      for i <- 1..100 do
        ProgressTracker.update(session_id, i * 100)
      end

      {:ok, progress} = ProgressTracker.get(session_id)
      assert progress.bars_processed == 10_000
      assert progress.percentage == 100.0
    end

    test "maintains accuracy with decimal percentages", %{session_id: session_id} do
      ProgressTracker.track(session_id, 7500)
      Process.sleep(10)

      ProgressTracker.update(session_id, 2250)

      {:ok, progress} = ProgressTracker.get(session_id)
      # 2250 / 7500 = 0.30 = 30.0%
      assert progress.percentage == 30.0
    end
  end
end
