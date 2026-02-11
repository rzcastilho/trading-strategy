# CodeMirror 6 + Yjs Implementation Guide
## Feature 005: Builder-DSL Synchronization

**Status**: Implementation-ready
**Target Framework**: Phoenix LiveView 1.7+ with esbuild
**Dependencies**: CodeMirror 6, Yjs, y-codemirror.next

---

## Quick Start

### 1. Install Dependencies

```bash
# In your Phoenix assets directory
cd assets

npm install --save \
  @codemirror/state \
  @codemirror/view \
  @codemirror/language \
  @codemirror/commands \
  @codemirror/lang-javascript \
  @codemirror/lang-html \
  @codemirror/lang-css \
  y-codemirror.next \
  yjs
```

### 2. Create Custom DSL Language Extension

**File**: `assets/js/dsl-language.js`

```javascript
import { Language, StreamLanguage, defineLanguage } from "@codemirror/language"
import { tags as t } from "@lezer/highlight"

// Simple streaming language for trading DSL
// Extend this with full Lezer grammar for production use
export const dslLanguage = StreamLanguage.define({
  token(stream) {
    // Keywords
    if (stream.match(/\b(strategy|indicators|entry|exit|conditions|parameters|period|length|threshold|price|volume)\b/)) {
      return "keyword"
    }

    // Comments
    if (stream.match(/^#.*/) || stream.match(/\/\/.*/)) {
      return "comment"
    }

    // Strings
    if (stream.match(/["']([^"']|\\.)*["']/)) {
      return "string"
    }

    // Numbers
    if (stream.match(/\d+\.?\d*([eE][+-]?\d+)?/)) {
      return "number"
    }

    // Operators
    if (stream.match(/[+\-*/%=<>!&|^~]/)) {
      return "operator"
    }

    // Brackets and punctuation
    if (stream.match(/[{}()\[\]]/)) {
      return "punctuation"
    }

    // Indicator names (RSI, MACD, etc.)
    if (stream.match(/\b[A-Z]{2,}\b/)) {
      return "function"
    }

    // Identifiers
    if (stream.match(/[a-zA-Z_][a-zA-Z0-9_]*/)) {
      return "variableName"
    }

    stream.next()
    return null
  }
})

// Styling configuration
export const dslHighlighting = {
  "keyword": "color: #06b; font-weight: bold;",
  "comment": "color: #6a9955; font-style: italic;",
  "string": "color: #ce9178;",
  "number": "color: #098658;",
  "operator": "color: #d4d4d4;",
  "function": "color: #dcdcaa;",
  "variableName": "color: #9cdcfe;",
  "punctuation": "color: #d4d4d4;"
}
```

### 3. Create Phoenix LiveView Hook

**File**: `assets/js/hooks/editor-hook.js`

```javascript
import { EditorState, EditorSelection } from "@codemirror/state"
import { EditorView, basicSetup } from "@codemirror/view"
import { dslLanguage, dslHighlighting } from "../dsl-language"
import * as Y from "yjs"
import { yCollab } from "y-codemirror.next"

export const DSLEditorHook = {
  mounted() {
    const hook = this

    // Initialize Yjs document
    const ydoc = new Y.Doc()
    const ytext = ydoc.getText("dsl-content")

    // Get initial content from server
    const initialContent = this.el.dataset.content || ""
    if (initialContent) {
      ytext.insert(0, initialContent)
    }

    // Create CodeMirror editor with collaboration
    const editor = new EditorView({
      state: EditorState.create({
        doc: initialContent,
        extensions: [
          basicSetup,
          dslLanguage.support,
          // Yjs collaboration extension
          yCollab(ytext, ydoc.getState(), {
            awareness: null // Can add awareness provider here for cursors
          }),
          // Custom theme
          EditorView.theme({
            ".cm-content": { fontSize: "14px", fontFamily: "monospace" },
            ".cm-gutters": { backgroundColor: "#f5f5f5" },
            ".cm-activeLineGutter": { backgroundColor: "#e8e8e8" }
          }),
          // Change event handler
          EditorView.updateListener.of((update) => {
            if (update.docChanged) {
              // Debounce changes (300ms)
              clearTimeout(hook.syncTimeout)
              hook.syncTimeout = setTimeout(() => {
                const newDSL = editor.state.doc.toString()
                // Push to LiveView
                hook.pushEvent("dsl_changed", { content: newDSL })
              }, 300)
            }
          })
        ]
      }),
      parent: this.el
    })

    // Store references
    this.editor = editor
    this.ydoc = ydoc
    this.ytext = ytext
    this.syncTimeout = null

    // Handle server updates from builder
    this.handleEvent("update_dsl", ({ content, cursorPos }) => {
      // Apply Yjs transaction to preserve undo/redo
      const transaction = this.editor.state.update({
        changes: {
          from: 0,
          to: this.editor.state.doc.length,
          insert: content
        }
      })

      this.editor.dispatch(transaction)

      // Restore cursor if provided
      if (cursorPos !== undefined) {
        const sel = EditorSelection.single(Math.min(cursorPos, content.length))
        this.editor.dispatch({
          selection: sel
        })
      }
    })
  },

  updated() {
    // Called when element is updated from server
    // For now, we rely on event handling
  },

  destroyed() {
    // Clean up
    if (this.editor) {
      this.editor.destroy()
    }
    if (this.ydoc) {
      this.ydoc.destroy()
    }
  }
}
```

### 4. Export Hook in Main JavaScript File

**File**: `assets/js/app.js`

```javascript
import { DSLEditorHook } from "./hooks/editor-hook"

// ... other imports

let liveSocket = new LiveSocket("/live", Socket, {
  params: { _csrf_token: csrfToken },
  hooks: {
    DSLEditor: DSLEditorHook
    // ... other hooks
  }
})
```

### 5. Phoenix LiveView Component

**File**: `lib/trading_strategy_web/live/strategy_live/dsl_editor.ex`

```elixir
defmodule TradingStrategyWeb.StrategyLive.DSLEditor do
  use TradingStrategyWeb, :live_component
  alias TradingStrategy.Strategies
  alias TradingStrategy.StrategyParser

  def render(assigns) do
    ~H"""
    <div class="dsl-editor-container">
      <div class="editor-header">
        <h3>Strategy DSL Editor</h3>
        <button phx-click="save_dsl" phx-target={@myself} class="btn btn-primary">
          Save
        </button>
      </div>

      <div id="dsl-editor"
           phx-hook="DSLEditor"
           data-content={@dsl_content}
           class="editor"
           phx-change="editor_changed"
           phx-target={@myself}>
      </div>

      <div class="editor-messages">
        <%= if @validation_error do %>
          <div class="alert alert-error">
            <strong>Error:</strong> <%= @validation_error %>
          </div>
        <% end %>

        <%= if @sync_status == :syncing do %>
          <div class="alert alert-info">
            <span class="spinner"></span> Syncing with builder...
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  def mount(assigns) do
    {:ok, assign(assigns, validation_error: nil, sync_status: :idle)}
  end

  def update(%{"strategy_id" => strategy_id} = assigns, socket) do
    strategy = Strategies.get_strategy!(strategy_id)
    dsl_content = strategy.dsl_content || ""

    {:ok, assign(socket, assigns, dsl_content: dsl_content)}
  end

  def handle_event("editor_changed", %{"content" => new_dsl}, socket) do
    # Validate DSL
    case StrategyParser.parse(new_dsl) do
      {:ok, parsed_strategy} ->
        # Broadcast to builder for sync
        send_update(TradingStrategyWeb.StrategyLive.BuilderForm,
          id: "builder-form",
          strategy_data: parsed_strategy
        )

        {:noreply, assign(socket, validation_error: nil, sync_status: :syncing)}

      {:error, error_message} ->
        {:noreply, assign(socket, validation_error: error_message)}
    end
  end

  def handle_event("save_dsl", _params, socket) do
    strategy_id = socket.assigns.strategy_id
    strategy = Strategies.get_strategy!(strategy_id)

    case Strategies.update_strategy(strategy, %{dsl_content: socket.assigns.dsl_content}) do
      {:ok, _strategy} ->
        {:noreply, put_flash(socket, :info, "Strategy saved successfully")}

      {:error, changeset} ->
        {:noreply, put_flash(socket, :error, "Save failed")}
    end
  end

  # Handle builder → DSL sync
  def handle_event("update_from_builder", %{"dsl" => dsl_content, "cursor_pos" => cursor_pos}, socket) do
    send_update(socket.assigns.id,
      dsl_content: dsl_content,
      cursor_pos: cursor_pos,
      sync_status: :idle
    )

    {:noreply, socket}
  end
end
```

---

## Architecture Patterns

### Bidirectional Sync Flow

```
DSL Editor (CodeMirror 6 + Yjs)
    ↓ (300ms debounce)
"dsl_changed" event → Phoenix LiveView
    ↓
StrategyParser.parse(dsl) → Validate
    ↓
If valid: BuilderForm.update() → Re-render builder
If invalid: Show error inline in editor
    ↓
Reverse flow (builder → DSL):
BuilderForm change → "builder_changed" event
    ↓
Convert builder state to DSL code
    ↓
push_event("update_dsl", ...) → DSLEditor
    ↓
Editor.dispatch({changes: ...}) → Display with Yjs (preserves undo)
```

### Cursor Position Preservation

```javascript
// When syncing external changes:
const cursorPos = editor.state.selection.main.anchor
const transaction = editor.state.update({
  changes: {...},
  selection: EditorSelection.single(cursorPos) // Restore cursor
})
editor.dispatch(transaction)
```

### Comment Preservation

```javascript
// Yjs preserves all content, including comments
// When parsing DSL → builder, extract metadata separately:

const lines = dsl.split('\n')
const comments = lines
  .map((line, idx) => ({ idx, text: line, isComment: line.trim().startsWith('#') }))
  .filter(item => item.isComment)

// Store comments separately for later reconstruction
// When builder → DSL, re-insert comments at original positions
```

---

## Error Handling

### DSL Validation Errors

```elixir
defmodule TradingStrategy.StrategyParser do
  def parse(dsl_content) do
    try do
      # Parse DSL using your DSL library (Feature 001)
      parsed = DSLParser.parse(dsl_content)

      case parsed do
        {:ok, strategy} -> {:ok, strategy}
        {:error, %{line: line, column: col, message: msg}} ->
          {:error, "Line #{line}, Column #{col}: #{msg}"}
      end
    rescue
      error ->
        Logger.error("DSL parser crash: #{inspect(error)}")
        {:error, "Parser error - please check syntax"}
    end
  end
end
```

### Handling Parser Failures (FR-005a)

```javascript
// In editor hook, catch exceptions
try {
  const result = parseAndSyncToBuilder(newDSL)
  // ...
} catch (error) {
  // Show error banner
  showErrorBanner(`Parser failed: ${error.message}`)

  // Log for debugging
  console.error("DSL parse failure", error)

  // Preserve last valid state - don't update builder
  // User can retry by clicking "Retry" button
}
```

---

## Testing Strategy

### Unit Tests (Elixir)

```elixir
# test/trading_strategy/strategy_parser_test.exs
defmodule TradingStrategy.StrategyParserTest do
  use ExUnit.Case

  describe "parse/1" do
    test "parses valid DSL" do
      dsl = """
      strategy:
        name: "Test Strategy"
        indicators:
          - name: RSI
            period: 14
      """

      assert {:ok, strategy} = StrategyParser.parse(dsl)
      assert strategy.name == "Test Strategy"
    end

    test "returns error with line/column for invalid DSL" do
      dsl = "invalid: ["

      assert {:error, message} = StrategyParser.parse(dsl)
      assert message =~ "Line"
    end
  end
end
```

### Integration Tests (LiveView)

```elixir
# test/trading_strategy_web/live/strategy_live/dsl_editor_test.exs
defmodule TradingStrategyWeb.StrategyLive.DSLEditorTest do
  use TradingStrategyWeb.ConnCase
  import Phoenix.LiveViewTest

  setup do
    strategy = insert(:strategy)
    {:ok, strategy: strategy}
  end

  test "syncs editor changes to builder", %{conn: conn, strategy: strategy} do
    {:ok, view, _html} = live(conn, "/strategies/#{strategy.id}")

    # Simulate editor change
    assert render_hook(view, "editor_changed", %{"content" => dsl_code}) =~ "builder updated"
  end

  test "displays validation errors", %{conn: conn, strategy: strategy} do
    {:ok, view, _html} = live(conn, "/strategies/#{strategy.id}")

    invalid_dsl = "invalid: ["
    assert render_hook(view, "editor_changed", %{"content" => invalid_dsl}) =~ "Error"
  end
end
```

---

## Performance Optimization

### Debouncing

```javascript
// Already implemented in hook (300ms minimum)
// Can adjust based on needs:
clearTimeout(hook.syncTimeout)
hook.syncTimeout = setTimeout(() => {
  hook.pushEvent("dsl_changed", { content: newDSL })
}, 300) // Adjust this value
```

### Large File Handling

```javascript
// For very large strategies (>5000 lines):
// CodeMirror 6 handles this automatically through viewport rendering
// But can optimize further:

// Disable syntax highlighting for lines outside viewport
EditorView.theme({
  ".cm-content": {
    fontSize: "14px",
    fontFamily: "monospace"
    // CodeMirror automatically optimizes here
  }
})

// Lazy-load indicators for very large strategies
// (Feature engineering, not required for MVP)
```

---

## Customization Examples

### Dark Theme

```javascript
import { oneDark } from "@codemirror/theme-one-dark"

// In editor extensions:
[
  basicSetup,
  oneDark,
  // ...
]
```

### Custom Keybindings

```javascript
import { keymap } from "@codemirror/view"
import { indentMore, indentLess } from "@codemirror/commands"

// In editor extensions:
[
  keymap.of([
    { key: "Tab", run: indentMore, shift: indentLess }
  ]),
  // ...
]
```

### Code Folding

```javascript
import { foldGutter, foldEffect } from "@codemirror/language"

// In editor extensions:
[
  foldGutter(),
  // ...
]
```

---

## Debugging Guide

### Inspect Tokens

```javascript
// In browser console, type (CodeMirror command):
// Open with Ctrl+K → "Inspect Tokens"
// Shows what tokens CodeMirror sees for debugging syntax highlighting
```

### Monitor Sync Events

```elixir
# In LiveView, add logging:
def handle_event("editor_changed", %{"content" => new_dsl}, socket) do
  Logger.info("DSL editor changed, parsing: #{String.length(new_dsl)} chars")
  # ... rest of handler
end
```

### Performance Profiling

```javascript
// In browser DevTools:
// Open Performance tab
// Record while making edits
// Check for long tasks (should be <100ms for 300ms debounce)
```

---

## Common Issues & Solutions

### Issue: Cursor loses position on sync
**Solution**: Always restore cursor using EditorSelection.single()

### Issue: Comments disappear during sync
**Solution**: Store comments separately or use custom diff algorithm

### Issue: Undo/redo not working across editors
**Solution**: Implement shared undo/redo stack using Yjs undoManager

### Issue: Performance degrades with many rapid updates
**Solution**: Increase debounce delay from 300ms to 500ms, or batch updates

### Issue: Yjs state grows too large
**Solution**: Periodically clean up old versions with doc.transact()

---

## Next Steps

1. **Set up CodeMirror 6** in assets pipeline
2. **Create DSL language** extension (start simple, extend later)
3. **Implement editor hook** and test with manual changes
4. **Connect to builder** with debounced sync events
5. **Handle validation errors** with clear user feedback
6. **Test bidirectional sync** end-to-end
7. **Optimize performance** with larger test documents
8. **Polish UX** with visual feedback and error messages

---

## Resources

- [CodeMirror 6 System Guide](https://codemirror.net/docs/guide/)
- [y-codemirror.next Documentation](https://docs.yjs.dev/)
- [Yjs CRDT Guide](https://docs.yjs.dev/getting-started/introduction)
- [Phoenix LiveView Hooks](https://hexdocs.pm/phoenix_live_view/dom-patching.html)

