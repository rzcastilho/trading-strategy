# Debouncing Quick Reference for 005-builder-dsl-sync

## TL;DR: Use the Hybrid Approach

For FR-008 (300ms debounce) + FR-001/FR-002 (<500ms sync latency):

```javascript
// Client: Colocated Hook (300ms debounce)
export default {
  debounceTimer: null,
  DEBOUNCE_MS: 300,

  mounted() {
    this.el.addEventListener("input", (e) => {
      clearTimeout(this.debounceTimer)
      this.debounceTimer = setTimeout(() => {
        this.pushEvent("sync", {content: this.el.value})
      }, this.DEBOUNCE_MS)
    })
  },
  destroyed() {
    clearTimeout(this.debounceTimer)
  }
}
```

```elixir
# Server: Rate Limiting (300ms minimum between syncs)
def handle_event("sync", params, socket) do
  now = System.monotonic_time(:millisecond)
  last_sync = socket.assigns.last_sync_time || 0

  if now - last_sync < 300 do
    {:noreply, socket |> assign(:pending_sync, params)}
  else
    {:noreply,
     socket
     |> process_sync(params)
     |> assign(:last_sync_time, now)}
  end
end
```

---

## Strategy Comparison Table

| Strategy | phx-debounce | JS Hook | GenServer | Rating | Effort |
|----------|--------------|---------|-----------|--------|--------|
| **phx-debounce only** | ✓ | | | ★★★☆☆ | 5 min |
| **JS Hook only** | | ✓ | | ★★★★☆ | 30 min |
| **Hook + Server Rate Limit** | | ✓ | ✓ | ★★★★★ | 1-2 hr |
| **Hook + GenServer Debouncer** | | ✓ | ✓ | ★★★★★ | 2-3 hr |

**Recommended**: Hook + Server Rate Limit (best balance)

---

## Implementation Quick Start

### Option 1: Minimal (phx-debounce attribute)

```heex
<textarea
  id="dsl-editor"
  name="content"
  phx-change="dsl_changed"
  phx-debounce="300"
/>
```

**Pros**: 1 line of code
**Cons**: Limited to single field, no complex coordination

### Option 2: Colocated Hook (Recommended)

```heex
<textarea
  id="dsl-editor"
  name="content"
  phx-hook=".DslSync"
  phx-update="ignore"
/>

<script :type={Phoenix.LiveView.ColocatedHook} name=".DslSync">
  export default {
    debounceTimer: null,
    mounted() {
      this.el.addEventListener("input", (e) => {
        clearTimeout(this.debounceTimer)
        this.debounceTimer = setTimeout(() => {
          this.pushEvent("dsl_sync", {value: this.el.value})
        }, 300)
      })
    },
    destroyed() {
      clearTimeout(this.debounceTimer)
    }
  }
</script>
```

**Pros**: Full control, good for complex syncing
**Cons**: More code

### Option 3: External Hook

```javascript
// hooks.js
export const DslSyncHook = {
  debounceTimer: null,
  mounted() { /* ... */ }
}
```

```javascript
// app.js
const liveSocket = new LiveSocket("/live", Socket, {
  hooks: {DslSync: DslSyncHook}
})
```

**Pros**: Organized, reusable
**Cons**: More setup

---

## Server-Side Rate Limiting

### Simple (In Handler)

```elixir
def handle_event("sync", params, socket) do
  now = System.monotonic_time(:millisecond)

  if now - (socket.assigns.last_sync || 0) >= 300 do
    # Process sync
    {:noreply, socket |> assign(:last_sync, now)}
  else
    # Too fast - reject or queue
    {:noreply, socket}
  end
end
```

### Medium (GenServer)

Create a GenServer to manage debounce timers, retry logic, and queuing.

```elixir
TradingStrategy.Synchronization.DebounceManager.schedule_sync(
  strategy_id,
  :dsl_editor,
  %{content: dsl_content}
)
```

### Complex (Redis + GenServer)

For distributed/multi-node systems, use Redis pubsub + GenServer per node.

---

## Timing Breakdown

```
User types: [a][b][c] -------- (pause 300ms)
                               │
                    Debounce fires ──→ Event sent (300ms)
                                         │
                               Server processes (50-100ms)
                                         │
                            Builder re-renders (20-50ms)
                                         │
Total: 370-450ms from last keystroke to visible update
```

---

## Requirement Mapping

| Requirement | Solution | Timing |
|-------------|----------|--------|
| FR-001: Builder→DSL sync <500ms | JS debounce (300) + server (150-200) | ✓ 450-500ms |
| FR-002: DSL→Builder sync <500ms | JS debounce (300) + server (150-200) | ✓ 450-500ms |
| FR-008: 300ms debounce | Colocated hook `DEBOUNCE_MS: 300` | ✓ Exact |
| FR-011: Loading indicator >200ms | Show after 200ms in debounce | ✓ Custom |
| SC-001: <500ms sync latency | As above | ✓ 450-500ms |
| SC-005: <500ms for 20 indicators | GenServer + server limiting | ✓ 400-500ms |

---

## Common Patterns

### Pattern 1: Debounce on Input, Sync on Blur

```javascript
export default {
  debounceTimer: null,

  mounted() {
    this.el.addEventListener("input", () => {
      clearTimeout(this.debounceTimer)
      this.debounceTimer = setTimeout(() => this.sync(), 300)
    })

    this.el.addEventListener("blur", () => {
      // Immediate sync on blur
      clearTimeout(this.debounceTimer)
      this.sync()
    })
  },

  sync() {
    this.pushEvent("sync", {value: this.el.value})
  }
}
```

### Pattern 2: Rate-Limited Queue

```elixir
def handle_event("change", params, socket) do
  now = System.monotonic_time(:millisecond)

  case check_rate_limit(socket, now) do
    :allowed ->
      process_and_update(socket, params, now)

    :rate_limited ->
      queue_for_later(socket, params)
  end
end

defp queue_for_later(socket, params) do
  queue = socket.assigns.pending_syncs || []
  {:noreply, assign(socket, :pending_syncs, [params | queue])}
end
```

### Pattern 3: Debounce with Cancel

```javascript
export default {
  debounceTimer: null,

  cancel_sync() {
    clearTimeout(this.debounceTimer)
    this.debounceTimer = null
  },

  schedule_sync(delay = 300) {
    this.cancel_sync()
    this.debounceTimer = setTimeout(() => {
      this.pushEvent("sync", {value: this.el.value})
    }, delay)
  }
}
```

---

## Testing Checklist

```elixir
# Unit: Debounce timing
test "debounce fires after 300ms" do
  # Simulate rapid input events
  # Assert only one event pushed after 300ms pause
end

# Unit: Server rate limiting
test "rate limit rejects events < 300ms apart" do
  # Send two events rapidly
  # Assert second is queued or rejected
end

# Integration: Bidirectional sync
test "DSL change syncs to builder" do
  # Edit DSL → assert builder updates
end

test "builder change syncs to DSL" do
  # Edit builder → assert DSL updates
end

# Load: High frequency edits
test "handles 100 edits/second without data loss" do
  # Rapid events → assert all changes captured
  # Note: Only one event sent per 300ms due to debounce
end

# Edge: Network latency
test "handles server delay >500ms gracefully" do
  # Mock slow server
  # Assert UI shows loading indicator
  # Assert no double-syncs
end
```

---

## Debugging Tips

### Check Debounce Timing

```javascript
// In browser console
let count = 0
const originalPushEvent = window.liveSocket.pushEvent

window.liveSocket.pushEvent = function(event, payload) {
  if (event === "sync") {
    console.log(`Event ${++count} sent at ${Date.now()}`)
  }
  return originalPushEvent.call(this, event, payload)
}

// Now edit - watch console for 300ms delays
```

### Monitor Server Processing

```elixir
def handle_event("sync", params, socket) do
  start = System.monotonic_time()

  result = process_sync(socket, params)

  duration = System.monotonic_time() - start
  Logger.info("Sync completed in #{duration / 1_000_000}ms")

  {:noreply, result}
end
```

### Check for Rate Limit Violations

```elixir
# In LiveView handler
Logger.info("Sync at #{DateTime.utc_now()} | Last sync: #{socket.assigns.last_sync_time}")

# Watch logs for events <300ms apart
```

---

## Common Issues & Solutions

| Issue | Cause | Solution |
|-------|-------|----------|
| **Events fire too often** | Debounce not set | Check `DEBOUNCE_MS: 300` in hook |
| **Editor feels laggy** | Server rate limit too strict | Reduce minimum to 200ms |
| **Data out of sync** | Missing blur handler | Add blur listener with immediate sync |
| **Memory leak** | Timer not cleared | Call `clearTimeout()` in destroyed() |
| **Form submits before sync** | Race condition | Check socket.assigns.pending_sync before save |
| **DSL not updating** | Hook not mounted | Check `phx-update="ignore"` is set |
| **Multi-field coordination fails** | Using phx-debounce alone | Switch to colocated hook |

---

## Performance Targets vs Actual

### Expected Performance (Hybrid Approach)

```
Keystroke to Server:          300ms (debounce)
Server Parse:                  50ms (DSL parse)
Server Update:                 20ms (builder state)
Network RTT:                   20ms (avg)
Client Render:                 20ms (LiveView)
                              ────────
TOTAL:                        410ms ✓ (under 500ms target)

With Loading Indicator Threshold: 200ms ✓
```

---

## Decision Tree

```
Need real-time sync between two editors?
├─ YES, single field only?
│  └─ Use phx-debounce="300" (1 line) ✓
│
├─ YES, multiple coordinated fields?
│  └─ Use colocated hook (30 min setup)
│       ├─ Need to prevent server spam?
│       │  └─ Add server-side rate limiting (30 min)
│       │
│       └─ Need queuing/retry logic?
│          └─ Add GenServer debouncer (2 hr)
│
└─ NO
   └─ Don't debounce (saves complexity)
```

---

## One-Liner Implementations

### Simplest Debounce
```heex
<textarea phx-debounce="300" name="content" />
```

### Simple Hook Debounce
```heex
<textarea phx-hook=".Sync" phx-update="ignore" />
<script :type={Phoenix.LiveView.ColocatedHook} name=".Sync">
export default {
  debounceTimer: null,
  mounted() {
    this.el.addEventListener("input", (e) => {
      clearTimeout(this.debounceTimer)
      this.debounceTimer = setTimeout(() => {
        this.pushEvent("sync", {value: this.el.value})
      }, 300)
    })
  }
}
</script>
```

### Simple Rate Limiter
```elixir
def handle_event("sync", params, socket) do
  if System.monotonic_time(:millisecond) - (socket.assigns.last_sync || 0) >= 300 do
    {:noreply, process_sync(socket, params) |> assign(:last_sync, System.monotonic_time(:millisecond))}
  else
    {:noreply, socket}
  end
end
```

---

## Further Reading

- **DEBOUNCE_RESEARCH.md** - Full detailed research document
- **spec.md** - Feature requirements (FR-001 through FR-020)
- **plan.md** - Implementation plan and timeline

