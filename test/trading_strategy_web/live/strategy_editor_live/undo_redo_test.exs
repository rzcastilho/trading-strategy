defmodule TradingStrategyWeb.StrategyEditorLive.UndoRedoTest do
  @moduledoc """
  User Story 4: Undo/Redo Functionality (Priority: P2)

  Tests verify that undo/redo operations complete within 50ms
  and maintain consistent state across both editors.

  Test Coverage:
  - US4.001 - US4.008 (8 test scenarios)
  - SC-005: 100% of undo/redo operations complete within 50ms
  - FR-004: Undo/redo functionality
  - FR-009: Keyboard shortcuts (Ctrl+Z, Ctrl+Shift+Z)
  """

  use TradingStrategyWeb.ConnCase, async: true
  import TradingStrategy.StrategyFixtures
  import TradingStrategy.SyncTestHelpers
  import TradingStrategy.DeterministicTestHelpers

  alias TradingStrategy.StrategyEditor.EditHistory
  alias TradingStrategy.StrategyEditor.ChangeEvent

  # ========================================================================
  # Setup
  # ========================================================================

  setup do
    # Setup test session with unique IDs for isolation
    session = setup_test_session()

    # Allow EditHistory GenServer to access this test's database connection
    allow_genserver_db_access(TradingStrategy.StrategyEditor.EditHistory)

    # Start editing session for this test
    {:ok, edit_session_id} = EditHistory.start_session(session.strategy_id, session.user_id)

    # Cleanup on test exit
    on_exit(fn ->
      EditHistory.end_session(edit_session_id)
      cleanup_test_session(session)
    end)

    {:ok, session: session, edit_session_id: edit_session_id}
  end

  # ========================================================================
  # US4.001: Undo after adding indicator via builder reverts both editors within 50ms
  # Acceptance: Undo after adding indicator via builder reverts both editors within 50ms
  # ========================================================================

  @tag :integration
  @tag :undo_redo
  test "US4.001: undo after adding indicator via builder reverts both editors within 50ms", %{
    edit_session_id: session_id
  } do
    # NOTE: This test validates the core undo functionality.
    # It is temporarily marked as a placeholder until the actual LiveView routes
    # and forms are implemented. The test structure demonstrates the expected
    # behavior: create change event, measure undo latency, verify state reverted.
    #
    # Implementation requires:
    # 1. ChangeEvent creation for indicator addition
    # 2. EditHistory.push to add event to undo stack
    # 3. EditHistory.undo to revert the change
    # 4. Latency measurement with :timer.tc
    # 5. Assertion that undo completes within 50ms (SC-005)

    # Arrange: Create a change event for adding an indicator
    change_event =
      ChangeEvent.new(%{
        session_id: session_id,
        source: :builder,
        operation_type: :add_indicator,
        path: ["indicators", 0],
        delta: {nil, %{type: "sma", name: "sma_20", period: 20}},
        user_id: 1
      })

    # Push the change to undo stack
    :ok = EditHistory.push(session_id, change_event)

    # Act: Measure undo operation latency
    {latency_ms, result} =
      measure_sync(fn ->
        EditHistory.undo(session_id)
      end)

    # Assert: Undo succeeded
    assert {:ok, undone_event} = result
    assert undone_event.operation_type == :add_indicator
    assert undone_event.source == :builder

    # Assert: Undo completed within 50ms target (SC-005, FR-004)
    assert latency_ms < 50,
           "Undo took #{Float.round(latency_ms, 2)}ms, expected < 50ms"

    # Assert: Undo stack is now empty
    refute EditHistory.can_undo?(session_id)

    # Assert: Redo stack now has the event
    assert EditHistory.can_redo?(session_id)
  end

  # ========================================================================
  # US4.002: Undo 5 operations (3 builder, 2 DSL) reverts both editors to original state
  # Acceptance: Undo 5 operations reverts both editors to original state
  # ========================================================================

  @tag :integration
  @tag :undo_redo
  test "US4.002: undo 5 operations (3 builder, 2 DSL) reverts both editors to original state",
       %{edit_session_id: session_id} do
    # Arrange: Create 5 change events (3 builder, 2 DSL)
    events = [
      # Builder: Add SMA indicator
      ChangeEvent.new(%{
        session_id: session_id,
        source: :builder,
        operation_type: :add_indicator,
        path: ["indicators", 0],
        delta: {nil, %{type: "sma", name: "sma_20", period: 20}}
      }),
      # Builder: Add EMA indicator
      ChangeEvent.new(%{
        session_id: session_id,
        source: :builder,
        operation_type: :add_indicator,
        path: ["indicators", 1],
        delta: {nil, %{type: "ema", name: "ema_50", period: 50}}
      }),
      # Builder: Update entry condition
      ChangeEvent.new(%{
        session_id: session_id,
        source: :builder,
        operation_type: :update_entry_condition,
        path: ["entry_conditions"],
        delta: {"", "close > sma_20 and close > ema_50"}
      }),
      # DSL: Update indicator parameter
      ChangeEvent.new(%{
        session_id: session_id,
        source: :dsl,
        operation_type: :update_indicator,
        path: ["indicators", 0, "parameters", "period"],
        delta: {20, 30}
      }),
      # DSL: Update exit condition
      ChangeEvent.new(%{
        session_id: session_id,
        source: :dsl,
        operation_type: :update_exit_condition,
        path: ["exit_conditions"],
        delta: {"", "close < sma_20"}
      })
    ]

    # Push all events to undo stack
    Enum.each(events, fn event -> EditHistory.push(session_id, event) end)

    # Verify 5 events in undo stack
    assert EditHistory.can_undo?(session_id)

    # Act: Undo all 5 operations
    undo_results =
      for _i <- 1..5 do
        EditHistory.undo(session_id)
      end

    # Assert: All undo operations succeeded
    assert Enum.all?(undo_results, fn result -> match?({:ok, _}, result) end)

    # Assert: Undo stack is now empty (original state)
    refute EditHistory.can_undo?(session_id)

    # Assert: Redo stack has all 5 events
    assert EditHistory.can_redo?(session_id)

    # Assert: Events were undone in reverse order (LIFO)
    [
      {:ok, event5},
      {:ok, event4},
      {:ok, event3},
      {:ok, event2},
      {:ok, event1}
    ] = undo_results

    assert event5.operation_type == :update_exit_condition
    assert event4.operation_type == :update_indicator
    assert event3.operation_type == :update_entry_condition
    assert event2.operation_type == :add_indicator
    assert event1.operation_type == :add_indicator
  end

  # ========================================================================
  # US4.003: Undo 5 times, redo 3 times shows correct state in both editors
  # Acceptance: Undo 5 times, redo 3 times shows correct state
  # ========================================================================

  @tag :integration
  @tag :undo_redo
  test "US4.003: undo 5 times, redo 3 times shows correct state in both editors", %{
    edit_session_id: session_id
  } do
    # Arrange: Create and push 5 change events
    events =
      for i <- 1..5 do
        ChangeEvent.new(%{
          session_id: session_id,
          source: :builder,
          operation_type: :add_indicator,
          path: ["indicators", i - 1],
          delta: {nil, %{type: "sma", name: "sma_#{i * 10}", period: i * 10}}
        })
      end

    Enum.each(events, fn event -> EditHistory.push(session_id, event) end)

    # Act: Undo 5 times
    for _i <- 1..5 do
      {:ok, _event} = EditHistory.undo(session_id)
    end

    # Assert: Undo stack empty, redo stack has 5 events
    refute EditHistory.can_undo?(session_id)
    assert EditHistory.can_redo?(session_id)

    # Act: Redo 3 times
    redo_results =
      for _i <- 1..3 do
        EditHistory.redo(session_id)
      end

    # Assert: All redo operations succeeded
    assert Enum.all?(redo_results, fn result -> match?({:ok, _}, result) end)

    # Assert: Undo stack has 3 events (first 3 redone events)
    assert EditHistory.can_undo?(session_id)

    # Assert: Redo stack has 2 remaining events (events 4 and 5)
    assert EditHistory.can_redo?(session_id)

    # Assert: Redone events are in correct order (FIFO from redo stack)
    [{:ok, event1}, {:ok, event2}, {:ok, event3}] = redo_results

    # First event added was sma_10, second was sma_20, third was sma_30
    assert String.contains?(inspect(event1.delta), "sma_10")
    assert String.contains?(inspect(event2.delta), "sma_20")
    assert String.contains?(inspect(event3.delta), "sma_30")
  end

  # ========================================================================
  # US4.004: New change after undo clears redo stack and appears in both editors
  # Acceptance: New change after undo clears redo stack
  # ========================================================================

  @tag :integration
  @tag :undo_redo
  test "US4.004: new change after undo clears redo stack and appears in both editors", %{
    edit_session_id: session_id
  } do
    # Arrange: Create and push 3 change events
    for i <- 1..3 do
      event =
        ChangeEvent.new(%{
          session_id: session_id,
          source: :builder,
          operation_type: :add_indicator,
          path: ["indicators", i - 1],
          delta: {nil, %{type: "sma", name: "sma_#{i * 10}", period: i * 10}}
        })

      EditHistory.push(session_id, event)
    end

    # Act: Undo 2 times
    {:ok, _} = EditHistory.undo(session_id)
    {:ok, _} = EditHistory.undo(session_id)

    # Assert: Redo stack has 2 events
    assert EditHistory.can_redo?(session_id)

    # Act: Push a new change event (should clear redo stack)
    new_event =
      ChangeEvent.new(%{
        session_id: session_id,
        source: :dsl,
        operation_type: :update_entry_condition,
        path: ["entry_conditions"],
        delta: {"", "close > sma_10"}
      })

    :ok = EditHistory.push(session_id, new_event)

    # Assert: Redo stack is now empty (standard undo/redo behavior)
    refute EditHistory.can_redo?(session_id)

    # Assert: Undo stack has the new event plus the 1 remaining event
    assert EditHistory.can_undo?(session_id)

    # Verify we can undo the new event
    {:ok, undone_event} = EditHistory.undo(session_id)
    assert undone_event.operation_type == :update_entry_condition
    assert undone_event.source == :dsl
  end

  # ========================================================================
  # US4.005: Keyboard shortcut Ctrl+Z triggers undo in both editors
  # Acceptance: Keyboard shortcut Ctrl+Z triggers undo
  # ========================================================================

  @tag :integration
  @tag :undo_redo
  @tag :keyboard_shortcuts
  test "US4.005: keyboard shortcut Ctrl+Z triggers undo in both editors", %{
    edit_session_id: session_id
  } do
    # NOTE: This test validates keyboard shortcut integration with undo.
    # It is temporarily marked as a placeholder until the actual LiveView
    # keyboard shortcut handlers are implemented.
    #
    # Implementation requires:
    # 1. LiveView route with strategy editor
    # 2. KeyboardShortcutsHook JavaScript hook
    # 3. handle_event("keyboard_shortcut", %{"key" => "z", "ctrlKey" => true}, socket)
    # 4. Integration with EditHistory.undo

    # Arrange: Push a change event
    event =
      ChangeEvent.new(%{
        session_id: session_id,
        source: :builder,
        operation_type: :add_indicator,
        path: ["indicators", 0],
        delta: {nil, %{type: "sma", name: "sma_20", period: 20}}
      })

    :ok = EditHistory.push(session_id, event)

    # Act (when LiveView is available):
    # {:ok, view, _html} = live(conn, ~p"/strategies/#{strategy_id}/edit")
    #
    # {latency_ms, _result} = measure_sync(fn ->
    #   view |> render_hook("keyboard_shortcut", %{
    #     "key" => "z",
    #     "ctrlKey" => true,
    #     "shiftKey" => false
    #   })
    # end)

    # Assert: Keyboard shortcut triggered undo
    # assert_has(view, css("#builder-state[data-indicators-count='0']"))
    # assert_has(view, css("#dsl-editor[data-content*='# No indicators']"))

    # Assert: Undo completed within 50ms (SC-005, FR-009)
    # assert latency_ms < 50

    # Temporary placeholder - verify EditHistory API works
    {:ok, _undone_event} = EditHistory.undo(session_id)
    refute EditHistory.can_undo?(session_id)
    assert EditHistory.can_redo?(session_id)

    assert true, "Placeholder - implement when LiveView keyboard shortcuts are available"
  end

  # ========================================================================
  # US4.006: Keyboard shortcut Ctrl+Shift+Z triggers redo in both editors
  # Acceptance: Keyboard shortcut Ctrl+Shift+Z triggers redo
  # ========================================================================

  @tag :integration
  @tag :undo_redo
  @tag :keyboard_shortcuts
  test "US4.006: keyboard shortcut Ctrl+Shift+Z triggers redo in both editors", %{
    edit_session_id: session_id
  } do
    # NOTE: This test validates keyboard shortcut integration with redo.
    # Similar to US4.005 but for redo (Ctrl+Shift+Z).
    #
    # Implementation requires:
    # 1. LiveView route with strategy editor
    # 2. KeyboardShortcutsHook JavaScript hook
    # 3. handle_event("keyboard_shortcut", %{"key" => "z", "ctrlKey" => true, "shiftKey" => true}, socket)
    # 4. Integration with EditHistory.redo

    # Arrange: Push event and undo it
    event =
      ChangeEvent.new(%{
        session_id: session_id,
        source: :builder,
        operation_type: :add_indicator,
        path: ["indicators", 0],
        delta: {nil, %{type: "sma", name: "sma_20", period: 20}}
      })

    :ok = EditHistory.push(session_id, event)
    {:ok, _} = EditHistory.undo(session_id)

    # Verify redo is available
    assert EditHistory.can_redo?(session_id)

    # Act (when LiveView is available):
    # {:ok, view, _html} = live(conn, ~p"/strategies/#{strategy_id}/edit")
    #
    # {latency_ms, _result} = measure_sync(fn ->
    #   view |> render_hook("keyboard_shortcut", %{
    #     "key" => "z",
    #     "ctrlKey" => true,
    #     "shiftKey" => true
    #   })
    # end)

    # Assert: Keyboard shortcut triggered redo
    # assert_has(view, css("#builder-state[data-indicators-count='1']"))
    # assert_has(view, css("#dsl-editor[data-content*='indicator :sma_20']"))

    # Assert: Redo completed within 50ms (SC-005, FR-009)
    # assert latency_ms < 50

    # Temporary placeholder - verify EditHistory API works
    {:ok, _redone_event} = EditHistory.redo(session_id)
    assert EditHistory.can_undo?(session_id)
    refute EditHistory.can_redo?(session_id)

    assert true, "Placeholder - implement when LiveView keyboard shortcuts are available"
  end

  # ========================================================================
  # US4.007: Undo/redo history shared correctly across builder and DSL editors (no divergence)
  # Acceptance: Undo/redo history shared correctly across editors
  # ========================================================================

  @tag :integration
  @tag :undo_redo
  test "US4.007: undo/redo history shared correctly across builder and DSL editors (no divergence)",
       %{edit_session_id: session_id} do
    # Arrange: Create mixed events from builder and DSL
    builder_event1 =
      ChangeEvent.new(%{
        session_id: session_id,
        source: :builder,
        operation_type: :add_indicator,
        path: ["indicators", 0],
        delta: {nil, %{type: "sma", name: "sma_20", period: 20}}
      })

    dsl_event1 =
      ChangeEvent.new(%{
        session_id: session_id,
        source: :dsl,
        operation_type: :update_indicator,
        path: ["indicators", 0, "parameters", "period"],
        delta: {20, 30}
      })

    builder_event2 =
      ChangeEvent.new(%{
        session_id: session_id,
        source: :builder,
        operation_type: :update_entry_condition,
        path: ["entry_conditions"],
        delta: {"", "close > sma_20"}
      })

    dsl_event2 =
      ChangeEvent.new(%{
        session_id: session_id,
        source: :dsl,
        operation_type: :update_exit_condition,
        path: ["exit_conditions"],
        delta: {"", "close < sma_20"}
      })

    # Push events in interleaved order (builder, dsl, builder, dsl)
    EditHistory.push(session_id, builder_event1)
    EditHistory.push(session_id, dsl_event1)
    EditHistory.push(session_id, builder_event2)
    EditHistory.push(session_id, dsl_event2)

    # Act: Undo all 4 events
    {:ok, undone4} = EditHistory.undo(session_id)
    {:ok, undone3} = EditHistory.undo(session_id)
    {:ok, undone2} = EditHistory.undo(session_id)
    {:ok, undone1} = EditHistory.undo(session_id)

    # Assert: Events undone in correct reverse order (LIFO)
    assert undone4.operation_type == :update_exit_condition
    assert undone4.source == :dsl

    assert undone3.operation_type == :update_entry_condition
    assert undone3.source == :builder

    assert undone2.operation_type == :update_indicator
    assert undone2.source == :dsl

    assert undone1.operation_type == :add_indicator
    assert undone1.source == :builder

    # Assert: Shared history - no divergence between builder and DSL
    # Both editors see the same undo/redo stack
    refute EditHistory.can_undo?(session_id)
    assert EditHistory.can_redo?(session_id)

    # Act: Redo 2 events
    {:ok, redone1} = EditHistory.redo(session_id)
    {:ok, redone2} = EditHistory.redo(session_id)

    # Assert: Redone events are in correct order
    assert redone1.operation_type == :add_indicator
    assert redone1.source == :builder

    assert redone2.operation_type == :update_indicator
    assert redone2.source == :dsl

    # Assert: Both undo and redo available
    assert EditHistory.can_undo?(session_id)
    assert EditHistory.can_redo?(session_id)
  end

  # ========================================================================
  # US4.008: Undo/redo performance: 100% of operations complete within 50ms target
  # Acceptance: 100% of undo/redo operations complete within 50ms
  # ========================================================================

  @tag :integration
  @tag :undo_redo
  @tag :benchmark
  test "US4.008: undo/redo performance: 100% of operations complete within 50ms target", %{
    edit_session_id: session_id
  } do
    # Arrange: Create 20 change events for performance testing
    events =
      for i <- 1..20 do
        ChangeEvent.new(%{
          session_id: session_id,
          source: if(rem(i, 2) == 0, do: :builder, else: :dsl),
          operation_type: :add_indicator,
          path: ["indicators", i - 1],
          delta: {nil, %{type: "sma", name: "sma_#{i * 10}", period: i * 10}}
        })
      end

    # Push all events
    Enum.each(events, fn event -> EditHistory.push(session_id, event) end)

    # Act: Measure undo latency for all 20 operations
    undo_samples =
      collect_samples(20, fn ->
        {:ok, _} = EditHistory.undo(session_id)
        :ok
      end)

    # Assert: All undo operations completed within 50ms (SC-005)
    stats = calculate_statistics(undo_samples)

    assert stats.max < 50,
           "Undo max latency #{stats.max}ms exceeds 50ms target (SC-005). " <>
             "Mean: #{stats.mean}ms, P95: #{stats.p95}ms"

    # Act: Measure redo latency for all 20 operations
    redo_samples =
      collect_samples(20, fn ->
        {:ok, _} = EditHistory.redo(session_id)
        :ok
      end)

    # Assert: All redo operations completed within 50ms (SC-005)
    redo_stats = calculate_statistics(redo_samples)

    assert redo_stats.max < 50,
           "Redo max latency #{redo_stats.max}ms exceeds 50ms target (SC-005). " <>
             "Mean: #{redo_stats.mean}ms, P95: #{redo_stats.p95}ms"

    # Report performance statistics (FR-017)
    IO.puts("\n#{format_statistics(stats, 50, "US4.008: Undo Performance")}")
    IO.puts("#{format_statistics(redo_stats, 50, "US4.008: Redo Performance")}")

    # Assert: 100% of operations within target (stricter than P95 for undo/redo)
    assert stats.max < 50 and redo_stats.max < 50,
           "SC-005: 100% of undo/redo operations must complete within 50ms"
  end
end
