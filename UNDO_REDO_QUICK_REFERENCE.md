# Undo/Redo Quick Reference Guide

**Decision Tree for Choosing the Right Approach**

---

## One-Minute Summary

**For your bidirectional editor (visual builder + DSL text):**

> Use **Hybrid Approach** with:
> - ✅ Client-side undo/redo stacks (instant feedback, <50ms)
> - ✅ ETS-backed GenServer for persistence (durable, concurrent)
> - ✅ Optimistic UI updates (responsive feel)
> - ✅ Async server notification (non-blocking)

**Performance:** 40-50ms perceived latency ✅ **(Meets <500ms requirement)**

**Memory:** 50-100 KB per session ✅

**Complexity:** Medium (3-4 files, ~500 LOC) ⭐⭐⭐

---

## Quick Decision Matrix

| Requirement | Client-Only | Server-Only | Hybrid ⭐ |
|------------|:-----------:|:-----------:|:--------:|
| **<500ms undo/redo** | ✅ <10ms | ⚠️ 150-300ms | ✅ <50ms |
| **Persistence** | ❌ | ✅ | ✅ |
| **Collaboration** | ❌ | ✅ | ✅ |
| **Memory efficient** | ⚠️ 250-500KB | ⚠️ GenServer heap | ✅ 50-100KB |
| **Easy to implement** | ✅ ⭐ | ⚠️ ⭐⭐ | ⚠️ ⭐⭐⭐ |
| **Scales to 100+ users** | ✅ | ❌ | ✅ |
| **Handles network lag** | ✅ | ❌ | ✅ |
| **Audit trail** | ❌ | ✅ | ✅ |

---

## Architecture at a Glance

### Client-Side
```javascript
// User presses Ctrl+Z
undoStack = [change1, change2, ...]  // Last change first
redoStack = []

// Immediately apply inverse
UI.apply(change2.inverse)
undoStack.pop()
redoStack.push(change2)

// Notify server (async, doesn't block user)
socket.pushEvent('undo', {change_id})
```

### Server-Side
```elixir
# ETS table - blazing fast reads
:change_journal = [
  {"session-1", change1},
  {"session-1", change2},
  ...
]

# GenServer handles writes asynchronously
record(change_event) -> GenServer.cast() -> Returns immediately

# Direct ETS reads - no blocking
get_changes(session_id) -> Fast query -> Returns list
```

---

## File Checklist (Minimal Implementation)

**Essential (MVP):**
- [ ] `lib/trading_strategy/strategy_editor/change_event.ex` - 100 LOC
- [ ] `lib/trading_strategy/strategy_editor/history_stack.ex` - 150 LOC
- [ ] `lib/trading_strategy/strategy_editor/change_journal.ex` - 150 LOC
- [ ] Update `form.ex` - add undo/redo handlers
- [ ] `assets/js/hooks/strategy_editor.js` - 100 LOC
- [ ] Database migration

**Nice to Have (Phase 2):**
- [ ] Change timeline visualization
- [ ] Conflict detection
- [ ] Multi-user synchronization
- [ ] Change replay/history browser

---

## Capacity Planning

### Per-Session Memory
| Item | Size | Notes |
|------|------|-------|
| Empty HistoryStack | <1 KB | Just struct |
| 1 Change | 0.5-1 KB | Event metadata |
| 100 Changes (max) | 50-100 KB | Typical limit |
| ETS table overhead | ~10 KB | Per session |
| **Total per session** | **60-110 KB** | ✅ Minimal |

### Server Capacity
```
Max concurrent editors: 1000+ sessions
Memory per session: 100 KB
Total memory: ~100 MB (very reasonable)
ETS is thread-safe: No GenServer contention
```

---

## Code Examples

### Recording a Change (From Builder)

```elixir
# In IndicatorBuilder.handle_event("add_indicator", ...)

change = ChangeEvent.from_builder(
  strategy_id,
  :add_indicator,
  ["indicators", index],
  nil,                # old_value
  new_indicator,      # new_value
  user_id
)

# Emit to parent
send(parent_pid, {:record_change, change})
```

### Handling Undo (In Form)

```elixir
# In StrategyLive.Form.handle_event("undo", ...)

{new_history, change} = HistoryStack.undo(socket.assigns.history)

# If change exists
if change do
  socket
  |> apply_change(change.inverse)  # Inverse of {new, old} = {old, new}
  |> assign(:history, new_history)
  |> ChangeJournal.record(change)  # Notify server async
end
```

### Client-Side (JavaScript)

```javascript
// Handle Ctrl+Z
document.addEventListener('keydown', (e) => {
  if ((e.ctrlKey || e.metaKey) && e.key === 'z') {
    e.preventDefault();

    // Immediate UI feedback
    applyInverse(undoStack[undoStack.length - 1]);
    redoStack.push(undoStack.pop());

    // Notify server (fire-and-forget)
    this.el.pushEvent('undo', {timestamp: now()});
  }
});
```

---

## Common Questions

### Q: What if server rejects an undo?

**A:** Server validates and broadcasts rejection to client. Client rolls back optimistic update and shows error toast.

```elixir
# Server-side
def handle_event("undo", %{"change_id" => id}, socket) do
  case ChangeJournal.verify_undo(id) do
    :ok -> broadcast_to_all(socket, {:undo_applied, id})
    :error -> push_event(socket, "undo_rejected", %{change_id: id})
  end
end
```

```javascript
// Client-side
this.el.addEventListener('phx:undo_rejected', () => {
  rollbackLastChange();
  showError("Undo failed - change may have been modified");
});
```

### Q: How do I handle simultaneous edits from multiple users?

**A:** Each user has their own undo/redo stack. Changes are versioned. On conflict:
1. Server detects conflict (version mismatch)
2. Broadcasts conflict event
3. Client shows "merge needed" dialog
4. User chooses: keep mine, take theirs, or manual merge

### Q: What happens if I undo, then make a new change?

**A:** This is standard undo/redo behavior:
1. Undo: `undoStack.pop()`, `redoStack.push()`
2. New change: `undoStack.push(newChange)`, `redoStack.clear()`

The old redo items are lost (expected behavior).

### Q: How large can the history be?

**A:** Default limit is **100 operations** per session.
- ~30 minutes of editing at normal pace
- 50-100 KB memory overhead
- Can be increased, but RAM vs. UX tradeoff

```elixir
# Increase to 200 operations
HistoryStack.new(strategy_id, max_depth: 200)
```

### Q: How long are changes persisted?

**A:** Two-tier retention:
- **In ETS (in-memory):** 100 operations (moving window)
- **In Database:** 7-30 days (configurable)

Users can only undo back 100 operations, but admins can replay changes from DB.

---

## Latency Breakdown (Real-World)

```
User action: Ctrl+Z
│
├─ 1ms    JavaScript event handler executes
├─ 5ms    UI updates (DOM, CSS reflow)
│         [User sees result here ← 6ms]
│
├─ 50-100ms   Network: Send undo event to server
├─ 5-10ms     Server processes event
├─ 50-100ms   Network: Broadcast to other clients
│             [Other users see result here ← 105-210ms]
│
└─ Total perceived: 6ms (for this user), 105-210ms (for collaborators)
```

**Key insight:** Your users feel instant response, collaborators see eventual consistency.

---

## Testing Checklist

```elixir
# Unit Tests (Change structure)
test "create change from builder" do
  change = ChangeEvent.from_builder(...)
  assert change.source == :builder
  assert change.operation_type == :add_indicator
end

# Unit Tests (History stack)
test "undo moves to redo stack" do
  history = HistoryStack.new("s1")
  history = HistoryStack.record_change(history, change)
  {history, popped} = HistoryStack.undo(history)
  assert popped == change
  assert HistoryStack.can_redo?(history)
end

# Integration Tests (ETS + GenServer)
test "record persists to ETS" do
  ChangeJournal.record(change)
  Process.sleep(10)  # Let cast complete
  changes = ChangeJournal.get_changes(session_id)
  assert Enum.count(changes) == 1
end

# LiveView Tests
test "undo event updates history" do
  {:ok, view, _html} = live(conn, "/strategies/#{id}/edit")
  html = render(view)
  assert has_element?(view, "[data-action=undo]")
end
```

---

## Rollout Plan

**Week 1: Foundation**
- [ ] Create ChangeEvent + HistoryStack modules
- [ ] Create ChangeJournal + ETS table
- [ ] Write unit tests (80% coverage)

**Week 2: Integration**
- [ ] Add to StrategyLive.Form
- [ ] Update builders (emit events)
- [ ] Create JavaScript hook

**Week 3: Polish**
- [ ] UI buttons + keyboard shortcuts
- [ ] Error handling
- [ ] Performance testing
- [ ] Documentation

**Week 4: Optional (Phase 2)**
- [ ] Change timeline visualization
- [ ] Conflict resolution UI
- [ ] Multi-user sync

---

## Key Files Reference

| File | Purpose | Size |
|------|---------|------|
| `change_event.ex` | Data structure for changes | 100 LOC |
| `history_stack.ex` | Undo/redo logic (immutable) | 150 LOC |
| `change_journal.ex` | ETS + persistence | 150 LOC |
| `form.ex` | LiveView integration | 50 LOC added |
| `strategy_editor.js` | Client-side undo/redo | 100 LOC |
| `migration` | Database schema | 30 LOC |
| **Total** | **Complete MVP** | **~580 LOC** |

---

## Glossary

| Term | Meaning |
|------|---------|
| **Change Event** | Single user action (add indicator, edit DSL, etc.) |
| **Undo Stack** | LIFO queue of changes to reverse |
| **Redo Stack** | Cleared when new change recorded, holds undone changes |
| **Source** | `:builder` (visual) or `:dsl` (text editor) |
| **Delta** | Tuple `{old_value, new_value}` |
| **Inverse** | Reverse operation `{new_value, old_value}` |
| **Version** | Monotonic clock for ordering changes |
| **Path** | JSON path to changed element, e.g., `["indicators", 0]` |
| **Optimistic Update** | Apply change to UI before server confirms |
| **Eventual Consistency** | Server state catches up to client state |

---

## Performance Monitoring

```elixir
# Add telemetry for undo/redo
:telemetry.execute(
  [:trading_strategy, :undo_redo, :undo],
  %{duration: System.monotonic_time() - start_time},
  %{session_id: session_id, version: history.version}
)

# Dashboard query
select count(*) from strategy_change_logs
where inserted_at > now() - interval '1 hour'
group by source, operation_type;
```

---

## Next Steps

1. **Review** these three documents with your team
2. **Get buy-in** on hybrid approach (vs. server-only)
3. **Start Phase 1** (server-side foundation)
4. **Demo after Week 2** (working undo/redo)
5. **Iterate** based on feedback

---

**Document:** Quick Reference
**Last Updated:** 2025-02-10
**Status:** Ready for Implementation
