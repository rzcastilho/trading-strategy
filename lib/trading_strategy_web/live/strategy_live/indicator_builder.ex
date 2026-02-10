defmodule TradingStrategyWeb.StrategyLive.IndicatorBuilder do
  @moduledoc """
  LiveComponent for building and managing trading strategy indicators.

  This component provides an interactive UI for:
  - Adding/removing indicators
  - Configuring indicator parameters
  - Validating indicator configurations
  - Displaying indicator list with state

  ## Socket Assigns

    * `:selected_indicators` - List of currently configured indicators
    * `:available_indicators` - Map of available indicator types with their parameters

  ## Events Sent to Parent

    * `{:indicators_changed, indicators}` - When indicators are added, removed, or modified
  """

  use TradingStrategyWeb, :live_component

  alias Phoenix.LiveView.JS

  @available_indicators %{
    "sma" => %{
      name: "Simple Moving Average (SMA)",
      params: [
        %{key: "period", type: "number", label: "Period", default: 20, min: 1, max: 500}
      ]
    },
    "ema" => %{
      name: "Exponential Moving Average (EMA)",
      params: [
        %{key: "period", type: "number", label: "Period", default: 20, min: 1, max: 500}
      ]
    },
    "rsi" => %{
      name: "Relative Strength Index (RSI)",
      params: [
        %{key: "period", type: "number", label: "Period", default: 14, min: 2, max: 100}
      ]
    },
    "macd" => %{
      name: "MACD",
      params: [
        %{key: "fast_period", type: "number", label: "Fast Period", default: 12, min: 1, max: 100},
        %{key: "slow_period", type: "number", label: "Slow Period", default: 26, min: 1, max: 100},
        %{key: "signal_period", type: "number", label: "Signal Period", default: 9, min: 1, max: 100}
      ]
    },
    "bollinger_bands" => %{
      name: "Bollinger Bands",
      params: [
        %{key: "period", type: "number", label: "Period", default: 20, min: 1, max: 100},
        %{key: "std_dev", type: "number", label: "Standard Deviations", default: 2.0, min: 0.5, max: 5.0, step: 0.1}
      ]
    },
    "stochastic" => %{
      name: "Stochastic Oscillator",
      params: [
        %{key: "k_period", type: "number", label: "%K Period", default: 14, min: 1, max: 100},
        %{key: "d_period", type: "number", label: "%D Period", default: 3, min: 1, max: 100}
      ]
    },
    "atr" => %{
      name: "Average True Range (ATR)",
      params: [
        %{key: "period", type: "number", label: "Period", default: 14, min: 1, max: 100}
      ]
    },
    "volume_sma" => %{
      name: "Volume SMA",
      params: [
        %{key: "period", type: "number", label: "Period", default: 20, min: 1, max: 100}
      ]
    }
  }

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:selected_indicators, [])
     |> assign(:available_indicators, @available_indicators)
     |> assign(:new_indicator_type, nil)
     |> assign(:new_indicator_params, %{})
     |> assign(:show_add_form, false)}
  end

  @impl true
  def update(%{indicators: indicators} = assigns, socket) when is_list(indicators) do
    # Update from parent with existing indicators
    {:ok,
     socket
     |> assign(assigns)
     |> assign(:selected_indicators, normalize_indicators(indicators))}
  end

  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} class="space-y-4">
      <div class="flex items-center justify-between">
        <h3 class="text-lg font-medium text-gray-900">Technical Indicators</h3>
        <button
          type="button"
          phx-click="toggle_add_form"
          phx-target={@myself}
          class="btn-sm btn-primary"
        >
          <span class="text-lg">+</span> Add Indicator
        </button>
      </div>

      <!-- Add Indicator Form -->
      <%= if @show_add_form do %>
        <div class="bg-gray-50 border border-gray-200 rounded-lg p-4 space-y-3">
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-2">
              Select Indicator Type
            </label>
            <select
              name="indicator_type"
              phx-change="select_indicator_type"
              phx-target={@myself}
              class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
            >
              <option value="">-- Choose an indicator --</option>
              <%= for {type, %{name: name}} <- Enum.sort_by(@available_indicators, fn {_k, v} -> v.name end) do %>
                <option value={type} selected={@new_indicator_type == type}>
                  <%= name %>
                </option>
              <% end %>
            </select>
          </div>

          <%= if @new_indicator_type && @available_indicators[@new_indicator_type] do %>
            <div class="space-y-3 border-t border-gray-200 pt-3">
              <h4 class="text-sm font-medium text-gray-700">
                Configure <%= @available_indicators[@new_indicator_type].name %>
              </h4>

              <div id={"#{@id}-add-form"}>
                <%= for param <- @available_indicators[@new_indicator_type].params do %>
                  <div>
                    <label class="block text-sm font-medium text-gray-700 mb-1">
                      <%= param.label %>
                    </label>
                    <input
                      type={param.type}
                      name={"indicator_param_#{param.key}"}
                      phx-change="update_param"
                      phx-value-key={param.key}
                      phx-target={@myself}
                      value={Map.get(@new_indicator_params, param.key, param.default)}
                      min={param[:min]}
                      max={param[:max]}
                      step={param[:step] || 1}
                      class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
                      required
                    />
                  </div>
                <% end %>

                <div class="flex gap-2 mt-4">
                  <button
                    type="button"
                    phx-click="add_indicator"
                    phx-target={@myself}
                    class="btn-sm btn-primary"
                  >
                    Add Indicator
                  </button>
                  <button
                    type="button"
                    phx-click="cancel_add"
                    phx-target={@myself}
                    class="btn-sm btn-secondary"
                  >
                    Cancel
                  </button>
                </div>
              </div>
            </div>
          <% end %>
        </div>
      <% end %>

      <!-- Selected Indicators List -->
      <%= if Enum.empty?(@selected_indicators) do %>
        <div class="text-center py-8 border-2 border-dashed border-gray-300 rounded-lg">
          <p class="text-gray-500 text-sm">No indicators configured yet.</p>
          <p class="text-gray-400 text-xs mt-1">Add indicators to build your strategy.</p>
        </div>
      <% else %>
        <div class="space-y-2">
          <%= for {indicator, index} <- Enum.with_index(@selected_indicators) do %>
            <div class="bg-white border border-gray-200 rounded-lg p-3 flex items-start justify-between hover:border-blue-300 transition-colors">
              <div class="flex-1">
                <div class="flex items-center gap-2">
                  <span class="text-xs font-mono text-gray-400">#<%= index + 1 %></span>
                  <h4 class="font-medium text-gray-900">
                    <%= get_indicator_name(indicator.type, @available_indicators) %>
                  </h4>
                  <span class={[
                    "px-2 py-0.5 text-xs rounded-full",
                    if(indicator.valid?, do: "bg-green-100 text-green-800", else: "bg-red-100 text-red-800")
                  ]}>
                    <%= if indicator.valid?, do: "Valid", else: "Invalid" %>
                  </span>
                </div>
                <div class="mt-1 text-sm text-gray-600">
                  <span class="font-mono text-xs bg-gray-100 px-2 py-0.5 rounded">
                    <%= format_indicator_params(indicator.params) %>
                  </span>
                </div>
              </div>
              <button
                type="button"
                phx-click="remove_indicator"
                phx-value-index={index}
                phx-target={@myself}
                class="text-red-600 hover:text-red-800 p-1"
                title="Remove indicator"
              >
                <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M6 18L18 6M6 6l12 12"
                  />
                </svg>
              </button>
            </div>
          <% end %>
        </div>

        <div class="text-xs text-gray-500 mt-2">
          Total indicators: <%= length(@selected_indicators) %>
        </div>
      <% end %>
    </div>
    """
  end

  @impl true
  def handle_event("toggle_add_form", _params, socket) do
    {:noreply, assign(socket, :show_add_form, !socket.assigns.show_add_form)}
  end

  @impl true
  def handle_event("select_indicator_type", %{"indicator_type" => type}, socket) do
    # Initialize params with default values when type is selected
    default_params =
      if type != "" && socket.assigns.available_indicators[type] do
        socket.assigns.available_indicators[type].params
        |> Enum.into(%{}, fn param -> {param.key, param.default} end)
      else
        %{}
      end

    {:noreply,
     socket
     |> assign(:new_indicator_type, type)
     |> assign(:new_indicator_params, default_params)}
  end

  @impl true
  def handle_event("update_param", %{"key" => key, "value" => value}, socket) do
    # Update parameter value in socket assigns
    updated_params = Map.put(socket.assigns.new_indicator_params, key, parse_param_value(value))
    {:noreply, assign(socket, :new_indicator_params, updated_params)}
  end

  @impl true
  def handle_event("add_indicator", _params, socket) do
    type = socket.assigns.new_indicator_type
    params = socket.assigns.new_indicator_params

    # Create new indicator
    new_indicator = %{
      id: generate_indicator_id(),
      type: type,
      params: params,
      valid?: validate_indicator(type, params, socket.assigns.available_indicators)
    }

    # Add to selected indicators
    updated_indicators = socket.assigns.selected_indicators ++ [new_indicator]

    # Notify parent
    send(self(), {:indicators_changed, updated_indicators})

    {:noreply,
     socket
     |> assign(:selected_indicators, updated_indicators)
     |> assign(:show_add_form, false)
     |> assign(:new_indicator_type, nil)
     |> assign(:new_indicator_params, %{})}
  end

  @impl true
  def handle_event("cancel_add", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_add_form, false)
     |> assign(:new_indicator_type, nil)
     |> assign(:new_indicator_params, %{})}
  end

  @impl true
  def handle_event("remove_indicator", %{"index" => index_str}, socket) do
    index = String.to_integer(index_str)

    updated_indicators =
      socket.assigns.selected_indicators
      |> List.delete_at(index)

    # Notify parent
    send(self(), {:indicators_changed, updated_indicators})

    {:noreply, assign(socket, :selected_indicators, updated_indicators)}
  end

  # Private helpers

  defp normalize_indicators(indicators) when is_list(indicators) do
    Enum.map(indicators, fn indicator ->
      %{
        id: indicator[:id] || generate_indicator_id(),
        type: indicator[:type] || indicator["type"],
        params: indicator[:params] || indicator["params"] || %{},
        valid?: indicator[:valid?] || true
      }
    end)
  end

  defp generate_indicator_id do
    "indicator_#{System.unique_integer([:positive, :monotonic])}"
  end

  defp parse_param_value(value) when is_binary(value) do
    case Float.parse(value) do
      {float, ""} -> float
      _ ->
        case Integer.parse(value) do
          {int, ""} -> int
          _ -> value
        end
    end
  end

  defp parse_param_value(value), do: value

  defp validate_indicator(type, params, available_indicators) do
    case available_indicators[type] do
      nil ->
        false

      %{params: required_params} ->
        # Check all required params are present and within bounds
        Enum.all?(required_params, fn param_def ->
          value = params[param_def.key]

          value != nil &&
            is_number(value) &&
            (is_nil(param_def[:min]) || value >= param_def[:min]) &&
            (is_nil(param_def[:max]) || value <= param_def[:max])
        end)
    end
  end

  defp get_indicator_name(type, available_indicators) do
    case available_indicators[type] do
      %{name: name} -> name
      _ -> String.upcase(type)
    end
  end

  defp format_indicator_params(params) when is_map(params) do
    params
    |> Enum.map(fn {k, v} -> "#{k}: #{v}" end)
    |> Enum.join(", ")
  end

  defp format_indicator_params(_), do: ""
end
