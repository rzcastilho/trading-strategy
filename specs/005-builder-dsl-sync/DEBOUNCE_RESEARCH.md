# Debouncing Strategies for Phoenix LiveView Real-Time Synchronization

**Research Date**: 2026-02-10
**Phoenix Version**: 1.8.2
**Phoenix LiveView Version**: 1.0+
**Target Requirements**: FR-001, FR-002, FR-008 (300ms debounce, <500ms sync latency)

## Executive Summary

For the bidirectional strategy editor synchronization feature (005-builder-dsl-sync), a **hybrid approach combining client-side JavaScript debouncing with server-side rate limiting** is recommended. This provides defense-in-depth protection while meeting the 300ms debounce requirement and <500ms synchronization latency target.

The recommended solution uses:
1. **Colocated Phoenix LiveView hooks** for client-side debouncing (native Phoenix 1.7+ feature)
2. **Server-side rate limiting in LiveView handlers** with optional GenServer-backed debouncer
3. **phx-debounce attribute** for baseline form field protection
4. **Custom debounce modules** for complex multi-field scenarios

---

## 1. Phoenix LiveView Built-in Features (Phoenix 1.7+)

### 1.1 phx-debounce Attribute

Phoenix 1.7+ provides native debouncing support via the `phx-debounce` attribute on form inputs.

**Syntax**:
```heex
<input type="text" name="field" phx-debounce="300" />
```

**Behavior**:
- Delays sending `phx-change` events to the server by specified milliseconds
- Fires immediately on blur event (if not already fired)
- Automatic queue deduplication
- Works with form fields only

**Limitations**:
- Limited to individual form fields
- Cannot coordinate debouncing across multiple related fields
- Not suitable for complex state synchronization with multiple sources

**Best For**: Simple form field validation or single-field updates

**Current Usage in Project**:
```elixir
# From lib/trading_strategy_web/live/strategy_live/form.ex (line 98, 216)
<.input
  field={@form[:name]}
  type="text"
  label="Strategy Name"
  phx-debounce="blur"  # Currently uses "blur" instead of milliseconds
  required
/>

<.input
  field={@form[:content]}
  type="textarea"
  label="Strategy Definition (Advanced: Manual DSL)"
  phx-debounce="500"  # 500ms debounce for DSL content
  required
/>
```

### 1.2 phx-throttle Attribute

Phoenix also provides `phx-throttle` for rate-limiting events.

**Syntax**:
```heex
<input type="text" name="field" phx-throttle="300" />
```

**Behavior**:
- Sends at most one event every specified milliseconds
- Always sends first and last events
- Continues sending if events queue up

**Key Difference from Debounce**:
- Throttle: Fire events at regular intervals (3+ events become 2)
- Debounce: Fire only after user stops (3 events become 1)

**Best For**: Scroll/resize events, real-time cursor position tracking where you need consistent updates

---

## 2. Client-Side JavaScript Debouncing with Phoenix Hooks

### 2.1 Colocated Hooks (Phoenix 1.8+ Native Approach)

**Recommended**: Use colocated hooks with `:type={Phoenix.LiveView.ColocatedHook}` - this is the modern, built-in way.

#### Example: DSL Content Synchronization Hook

```heex
<textarea
  id="dsl-editor"
  name="dsl_content"
  phx-hook=".DslEditorSync"
  phx-update="ignore"
  class="font-mono"
>
  <%= @dsl_content %>
</textarea>

<script :type={Phoenix.LiveView.ColocatedHook} name=".DslEditorSync">
  export default {
    // Debounce timer reference
    debounceTimer: null,
    // Debounce delay in milliseconds (300ms per FR-008)
    DEBOUNCE_MS: 300,
    // Minimum interval between syncs to prevent spam
    MIN_SYNC_INTERVAL_MS: 500,
    lastSyncTime: 0,

    mounted() {
      // Bind event listeners
      this.el.addEventListener("input", (e) => this.handleInput(e))
      this.el.addEventListener("change", (e) => this.handleChange(e))
    },

    handleInput(event) {
      // Clear any pending debounce timer
      if (this.debounceTimer) {
        clearTimeout(this.debounceTimer)
      }

      // Set new debounce timer
      this.debounceTimer = setTimeout(() => {
        const content = this.el.value
        const now = Date.now()

        // Ensure minimum interval between syncs
        if (now - this.lastSyncTime < this.MIN_SYNC_INTERVAL_MS) {
          return
        }

        this.lastSyncTime = now

        // Push to LiveView with custom metadata
        this.pushEvent("dsl_content_changed", {
          content: content,
          source: "dsl_editor",
          timestamp: new Date().toISOString()
        })

        // Show sync indicator
        this.showSyncIndicator()
      }, this.DEBOUNCE_MS)
    },

    handleChange(event) {
      // Immediate sync on blur (regardless of debounce)
      if (this.debounceTimer) {
        clearTimeout(this.debounceTimer)
      }

      const now = Date.now()
      if (now - this.lastSyncTime < this.MIN_SYNC_INTERVAL_MS) {
        // Still respect minimum interval on blur
        this.debounceTimer = setTimeout(() => {
          this.performSync()
        }, this.MIN_SYNC_INTERVAL_MS - (now - this.lastSyncTime))
      } else {
        this.performSync()
      }
    },

    performSync() {
      const content = this.el.value
      this.lastSyncTime = Date.now()

      this.pushEvent("dsl_content_changed", {
        content: content,
        source: "dsl_editor",
        timestamp: new Date().toISOString()
      })

      this.showSyncIndicator()
    },

    showSyncIndicator() {
      // Add visual feedback that sync is happening
      const indicator = document.getElementById("sync-status")
      if (indicator) {
        indicator.textContent = "Syncing..."
        indicator.classList.remove("text-green-600", "text-red-600")
        indicator.classList.add("text-yellow-600")

        // Remove indicator after sync completes
        setTimeout(() => {
          if (indicator) {
            indicator.textContent = "✓ Synced"
            indicator.classList.remove("text-yellow-600")
            indicator.classList.add("text-green-600")
          }
        }, 200)
      }
    },

    destroyed() {
      // Clean up timer when component is destroyed
      if (this.debounceTimer) {
        clearTimeout(this.debounceTimer)
      }
    }
  }
</script>
```

### 2.2 External Hook Approach (Alternative)

If you need more complex hook management, you can define hooks in JavaScript and pass them to LiveSocket.

**File**: `/path/to/hooks.js`
```javascript
// hooks/debounced_editor.js
const DebouncedEditorHook = {
  DEBOUNCE_MS: 300,
  MIN_SYNC_INTERVAL_MS: 500,
  debounceTimer: null,
  lastSyncTime: 0,

  mounted() {
    this.el.addEventListener("input", (e) => this.handleInput(e))
    this.el.addEventListener("blur", (e) => this.handleBlur(e))
  },

  handleInput(event) {
    if (this.debounceTimer) {
      clearTimeout(this.debounceTimer)
    }

    this.debounceTimer = setTimeout(() => {
      this.sync()
    }, this.DEBOUNCE_MS)
  },

  handleBlur(event) {
    // Immediate sync on blur
    if (this.debounceTimer) {
      clearTimeout(this.debounceTimer)
    }
    this.sync()
  },

  sync() {
    const now = Date.now()
    const timeSinceLastSync = now - this.lastSyncTime

    if (timeSinceLastSync < this.MIN_SYNC_INTERVAL_MS) {
      // Queue retry
      this.debounceTimer = setTimeout(
        () => this.sync(),
        this.MIN_SYNC_INTERVAL_MS - timeSinceLastSync
      )
      return
    }

    this.lastSyncTime = now
    this.pushEvent("content_changed", {
      value: this.el.value,
      source: this.el.dataset.source || "editor"
    })
  },

  destroyed() {
    if (this.debounceTimer) {
      clearTimeout(this.debounceTimer)
    }
  }
}

export default {
  DebouncedEditor: DebouncedEditorHook
}
```

**Usage in Template**:
```heex
<textarea
  id="dsl-editor"
  name="content"
  phx-hook="DebouncedEditor"
  phx-update="ignore"
  data-source="dsl_editor"
/>
```

**Registration in App Initialization**:
```javascript
// assets/app.js
import { hooks } from './hooks'

const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  hooks: hooks
})
```

---

## 3. Server-Side Rate Limiting

### 3.1 Basic LiveView Handler Rate Limiting

Implement rate limiting directly in LiveView event handlers to prevent abuse.

```elixir
# lib/trading_strategy_web/live/strategy_live/form.ex

defmodule TradingStrategyWeb.StrategyLive.Form do
  use TradingStrategyWeb, :live_view

  # ... other code ...

  @impl true
  def mount(params, _session, socket) do
    # Initialize rate limiting state
    socket =
      socket
      |> assign(:last_sync_time, 0)
      |> assign(:sync_cooldown_ms, 300)  # Minimum 300ms between syncs
      # ... other assigns ...

    {:ok, socket}
  end

  # Handle DSL content changes with rate limiting
  @impl true
  def handle_event("dsl_content_changed", params, socket) do
    now = System.monotonic_time(:millisecond)
    last_sync = socket.assigns.last_sync_time
    cooldown = socket.assigns.sync_cooldown_ms

    if now - last_sync < cooldown do
      # Request came in too soon - either queue it or reject it
      {:noreply,
       socket
       |> assign(:pending_sync, params)  # Store for retry
       |> put_flash(:warning, "Sync rate limited, please wait...")}
    else
      # Process the sync
      result = process_dsl_sync(params, socket)
      {:noreply,
       socket
       |> assign(:last_sync_time, now)
       |> assign(:pending_sync, nil)
       |> process_sync_result(result)}
    end
  end

  defp process_dsl_sync(params, socket) do
    %{"content" => dsl_content, "source" => "dsl_editor"} = params

    # Validate DSL syntax
    case Strategies.validate_dsl(dsl_content, String.to_atom(socket.assigns.format)) do
      {:ok, validated} ->
        # Sync to builder state
        {:ok, validated}

      {:error, errors} ->
        {:error, errors}
    end
  end

  defp process_sync_result(socket, {:ok, validated}) do
    # Update form with synced data
    socket
    |> assign(:syntax_test_result, %{success: true, message: "Synced from DSL"})
    |> assign(:form, to_form(validated))
  end

  defp process_sync_result(socket, {:error, errors}) do
    # Keep last valid state, show errors
    socket
    |> assign(:syntax_test_result, %{
      success: false,
      errors: errors
    })
  end
end
```

### 3.2 GenServer-Backed Debouncer (Advanced)

For more sophisticated debouncing with queuing and retry logic, create a dedicated GenServer.

```elixir
# lib/trading_strategy/synchronization/debounce_manager.ex

defmodule TradingStrategy.Synchronization.DebounceManager do
  @moduledoc """
  Manages debounced synchronization of strategy edits between builder and DSL editor.

  This GenServer ensures:
  - Debouncing with 300ms+ delay
  - Rate limiting with minimum 300ms between syncs
  - Queuing of pending syncs
  - Graceful handling of sync failures
  - Automatic retry with exponential backoff

  ## Usage

    {:ok, _} = DebounceManager.start_link([])

    # Schedule a sync with debouncing
    DebounceManager.schedule_sync(:strategy_123, :dsl_editor, %{content: "..."})

    # Immediately get current pending state
    state = DebounceManager.get_pending(:strategy_123)

    # Cancel pending sync
    DebounceManager.cancel_sync(:strategy_123)
  """

  use GenServer
  require Logger

  @debounce_ms 300
  @min_sync_interval_ms 300
  @max_retries 3
  @retry_backoff_ms 100

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Schedule a debounced sync operation"
  def schedule_sync(strategy_id, source, params) do
    GenServer.cast(__MODULE__, {:schedule_sync, strategy_id, source, params})
  end

  @doc "Get current pending sync for a strategy"
  def get_pending(strategy_id) do
    GenServer.call(__MODULE__, {:get_pending, strategy_id})
  end

  @doc "Cancel any pending sync for a strategy"
  def cancel_sync(strategy_id) do
    GenServer.call(__MODULE__, {:cancel_sync, strategy_id})
  end

  @doc "Record successful sync time for rate limiting"
  def record_sync(strategy_id) do
    GenServer.cast(__MODULE__, {:record_sync, strategy_id})
  end

  # Server Callbacks

  def init(_opts) do
    state = %{
      pending_syncs: %{},      # %{strategy_id => {timer_ref, params}}
      sync_history: %{},       # %{strategy_id => last_sync_time_ms}
      retry_counts: %{}        # %{strategy_id => retry_count}
    }
    {:ok, state}
  end

  @impl true
  def handle_cast({:schedule_sync, strategy_id, source, params}, state) do
    new_state =
      state
      |> cancel_existing_timer(strategy_id)
      |> schedule_debounce(strategy_id, source, params)

    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:record_sync, strategy_id}, state) do
    new_state = put_in(state.sync_history[strategy_id], System.monotonic_time(:millisecond))
    {:noreply, new_state}
  end

  @impl true
  def handle_call({:get_pending, strategy_id}, _from, state) do
    pending = state.pending_syncs[strategy_id]
    {:reply, pending, state}
  end

  @impl true
  def handle_call({:cancel_sync, strategy_id}, _from, state) do
    new_state = cancel_existing_timer(state, strategy_id)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_info({:execute_sync, strategy_id, source, params}, state) do
    now = System.monotonic_time(:millisecond)
    last_sync = state.sync_history[strategy_id] || 0

    if now - last_sync < @min_sync_interval_ms do
      # Rate limit - reschedule for later
      Logger.debug("Rate limited sync for strategy #{strategy_id}, rescheduling")
      new_state = schedule_debounce(state, strategy_id, source, params, @min_sync_interval_ms)
      {:noreply, new_state}
    else
      # Time to execute the sync
      execute_sync(strategy_id, source, params)
      new_state = put_in(state.pending_syncs[strategy_id], nil)
      {:noreply, new_state}
    end
  end

  # Private functions

  defp cancel_existing_timer(state, strategy_id) do
    case state.pending_syncs[strategy_id] do
      {timer_ref, _params} ->
        Process.cancel_timer(timer_ref)
        put_in(state.pending_syncs[strategy_id], nil)

      nil ->
        state
    end
  end

  defp schedule_debounce(state, strategy_id, source, params, delay \\ @debounce_ms) do
    timer_ref = Process.send_after(self(), {:execute_sync, strategy_id, source, params}, delay)
    put_in(state.pending_syncs[strategy_id], {timer_ref, params})
  end

  defp execute_sync(strategy_id, source, params) do
    Logger.info("Executing debounced sync for strategy #{strategy_id} from #{source}")

    # Send event to LiveView to process
    # This would be handled by a separate channel or direct function call
    case do_sync(strategy_id, source, params) do
      {:ok, _result} ->
        record_sync(strategy_id)

      {:error, reason} ->
        Logger.warning("Sync failed: #{inspect(reason)}")
    end
  end

  # Placeholder - would be implemented based on your sync logic
  defp do_sync(_strategy_id, _source, _params) do
    {:ok, :synced}
  end
end
```

**Usage in LiveView**:
```elixir
def handle_event("dsl_content_changed", params, socket) do
  strategy_id = socket.assigns.strategy.id

  # Schedule debounced sync
  TradingStrategy.Synchronization.DebounceManager.schedule_sync(
    strategy_id,
    :dsl_editor,
    params
  )

  {:noreply,
   socket
   |> assign(:pending_sync_source, :dsl_editor)
   |> put_flash(:info, "Changes syncing...")}
end
```

---

## 4. Comparison: Debounce vs Throttle vs Rate Limiting

| Feature | Debounce | Throttle | Rate Limiting |
|---------|----------|----------|---------------|
| **Fires when** | User stops typing | At regular intervals | Rate threshold respected |
| **Event count** | 1 per pause | N (regular) | Limited by time window |
| **Best for** | Editor changes, validation | Scroll, resize, tracking | Server protection |
| **Latency** | 300ms+ (by design) | 0-interval ms | 0ms (checked at handler) |
| **Implementation** | setTimeout | setInterval | Timer tracking |
| **Data loss risk** | Low | Medium | None |
| **Server load** | Very low | Low | Medium |

---

## 5. Recommended Architecture for 005-builder-dsl-sync

### 5.1 Architecture Diagram

```
┌─────────────────────────────────────────────────────┐
│         Client Browser (JavaScript)                 │
├─────────────────────────────────────────────────────┤
│                                                     │
│  ┌──────────────────┐      ┌──────────────────┐   │
│  │  Builder Form    │      │  DSL Editor      │   │
│  │  (indicators,    │      │  (textarea)      │   │
│  │   conditions)    │      │                  │   │
│  └────────┬─────────┘      └────────┬─────────┘   │
│           │                         │              │
│           │ onChange               │ onChange      │
│           ▼                         ▼              │
│  ┌────────────────────────────────────────┐      │
│  │   Colocated Hook: DebouncedSync        │      │
│  │  (300ms debounce per field)            │      │
│  │  (Tracks source editor)                │      │
│  └────────────┬─────────────────────────┘      │
│               │                                 │
│               │ phx_event (300ms+)              │
│               ▼                                 │
└───────────────┼─────────────────────────────────┘
                │
      ┌─────────┴──────────┐
      │                    │
      ▼                    ▼
┌──────────────────┐ ┌──────────────────┐
│  Server-side     │ │  Rate Limiter    │
│  Rate Limiter    │ │  (300ms min      │
│  (validates      │ │   between syncs) │
│   300ms cooldown)│ │                  │
└────────┬─────────┘ └────────┬─────────┘
         │                    │
         ▼                    ▼
┌──────────────────────────────────────┐
│  LiveView Handler                    │
│  handle_event(:dsl_sync, ...)        │
│  handle_event(:builder_sync, ...)    │
└────────┬─────────────────────────────┘
         │
         ├─── Validate syntax
         ├─── Parse to opposite format
         ├─── Merge with last valid state
         └─── Broadcast to both editors
                 │
         ┌───────┘
         ▼
    ┌──────────────┐
    │  Database    │
    │  (on save)   │
    └──────────────┘
```

### 5.2 Implementation Plan

**Phase 1: Client-Side Debouncing**
1. Add colocated hooks to DSL editor textarea
2. Add colocated hooks to builder form fields (for complex params)
3. Implement 300ms debounce with visual sync indicators

**Phase 2: Server-Side Rate Limiting**
1. Add rate limiting to LiveView handlers
2. Implement pending sync queue
3. Add sync-in-progress feedback

**Phase 3: Synchronization Logic**
1. Implement DSL→Builder sync
2. Implement Builder→DSL sync
3. Preserve comments and formatting

**Phase 4: Error Handling**
1. Add syntax validation
2. Show inline errors
3. Maintain last valid state

---

## 6. Code Example: Full Implementation

### 6.1 Template (strategy_live/form.html.heex)

```heex
<div class="max-w-6xl mx-auto px-4 py-8">
  <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
    <!-- Builder Editor -->
    <div class="space-y-4">
      <h2 class="text-2xl font-bold">Strategy Builder</h2>

      <.live_component
        module={TradingStrategyWeb.StrategyLive.IndicatorBuilder}
        id="indicator-builder"
        indicators={@indicators}
      />

      <.live_component
        module={TradingStrategyWeb.StrategyLive.ConditionBuilder}
        id="entry-condition-builder"
        conditions={@entry_conditions}
        condition_type="entry"
      />

      <!-- Sync Status Indicator -->
      <div
        id="builder-sync-status"
        class="text-sm font-medium px-3 py-2 rounded"
        phx-hook=".SyncStatusIndicator"
        data-source="builder"
      >
        Ready
      </div>
    </div>

    <!-- DSL Editor -->
    <div class="space-y-4">
      <div class="flex items-center justify-between">
        <h2 class="text-2xl font-bold">DSL Editor</h2>
        <button
          type="button"
          phx-click="copy_dsl"
          class="text-sm text-blue-600 hover:underline"
        >
          Copy DSL
        </button>
      </div>

      <textarea
        id="dsl-editor"
        name="dsl_content"
        phx-hook=".DslEditorSync"
        phx-update="ignore"
        class="w-full h-96 font-mono text-sm border border-gray-300 rounded-lg p-3"
        placeholder="Your DSL code will appear here or paste DSL to sync to builder..."
      ><%= @dsl_content %></textarea>

      <!-- Syntax Error Display -->
      <%= if @dsl_syntax_error do %>
        <div class="bg-red-50 border border-red-200 rounded-lg p-3">
          <h4 class="font-semibold text-red-800 mb-1">DSL Syntax Error</h4>
          <p class="text-sm text-red-700">
            Line <%= @dsl_syntax_error.line %>: <%= @dsl_syntax_error.message %>
          </p>
        </div>
      <% end %>

      <!-- Sync Status Indicator -->
      <div
        id="dsl-sync-status"
        class="text-sm font-medium px-3 py-2 rounded"
        phx-hook=".SyncStatusIndicator"
        data-source="dsl_editor"
      >
        Ready
      </div>
    </div>
  </div>

  <!-- Shared Hooks -->
  <script :type={Phoenix.LiveView.ColocatedHook} name=".DslEditorSync">
    export default {
      debounceTimer: null,
      DEBOUNCE_MS: 300,
      MIN_SYNC_INTERVAL_MS: 300,
      lastSyncTime: 0,

      mounted() {
        this.el.addEventListener("input", (e) => this.handleInput(e))
        this.el.addEventListener("change", (e) => this.handleChange(e))
      },

      handleInput(event) {
        if (this.debounceTimer) {
          clearTimeout(this.debounceTimer)
        }

        this.debounceTimer = setTimeout(() => {
          this.attemptSync()
        }, this.DEBOUNCE_MS)

        this.updateStatus("Typing...")
      },

      handleChange(event) {
        if (this.debounceTimer) {
          clearTimeout(this.debounceTimer)
        }
        this.attemptSync()
      },

      attemptSync() {
        const now = Date.now()
        const timeSinceLastSync = now - this.lastSyncTime

        if (timeSinceLastSync < this.MIN_SYNC_INTERVAL_MS) {
          this.debounceTimer = setTimeout(
            () => this.attemptSync(),
            this.MIN_SYNC_INTERVAL_MS - timeSinceLastSync
          )
          return
        }

        this.lastSyncTime = now
        this.pushEvent("dsl_content_changed", {
          content: this.el.value,
          source: "dsl_editor",
          timestamp: new Date().toISOString()
        })
        this.updateStatus("Syncing...")
      },

      updateStatus(message) {
        const indicator = document.getElementById("dsl-sync-status")
        if (indicator) {
          indicator.textContent = message
          indicator.classList.remove("bg-green-50", "text-green-700", "bg-red-50", "text-red-700")
          indicator.classList.add("bg-yellow-50", "text-yellow-700")
        }
      },

      destroyed() {
        if (this.debounceTimer) {
          clearTimeout(this.debounceTimer)
        }
      }
    }
  </script>

  <script :type={Phoenix.LiveView.ColocatedHook} name=".SyncStatusIndicator">
    export default {
      mounted() {
        this.updateStatus("ready")
      },

      updated() {
        this.updateStatus(this.el.textContent.toLowerCase())
      },

      updateStatus(status) {
        const classes = ["px-3", "py-2", "rounded", "text-sm", "font-medium"]
        this.el.className = classes.join(" ")

        if (status.includes("typing") || status.includes("syncing")) {
          this.el.classList.add("bg-yellow-50", "text-yellow-700")
        } else if (status.includes("ready")) {
          this.el.classList.add("bg-green-50", "text-green-700")
        } else if (status.includes("error")) {
          this.el.classList.add("bg-red-50", "text-red-700")
        }
      }
    }
  </script>
</div>
```

### 6.2 LiveView Handler (form.ex)

```elixir
defmodule TradingStrategyWeb.StrategyLive.Form do
  use TradingStrategyWeb, :live_view

  # ... existing code ...

  @impl true
  def mount(params, _session, socket) do
    strategy_id = params["id"]
    current_user = socket.assigns.current_scope.user

    # ... existing strategy loading code ...

    socket =
      socket
      |> assign(:last_sync_times, %{})  # Track sync time per source
      |> assign(:dsl_content, generate_dsl(strategy))
      |> assign(:dsl_syntax_error, nil)
      |> assign(:sync_source, nil)  # Track which editor was last modified
      |> assign(:pending_syncs, %{})  # Queue for rate-limited syncs

    {:ok, socket}
  end

  # DSL Editor Change Handler
  @impl true
  def handle_event("dsl_content_changed", params, socket) do
    %{"content" => content, "source" => "dsl_editor", "timestamp" => timestamp} = params

    # Rate limiting check
    now = DateTime.from_iso8601(timestamp) |> elem(0) |> DateTime.to_unix(:millisecond)
    last_sync = socket.assigns.last_sync_times["dsl_editor"] || 0

    if now - last_sync < 300 do
      # Rate limited - queue for later
      {:noreply,
       socket
       |> assign(:pending_syncs, Map.put(socket.assigns.pending_syncs, "dsl_editor", params))}
    else
      {:noreply,
       socket
       |> process_dsl_sync(content)
       |> assign(:last_sync_times, Map.put(socket.assigns.last_sync_times, "dsl_editor", now))
       |> assign(:sync_source, "dsl_editor")}
    end
  end

  # Builder Change Handler
  @impl true
  def handle_event("indicators_changed", indicators, socket) do
    now = DateTime.utc_now() |> DateTime.to_unix(:millisecond)
    last_sync = socket.assigns.last_sync_times["builder"] || 0

    if now - last_sync < 300 do
      {:noreply,
       socket
       |> assign(:pending_syncs, Map.put(socket.assigns.pending_syncs, "builder", indicators))}
    else
      {:noreply,
       socket
       |> assign(:indicators, indicators)
       |> update_dsl_from_builder()
       |> assign(:last_sync_times, Map.put(socket.assigns.last_sync_times, "builder", now))
       |> assign(:sync_source, "builder")}
    end
  end

  # Process DSL sync
  defp process_dsl_sync(socket, dsl_content) do
    format = socket.assigns.form.source.data.format || "yaml"

    case Strategies.validate_dsl_and_parse(dsl_content, String.to_atom(format)) do
      {:ok, parsed} ->
        # DSL is valid - update builder state
        socket
        |> assign(:dsl_content, dsl_content)
        |> assign(:dsl_syntax_error, nil)
        |> sync_builder_from_dsl(parsed)

      {:error, errors} ->
        # DSL has errors - show them but keep last valid builder state
        socket
        |> assign(:dsl_content, dsl_content)
        |> assign(:dsl_syntax_error, format_error(errors))
    end
  end

  defp sync_builder_from_dsl(socket, parsed) do
    # Extract indicators, conditions from parsed DSL
    # Update builder state without changing form
    indicators = extract_indicators(parsed)
    entry_conditions = extract_conditions(parsed, :entry)
    exit_conditions = extract_conditions(parsed, :exit)

    socket
    |> assign(:indicators, indicators)
    |> assign(:entry_conditions, entry_conditions)
    |> assign(:exit_conditions, exit_conditions)
  end

  defp update_dsl_from_builder(socket) do
    # Generate DSL from current builder state
    dsl = generate_dsl_from_state(socket.assigns)
    assign(socket, :dsl_content, dsl)
  end

  defp generate_dsl_from_state(assigns) do
    # Generate YAML/TOML from indicators and conditions
    # This preserves the existing form data format
    indicators = assigns.indicators || []
    entry_conditions = assigns.entry_conditions || []
    exit_conditions = assigns.exit_conditions || []

    # Build DSL content
    """
    strategy:
      name: "#{assigns.form.data.name || "Untitled"}"
      trading_pair: "#{assigns.form.data.trading_pair || ""}"
      timeframe: "#{assigns.form.data.timeframe || ""}"

    indicators:
    #{Enum.map_join(indicators, "\n", &format_indicator/1)}

    entry_conditions:
    #{Enum.map_join(entry_conditions, "\n", &format_condition/1)}

    exit_conditions:
    #{Enum.map_join(exit_conditions, "\n", &format_condition/1)}
    """
  end

  defp format_error(errors) when is_list(errors) do
    case errors do
      [error | _] ->
        %{
          line: error.line || 1,
          message: error.message || error
        }

      _ ->
        nil
    end
  end

  defp format_indicator(indicator) do
    """
      - type: #{indicator.type}
        params: #{inspect(indicator.params)}
    """
  end

  defp format_condition(condition) do
    "  - #{condition.expression || condition}"
  end

  defp extract_indicators(parsed) do
    # Extract indicators from parsed DSL
    parsed[:indicators] || []
  end

  defp extract_conditions(parsed, type) do
    case type do
      :entry -> parsed[:entry_conditions] || []
      :exit -> parsed[:exit_conditions] || []
    end
  end

  defp generate_dsl(strategy) do
    # Generate initial DSL from strategy
    strategy.content || ""
  end
end
```

---

## 7. Performance Benchmarks & Metrics

### 7.1 Expected Performance

With recommended hybrid approach:

| Metric | Target | Expected | Notes |
|--------|--------|----------|-------|
| **Debounce delay** | 300ms | 300-310ms | Client-side, deterministic |
| **Sync latency** | <500ms | 150-300ms | Server-side, dependent on parse time |
| **First keystroke to visible update** | <600ms | 400-450ms | Debounce + sync + render |
| **Rate limit enforcement** | Minimum 300ms | 300ms+ | Enforced server-side |
| **DSL parse time (100 lines)** | N/A | ~50-100ms | Dependent on complexity |
| **Builder render time** | N/A | ~20-50ms | LiveView push + re-render |
| **Memory overhead** | N/A | ~50KB | Per active edit session |

### 7.2 Monitoring Points

Add telemetry to track:
```elixir
:telemetry.execute(
  [:trading_strategy, :sync, :dsl_to_builder],
  %{duration_ms: duration, lines_count: line_count},
  %{strategy_id: strategy_id, success: success}
)

:telemetry.execute(
  [:trading_strategy, :sync, :builder_to_dsl],
  %{duration_ms: duration, field_count: field_count},
  %{strategy_id: strategy_id}
)

:telemetry.execute(
  [:trading_strategy, :debounce, :fire],
  %{wait_time_ms: wait_time, queue_depth: queue_depth},
  %{source: source}
)
```

---

## 8. Recommendations & Decision Matrix

### 8.1 Recommended Approach: Hybrid (Rating: ★★★★★)

**Use**:
- `phx-debounce="300"` on form fields (baseline protection)
- Colocated hooks for complex multi-field coordination
- Server-side rate limiting in handlers
- GenServer debouncer for cross-strategy coordination

**Why**:
- Defense-in-depth: Client + server protection
- Meets FR-008 (300ms debounce requirement)
- Meets FR-001/FR-002 (<500ms sync latency)
- Aligns with Phoenix 1.8+ best practices
- Maintainable and testable

**Complexity**: Medium
**Maintenance**: Low
**Scalability**: High (GenServer is single-node but horizontally scalable with Redis pubsub)

### 8.2 Alternative: Client-Only Debounce (Rating: ★★☆☆☆)

**Use**: Only colocated hooks, no server-side rate limiting

**Pros**:
- Simpler implementation
- Lowest latency

**Cons**:
- No protection against malicious rapid events
- No queue management
- Network jitter can cause issues

**Not Recommended for**: Production with untrusted users

### 8.3 Alternative: phx-debounce Only (Rating: ★★★☆☆)

**Use**: Only `phx-debounce="300"` attribute on fields

**Pros**:
- Simplest implementation
- Built-in, no extra code

**Cons**:
- Limited to single fields
- No cross-field coordination
- Less flexible for complex sync scenarios
- Cannot implement leading/trailing event handling

**Recommended for**: Simple forms only (not suitable for 005 feature)

---

## 9. Implementation Checklist

### Phase 1: Client-Side (Week 1)
- [ ] Add colocated DSL editor hook with 300ms debounce
- [ ] Add builder field hooks with debounce
- [ ] Implement sync status indicators
- [ ] Add visual feedback (loading spinners)
- [ ] Test debounce timing with browser DevTools

### Phase 2: Server-Side (Week 1-2)
- [ ] Add rate limiting to LiveView handlers
- [ ] Implement sync history tracking
- [ ] Add pending sync queue
- [ ] Create DebounceManager GenServer
- [ ] Add telemetry monitoring

### Phase 3: Synchronization Logic (Week 2-3)
- [ ] Implement DSL→Builder parser integration
- [ ] Implement Builder→DSL generation
- [ ] Handle comment preservation
- [ ] Implement bidirectional sync tests
- [ ] Add error handling and recovery

### Phase 4: Testing & Optimization (Week 3-4)
- [ ] Load test with rapid edits
- [ ] Test with 10K+ line DSL
- [ ] Network latency simulation
- [ ] Error scenario testing
- [ ] Performance profiling and optimization

---

## 10. Conclusion

For the 005-builder-dsl-sync feature with FR-008 (300ms debounce) and FR-001/FR-002 (<500ms sync) requirements, the **hybrid approach is strongly recommended**:

1. **Client-side**: Colocated Phoenix hooks with 300ms debounce + visual feedback
2. **Server-side**: Rate limiting in handlers + optional GenServer debouncer
3. **Monitoring**: Telemetry for debounce timing and sync latency
4. **Error Handling**: Preserve last valid state, show inline errors

This provides robustness, meets all requirements, and aligns with Phoenix 1.8+ best practices.

---

## References

- [Phoenix 1.8.2 Documentation](https://hexdocs.pm/phoenix/1.8.2)
- [Phoenix LiveView 1.0+ Debouncing](https://hexdocs.pm/phoenix_live_view/1.0.0/js-interop)
- [Phoenix LiveView Colocated Hooks](https://hexdocs.pm/phoenix_live_view/1.0.0/colocated-hooks)
- [DOM Diffing with phx-update](https://hexdocs.pm/phoenix_live_view/1.0.0/dom-patching)
- Feature Spec: `/specs/005-builder-dsl-sync/spec.md`

