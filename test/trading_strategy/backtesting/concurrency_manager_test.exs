defmodule TradingStrategy.Backtesting.ConcurrencyManagerTest do
  use ExUnit.Case, async: false

  alias TradingStrategy.Backtesting.ConcurrencyManager

  setup do
    # Stop the existing ConcurrencyManager if running
    case Process.whereis(ConcurrencyManager) do
      nil -> :ok
      pid -> GenServer.stop(pid)
    end

    # Start a fresh ConcurrencyManager for testing
    {:ok, pid} = ConcurrencyManager.start_link(max_concurrent: 3)

    on_exit(fn ->
      if Process.alive?(pid), do: GenServer.stop(pid)
    end)

    {:ok, pid: pid}
  end

  describe "slot management" do
    test "grants slot when capacity available" do
      session_id = Ecto.UUID.generate()

      assert {:ok, :granted} = ConcurrencyManager.request_slot(session_id)
    end

    test "tracks running sessions" do
      session1 = Ecto.UUID.generate()
      session2 = Ecto.UUID.generate()

      {:ok, :granted} = ConcurrencyManager.request_slot(session1)
      {:ok, :granted} = ConcurrencyManager.request_slot(session2)

      status = ConcurrencyManager.get_status()

      assert MapSet.size(status.running) == 2
      assert MapSet.member?(status.running, session1)
      assert MapSet.member?(status.running, session2)
    end

    test "queues requests when max concurrent reached" do
      session1 = Ecto.UUID.generate()
      session2 = Ecto.UUID.generate()
      session3 = Ecto.UUID.generate()
      session4 = Ecto.UUID.generate()

      # Fill all slots (max_concurrent = 3)
      {:ok, :granted} = ConcurrencyManager.request_slot(session1)
      {:ok, :granted} = ConcurrencyManager.request_slot(session2)
      {:ok, :granted} = ConcurrencyManager.request_slot(session3)

      # Next request should be queued
      assert {:ok, {:queued, 1}} = ConcurrencyManager.request_slot(session4)

      status = ConcurrencyManager.get_status()
      assert MapSet.size(status.running) == 3
      assert :queue.len(status.queue) == 1
    end

    test "releases slot and removes from running set" do
      session_id = Ecto.UUID.generate()

      {:ok, :granted} = ConcurrencyManager.request_slot(session_id)
      :ok = ConcurrencyManager.release_slot(session_id)

      status = ConcurrencyManager.get_status()
      assert MapSet.size(status.running) == 0
    end

    test "grants slot to queued request after release" do
      session1 = Ecto.UUID.generate()
      session2 = Ecto.UUID.generate()
      session3 = Ecto.UUID.generate()
      session4 = Ecto.UUID.generate()

      # Fill all slots
      {:ok, :granted} = ConcurrencyManager.request_slot(session1)
      {:ok, :granted} = ConcurrencyManager.request_slot(session2)
      {:ok, :granted} = ConcurrencyManager.request_slot(session3)

      # Queue next request
      {:ok, {:queued, 1}} = ConcurrencyManager.request_slot(session4)

      # Release one slot
      :ok = ConcurrencyManager.release_slot(session1)

      # Wait a bit for the dequeue to process
      Process.sleep(50)

      status = ConcurrencyManager.get_status()
      assert MapSet.size(status.running) == 3
      assert MapSet.member?(status.running, session4)
      assert :queue.len(status.queue) == 0
    end

    test "handles release of non-existent session gracefully" do
      session_id = Ecto.UUID.generate()

      assert :ok = ConcurrencyManager.release_slot(session_id)
    end

    test "prevents duplicate slot requests for same session" do
      session_id = Ecto.UUID.generate()

      {:ok, :granted} = ConcurrencyManager.request_slot(session_id)

      # Second request for same session should be rejected
      assert {:error, :already_running} = ConcurrencyManager.request_slot(session_id)
    end
  end

  describe "capacity management" do
    test "respects max_concurrent configuration" do
      session1 = Ecto.UUID.generate()
      session2 = Ecto.UUID.generate()
      session3 = Ecto.UUID.generate()
      session4 = Ecto.UUID.generate()

      {:ok, :granted} = ConcurrencyManager.request_slot(session1)
      {:ok, :granted} = ConcurrencyManager.request_slot(session2)
      {:ok, :granted} = ConcurrencyManager.request_slot(session3)

      # Should queue when max reached
      assert {:ok, {:queued, 1}} = ConcurrencyManager.request_slot(session4)
    end

    test "returns current status with running count and queue depth" do
      session1 = Ecto.UUID.generate()
      session2 = Ecto.UUID.generate()
      session3 = Ecto.UUID.generate()
      session4 = Ecto.UUID.generate()
      session5 = Ecto.UUID.generate()

      {:ok, :granted} = ConcurrencyManager.request_slot(session1)
      {:ok, :granted} = ConcurrencyManager.request_slot(session2)
      {:ok, :granted} = ConcurrencyManager.request_slot(session3)
      {:ok, {:queued, 1}} = ConcurrencyManager.request_slot(session4)
      {:ok, {:queued, 2}} = ConcurrencyManager.request_slot(session5)

      status = ConcurrencyManager.get_status()

      assert MapSet.size(status.running) == 3
      assert :queue.len(status.queue) == 2
      assert status.max_concurrent == 3
    end
  end

  describe "FIFO queue management" do
    test "processes queue in FIFO order" do
      session1 = Ecto.UUID.generate()
      session2 = Ecto.UUID.generate()
      session3 = Ecto.UUID.generate()
      session4 = Ecto.UUID.generate()
      session5 = Ecto.UUID.generate()
      session6 = Ecto.UUID.generate()

      # Fill slots
      {:ok, :granted} = ConcurrencyManager.request_slot(session1)
      {:ok, :granted} = ConcurrencyManager.request_slot(session2)
      {:ok, :granted} = ConcurrencyManager.request_slot(session3)

      # Queue multiple requests
      {:ok, {:queued, 1}} = ConcurrencyManager.request_slot(session4)
      {:ok, {:queued, 2}} = ConcurrencyManager.request_slot(session5)
      {:ok, {:queued, 3}} = ConcurrencyManager.request_slot(session6)

      # Release first slot
      :ok = ConcurrencyManager.release_slot(session1)
      Process.sleep(50)

      # session4 should now be running (FIFO)
      status = ConcurrencyManager.get_status()
      assert MapSet.member?(status.running, session4)
      assert :queue.len(status.queue) == 2

      # Release second slot
      :ok = ConcurrencyManager.release_slot(session2)
      Process.sleep(50)

      # session5 should now be running (FIFO)
      status = ConcurrencyManager.get_status()
      assert MapSet.member?(status.running, session5)
      assert :queue.len(status.queue) == 1
    end

    test "returns correct queue position" do
      session1 = Ecto.UUID.generate()
      session2 = Ecto.UUID.generate()
      session3 = Ecto.UUID.generate()
      session4 = Ecto.UUID.generate()
      session5 = Ecto.UUID.generate()
      session6 = Ecto.UUID.generate()

      {:ok, :granted} = ConcurrencyManager.request_slot(session1)
      {:ok, :granted} = ConcurrencyManager.request_slot(session2)
      {:ok, :granted} = ConcurrencyManager.request_slot(session3)

      {:ok, {:queued, pos1}} = ConcurrencyManager.request_slot(session4)
      {:ok, {:queued, pos2}} = ConcurrencyManager.request_slot(session5)
      {:ok, {:queued, pos3}} = ConcurrencyManager.request_slot(session6)

      assert pos1 == 1
      assert pos2 == 2
      assert pos3 == 3
    end

    test "maintains queue order after multiple operations" do
      sessions = for _ <- 1..10, do: Ecto.UUID.generate()
      [s1, s2, s3 | queued_sessions] = sessions

      # Fill slots
      {:ok, :granted} = ConcurrencyManager.request_slot(s1)
      {:ok, :granted} = ConcurrencyManager.request_slot(s2)
      {:ok, :granted} = ConcurrencyManager.request_slot(s3)

      # Queue the rest
      for session <- queued_sessions do
        {:ok, {:queued, _pos}} = ConcurrencyManager.request_slot(session)
      end

      # Release s1, s2, s3 and verify FIFO order
      initially_running = [s1, s2, s3]

      # Release initial running sessions and verify queued sessions start in FIFO order
      Enum.zip(initially_running, Enum.take(queued_sessions, 3))
      |> Enum.each(fn {running_session, expected_queued} ->
        :ok = ConcurrencyManager.release_slot(running_session)
        Process.sleep(50)

        status = ConcurrencyManager.get_status()

        assert MapSet.member?(status.running, expected_queued),
               "Expected #{expected_queued} to be running in FIFO order"
      end)

      # Release the sessions that just got promoted and verify next queued sessions
      Enum.take(queued_sessions, 3)
      |> Enum.zip(Enum.drop(queued_sessions, 3))
      |> Enum.each(fn {promoted_session, next_expected} ->
        :ok = ConcurrencyManager.release_slot(promoted_session)
        Process.sleep(50)

        status = ConcurrencyManager.get_status()

        assert MapSet.member?(status.running, next_expected),
               "Expected #{next_expected} to be running in FIFO order"
      end)
    end

    test "handles empty queue gracefully" do
      session1 = Ecto.UUID.generate()

      {:ok, :granted} = ConcurrencyManager.request_slot(session1)
      :ok = ConcurrencyManager.release_slot(session1)

      # Should not crash when releasing with empty queue
      status = ConcurrencyManager.get_status()
      assert MapSet.size(status.running) == 0
      assert :queue.len(status.queue) == 0
    end
  end

  describe "edge cases" do
    test "handles multiple releases in succession" do
      session1 = Ecto.UUID.generate()
      session2 = Ecto.UUID.generate()
      session3 = Ecto.UUID.generate()

      {:ok, :granted} = ConcurrencyManager.request_slot(session1)
      {:ok, :granted} = ConcurrencyManager.request_slot(session2)
      {:ok, :granted} = ConcurrencyManager.request_slot(session3)

      :ok = ConcurrencyManager.release_slot(session1)
      :ok = ConcurrencyManager.release_slot(session2)
      :ok = ConcurrencyManager.release_slot(session3)

      status = ConcurrencyManager.get_status()
      assert MapSet.size(status.running) == 0
    end

    test "handles queue exhaustion with multiple releases" do
      session1 = Ecto.UUID.generate()
      session2 = Ecto.UUID.generate()
      session3 = Ecto.UUID.generate()
      session4 = Ecto.UUID.generate()
      session5 = Ecto.UUID.generate()

      {:ok, :granted} = ConcurrencyManager.request_slot(session1)
      {:ok, :granted} = ConcurrencyManager.request_slot(session2)
      {:ok, :granted} = ConcurrencyManager.request_slot(session3)
      {:ok, {:queued, 1}} = ConcurrencyManager.request_slot(session4)
      {:ok, {:queued, 2}} = ConcurrencyManager.request_slot(session5)

      # Release all running
      :ok = ConcurrencyManager.release_slot(session1)
      Process.sleep(50)
      :ok = ConcurrencyManager.release_slot(session2)
      Process.sleep(50)

      status = ConcurrencyManager.get_status()
      assert MapSet.size(status.running) == 3
      assert :queue.len(status.queue) == 0
    end
  end
end
