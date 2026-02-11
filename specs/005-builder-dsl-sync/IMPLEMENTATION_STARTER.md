# Implementation Starter Code: Hybrid DSL Parsing

**Status**: Ready to code
**Complexity**: Medium
**Estimated Time**: 2-3 weeks

---

## Part 1: Server-Side Implementation (Elixir)

### File 1: `lib/trading_strategy/strategy_editor/dsl_parser.ex`

```elixir
defmodule TradingStrategy.StrategyEditor.DSLParser do
  @moduledoc """
  DSL parser wrapper for LiveView integration.

  Wraps the Feature 001 DSL parser (TradingStrategy.Strategies.DSL.Parser)
  with error handling suitable for real-time synchronization.
  """

  require Logger
  alias TradingStrategy.Strategies.DSL.{Parser, Validator}

  @doc """
  Parses and validates DSL content, returning structured result for LiveView.

  Returns {:ok, result} where result is a map:
    %{
      valid: true | false,
      strategy: map() | nil,  # parsed strategy if valid
      errors: [String.t()],   # validation errors if invalid
      warnings: [String.t()], # non-blocking issues (e.g., unsupported features)
      parse_time_ms: integer  # performance metric
    }

  This never raises exceptions - always returns {:ok, _} for UI safety.
  """
  @spec parse_and_validate(String.t()) :: {:ok, map()}
  def parse_and_validate(dsl_text) when is_binary(dsl_text) do
    start_time = System.monotonic_time(:millisecond)

    result =
      case execute_parse(dsl_text) do
        {:ok, strategy} ->
          case validate_strategy(strategy) do
            {:ok, validated} ->
              %{
                valid: true,
                strategy: validated,
                errors: [],
                warnings: detect_unsupported_features(validated),
                parse_time_ms: elapsed_time(start_time)
              }

            {:error, validation_errors} ->
              %{
                valid: false,
                strategy: nil,
                errors: validation_errors,
                warnings: [],
                parse_time_ms: elapsed_time(start_time)
              }
          end

        {:error, parse_error} ->
          %{
            valid: false,
            strategy: nil,
            errors: [parse_error],
            warnings: [],
            parse_time_ms: elapsed_time(start_time)
          }

        {:error, :timeout} ->
          %{
            valid: false,
            strategy: nil,
            errors: ["Parser timeout (strategy too complex)"],
            warnings: [],
            parse_time_ms: elapsed_time(start_time)
          }
      end

    {:ok, result}
  end

  def parse_and_validate(_), do: {:ok, invalid_input_result()}

  # Private Functions

  defp execute_parse(dsl_text) do
    # Determine format (YAML or TOML) and parse
    format = infer_format(dsl_text)

    # Wrap in timeout to prevent hanging on malformed input
    try do
      case Parser.parse(dsl_text, format) do
        {:ok, strategy} -> {:ok, strategy}
        {:error, reason} -> {:error, format_error(reason)}
      end
    rescue
      error ->
        Logger.error("DSL parser error: #{inspect(error)}")
        {:error, "Parser error: #{Exception.message(error)}"}
    catch
      :timeout -> {:error, :timeout}
    end
  end

  defp validate_strategy(strategy) do
    case Validator.validate(strategy) do
      {:ok, validated} ->
        {:ok, validated}

      {:error, errors} when is_list(errors) ->
        {:error, errors}

      {:error, error} when is_binary(error) ->
        {:error, [error]}

      {:error, other} ->
        {:error, ["Unexpected validation error: #{inspect(other)}"]}
    end
  end

  defp infer_format(dsl_text) do
    # Basic heuristic: look for TOML/YAML characteristics
    cond do
      String.contains?(dsl_text, ["[[", "[", "="]) and
        String.contains?(dsl_text, ["indicators", "entry"]) ->
        :toml

      true ->
        :yaml # Default to YAML
    end
  end

  defp detect_unsupported_features(strategy) do
    # Placeholder: Add checks for DSL features that builder can't represent
    # Examples: custom functions, advanced logic, etc.
    []
  end

  defp format_error(error) when is_binary(error), do: error
  defp format_error(error), do: "Parse error: #{inspect(error)}"

  defp elapsed_time(start_time) do
    System.monotonic_time(:millisecond) - start_time
  end

  defp invalid_input_result do
    %{
      valid: false,
      strategy: nil,
      errors: ["Invalid input: expected DSL string"],
      warnings: [],
      parse_time_ms: 0
    }
  end
end
```

### File 2: `lib/trading_strategy_web/live/strategy_live/edit.ex` (Modified)

```elixir
defmodule TradingStrategyWeb.StrategyLive.Edit do
  use TradingStrategyWeb, :live_view

  require Logger
  alias TradingStrategy.StrategyEditor.DSLParser
  alias TradingStrategy.Strategies

  @doc """
  Main strategy editor LiveView supporting bidirectional sync.

  Assigns:
    - :strategy - Strategy being edited
    - :dsl_text - Current DSL text in editor
    - :builder_state - Current builder form state
    - :dsl_errors - List of validation errors
    - :sync_status - Current sync state (:idle, :syncing, :success, :error)
    - :last_modified_editor - Which editor was last changed (:builder or :dsl)
    - :dirty - Whether there are unsaved changes
  """

  @impl true
  def mount(params, _session, socket) do
    strategy_id = params["id"]
    current_user = socket.assigns.current_scope.user

    strategy =
      if strategy_id do
        Strategies.get_strategy(strategy_id, current_user)
      else
        # New strategy - initialize with template
        %Strategies.Strategy{
          user_id: current_user.id,
          status: "draft",
          dsl_code: default_dsl_template()
        }
      end

    if is_nil(strategy) do
      {:ok, push_navigate(socket, to: ~p"/strategies")}
    else
      # Parse initial DSL to populate builder
      {:ok, parse_result} = DSLParser.parse_and_validate(strategy.dsl_code || "")

      {:ok,
       socket
       |> assign(:strategy, strategy)
       |> assign(:dsl_text, strategy.dsl_code || "")
       |> assign(:builder_state, parse_result[:strategy] || %{})
       |> assign(:dsl_errors, parse_result[:errors] || [])
       |> assign(:dsl_warnings, parse_result[:warnings] || [])
       |> assign(:sync_status, :idle)
       |> assign(:last_modified_editor, nil)
       |> assign(:dirty, false)
       |> assign(:last_sync_ms, 0)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="grid grid-cols-2 gap-4 h-screen p-4">
      <!-- Left Pane: Strategy Builder (Form) -->
      <div class="builder-pane border-r border-gray-200 overflow-y-auto">
        <div class="sticky top-0 bg-white z-10 pb-4">
          <h2 class="text-xl font-bold">Strategy Builder</h2>
          <p class="text-sm text-gray-500">Visual form interface</p>
        </div>

        <%= if Enum.any?(@dsl_warnings) do %>
          <div class="mb-4 p-3 bg-yellow-50 border border-yellow-200 rounded">
            <p class="text-sm font-semibold text-yellow-900">Unsupported Features:</p>
            <ul class="mt-2 text-sm text-yellow-700 space-y-1">
              <%= for warning <- @dsl_warnings do %>
                <li>• <%= warning %></li>
              <% end %>
            </ul>
          </div>
        <% end %>

        <%= if Enum.any?(@dsl_errors) && @last_modified_editor == :dsl do %>
          <div class="mb-4 p-3 bg-red-50 border border-red-200 rounded">
            <p class="text-sm font-semibold text-red-900">DSL Errors:</p>
            <ul class="mt-2 text-sm text-red-700 space-y-1">
              <%= for error <- @dsl_errors do %>
                <li>• <%= error %></li>
              <% end %>
            </ul>
            <p class="mt-2 text-xs text-red-600">
              Showing last valid builder state. Fix DSL errors to continue.
            </p>
          </div>
        <% end %>

        <.live_component
          module={TradingStrategyWeb.StrategyLive.BuilderForm}
          id="builder-form"
          strategy={@builder_state}
          disabled={Enum.any?(@dsl_errors) && @last_modified_editor == :dsl}
        />
      </div>

      <!-- Right Pane: DSL Editor -->
      <div class="dsl-pane flex flex-col border-l border-gray-200">
        <div class="sticky top-0 bg-white z-10 pb-4 flex justify-between items-center">
          <div>
            <h2 class="text-xl font-bold">DSL Editor</h2>
            <p class="text-sm text-gray-500">Text-based configuration</p>
          </div>

          <div class="flex items-center gap-2">
            <%= case @sync_status do %>
              <% :syncing -> %>
                <span class="inline-flex items-center gap-1 text-sm text-blue-600">
                  <svg class="animate-spin h-4 w-4" fill="none" viewBox="0 0 24 24">
                    <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                    <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                  </svg>
                  Syncing...
                </span>

              <% :success -> %>
                <span class="inline-flex items-center gap-1 text-sm text-green-600">
                  <svg class="h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"></path>
                  </svg>
                  Synced
                </span>

              <% :error -> %>
                <span class="inline-flex items-center gap-1 text-sm text-red-600">
                  <svg class="h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>
                  </svg>
                  Error
                </span>

              <% _ -> %>
                <span class="text-sm text-gray-400">Ready</span>
            <% end %>
          </div>
        </div>

        <!-- CodeMirror Editor Container -->
        <div
          id="dsl-editor"
          class="flex-1 border border-gray-300 rounded"
          data-initial-dsl={@dsl_text}
          phx-hook="DSLEditor"
        >
        </div>

        <!-- Syntax Errors Panel -->
        <%= if Enum.any?(@dsl_errors) do %>
          <div class="mt-4 p-3 bg-red-50 border border-red-200 rounded max-h-24 overflow-y-auto">
            <p class="text-sm font-semibold text-red-900">Validation Errors:</p>
            <ul class="mt-1 text-xs text-red-700 space-y-1 font-mono">
              <%= for error <- @dsl_errors do %>
                <li>✗ <%= error %></li>
              <% end %>
            </ul>
          </div>
        <% end %>

        <!-- Performance Indicator -->
        <div class="mt-2 text-xs text-gray-500">
          <%= if @last_sync_ms > 0 do %>
            Last sync: <%= @last_sync_ms %>ms
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Handle DSL text changes from JavaScript editor hook.

  This event fires after debouncing (300ms), allowing server to validate.
  """
  @impl true
  def handle_event("dsl_changed", %{"dsl" => dsl_text}, socket) do
    # Mark as currently syncing
    socket = assign(socket, sync_status: :syncing)
    send(self(), {:parse_dsl, dsl_text})

    {:noreply, socket}
  end

  @doc """
  Handle builder form changes.

  When user edits the builder form, convert to DSL and send to editor.
  (Implementation: emit to JavaScript to update CodeMirror)
  """
  @impl true
  def handle_event("builder_changed", %{"strategy" => strategy_params}, socket) do
    # TODO: Convert strategy_params to DSL format
    # TODO: Emit event to update DSL editor: push_event("update_dsl", %{dsl: new_dsl})

    {:noreply, assign(socket, last_modified_editor: :builder, dirty: true)}
  end

  @doc """
  Handle save action from user.
  """
  @impl true
  def handle_event("save", _params, socket) do
    %{strategy: strategy, dsl_text: dsl_text} = socket.assigns

    case Strategies.update_strategy(strategy, %{dsl_code: dsl_text}) do
      {:ok, updated_strategy} ->
        {:noreply,
         socket
         |> assign(:strategy, updated_strategy)
         |> assign(:dirty, false)
         |> put_flash(:info, "Strategy saved successfully")}

      {:error, changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, "Failed to save strategy")}
    end
  end

  @doc """
  Async message handler for DSL parsing.
  """
  @impl true
  def handle_info({:parse_dsl, dsl_text}, socket) do
    start_time = System.monotonic_time(:millisecond)

    {:ok, parse_result} = DSLParser.parse_and_validate(dsl_text)
    elapsed = System.monotonic_time(:millisecond) - start_time

    new_status =
      if parse_result[:valid] do
        :success
      else
        :error
      end

    socket =
      socket
      |> assign(:dsl_text, dsl_text)
      |> assign(:sync_status, new_status)
      |> assign(:last_modified_editor, :dsl)
      |> assign(:dirty, true)
      |> assign(:last_sync_ms, elapsed)

    socket =
      if parse_result[:valid] do
        assign(socket,
          builder_state: parse_result[:strategy],
          dsl_errors: [],
          dsl_warnings: parse_result[:warnings]
        )
      else
        assign(socket,
          dsl_errors: parse_result[:errors],
          dsl_warnings: []
        )
      end

    # Revert status after 2 seconds
    Process.send_after(self(), {:revert_sync_status}, 2000)

    {:noreply, socket}
  end

  def handle_info({:revert_sync_status}, socket) do
    {:noreply, assign(socket, sync_status: :idle)}
  end

  # Private Helpers

  defp default_dsl_template do
    """
    name: My Strategy
    trading_pair: BTC/USD
    timeframe: 1h
    indicators:
      - type: rsi
        name: rsi_14
        parameters:
          period: 14
    entry_conditions: "rsi_14 < 30"
    exit_conditions: "rsi_14 > 70"
    stop_conditions: "close < entry_price * 0.95"
    position_sizing:
      type: percentage
      percentage_of_capital: 0.1
    risk_parameters:
      max_daily_loss: 0.03
      max_drawdown: 0.15
    """
  end
end
```

---

## Part 2: Client-Side Implementation (JavaScript)

### File 1: `priv/static/assets/js/validators/dsl_syntax_validator.js`

```javascript
/**
 * DSL Syntax Validator
 *
 * Performs client-side syntax validation only (no semantic parsing).
 * This provides instant feedback for:
 * - Parentheses balance
 * - Quote balance
 * - Basic YAML/TOML indentation
 *
 * Semantic validation (indicator types, parameter values) happens server-side.
 */

export class DSLSyntaxValidator {
  constructor() {
    this.errors = [];
  }

  /**
   * Validate DSL syntax only.
   * Returns array of error objects: { line, column, message, severity }
   * severity: 'error' | 'warning'
   */
  validate(text) {
    this.errors = [];
    const lines = text.split('\n');

    // Check 1: Parentheses balance
    this.checkParenthesesBalance(text);

    // Check 2: Quotes balance
    this.checkQuotesBalance(text);

    // Check 3: YAML/TOML structure
    this.checkIndentation(lines);

    // Check 4: Common typos (optional)
    this.checkCommonErrors(text, lines);

    return this.errors;
  }

  /**
   * Check that parentheses are balanced.
   * Handles both round () and square [] brackets.
   */
  checkParenthesesBalance(text) {
    const parens = { '(': ')', '[': ']', '{': '}' };
    const stack = [];
    let line = 1;
    let col = 1;

    for (let i = 0; i < text.length; i++) {
      const char = text[i];

      if (char === '\n') {
        line++;
        col = 1;
        continue;
      }

      if (parens[char]) {
        stack.push({ open: char, line, col });
      } else if (Object.values(parens).includes(char)) {
        // This is a closing bracket
        if (stack.length === 0) {
          this.addError(line, col, `Unexpected closing bracket '${char}'`, 'error');
        } else {
          const { open } = stack[stack.length - 1];
          if (parens[open] !== char) {
            this.addError(line, col, `Mismatched bracket: expected '${parens[open]}', got '${char}'`, 'error');
          } else {
            stack.pop();
          }
        }
      }

      col++;
    }

    // Check for unclosed brackets
    stack.forEach(({ open, line, col }) => {
      this.addError(line, col, `Unclosed bracket '${open}'`, 'error');
    });
  }

  /**
   * Check that quotes are balanced.
   * Handles both single and double quotes.
   */
  checkQuotesBalance(text) {
    let doubleQuotes = 0;
    let singleQuotes = 0;
    let inDouble = false;
    let inSingle = false;
    let line = 1;
    let col = 1;

    for (let i = 0; i < text.length; i++) {
      const char = text[i];
      const prevChar = i > 0 ? text[i - 1] : '';

      if (char === '\n') {
        line++;
        col = 1;
        continue;
      }

      // Skip escaped quotes
      if (prevChar === '\\') {
        col++;
        continue;
      }

      if (char === '"' && !inSingle) {
        inDouble = !inDouble;
        doubleQuotes++;
      } else if (char === "'" && !inDouble) {
        inSingle = !inSingle;
        singleQuotes++;
      }

      col++;
    }

    if (doubleQuotes % 2 !== 0) {
      this.addError(line, col, 'Unmatched double quotes', 'error');
    }
    if (singleQuotes % 2 !== 0) {
      this.addError(line, col, 'Unmatched single quotes', 'error');
    }
  }

  /**
   * Check basic YAML/TOML indentation rules.
   */
  checkIndentation(lines) {
    let expectedIndent = 0;

    lines.forEach((line, idx) => {
      if (line.trim() === '') return; // Skip empty lines

      const indent = line.search(/\S/);
      const lineNum = idx + 1;

      // Check if indentation is multiple of 2 (YAML standard)
      if (indent % 2 !== 0) {
        this.addError(lineNum, indent, 'Indentation should be multiple of 2 spaces', 'warning');
      }

      // Check for huge indentation jumps
      if (indent > expectedIndent + 4) {
        this.addError(lineNum, indent, 'Unexpected indentation level', 'warning');
      }

      // If line ends with colon, next line should be indented more
      if (line.trimRight().endsWith(':')) {
        const nextLine = lines[idx + 1];
        if (nextLine && nextLine.trim()) {
          const nextIndent = nextLine.search(/\S/);
          if (nextIndent <= indent) {
            // This is a warning, not an error (might be intentional)
          }
        }
      }
    });
  }

  /**
   * Check for common mistakes.
   */
  checkCommonErrors(text, lines) {
    // Check for common YAML mistakes
    const commonErrors = [
      { regex: /:\s*$/, message: 'Line ends with colon but has no value', severity: 'warning' },
      { regex: /^[^:]*:\s*\[.*\]\s*$/, message: 'Inline arrays are allowed', severity: 'info' }, // Not actually an error
    ];

    lines.forEach((line, idx) => {
      const lineNum = idx + 1;

      if (line.trim().endsWith(':') && !line.includes('[') && !line.includes('{')) {
        // This is OK in YAML (object marker), don't flag it
      }
    });
  }

  /**
   * Add an error to the list (avoiding duplicates).
   */
  addError(line, col, message, severity = 'error') {
    // Check for duplicate
    const isDuplicate = this.errors.some(
      (e) => e.line === line && e.column === col && e.message === message
    );

    if (!isDuplicate) {
      this.errors.push({ line, column: col, message, severity });
    }
  }

  /**
   * Severity level: 0 = info, 1 = warning, 2 = error
   * Used for sorting/filtering
   */
  severityLevel(severity) {
    const levels = { info: 0, warning: 1, error: 2 };
    return levels[severity] || 0;
  }
}
```

### File 2: `priv/static/assets/js/hooks/dsl_editor_hook.js`

```javascript
import { EditorView, basicSetup } from "codemirror";
import { yaml } from "@codemirror/lang-yaml";
import { oneDark } from "@codemirror/theme-one-dark";
import { DSLSyntaxValidator } from "../validators/dsl_syntax_validator.js";

/**
 * Phoenix LiveView hook for DSL editor integration.
 *
 * Manages:
 * - CodeMirror editor instance
 * - Syntax validation
 * - Debounced server synchronization
 * - Visual error feedback
 */

const DSL_EDITOR_HOOK = {
  mounted() {
    this.validator = new DSLSyntaxValidator();
    this.debounceTimer = null;
    this.syntaxCheckTimer = null;
    this.debounceDelay = 300; // ms
    this.syntaxCheckDelay = 50; // ms

    // Initialize CodeMirror
    this.editor = new EditorView({
      doc: this.el.dataset.initialDsl || this.getDefaultDSL(),
      extensions: [
        basicSetup,
        yaml(),
        EditorView.updateListener.of((update) => {
          if (update.docChanged) {
            this.handleChange();
          }
        }),
      ],
      theme: oneDark,
      parent: this.el,
    });

    // Expose to LiveView for programmatic updates
    this.el.editorView = this.editor;
  },

  /**
   * Called when DSL text changes in the editor.
   */
  handleChange() {
    const dslText = this.editor.state.doc.toString();

    // Clear previous timers
    clearTimeout(this.syntaxCheckTimer);
    clearTimeout(this.debounceTimer);

    // Syntax check immediately (client-side, no network)
    this.syntaxCheckTimer = setTimeout(() => {
      this.performSyntaxCheck(dslText);
    }, this.syntaxCheckDelay);

    // Server sync after debounce
    this.debounceTimer = setTimeout(() => {
      this.syncToServer(dslText);
    }, this.debounceDelay);
  },

  /**
   * Perform client-side syntax validation.
   * Shows errors inline in the editor.
   */
  performSyntaxCheck(dslText) {
    const errors = this.validator.validate(dslText);

    // Convert errors to CodeMirror diagnostics
    // (This would integrate with CodeMirror's lint extension in production)
    if (errors.length > 0) {
      // Send to LiveView for display (optional - could show in editor only)
      this.pushEvent("syntax_check", { errors });
    }
  },

  /**
   * Send DSL to server for semantic validation.
   * This happens after debounce (user stops typing for 300ms).
   */
  syncToServer(dslText) {
    if (!dslText || dslText.trim() === '') {
      return; // Don't sync empty DSL
    }

    // Send to Phoenix LiveView via event
    this.pushEvent("dsl_changed", { dsl: dslText });
  },

  /**
   * Called from LiveView to update editor content.
   * Used when builder changes and we need to update DSL.
   */
  pushUpdateDSL(newDSL) {
    const view = this.editor;
    view.dispatch({
      changes: {
        from: 0,
        to: view.state.doc.length,
        insert: newDSL,
      },
    });
  },

  getDefaultDSL() {
    return `name: My Strategy
trading_pair: BTC/USD
timeframe: 1h
indicators:
  - type: rsi
    name: rsi_14
    parameters:
      period: 14
entry_conditions: "rsi_14 < 30"
exit_conditions: "rsi_14 > 70"
stop_conditions: "close < entry_price * 0.95"
position_sizing:
  type: percentage
  percentage_of_capital: 0.1
risk_parameters:
  max_daily_loss: 0.03
  max_drawdown: 0.15`;
  },

  destroyed() {
    if (this.editor) {
      this.editor.destroy();
    }
  },
};

export default DSL_EDITOR_HOOK;
```

### File 3: `priv/static/assets/js/app.js` (Modified)

```javascript
// Register DSL editor hook
import DSLEditorHook from "./hooks/dsl_editor_hook";

let liveSocket = new LiveSocket("/live", Socket, {
  hooks: {
    DSLEditor: DSLEditorHook,
    // ... other hooks
  },
  params: { _csrf_token: csrfToken },
});

liveSocket.connect();
```

---

## Part 3: Testing

### File: `test/trading_strategy/strategy_editor/dsl_parser_test.exs`

```elixir
defmodule TradingStrategy.StrategyEditorTest.DSLParserTest do
  use ExUnit.Case

  alias TradingStrategy.StrategyEditor.DSLParser

  describe "parse_and_validate/1" do
    test "returns valid result for correct DSL" do
      dsl = """
      name: Test Strategy
      trading_pair: BTC/USD
      timeframe: 1h
      indicators:
        - type: rsi
          name: rsi_14
          parameters:
            period: 14
      entry_conditions: "rsi_14 < 30"
      exit_conditions: "rsi_14 > 70"
      stop_conditions: "close < entry_price * 0.95"
      position_sizing:
        type: percentage
        percentage_of_capital: 0.1
      risk_parameters:
        max_daily_loss: 0.03
        max_drawdown: 0.15
      """

      {:ok, result} = DSLParser.parse_and_validate(dsl)

      assert result[:valid] == true
      assert result[:strategy] != nil
      assert result[:errors] == []
      assert result[:parse_time_ms] >= 0
    end

    test "returns error for invalid syntax" do
      dsl = "name: Test\ninvalid: [unclosed"

      {:ok, result} = DSLParser.parse_and_validate(dsl)

      assert result[:valid] == false
      assert Enum.any?(result[:errors])
      assert result[:strategy] == nil
    end

    test "handles non-string input gracefully" do
      {:ok, result} = DSLParser.parse_and_validate(nil)

      assert result[:valid] == false
      assert Enum.any?(result[:errors])
    end

    test "performance is acceptable for 20-indicator strategy" do
      dsl = build_large_dsl(20)

      start_time = System.monotonic_time(:millisecond)
      {:ok, result} = DSLParser.parse_and_validate(dsl)
      elapsed = System.monotonic_time(:millisecond) - start_time

      assert result[:parse_time_ms] < 100
      assert elapsed < 150 # Allow some margin
    end
  end

  # Helper functions
  defp build_large_dsl(indicator_count) do
    indicators = Enum.map(1..indicator_count, fn i ->
      """
      - type: rsi
        name: rsi_#{14 + i}
        parameters:
          period: #{14 + i}
      """
    end) |> Enum.join("\n")

    """
    name: Large Strategy
    trading_pair: BTC/USD
    timeframe: 1h
    indicators:
    #{indicators}
    entry_conditions: "rsi_14 < 30"
    exit_conditions: "rsi_14 > 70"
    stop_conditions: "close < entry_price * 0.95"
    position_sizing:
      type: percentage
      percentage_of_capital: 0.1
    risk_parameters:
      max_daily_loss: 0.03
      max_drawdown: 0.15
    """
  end
end
```

---

## Getting Started

1. **Install CodeMirror dependencies**:
   ```bash
   npm install codemirror @codemirror/lang-yaml @codemirror/theme-one-dark
   ```

2. **Create the server-side file**: `lib/trading_strategy/strategy_editor/dsl_parser.ex`

3. **Create client-side files**: `priv/static/assets/js/validators/dsl_syntax_validator.js` and `priv/static/assets/js/hooks/dsl_editor_hook.js`

4. **Update the strategy LiveView**: Modify `lib/trading_strategy_web/live/strategy_live/edit.ex`

5. **Register hooks**: Update `priv/static/assets/js/app.js`

6. **Run tests**:
   ```bash
   mix test test/trading_strategy/strategy_editor/dsl_parser_test.exs
   ```

---

## Next Steps for Full Implementation

1. **Builder state synchronization**: Implement builder → DSL conversion
2. **Undo/redo stack**: Create shared edit history
3. **Comment preservation**: Parse/reconstruct DSL with comments
4. **Unsupported feature detection**: Identify DSL features builder can't represent
5. **Loading indicators**: Show sync status after 200ms
6. **Error recovery**: Preserve last valid state on parser failure

See main research documents for detailed specifications.
