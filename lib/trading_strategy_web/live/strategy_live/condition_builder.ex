defmodule TradingStrategyWeb.StrategyLive.ConditionBuilder do
  @moduledoc """
  LiveComponent for building and managing entry/exit conditions for trading strategies.

  This component provides an interactive UI for:
  - Adding/removing conditions
  - Configuring condition logic (comparisons, operators)
  - Building complex multi-condition rules
  - Validating condition syntax

  ## Socket Assigns

    * `:conditions` - List of currently configured conditions
    * `:condition_type` - Type of conditions: "entry" or "exit"
    * `:available_operators` - Map of available comparison operators
    * `:available_indicators` - List of available indicators from parent

  ## Events Sent to Parent

    * `{:conditions_changed, type, conditions}` - When conditions are added, removed, or modified
      where `type` is either "entry" or "exit"
  """

  use TradingStrategyWeb, :live_component

  @operators %{
    "gt" => %{symbol: ">", label: "Greater than"},
    "lt" => %{symbol: "<", label: "Less than"},
    "gte" => %{symbol: ">=", label: "Greater than or equal to"},
    "lte" => %{symbol: "<=", label: "Less than or equal to"},
    "eq" => %{symbol: "==", label: "Equal to"},
    "neq" => %{symbol: "!=", label: "Not equal to"},
    "crosses_above" => %{symbol: "⤴", label: "Crosses above"},
    "crosses_below" => %{symbol: "⤵", label: "Crosses below"}
  }

  @logical_operators %{
    "and" => "AND",
    "or" => "OR"
  }

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:conditions, [])
     |> assign(:available_operators, @operators)
     |> assign(:logical_operators, @logical_operators)
     |> assign(:show_add_form, false)
     |> assign(:new_condition, %{})}
  end

  @impl true
  def update(%{conditions: conditions, condition_type: type} = assigns, socket)
      when is_list(conditions) do
    # Update from parent with existing conditions
    {:ok,
     socket
     |> assign(assigns)
     |> assign(:conditions, normalize_conditions(conditions))
     |> assign(:condition_type, type)}
  end

  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} class="space-y-4">
      <div class="flex items-center justify-between">
        <div>
          <h3 class="text-lg font-medium text-gray-900">
            <%= String.capitalize(@condition_type) %> Conditions
          </h3>
          <p class="text-xs text-gray-500 mt-1">
            Define when to <%= @condition_type %> a position
          </p>
        </div>
        <button
          type="button"
          phx-click="toggle_add_form"
          phx-target={@myself}
          class="btn-sm btn-primary"
        >
          <span class="text-lg">+</span> Add Condition
        </button>
      </div>

      <!-- Add Condition Form -->
      <%= if @show_add_form do %>
        <div class="bg-gray-50 border border-gray-200 rounded-lg p-4 space-y-3">
          <h4 class="text-sm font-medium text-gray-700">
            New <%= String.capitalize(@condition_type) %> Condition
          </h4>

          <.form
            :let={f}
            for={%{}}
            as={:condition}
            phx-submit="add_condition"
            phx-target={@myself}
            id={"#{@id}-add-form"}
          >
            <div class="grid grid-cols-3 gap-3">
              <!-- Left Side (Indicator or Value) -->
              <div>
                <label class="block text-sm font-medium text-gray-700 mb-1">
                  Left Side
                </label>
                <input
                  type="text"
                  name="condition[left]"
                  placeholder="e.g., rsi, price, close"
                  class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
                  required
                />
                <p class="text-xs text-gray-500 mt-1">
                  Indicator name or value
                </p>
              </div>

              <!-- Operator -->
              <div>
                <label class="block text-sm font-medium text-gray-700 mb-1">
                  Operator
                </label>
                <select
                  name="condition[operator]"
                  class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
                  required
                >
                  <%= for {op, %{symbol: symbol, label: label}} <- Enum.sort_by(@available_operators, fn {_k, v} -> v.label end) do %>
                    <option value={op}><%= symbol %> <%= label %></option>
                  <% end %>
                </select>
              </div>

              <!-- Right Side (Indicator or Value) -->
              <div>
                <label class="block text-sm font-medium text-gray-700 mb-1">
                  Right Side
                </label>
                <input
                  type="text"
                  name="condition[right]"
                  placeholder="e.g., 70, sma_20"
                  class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
                  required
                />
                <p class="text-xs text-gray-500 mt-1">
                  Number or indicator
                </p>
              </div>
            </div>

            <!-- Logical Connector (for multiple conditions) -->
            <%= if !Enum.empty?(@conditions) do %>
              <div>
                <label class="block text-sm font-medium text-gray-700 mb-1">
                  Logical Connector
                </label>
                <select
                  name="condition[connector]"
                  class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
                  required
                >
                  <%= for {op, label} <- @logical_operators do %>
                    <option value={op}><%= label %></option>
                  <% end %>
                </select>
                <p class="text-xs text-gray-500 mt-1">
                  How to combine with previous conditions
                </p>
              </div>
            <% end %>

            <div class="flex gap-2 mt-4">
              <button type="submit" class="btn-sm btn-primary">
                Add Condition
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
          </.form>
        </div>
      <% end %>

      <!-- Conditions List -->
      <%= if Enum.empty?(@conditions) do %>
        <div class="text-center py-8 border-2 border-dashed border-gray-300 rounded-lg">
          <p class="text-gray-500 text-sm">
            No <%= @condition_type %> conditions configured yet.
          </p>
          <p class="text-gray-400 text-xs mt-1">
            Add conditions to define when to <%= @condition_type %> positions.
          </p>
        </div>
      <% else %>
        <div class="space-y-1">
          <%= for {condition, index} <- Enum.with_index(@conditions) do %>
            <!-- Connector (if not first condition) -->
            <%= if index > 0 && condition.connector do %>
              <div class="text-center py-1">
                <span class="inline-block px-3 py-1 text-xs font-semibold bg-blue-100 text-blue-800 rounded-full">
                  <%= String.upcase(condition.connector) %>
                </span>
              </div>
            <% end %>

            <!-- Condition Card -->
            <div class="bg-white border border-gray-200 rounded-lg p-3 flex items-start justify-between hover:border-blue-300 transition-colors">
              <div class="flex-1">
                <div class="flex items-center gap-2">
                  <span class="text-xs font-mono text-gray-400">#<%= index + 1 %></span>
                  <span class={[
                    "px-2 py-0.5 text-xs rounded-full",
                    if(condition.valid?, do: "bg-green-100 text-green-800", else: "bg-red-100 text-red-800")
                  ]}>
                    <%= if condition.valid?, do: "Valid", else: "Invalid" %>
                  </span>
                </div>
                <div class="mt-2 font-mono text-sm text-gray-900 bg-gray-50 px-3 py-2 rounded">
                  <span class="font-semibold text-blue-600"><%= condition.left %></span>
                  <span class="mx-2 text-gray-600"><%= get_operator_symbol(condition.operator, @available_operators) %></span>
                  <span class="font-semibold text-green-600"><%= condition.right %></span>
                </div>
              </div>
              <button
                type="button"
                phx-click="remove_condition"
                phx-value-index={index}
                phx-target={@myself}
                class="text-red-600 hover:text-red-800 p-1 ml-2"
                title="Remove condition"
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

        <!-- Condition Summary -->
        <div class="bg-blue-50 border border-blue-200 rounded-lg p-3 mt-4">
          <h4 class="text-sm font-medium text-blue-900 mb-2">
            <%= String.capitalize(@condition_type) %> Logic Summary
          </h4>
          <div class="font-mono text-xs text-blue-800">
            <%= format_conditions_summary(@conditions, @available_operators) %>
          </div>
        </div>

        <div class="text-xs text-gray-500 mt-2">
          Total conditions: <%= length(@conditions) %>
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
  def handle_event("add_condition", %{"condition" => condition_params}, socket) do
    # Create new condition
    new_condition = %{
      id: generate_condition_id(),
      left: String.trim(condition_params["left"]),
      operator: condition_params["operator"],
      right: String.trim(condition_params["right"]),
      connector: condition_params["connector"],
      valid?: validate_condition(condition_params)
    }

    # Add to conditions list
    updated_conditions = socket.assigns.conditions ++ [new_condition]

    # Notify parent
    send(self(), {:conditions_changed, socket.assigns.condition_type, updated_conditions})

    {:noreply,
     socket
     |> assign(:conditions, updated_conditions)
     |> assign(:show_add_form, false)
     |> assign(:new_condition, %{})}
  end

  @impl true
  def handle_event("cancel_add", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_add_form, false)
     |> assign(:new_condition, %{})}
  end

  @impl true
  def handle_event("remove_condition", %{"index" => index_str}, socket) do
    index = String.to_integer(index_str)

    updated_conditions =
      socket.assigns.conditions
      |> List.delete_at(index)
      # If we removed first condition, clear connector from new first condition
      |> update_connectors_after_removal(index)

    # Notify parent
    send(self(), {:conditions_changed, socket.assigns.condition_type, updated_conditions})

    {:noreply, assign(socket, :conditions, updated_conditions)}
  end

  # Private helpers

  defp normalize_conditions(conditions) when is_list(conditions) do
    Enum.map(conditions, fn condition ->
      %{
        id: condition[:id] || generate_condition_id(),
        left: condition[:left] || condition["left"],
        operator: condition[:operator] || condition["operator"],
        right: condition[:right] || condition["right"],
        connector: condition[:connector] || condition["connector"],
        valid?: condition[:valid?] || true
      }
    end)
  end

  defp generate_condition_id do
    "condition_#{System.unique_integer([:positive, :monotonic])}"
  end

  defp validate_condition(params) do
    # Basic validation: all required fields present and non-empty
    left = String.trim(params["left"] || "")
    right = String.trim(params["right"] || "")
    operator = params["operator"]

    left != "" && right != "" && operator != nil && operator != ""
  end

  defp update_connectors_after_removal(conditions, 0) when length(conditions) > 0 do
    # If we removed the first condition, the new first shouldn't have a connector
    [first | rest] = conditions
    [Map.put(first, :connector, nil) | rest]
  end

  defp update_connectors_after_removal(conditions, _index), do: conditions

  defp get_operator_symbol(operator, available_operators) do
    case available_operators[operator] do
      %{symbol: symbol} -> symbol
      _ -> operator
    end
  end

  defp format_conditions_summary(conditions, available_operators) do
    conditions
    |> Enum.with_index()
    |> Enum.map(fn {condition, index} ->
      prefix =
        if index > 0 && condition.connector,
          do: "#{String.upcase(condition.connector)} ",
          else: ""

      operator = get_operator_symbol(condition.operator, available_operators)
      "#{prefix}(#{condition.left} #{operator} #{condition.right})"
    end)
    |> Enum.join("\n")
  end
end
