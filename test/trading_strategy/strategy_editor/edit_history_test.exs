defmodule TradingStrategy.StrategyEditor.EditHistoryTest do
  @moduledoc """
  Unit tests for EditHistory GenServer.

  Tests undo/redo stack operations, session management, and persistence.
  """
  # GenServer tests must run sequentially
  use ExUnit.Case, async: false

  alias TradingStrategy.StrategyEditor.{EditHistory, ChangeEvent}

  setup do
    # Ensure EditHistory server is running (should be started by application)
    # Each test gets a unique session ID
    session_id = Ecto.UUID.generate()
    user_id = Ecto.UUID.generate()
    strategy_id = Ecto.UUID.generate()

    {:ok, session_id: session_id, user_id: user_id, strategy_id: strategy_id}
  end

  describe "session management" do
    test "start_session creates a new editing session", %{
      strategy_id: strategy_id,
      user_id: user_id
    } do
      {:ok, session_id} = EditHistory.start_session(strategy_id, user_id)

      assert is_binary(session_id)
      assert String.length(session_id) > 0

      # Session should exist and be accessible
      assert {:ok, %{undo_stack: [], redo_stack: []}} = EditHistory.get_session(session_id)
    end

    test "end_session cleans up session data", %{strategy_id: strategy_id, user_id: user_id} do
      {:ok, session_id} = EditHistory.start_session(strategy_id, user_id)

      # Add some changes
      event = create_test_event(session_id, user_id, :add_indicator)
      EditHistory.push_event(session_id, event)

      # End session
      :ok = EditHistory.end_session(session_id)

      # Session should no longer exist
      assert {:error, :session_not_found} = EditHistory.get_session(session_id)
    end

    test "get_session returns session state", %{strategy_id: strategy_id, user_id: user_id} do
      {:ok, session_id} = EditHistory.start_session(strategy_id, user_id)

      {:ok, state} = EditHistory.get_session(session_id)

      assert %{
               undo_stack: [],
               redo_stack: [],
               max_size: _,
               created_at: _,
               last_modified_at: _
             } = state
    end

    test "session not found error for invalid session ID" do
      invalid_session_id = "nonexistent-session-#{:rand.uniform(1000)}"

      assert {:error, :session_not_found} = EditHistory.get_session(invalid_session_id)
      assert {:error, :session_not_found} = EditHistory.undo(invalid_session_id)
      assert {:error, :session_not_found} = EditHistory.redo(invalid_session_id)
    end
  end

  describe "push_event (undo stack management)" do
    test "push_event adds change to undo stack", %{strategy_id: strategy_id, user_id: user_id} do
      {:ok, session_id} = EditHistory.start_session(strategy_id, user_id)

      event = create_test_event(session_id, user_id, :add_indicator)
      :ok = EditHistory.push_event(session_id, event)

      {:ok, state} = EditHistory.get_session(session_id)
      assert length(state.undo_stack) == 1
      assert hd(state.undo_stack).operation_type == :add_indicator
    end

    test "push_event clears redo stack", %{strategy_id: strategy_id, user_id: user_id} do
      {:ok, session_id} = EditHistory.start_session(strategy_id, user_id)

      # Add event and undo it (creates redo stack)
      event1 = create_test_event(session_id, user_id, :add_indicator)
      EditHistory.push_event(session_id, event1)
      EditHistory.undo(session_id)

      {:ok, state_before} = EditHistory.get_session(session_id)
      assert length(state_before.redo_stack) == 1

      # Push new event - should clear redo stack
      event2 = create_test_event(session_id, user_id, :update_indicator)
      EditHistory.push_event(session_id, event2)

      {:ok, state_after} = EditHistory.get_session(session_id)
      assert length(state_after.redo_stack) == 0
      assert length(state_after.undo_stack) == 1
    end

    test "undo stack enforces max_size limit", %{strategy_id: strategy_id, user_id: user_id} do
      {:ok, session_id} = EditHistory.start_session(strategy_id, user_id)

      # Default max size
      max_size = 100

      # Push more events than max_size
      for i <- 1..(max_size + 20) do
        event = create_test_event(session_id, user_id, :update_indicator, version: i)
        EditHistory.push_event(session_id, event)
      end

      {:ok, state} = EditHistory.get_session(session_id)

      # Stack should be capped at max_size
      assert length(state.undo_stack) <= max_size,
             "Undo stack exceeded max size: #{length(state.undo_stack)} > #{max_size}"

      # Most recent event should still be at the top
      assert hd(state.undo_stack).version == max_size + 20
    end
  end

  describe "undo operation" do
    test "undo pops event from undo stack", %{strategy_id: strategy_id, user_id: user_id} do
      {:ok, session_id} = EditHistory.start_session(strategy_id, user_id)

      event = create_test_event(session_id, user_id, :add_indicator)
      EditHistory.push_event(session_id, event)

      {:ok, undone_event} = EditHistory.undo(session_id)

      assert undone_event.operation_type == :add_indicator

      {:ok, state} = EditHistory.get_session(session_id)
      assert length(state.undo_stack) == 0
      assert length(state.redo_stack) == 1
    end

    test "undo moves event to redo stack", %{strategy_id: strategy_id, user_id: user_id} do
      {:ok, session_id} = EditHistory.start_session(strategy_id, user_id)

      event = create_test_event(session_id, user_id, :add_indicator)
      EditHistory.push_event(session_id, event)

      EditHistory.undo(session_id)

      {:ok, state} = EditHistory.get_session(session_id)
      assert length(state.redo_stack) == 1
      assert hd(state.redo_stack).operation_type == :add_indicator
    end

    test "undo on empty stack returns error", %{strategy_id: strategy_id, user_id: user_id} do
      {:ok, session_id} = EditHistory.start_session(strategy_id, user_id)

      assert {:error, :nothing_to_undo} = EditHistory.undo(session_id)
    end

    test "multiple undos work correctly", %{strategy_id: strategy_id, user_id: user_id} do
      {:ok, session_id} = EditHistory.start_session(strategy_id, user_id)

      # Push 3 events
      events = [
        create_test_event(session_id, user_id, :add_indicator, version: 1),
        create_test_event(session_id, user_id, :update_indicator, version: 2),
        create_test_event(session_id, user_id, :remove_indicator, version: 3)
      ]

      Enum.each(events, &EditHistory.push_event(session_id, &1))

      # Undo all 3
      {:ok, event3} = EditHistory.undo(session_id)
      {:ok, event2} = EditHistory.undo(session_id)
      {:ok, event1} = EditHistory.undo(session_id)

      assert event3.version == 3
      assert event2.version == 2
      assert event1.version == 1

      {:ok, state} = EditHistory.get_session(session_id)
      assert length(state.undo_stack) == 0
      assert length(state.redo_stack) == 3
    end
  end

  describe "redo operation" do
    test "redo pops event from redo stack", %{strategy_id: strategy_id, user_id: user_id} do
      {:ok, session_id} = EditHistory.start_session(strategy_id, user_id)

      event = create_test_event(session_id, user_id, :add_indicator)
      EditHistory.push_event(session_id, event)
      EditHistory.undo(session_id)

      {:ok, redone_event} = EditHistory.redo(session_id)

      assert redone_event.operation_type == :add_indicator

      {:ok, state} = EditHistory.get_session(session_id)
      assert length(state.undo_stack) == 1
      assert length(state.redo_stack) == 0
    end

    test "redo on empty stack returns error", %{strategy_id: strategy_id, user_id: user_id} do
      {:ok, session_id} = EditHistory.start_session(strategy_id, user_id)

      assert {:error, :nothing_to_redo} = EditHistory.redo(session_id)
    end

    test "undo → redo → undo workflow", %{strategy_id: strategy_id, user_id: user_id} do
      {:ok, session_id} = EditHistory.start_session(strategy_id, user_id)

      event = create_test_event(session_id, user_id, :add_indicator)
      EditHistory.push_event(session_id, event)

      # Undo
      {:ok, _} = EditHistory.undo(session_id)
      {:ok, state1} = EditHistory.get_session(session_id)
      assert length(state1.undo_stack) == 0
      assert length(state1.redo_stack) == 1

      # Redo
      {:ok, _} = EditHistory.redo(session_id)
      {:ok, state2} = EditHistory.get_session(session_id)
      assert length(state2.undo_stack) == 1
      assert length(state2.redo_stack) == 0

      # Undo again
      {:ok, _} = EditHistory.undo(session_id)
      {:ok, state3} = EditHistory.get_session(session_id)
      assert length(state3.undo_stack) == 0
      assert length(state3.redo_stack) == 1
    end
  end

  describe "can_undo?/can_redo? status" do
    test "can_undo? returns true when undo stack has events", %{
      strategy_id: strategy_id,
      user_id: user_id
    } do
      {:ok, session_id} = EditHistory.start_session(strategy_id, user_id)

      assert EditHistory.can_undo?(session_id) == false

      event = create_test_event(session_id, user_id, :add_indicator)
      EditHistory.push_event(session_id, event)

      assert EditHistory.can_undo?(session_id) == true
    end

    test "can_redo? returns true when redo stack has events", %{
      strategy_id: strategy_id,
      user_id: user_id
    } do
      {:ok, session_id} = EditHistory.start_session(strategy_id, user_id)

      assert EditHistory.can_redo?(session_id) == false

      event = create_test_event(session_id, user_id, :add_indicator)
      EditHistory.push_event(session_id, event)
      EditHistory.undo(session_id)

      assert EditHistory.can_redo?(session_id) == true
    end
  end

  describe "performance" do
    @tag :benchmark
    test "undo/redo operations complete within 50ms", %{
      strategy_id: strategy_id,
      user_id: user_id
    } do
      {:ok, session_id} = EditHistory.start_session(strategy_id, user_id)

      # Add 100 events
      for i <- 1..100 do
        event = create_test_event(session_id, user_id, :update_indicator, version: i)
        EditHistory.push_event(session_id, event)
      end

      # Benchmark undo
      {undo_time, {:ok, _event}} =
        :timer.tc(fn ->
          EditHistory.undo(session_id)
        end)

      undo_ms = undo_time / 1000

      assert undo_ms < 50,
             "Undo took #{undo_ms}ms, expected < 50ms"

      # Benchmark redo
      {redo_time, {:ok, _event}} =
        :timer.tc(fn ->
          EditHistory.redo(session_id)
        end)

      redo_ms = redo_time / 1000

      assert redo_ms < 50,
             "Redo took #{redo_ms}ms, expected < 50ms"

      IO.puts(
        "\n[PERFORMANCE] Undo: #{Float.round(undo_ms, 2)}ms, Redo: #{Float.round(redo_ms, 2)}ms"
      )
    end
  end

  # Helper Functions

  defp create_test_event(session_id, user_id, operation_type, opts \\ []) do
    version = Keyword.get(opts, :version, 1)

    %ChangeEvent{
      id: Ecto.UUID.generate(),
      session_id: session_id,
      timestamp: System.monotonic_time(:millisecond),
      source: :builder,
      operation_type: operation_type,
      path: ["indicators", 0, "period"],
      delta: {14, 21},
      inverse: {21, 14},
      user_id: user_id,
      version: version
    }
  end
end
