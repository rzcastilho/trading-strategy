# Data Model: Indicator Output Values Display

**Feature**: 006-indicator-value-inspection
**Date**: 2026-02-11
**Phase**: 1 - Design

## Overview

This document defines the data structures and entities for displaying indicator output value metadata in the strategy builder UI. This is primarily a UI feature that consumes existing metadata from the TradingIndicators library.

---

## Entities

### 1. OutputFieldMetadata (External - TradingIndicators Library)

**Source**: `TradingIndicators.Types.OutputFieldMetadata`
**Purpose**: Describes the values an indicator produces
**Lifecycle**: Immutable at runtime, only changes with library version upgrades

```elixir
%TradingIndicators.Types.OutputFieldMetadata{
  type: :single_value | :multi_value,
  fields: [%FieldInfo{}] | nil,      # Only for multi_value
  description: String.t() | nil,
  example: String.t() | nil,
  unit: String.t() | nil              # Only for single_value
}
```

**Field Attributes**:
- `type` - Classification (single-value vs multi-value indicator)
- `fields` - List of output fields for multi-value indicators
- `description` - Human-readable description of what the indicator measures
- `example` - Example usage syntax in conditions
- `unit` - Unit or data type for single-value indicators (e.g., "price", "%")

**Validation Rules**:
- `type` must be either `:single_value` or `:multi_value`
- If `type == :multi_value`, `fields` must be a non-empty list
- If `type == :single_value`, `fields` must be `nil` and `unit` should be present

**State Transitions**: None (immutable)

---

### 2. FieldInfo (External - TradingIndicators Library)

**Purpose**: Individual value produced by a multi-value indicator
**Lifecycle**: Immutable at runtime

```elixir
%{
  name: atom(),
  type: :decimal | :integer | :map,
  description: String.t() | nil,
  unit: String.t() | nil
}
```

**Field Attributes**:
- `name` - Field name (e.g., `:upper_band`, `:macd`, `:signal`)
- `type` - Data type of the field value
- `description` - Explanation of what the field represents
- `unit` - Unit or data type (e.g., "price", "%", "volume")

**Validation Rules**:
- `name` must be a valid atom
- `type` must be one of `:decimal`, `:integer`, or `:map`
- `description` should be present for clarity (though nullable)

---

### 3. TooltipContent (Internal - Generated)

**Purpose**: Formatted text content for tooltips
**Lifecycle**: Generated on-demand from OutputFieldMetadata
**Location**: `TradingStrategy.StrategyEditor.IndicatorMetadata`

```elixir
# Type specification
@type tooltip_content :: String.t()

# Example structure (formatted string):
"""
SMA (Simple Moving Average)

Type: Single-value indicator
Reference directly as: sma_20

Unit: price
Description: Simple Moving Average - arithmetic mean of prices over a period

Example usage:
  sma_20 > close
"""

# For multi-value indicators:
"""
Bollinger Bands

Type: Multi-value indicator
Access fields with dot notation: bb_20.field_name

Available fields:
  • upper_band (price) - Upper Bollinger Band (SMA + multiplier × standard deviation)
  • middle_band (price) - Middle Bollinger Band (Simple Moving Average)
  • lower_band (price) - Lower Bollinger Band (SMA - multiplier × standard deviation)
  • percent_b (%) - %B indicator - price position relative to bands
  • bandwidth (%) - Bandwidth - distance between upper and lower bands

Example usage:
  close > bb_20.upper_band or close < bb_20.lower_band
"""
```

**Generation Rules**:
1. **Single-value indicators**:
   - Header: Indicator name and description
   - Type classification
   - Usage syntax (direct reference)
   - Unit if available
   - Example usage

2. **Multi-value indicators**:
   - Header: Indicator name and description
   - Type classification
   - Usage syntax (dot notation)
   - Bulleted list of fields with units and descriptions
   - Example usage

3. **Fallback** (metadata unavailable):
   ```
   Output information unavailable

   This indicator's metadata could not be retrieved.
   You can still add and configure this indicator normally.
   ```

**Validation Rules**:
- Must be non-empty string
- Must include usage example if available
- Must clearly distinguish single-value vs multi-value indicators

---

## Helper Modules

### IndicatorMetadata Module

**Purpose**: Encapsulate metadata fetching and formatting logic
**Location**: `lib/trading_strategy/strategy_editor/indicator_metadata.ex`

```elixir
defmodule TradingStrategy.StrategyEditor.IndicatorMetadata do
  @moduledoc """
  Helper module for fetching and formatting indicator output metadata.

  Uses lazy persistent_term caching for performance (0.0006ms retrieval).
  """

  alias TradingIndicators.Types.OutputFieldMetadata
  alias TradingStrategy.StrategyEditor.Registry

  @doc """
  Fetches formatted tooltip content for an indicator.

  ## Examples

      iex> format_help("sma")
      {:ok, "SMA (Simple Moving Average)\\n\\nType: Single-value..."}

      iex> format_help("bollinger_bands")
      {:ok, "Bollinger Bands\\n\\nType: Multi-value..."}

      iex> format_help("nonexistent")
      {:error, :indicator_not_found}
  """
  @spec format_help(String.t()) :: {:ok, String.t()} | {:error, atom()}
  def format_help(indicator_name)

  @doc """
  Fetches output field metadata for an indicator module.

  Uses persistent_term caching for performance.
  """
  @spec get_output_metadata(module()) :: {:ok, OutputFieldMetadata.t()} | {:error, atom()}
  def get_output_metadata(module)

  @doc """
  Formats OutputFieldMetadata into human-readable tooltip content.
  """
  @spec format_metadata(OutputFieldMetadata.t(), String.t()) :: String.t()
  defp format_metadata(metadata, indicator_name)
end
```

**State Management**:
- Uses `:persistent_term` for caching (read-only, global)
- Cache key format: `{:indicator_output_fields, module_name}`
- Lazy loading: Metadata fetched and cached on first access
- No cache invalidation needed (metadata is immutable at runtime)

**Error Handling**:
- Returns `{:error, :indicator_not_found}` if indicator doesn't exist in Registry
- Returns `{:error, :no_metadata_function}` if indicator module lacks `output_fields_metadata/0`
- Returns `{:error, :invalid_metadata}` if metadata structure is malformed
- All errors result in fallback content: "Output information unavailable"

---

## UI Components

### Tooltip Component

**Purpose**: Display indicator metadata in accessible tooltips
**Location**: `lib/trading_strategy_web/components/core_components.ex`

```elixir
@doc """
Renders a tooltip with keyboard accessibility.

## Examples

    <.tooltip id="bb-output-info" content={@indicator_help_text}>
      <button type="button" class="btn btn-circle btn-ghost btn-xs">
        <.icon name="hero-information-circle" class="size-4" />
      </button>
    </.tooltip>
"""
attr :id, :string, required: true
attr :content, :string, required: true
attr :position, :string, default: "top", values: ~w(top bottom left right)
slot :inner_block, required: true

def tooltip(assigns)
```

**Attributes**:
- `id` (required) - Unique identifier for tooltip instance
- `content` (required) - Formatted tooltip text (from `IndicatorMetadata.format_help/1`)
- `position` (optional) - Tooltip placement (top, bottom, left, right)
- `inner_block` (slot) - Trigger element (typically info icon button)

**ARIA Attributes** (rendered):
- `role="button"` on trigger
- `tabindex="0"` on trigger (keyboard focusable)
- `aria-describedby="tooltip-id"` (links trigger to content)
- `aria-expanded="false|true"` (tooltip visibility state)
- `role="tooltip"` on content div

**CSS Classes**:
- `tooltip-container` - Wrapper for positioning context
- `tooltip-trigger` - Focusable trigger element
- `tooltip-content` - Floating tooltip panel (daisyUI styled)

**JavaScript Hook**: `TooltipHook` (see JavaScript Hooks section below)

---

### TooltipHook (JavaScript)

**Purpose**: Handle tooltip interactions and keyboard navigation
**Location**: `assets/js/hooks/tooltip_hook.js`

```javascript
const TooltipHook = {
  mounted() {
    // Initialize tooltip state
    this.tooltipId = this.el.dataset.tooltipId
    this.trigger = this.el.querySelector(`#${this.tooltipId}-trigger`)
    this.content = this.el.querySelector(`#${this.tooltipId}-content`)
    this.isOpen = false

    // Register event listeners
    this.setupEventListeners()
  },

  destroyed() {
    // Cleanup event listeners
    this.teardownEventListeners()
  },

  // Event handlers
  onTriggerClick(event) { /* Toggle on click */ },
  onTriggerKeydown(event) { /* Toggle on Enter/Space */ },
  onTriggerMouseEnter() { /* Show after 300ms delay */ },
  onTriggerMouseLeave() { /* Hide tooltip */ },
  onEscape(event) { /* Hide on Escape key */ },
  onDocumentClick(event) { /* Hide when clicking outside */ },

  // State management
  show() { /* Display tooltip, position dynamically */ },
  hide() { /* Hide tooltip */ },
  toggle() { /* Toggle visibility */ },
  positionTooltip() { /* Calculate position based on trigger */ }
}
```

**State Management**:
- `isOpen` (boolean) - Current visibility state
- `hoverTimeout` (number) - Timer for debounced hover (300ms)

**Event Listeners**:
- `click` on trigger - Toggle tooltip
- `keydown` on trigger - Enter/Space to toggle
- `mouseenter` on trigger - Show after 300ms delay (WCAG 1.4.13)
- `mouseleave` on trigger - Hide tooltip
- `keydown` on document - Escape to dismiss
- `click` on document - Click outside to dismiss

**Performance**:
- Debounced hover (300ms) reduces unnecessary renders
- Position calculated only on show (not on every hover)
- Cleanup on destroyed prevents memory leaks

---

## Integration Points

### 1. IndicatorBuilder LiveComponent

**Location**: `lib/trading_strategy_web/live/strategy_live/indicator_builder.ex`
**Modifications**: Add tooltip with metadata display

```elixir
defmodule TradingStrategyWeb.StrategyLive.IndicatorBuilder do
  use TradingStrategyWeb, :live_component

  alias TradingStrategy.StrategyEditor.IndicatorMetadata

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> maybe_fetch_indicator_help()

    {:ok, socket}
  end

  defp maybe_fetch_indicator_help(%{assigns: %{selected_indicator: indicator}} = socket)
       when not is_nil(indicator) do
    case IndicatorMetadata.format_help(indicator) do
      {:ok, help_text} ->
        assign(socket, :indicator_help_text, help_text)

      {:error, _reason} ->
        assign(socket, :indicator_help_text, "Output information unavailable")
    end
  end

  defp maybe_fetch_indicator_help(socket), do: socket

  @impl true
  def render(assigns) do
    ~H"""
    <div class="indicator-builder">
      <!-- Existing form fields -->

      <div class="flex items-center gap-2">
        <label>Indicator Type</label>

        <%= if assigns[:indicator_help_text] do %>
          <.tooltip id="indicator-output-info" content={@indicator_help_text}>
            <button
              type="button"
              class="btn btn-circle btn-ghost btn-xs"
              aria-label="View output fields"
            >
              <.icon name="hero-information-circle" class="size-4" />
            </button>
          </.tooltip>
        <% end %>
      </div>
    </div>
    """
  end
end
```

**Data Flow**:
1. User selects indicator type from dropdown
2. LiveView update triggers `maybe_fetch_indicator_help/1`
3. `IndicatorMetadata.format_help/1` fetches and formats metadata
4. Formatted text assigned to `indicator_help_text`
5. Tooltip component renders with help text
6. User hovers/clicks info icon to view metadata

### 2. Configured Indicators List

**Location**: Same LiveComponent or parent LiveView
**Pattern**: Similar to above, but fetch metadata for already-configured indicators

```elixir
# In render function for configured indicators
~H"""
<div :for={indicator <- @configured_indicators} class="indicator-card">
  <span>{indicator.name} (period={indicator.period})</span>

  <.tooltip id={"configured-#{indicator.id}-info"} content={indicator.help_text}>
    <button type="button" class="btn btn-circle btn-ghost btn-xs">
      <.icon name="hero-information-circle" class="size-4" />
    </button>
  </.tooltip>
</div>
"""
```

---

## Validation Rules

### IndicatorMetadata.format_help/1

1. **Input Validation**:
   - `indicator_name` must be a non-empty string
   - Indicator must exist in `Registry.get_module/1`

2. **Metadata Validation**:
   - `type` must be `:single_value` or `:multi_value`
   - If multi_value, `fields` must be non-empty list
   - Each field must have `:name` and `:type` at minimum

3. **Output Validation**:
   - Returned string must be non-empty
   - Must include indicator name/description
   - Must include usage example if available

### Tooltip Component

1. **Attribute Validation**:
   - `id` must be unique across the page (prevents ARIA conflicts)
   - `content` must be non-empty string
   - `position` must be one of: `top`, `bottom`, `left`, `right`

2. **Accessibility Validation**:
   - Trigger must have `tabindex="0"` (keyboard focusable)
   - Trigger must have `aria-describedby` linking to content
   - Content must have `role="tooltip"`

---

## Performance Considerations

### Caching Strategy

**persistent_term Cache**:
- **Latency**: 0.0006ms retrieval (2000x faster than 200ms requirement)
- **Memory**: 4KB for all 20 indicators
- **Invalidation**: None needed (metadata immutable at runtime)
- **Consistency**: Matches existing Registry module pattern

**Cache Key Format**:
```elixir
{:indicator_output_fields, TradingIndicators.Trend.SMA}
```

### Tooltip Rendering

**Expected Performance**:
- Initial render: 20-30ms
- Tooltip show: 10-20ms (meets SC-007: <200ms)
- Memory per instance: ~2KB
- Bundle size increase: ~3KB (TooltipHook.js)

**Optimizations**:
- Lazy metadata fetching (only when indicator selected)
- Position calculation only on show (not on every hover)
- 300ms hover debounce reduces unnecessary renders
- CSS transitions (no JavaScript animation libraries)

---

## Error Handling

### Graceful Degradation

1. **Indicator Not Found**:
   - Error: `{:error, :indicator_not_found}`
   - Fallback: "Output information unavailable"
   - User can still add and configure the indicator

2. **Metadata Function Missing**:
   - Error: `{:error, :no_metadata_function}`
   - Fallback: "Output information unavailable"
   - Logged as warning for debugging

3. **Invalid Metadata Structure**:
   - Error: `{:error, :invalid_metadata}`
   - Fallback: "Output information unavailable"
   - Logged as error (indicates library bug)

4. **JavaScript Hook Failure**:
   - Tooltip falls back to CSS-only hover behavior
   - Keyboard accessibility degraded but not broken
   - User can still access content by hovering

### Logging

```elixir
# In IndicatorMetadata module
Logger.warning("No metadata function for indicator #{inspect(module)}")
Logger.error("Invalid metadata structure for #{inspect(module)}: #{inspect(metadata)}")
```

---

## Testing Strategy

### Unit Tests

**IndicatorMetadata Module**:
- Test `format_help/1` for single-value indicators (SMA, RSI)
- Test `format_help/1` for multi-value indicators (Bollinger Bands, MACD)
- Test error handling (invalid indicator, missing metadata)
- Test caching behavior (cache hit, cache miss)
- Test fallback content generation

**Tooltip Component**:
- Test component rendering with required attributes
- Test ARIA attributes presence and correctness
- Test slot rendering (inner_block)

### Integration Tests (Wallaby)

**Keyboard Navigation**:
```elixir
test "tooltip displays on Enter key and dismisses on Escape", %{session: session} do
  session
  |> visit("/strategies/#{strategy.id}/edit")
  |> assert_has(Query.css("#indicator-output-info-trigger"))
  |> send_keys([:tab])    # Focus trigger
  |> send_keys([:enter])  # Show tooltip
  |> assert_has(Query.css("#indicator-output-info-content:not(.hidden)"))
  |> send_keys([:escape]) # Hide tooltip
  |> refute_has(Query.css("#indicator-output-info-content:not(.hidden)"))
end
```

**Mouse Interaction**:
```elixir
test "tooltip displays on hover and hides on mouse leave", %{session: session} do
  session
  |> visit("/strategies/#{strategy.id}/edit")
  |> hover_on(Query.css("#indicator-output-info-trigger"))
  |> assert_has(Query.css("#indicator-output-info-content:not(.hidden)"))
  |> move_to_element(Query.css("body"))
  |> refute_has(Query.css("#indicator-output-info-content:not(.hidden)"))
end
```

### Performance Tests

**Metadata Retrieval Latency**:
```elixir
test "metadata retrieval meets <200ms target" do
  indicators = ["sma", "rsi", "bollinger_bands", "macd"]

  for indicator <- indicators do
    {time_us, {:ok, _content}} =
      :timer.tc(fn -> IndicatorMetadata.format_help(indicator) end)

    time_ms = time_us / 1000
    assert time_ms < 200, "Expected <200ms, got #{time_ms}ms for #{indicator}"
  end
end
```

**Caching Performance**:
```elixir
test "subsequent calls use cache (sub-millisecond)" do
  # First call - cache miss
  {time1_us, {:ok, _}} = :timer.tc(fn -> IndicatorMetadata.format_help("sma") end)

  # Second call - cache hit
  {time2_us, {:ok, _}} = :timer.tc(fn -> IndicatorMetadata.format_help("sma") end)

  time2_ms = time2_us / 1000
  assert time2_ms < 1.0, "Expected <1ms cache hit, got #{time2_ms}ms"
  assert time2_us < time1_us, "Cache hit should be faster than cache miss"
end
```

---

## Summary

This data model defines:

1. **External Entities**: OutputFieldMetadata and FieldInfo (from TradingIndicators library)
2. **Internal Entities**: TooltipContent (generated strings), IndicatorMetadata module (helper)
3. **UI Components**: Tooltip component and TooltipHook JavaScript hook
4. **Integration Points**: IndicatorBuilder LiveComponent, configured indicators list
5. **Validation Rules**: Input, metadata, and output validation at all layers
6. **Performance Strategy**: Lazy persistent_term caching, debounced interactions
7. **Error Handling**: Graceful degradation with fallback content
8. **Testing Approach**: Unit, integration, and performance tests

All entities and components are designed to meet the feature requirements (FR-001 through FR-011) and success criteria (SC-001 through SC-007).
