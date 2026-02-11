# Quickstart Guide: Indicator Output Values Display

**Feature**: 006-indicator-value-inspection
**Date**: 2026-02-11
**Audience**: Developers integrating indicator metadata tooltips

## Overview

This guide shows you how to display indicator output value metadata using the new tooltip component and `IndicatorMetadata` helper module.

---

## Quick Example

**Goal**: Add an info icon that shows Bollinger Bands output fields when clicked/hovered.

```elixir
defmodule TradingStrategyWeb.StrategyLive.IndicatorBuilder do
  use TradingStrategyWeb, :live_component

  alias TradingStrategy.StrategyEditor.IndicatorMetadata

  @impl true
  def update(%{selected_indicator: indicator} = assigns, socket) do
    help_text = case IndicatorMetadata.format_help(indicator) do
      {:ok, text} -> text
      {:error, _} -> "Output information unavailable"
    end

    socket =
      socket
      |> assign(assigns)
      |> assign(:indicator_help_text, help_text)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="form-field">
      <label>Bollinger Bands</label>

      <.tooltip id="bb-output-info" content={@indicator_help_text}>
        <button type="button" class="btn btn-circle btn-ghost btn-xs">
          <.icon name="hero-information-circle" class="size-4" />
        </button>
      </.tooltip>
    </div>
    """
  end
end
```

**Result**: User can hover/click the info icon to see:
```
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
```

---

## 1. Fetch Indicator Metadata

### IndicatorMetadata.format_help/1

**Purpose**: Get formatted tooltip content for an indicator.

**Signature**:
```elixir
@spec format_help(String.t()) :: {:ok, String.t()} | {:error, atom()}
```

**Usage**:
```elixir
alias TradingStrategy.StrategyEditor.IndicatorMetadata

# Single-value indicator
{:ok, help} = IndicatorMetadata.format_help("sma")
# Returns formatted text: "SMA (Simple Moving Average)..."

# Multi-value indicator
{:ok, help} = IndicatorMetadata.format_help("bollinger_bands")
# Returns formatted text with all 5 fields

# Error handling
case IndicatorMetadata.format_help("unknown_indicator") do
  {:ok, text} -> text
  {:error, _reason} -> "Output information unavailable"
end
```

**Caching**: Uses `persistent_term` for sub-millisecond retrieval (0.0006ms). First call fetches and caches, subsequent calls return cached value.

**Error Cases**:
- `{:error, :indicator_not_found}` - Indicator doesn't exist in Registry
- `{:error, :no_metadata_function}` - Indicator module lacks `output_fields_metadata/0`
- `{:error, :invalid_metadata}` - Metadata structure is malformed

---

## 2. Display Metadata in Tooltips

### Tooltip Component

**Purpose**: Accessible tooltip with keyboard navigation support.

**Signature**:
```elixir
<.tooltip id={string} content={string} position={:top | :bottom | :left | :right}>
  <!-- Trigger element (button, icon, etc.) -->
</.tooltip>
```

**Attributes**:
- `id` (required) - Unique identifier for this tooltip instance
- `content` (required) - Text to display (from `IndicatorMetadata.format_help/1`)
- `position` (optional, default: "top") - Tooltip placement
- `inner_block` (slot) - Element that triggers the tooltip

**Example**:
```elixir
~H"""
<.tooltip id="rsi-help" content={@rsi_help_text}>
  <button type="button" class="btn btn-circle btn-ghost btn-xs" aria-label="View RSI output values">
    <.icon name="hero-information-circle" class="size-4" />
  </button>
</.tooltip>
"""
```

**Keyboard Accessibility**:
- **Tab**: Focus the trigger (tooltip stays hidden)
- **Enter/Space**: Show/hide tooltip
- **Escape**: Dismiss tooltip and keep focus on trigger
- **Click outside**: Dismiss tooltip

**Mouse Interaction**:
- **Hover**: Show tooltip after 300ms delay
- **Leave**: Hide tooltip
- **Click**: Toggle tooltip visibility

---

## 3. Integration Patterns

### Pattern 1: Add Indicator Form

**Use Case**: Show metadata when user selects an indicator type from dropdown.

```elixir
defmodule TradingStrategyWeb.StrategyLive.IndicatorBuilder do
  use TradingStrategyWeb, :live_component

  alias TradingStrategy.StrategyEditor.IndicatorMetadata

  @impl true
  def handle_event("indicator_type_changed", %{"type" => indicator_type}, socket) do
    help_text = fetch_help_text(indicator_type)

    socket =
      socket
      |> assign(:selected_indicator, indicator_type)
      |> assign(:indicator_help_text, help_text)

    {:noreply, socket}
  end

  defp fetch_help_text(indicator_type) do
    case IndicatorMetadata.format_help(indicator_type) do
      {:ok, text} -> text
      {:error, _} -> "Output information unavailable"
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <form phx-change="indicator_type_changed">
      <div class="flex items-center gap-2">
        <select name="type">
          <option value="sma">SMA</option>
          <option value="bollinger_bands">Bollinger Bands</option>
          <!-- ... -->
        </select>

        <%= if assigns[:indicator_help_text] do %>
          <.tooltip id="indicator-output-info" content={@indicator_help_text} position="right">
            <button type="button" class="btn btn-circle btn-ghost btn-xs">
              <.icon name="hero-information-circle" class="size-4" />
            </button>
          </.tooltip>
        <% end %>
      </div>
    </form>
    """
  end
end
```

---

### Pattern 2: Configured Indicators List

**Use Case**: Show metadata for already-configured indicators in the strategy.

```elixir
defmodule TradingStrategyWeb.StrategyLive.Index do
  use TradingStrategyWeb, :live_view

  alias TradingStrategy.StrategyEditor.IndicatorMetadata

  @impl true
  def mount(_params, _session, socket) do
    indicators = load_configured_indicators()

    # Fetch help text for all indicators upfront
    indicators_with_help = Enum.map(indicators, fn indicator ->
      help_text = case IndicatorMetadata.format_help(indicator.type) do
        {:ok, text} -> text
        {:error, _} -> "Output information unavailable"
      end

      Map.put(indicator, :help_text, help_text)
    end)

    {:ok, assign(socket, :indicators, indicators_with_help)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="indicators-list">
      <div :for={indicator <- @indicators} class="indicator-card">
        <div class="flex items-center justify-between">
          <span>{indicator.name} (period={indicator.period})</span>

          <.tooltip
            id={"indicator-#{indicator.id}-info"}
            content={indicator.help_text}
            position="left"
          >
            <button type="button" class="btn btn-circle btn-ghost btn-xs">
              <.icon name="hero-information-circle" class="size-4" />
            </button>
          </.tooltip>
        </div>
      </div>
    </div>
    """
  end
end
```

---

### Pattern 3: Conditional Display

**Use Case**: Only show tooltip if metadata is available.

```elixir
~H"""
<div class="indicator-name">
  {indicator.name}

  <%= if help_text_available?(@indicator) do %>
    <.tooltip id={"#{@indicator.id}-help"} content={@indicator.help_text}>
      <button type="button" class="btn btn-circle btn-ghost btn-xs">
        <.icon name="hero-information-circle" class="size-4" />
      </button>
    </.tooltip>
  <% end %>
</div>
"""

# Helper function
defp help_text_available?(indicator) do
  case IndicatorMetadata.format_help(indicator.type) do
    {:ok, _text} -> true
    {:error, _} -> false
  end
end
```

---

## 4. Tooltip Positioning

### Position Options

```elixir
# Top (default)
<.tooltip id="tip-1" content="Help text" position="top">
  <button>Info</button>
</.tooltip>

# Bottom
<.tooltip id="tip-2" content="Help text" position="bottom">
  <button>Info</button>
</.tooltip>

# Left
<.tooltip id="tip-3" content="Help text" position="left">
  <button>Info</button>
</.tooltip>

# Right
<.tooltip id="tip-4" content="Help text" position="right">
  <button>Info</button>
</.tooltip>
```

**Smart Positioning**: The `TooltipHook` JavaScript automatically calculates position to ensure tooltip stays within viewport. The `position` attribute is a preference, not a guarantee.

---

## 5. Styling

### Default Styling

Tooltips use daisyUI + Tailwind CSS classes:

```html
<div class="tooltip-content bg-base-300 text-base-content rounded-lg px-3 py-2 text-sm max-w-xs shadow-lg">
  <!-- Content here -->
</div>
```

### Custom Styling

You can customize the tooltip appearance by modifying `core_components.ex`:

```elixir
def tooltip(assigns) do
  ~H"""
  <!-- ... -->
  <div
    id={"#{@id}-content"}
    role="tooltip"
    class={[
      "tooltip-content hidden absolute z-50",
      "bg-base-300 text-base-content",  # Change these for custom colors
      "rounded-lg px-3 py-2",
      "text-sm max-w-xs",
      "shadow-lg"
    ]}
  >
    {@content}
  </div>
  """
end
```

**daisyUI Themes**: Tooltips automatically adapt to daisyUI theme changes (light/dark mode).

---

## 6. Performance Tips

### Tip 1: Fetch Once, Use Many Times

**Bad** (fetches on every render):
```elixir
~H"""
<.tooltip id="sma-help" content={fetch_help("sma")}>
  <button>Info</button>
</.tooltip>
"""
```

**Good** (fetch in mount/update, assign to socket):
```elixir
def update(assigns, socket) do
  {:ok, help_text} = IndicatorMetadata.format_help("sma")
  {:ok, assign(socket, :sma_help, help_text)}
end

~H"""
<.tooltip id="sma-help" content={@sma_help}>
  <button>Info</button>
</.tooltip>
"""
```

### Tip 2: Lazy Loading

**Use Case**: Many indicators, but user only views a few.

```elixir
@impl true
def handle_event("expand_indicator", %{"id" => id}, socket) do
  indicator = Enum.find(socket.assigns.indicators, &(&1.id == id))

  help_text = case IndicatorMetadata.format_help(indicator.type) do
    {:ok, text} -> text
    {:error, _} -> "Output information unavailable"
  end

  updated_indicators = Enum.map(socket.assigns.indicators, fn ind ->
    if ind.id == id, do: Map.put(ind, :help_text, help_text), else: ind
  end)

  {:noreply, assign(socket, :indicators, updated_indicators)}
end
```

### Tip 3: Batch Fetching

**Use Case**: Load all indicator help texts at once.

```elixir
def mount(_params, _session, socket) do
  indicator_types = ["sma", "rsi", "bollinger_bands", "macd"]

  help_texts = Enum.reduce(indicator_types, %{}, fn type, acc ->
    case IndicatorMetadata.format_help(type) do
      {:ok, text} -> Map.put(acc, type, text)
      {:error, _} -> Map.put(acc, type, "Output information unavailable")
    end
  end)

  {:ok, assign(socket, :help_texts, help_texts)}
end

# In render:
~H"""
<.tooltip id="sma-help" content={@help_texts["sma"]}>
  <button>SMA Info</button>
</.tooltip>
"""
```

---

## 7. Testing

### Unit Test: IndicatorMetadata

```elixir
defmodule TradingStrategy.StrategyEditor.IndicatorMetadataTest do
  use ExUnit.Case, async: true

  alias TradingStrategy.StrategyEditor.IndicatorMetadata

  describe "format_help/1" do
    test "formats single-value indicator (SMA)" do
      assert {:ok, help} = IndicatorMetadata.format_help("sma")
      assert help =~ "SMA"
      assert help =~ "Single-value"
      assert help =~ "sma_20"
    end

    test "formats multi-value indicator (Bollinger Bands)" do
      assert {:ok, help} = IndicatorMetadata.format_help("bollinger_bands")
      assert help =~ "Bollinger Bands"
      assert help =~ "Multi-value"
      assert help =~ "upper_band"
      assert help =~ "middle_band"
      assert help =~ "lower_band"
    end

    test "returns error for unknown indicator" do
      assert {:error, :indicator_not_found} = IndicatorMetadata.format_help("unknown")
    end
  end
end
```

### Integration Test: Tooltip Component

```elixir
defmodule TradingStrategyWeb.StrategyLive.IndicatorBuilderTest do
  use TradingStrategyWeb.ConnCase
  use Wallaby.Feature

  import Wallaby.Query

  @moduletag :integration

  feature "displays indicator metadata in tooltip", %{session: session} do
    session
    |> visit("/strategies/#{strategy.id}/edit")
    |> click(Query.css("#indicator-output-info-trigger"))
    |> assert_has(Query.css("#indicator-output-info-content:not(.hidden)"))
    |> assert_text("Bollinger Bands")
    |> assert_text("upper_band")
  end

  feature "tooltip responds to keyboard navigation", %{session: session} do
    session
    |> visit("/strategies/#{strategy.id}/edit")
    |> send_keys([:tab])    # Focus trigger
    |> send_keys([:enter])  # Show tooltip
    |> assert_has(Query.css("#indicator-output-info-content:not(.hidden)"))
    |> send_keys([:escape]) # Hide tooltip
    |> refute_has(Query.css("#indicator-output-info-content:not(.hidden)"))
  end
end
```

---

## 8. Troubleshooting

### Problem: Tooltip doesn't show

**Possible Causes**:
1. `TooltipHook` not registered in `assets/js/app.js`
2. Missing `phx-hook="TooltipHook"` attribute
3. Invalid `id` attribute (duplicate IDs on page)

**Solution**:
```javascript
// In assets/js/app.js
import TooltipHook from "./hooks/tooltip_hook.js"

let Hooks = {}
Hooks.TooltipHook = TooltipHook  // Make sure this is present

let liveSocket = new LiveSocket("/live", Socket, {
  hooks: Hooks,
  // ...
})
```

### Problem: Keyboard navigation doesn't work

**Possible Causes**:
1. Trigger element missing `tabindex="0"`
2. ARIA attributes not set correctly
3. JavaScript hook event listeners not attached

**Solution**: Verify component renders correct HTML:
```html
<div id="tooltip-trigger" tabindex="0" role="button" aria-describedby="tooltip-content" aria-expanded="false">
  <!-- Trigger content -->
</div>
```

### Problem: Content shows "Output information unavailable"

**Possible Causes**:
1. Indicator name mismatch (e.g., "BollingerBands" vs "bollinger_bands")
2. Indicator not in Registry
3. Indicator module missing `output_fields_metadata/0` function

**Solution**: Check indicator name in Registry:
```elixir
iex> TradingStrategy.StrategyEditor.Registry.get_module("bollinger_bands")
{:ok, TradingIndicators.Volatility.BollingerBands}

iex> TradingIndicators.Volatility.BollingerBands.output_fields_metadata()
%TradingIndicators.Types.OutputFieldMetadata{...}
```

### Problem: Tooltip position is wrong

**Possible Causes**:
1. Viewport boundary collision
2. Incorrect `position` attribute
3. Parent container has `overflow: hidden`

**Solution**: The `TooltipHook` calculates position dynamically. Try changing `position` attribute:
```elixir
# If tooltip is cut off at top, try bottom:
<.tooltip id="tip" content="text" position="bottom">
```

---

## 9. Advanced Usage

### Custom Tooltip Content

**Use Case**: Add custom formatting beyond indicator metadata.

```elixir
defp format_custom_help(indicator) do
  case IndicatorMetadata.format_help(indicator.type) do
    {:ok, base_help} ->
      """
      #{base_help}

      ---
      Configuration:
        Period: #{indicator.period}
        Source: #{indicator.source}
      """

    {:error, _} ->
      "Output information unavailable"
  end
end
```

### Multiple Tooltips per Indicator

**Use Case**: Separate tooltips for parameters vs output values.

```elixir
~H"""
<div class="indicator-config">
  <span>Bollinger Bands</span>

  <!-- Parameters tooltip -->
  <.tooltip id="bb-params" content={@bb_param_help}>
    <button type="button" class="btn btn-xs">
      <.icon name="hero-cog" class="size-4" />
    </button>
  </.tooltip>

  <!-- Output values tooltip -->
  <.tooltip id="bb-output" content={@bb_output_help}>
    <button type="button" class="btn btn-xs">
      <.icon name="hero-information-circle" class="size-4" />
    </button>
  </.tooltip>
</div>
"""
```

---

## 10. Summary

**Key Takeaways**:
1. Use `IndicatorMetadata.format_help/1` to fetch formatted tooltip content
2. Use `<.tooltip>` component with unique `id` for each tooltip
3. Fetch metadata in `mount/update`, assign to socket (don't fetch in render)
4. Tooltips are keyboard accessible (Tab, Enter, Escape)
5. Performance is excellent (<1ms) due to persistent_term caching

**Common Pattern**:
```elixir
# In LiveComponent
def update(%{indicator: indicator} = assigns, socket) do
  help_text = case IndicatorMetadata.format_help(indicator.type) do
    {:ok, text} -> text
    {:error, _} -> "Output information unavailable"
  end

  {:ok, assign(socket, :help_text, help_text)}
end

# In template
~H"""
<.tooltip id="indicator-help" content={@help_text}>
  <button type="button" class="btn btn-circle btn-ghost btn-xs">
    <.icon name="hero-information-circle" class="size-4" />
  </button>
</.tooltip>
"""
```

**Next Steps**:
- Read `data-model.md` for detailed entity structures
- See `plan.md` for full implementation phases
- Run tests with `mix test test/trading_strategy/strategy_editor/indicator_metadata_test.exs`

---

For questions or issues, refer to the research findings in `specs/006-indicator-value-inspection/research.md`.
