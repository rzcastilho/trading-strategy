defmodule TradingStrategyWeb.StrategyLive.Form do
  use TradingStrategyWeb, :live_view

  alias TradingStrategy.Strategies
  alias TradingStrategy.Strategies.Strategy

  @impl true
  def mount(params, _session, socket) do
    strategy_id = params["id"]
    current_user = socket.assigns.current_scope.user

    {strategy, mode} =
      if strategy_id do
        case Strategies.get_strategy(strategy_id, current_user) do
          nil ->
            {nil, :not_found}

          strategy ->
            # Check if strategy can be edited
            if Strategies.can_edit?(strategy) do
              {strategy, :edit}
            else
              {strategy, :cannot_edit}
            end
        end
      else
        {%Strategy{user_id: current_user.id, status: "draft"}, :new}
      end

    case mode do
      :not_found ->
        {:ok,
         socket
         |> put_flash(:error, "Strategy not found")
         |> push_navigate(to: ~p"/strategies")}

      :cannot_edit ->
        {:ok,
         socket
         |> put_flash(:error, "Cannot edit an active or archived strategy")
         |> push_navigate(to: ~p"/strategies/#{strategy.id}")}

      _ ->
        changeset = Strategies.change_strategy(strategy, %{})

        socket =
          socket
          |> assign(:strategy, strategy)
          |> assign(:mode, mode)
          |> assign(:form, to_form(changeset))
          |> assign(:syntax_test_result, nil)
          |> assign(:syntax_test_loading, false)
          |> assign(:autosave_enabled, true)
          |> assign(:last_autosave, nil)
          |> assign(:unsaved_changes, false)
          |> assign(:indicators, [])
          |> assign(:entry_conditions, [])
          |> assign(:exit_conditions, [])

        # Start autosave timer if connected
        if connected?(socket) do
          Process.send_after(self(), :autosave, 30_000)
        end

        {:ok, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
      <div class="mb-6">
        <h1 class="text-3xl font-bold text-gray-900">
          <%= if @mode == :new, do: "Register New Strategy", else: "Edit Strategy" %>
        </h1>
        <%= if @last_autosave do %>
          <p class="text-sm text-gray-500 mt-1">
            Last saved: <%= Calendar.strftime(@last_autosave, "%H:%M:%S") %>
          </p>
        <% end %>
      </div>

      <.form
        id="strategy-form"
        for={@form}
        phx-change="validate"
        phx-submit="save"
        class="space-y-6"
      >
        <!-- Name -->
        <div>
          <.input
            field={@form[:name]}
            type="text"
            label="Strategy Name"
            placeholder="e.g., Momentum Breakout Strategy"
            phx-debounce="blur"
            required
          />
          <p class="mt-1 text-sm text-gray-500">
            A unique, descriptive name for your strategy (3-200 characters)
          </p>
        </div>

        <!-- Description -->
        <div>
          <.input
            field={@form[:description]}
            type="textarea"
            label="Description"
            placeholder="Describe what this strategy does, when to use it, and any important notes..."
            rows="3"
          />
          <p class="mt-1 text-sm text-gray-500">
            Optional: Explain your strategy's logic and purpose
          </p>
        </div>

        <!-- Trading Pair -->
        <div>
          <.input
            field={@form[:trading_pair]}
            type="text"
            label="Trading Pair"
            placeholder="e.g., BTC/USD, ETH/USD"
            required
          />
          <p class="mt-1 text-sm text-gray-500">
            The market pair this strategy will trade
          </p>
        </div>

        <!-- Timeframe -->
        <div>
          <.input
            field={@form[:timeframe]}
            type="select"
            label="Timeframe"
            options={[
              {"1 minute", "1m"},
              {"5 minutes", "5m"},
              {"15 minutes", "15m"},
              {"30 minutes", "30m"},
              {"1 hour", "1h"},
              {"4 hours", "4h"},
              {"1 day", "1d"},
              {"1 week", "1w"}
            ]}
            required
          />
          <p class="mt-1 text-sm text-gray-500">
            The candlestick timeframe for this strategy
          </p>
        </div>

        <!-- Format -->
        <div>
          <.input
            field={@form[:format]}
            type="select"
            label="DSL Format"
            options={[{"YAML", "yaml"}, {"TOML", "toml"}]}
            required
          />
          <p class="mt-1 text-sm text-gray-500">
            Choose the format for your strategy definition
          </p>
        </div>

        <!-- Advanced Strategy Builder (Optional) -->
        <div class="border-t border-gray-200 pt-6 space-y-6">
          <div>
            <h2 class="text-xl font-semibold text-gray-900 mb-2">
              Advanced Strategy Builder
            </h2>
            <p class="text-sm text-gray-600">
              Use the visual builders below to construct your strategy, or manually edit the DSL content.
            </p>
          </div>

          <!-- Indicator Builder -->
          <.live_component
            module={TradingStrategyWeb.StrategyLive.IndicatorBuilder}
            id="indicator-builder"
            indicators={@indicators}
          />

          <!-- Entry Conditions Builder -->
          <.live_component
            module={TradingStrategyWeb.StrategyLive.ConditionBuilder}
            id="entry-condition-builder"
            conditions={@entry_conditions}
            condition_type="entry"
            available_indicators={@indicators}
          />

          <!-- Exit Conditions Builder -->
          <.live_component
            module={TradingStrategyWeb.StrategyLive.ConditionBuilder}
            id="exit-condition-builder"
            conditions={@exit_conditions}
            condition_type="exit"
            available_indicators={@indicators}
          />
        </div>

        <!-- Content (DSL) - Manual Override -->
        <div class="border-t border-gray-200 pt-6">
          <.input
            field={@form[:content]}
            type="textarea"
            label="Strategy Definition (Advanced: Manual DSL)"
            placeholder={content_placeholder(@form[:format].value)}
            rows="15"
            phx-debounce="500"
            required
          />
          <p class="mt-1 text-sm text-gray-500">
            Define your strategy using the DSL format selected above, or use the visual builders above.
          </p>
        </div>

        <!-- Syntax Test Result -->
        <%= if @syntax_test_result do %>
          <div class={[
            "p-4 rounded-md",
            if(@syntax_test_result.success,
              do: "bg-green-50 border border-green-200",
              else: "bg-red-50 border border-red-200"
            )
          ]}>
            <h4 class={[
              "text-sm font-medium mb-2",
              if(@syntax_test_result.success, do: "text-green-800", else: "text-red-800")
            ]}>
              <%= if @syntax_test_result.success,
                do: "✓ Syntax Valid",
                else: "✗ Syntax Errors" %>
            </h4>
            <%= if @syntax_test_result.success do %>
              <pre class="text-xs text-green-700 whitespace-pre-wrap"><%= @syntax_test_result.message %></pre>
            <% else %>
              <ul class="text-sm text-red-700 list-disc list-inside space-y-1">
                <%= for error <- @syntax_test_result.errors do %>
                  <li><%= error %></li>
                <% end %>
              </ul>
            <% end %>
          </div>
        <% end %>

        <!-- Actions -->
        <div class="flex items-center justify-between pt-6 border-t border-gray-200">
          <div class="flex gap-3">
            <.button type="submit" class="btn-primary">
              <%= if @mode == :new, do: "Create Strategy", else: "Update Strategy" %>
            </.button>

            <.button
              type="button"
              phx-click="save_draft"
              class="btn-secondary"
              disabled={not @unsaved_changes}
            >
              Save Draft
            </.button>

            <.button
              type="button"
              phx-click="test_syntax"
              class="btn-outline"
              disabled={@syntax_test_loading}
            >
              <%= if @syntax_test_loading, do: "Testing...", else: "Test Syntax" %>
            </.button>
          </div>

          <.link navigate={~p"/strategies"} class="text-sm text-gray-600 hover:text-gray-900">
            Cancel
          </.link>
        </div>
      </.form>
    </div>
    """
  end

  @impl true
  def handle_event("validate", %{"strategy" => params}, socket) do
    # T038: Add telemetry for validation response time monitoring
    start_time = System.monotonic_time()

    changeset =
      socket.assigns.strategy
      |> Strategies.change_strategy(params)
      |> Map.put(:action, :validate)

    duration = System.monotonic_time() - start_time

    # Emit telemetry event for validation duration
    :telemetry.execute(
      [:trading_strategy, :strategies, :validate],
      %{duration: duration},
      %{
        mode: socket.assigns.mode,
        has_errors: !changeset.valid?,
        error_count: length(changeset.errors)
      }
    )

    {:noreply,
     socket
     |> assign(:form, to_form(changeset))
     |> assign(:unsaved_changes, true)}
  end

  @impl true
  def handle_event("save", %{"strategy" => params}, socket) do
    save_strategy(socket, socket.assigns.mode, params)
  end

  @impl true
  def handle_event("save_draft", _params, socket) do
    # Get current form data
    changeset = socket.assigns.form.source
    params = changeset_to_params(changeset)
    params = Map.put(params, "status", "draft")

    case socket.assigns.mode do
      :new ->
        case Strategies.create_strategy(params, socket.assigns.current_scope.user) do
          {:ok, strategy} ->
            {:noreply,
             socket
             |> put_flash(:info, "Draft saved successfully")
             |> assign(:strategy, strategy)
             |> assign(:mode, :edit)
             |> assign(:last_autosave, DateTime.utc_now())
             |> assign(:unsaved_changes, false)}

          {:error, changeset} ->
            {:noreply, assign(socket, :form, to_form(changeset))}
        end

      :edit ->
        case Strategies.update_strategy(socket.assigns.strategy, params, socket.assigns.current_scope.user) do
          {:ok, strategy} ->
            {:noreply,
             socket
             |> put_flash(:info, "Draft saved successfully")
             |> assign(:strategy, strategy)
             |> assign(:last_autosave, DateTime.utc_now())
             |> assign(:unsaved_changes, false)}

          {:error, changeset} ->
            {:noreply, assign(socket, :form, to_form(changeset))}
        end
    end
  end

  @impl true
  def handle_event("test_syntax", _params, socket) do
    content = get_field_value(socket.assigns.form, :content)
    format = get_field_value(socket.assigns.form, :format)

    if content && format do
      {:noreply,
       socket
       |> assign(:syntax_test_loading, true)
       |> start_async(:test_syntax, fn -> test_syntax_async(content, format) end)}
    else
      {:noreply,
       socket
       |> put_flash(:error, "Please provide DSL content and format")}
    end
  end

  @impl true
  def handle_async(:test_syntax, {:ok, result}, socket) do
    {:noreply,
     socket
     |> assign(:syntax_test_result, result)
     |> assign(:syntax_test_loading, false)}
  end

  def handle_async(:test_syntax, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:syntax_test_result, %{
       success: false,
       errors: ["Syntax test failed: #{inspect(reason)}"]
     })
     |> assign(:syntax_test_loading, false)}
  end

  @impl true
  def handle_info({:indicators_changed, indicators}, socket) do
    # Update indicators state when component notifies us
    {:noreply, assign(socket, :indicators, indicators)}
  end

  @impl true
  def handle_info({:conditions_changed, "entry", conditions}, socket) do
    # Update entry conditions state when component notifies us
    {:noreply, assign(socket, :entry_conditions, conditions)}
  end

  @impl true
  def handle_info({:conditions_changed, "exit", conditions}, socket) do
    # Update exit conditions state when component notifies us
    {:noreply, assign(socket, :exit_conditions, conditions)}
  end

  @impl true
  def handle_info(:autosave, socket) do
    # Schedule next autosave
    Process.send_after(self(), :autosave, 30_000)

    # Only autosave if there are unsaved changes
    if socket.assigns.autosave_enabled && socket.assigns.unsaved_changes do
      # Get current form data
      changeset = socket.assigns.form.source

      if changeset.changes != %{} do
        params =
          changeset.changes
          |> Map.put(:status, "draft")
          |> Enum.into(%{}, fn {k, v} -> {to_string(k), v} end)

        case socket.assigns.mode do
          :new ->
            case Strategies.create_strategy(params, socket.assigns.current_scope.user) do
              {:ok, strategy} ->
                {:noreply,
                 socket
                 |> assign(:strategy, strategy)
                 |> assign(:mode, :edit)
                 |> assign(:last_autosave, DateTime.utc_now())
                 |> assign(:unsaved_changes, false)}

              {:error, _changeset} ->
                # Don't interrupt user on autosave failure
                {:noreply, socket}
            end

          :edit ->
            case Strategies.update_strategy(
                   socket.assigns.strategy,
                   params,
                   socket.assigns.current_scope.user
                 ) do
              {:ok, strategy} ->
                {:noreply,
                 socket
                 |> assign(:strategy, strategy)
                 |> assign(:last_autosave, DateTime.utc_now())
                 |> assign(:unsaved_changes, false)}

              {:error, _changeset} ->
                {:noreply, socket}
            end
        end
      else
        {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  # Private Functions

  defp save_strategy(socket, :new, params) do
    case Strategies.create_strategy(params, socket.assigns.current_scope.user) do
      {:ok, strategy} ->
        {:noreply,
         socket
         |> put_flash(:info, "Strategy created successfully")
         |> push_navigate(to: ~p"/strategies/#{strategy.id}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp save_strategy(socket, :edit, params) do
    case Strategies.update_strategy(
           socket.assigns.strategy,
           params,
           socket.assigns.current_scope.user
         ) do
      {:ok, strategy} ->
        {:noreply,
         socket
         |> put_flash(:info, "Strategy updated successfully")
         |> push_navigate(to: ~p"/strategies/#{strategy.id}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}

      {:error, :unauthorized} ->
        {:noreply,
         socket
         |> put_flash(:error, "You are not authorized to edit this strategy")
         |> push_navigate(to: ~p"/strategies")}
    end
  rescue
    Ecto.StaleEntryError ->
      # Version conflict - reload latest version
      latest = Strategies.get_strategy(socket.assigns.strategy.id, socket.assigns.current_scope.user)

      {:noreply,
       socket
       |> assign(:strategy, latest)
       |> assign(:form, to_form(Strategies.change_strategy(latest, %{})))
       |> put_flash(
         :error,
         "Strategy was modified by another session. Your form has been reloaded with the latest version."
       )}
  end

  defp test_syntax_async(content, format) do
    case Strategies.test_strategy_syntax(content, String.to_existing_atom(format)) do
      {:ok, result} ->
        %{
          success: true,
          message: format_syntax_success(result)
        }

      {:error, errors} when is_list(errors) ->
        %{
          success: false,
          errors: errors
        }

      {:error, error} ->
        %{
          success: false,
          errors: [to_string(error)]
        }
    end
  end

  defp format_syntax_success(%{summary: summary}) do
    """
    ✓ Strategy successfully parsed and validated!

    📊 Strategy: #{summary.name}
    📈 Trading Pair: #{summary.trading_pair}
    ⏱  Timeframe: #{summary.timeframe}

    📌 Indicators (#{summary.indicator_count}):
    #{Enum.map_join(summary.indicators, "\n", &"  • #{&1}")}

    🔵 Entry Conditions: #{summary.entry_condition_count}
    🔴 Exit Conditions: #{summary.exit_condition_count}
    ⛔ Stop Conditions: #{summary.stop_condition_count}

    #{if summary.has_position_sizing, do: "✓ Position sizing configured", else: "✗ Position sizing missing"}
    #{if summary.has_risk_parameters, do: "✓ Risk parameters configured", else: "✗ Risk parameters missing"}
    """
  end

  defp format_syntax_success(result) do
    """
    Strategy successfully parsed!

    Summary:
    #{inspect(result, pretty: true, limit: :infinity)}
    """
  end

  defp content_placeholder("yaml") do
    """
    strategy:
      name: "My Strategy"
      trading_pair: "BTC/USD"
      timeframe: "1h"

    indicators:
      - type: sma
        period: 20
      - type: rsi
        period: 14

    entry_conditions:
      - rsi < 30
      - price > sma_20

    exit_conditions:
      - rsi > 70

    risk_management:
      max_position_size: 1000
      stop_loss_pct: 0.02
      daily_loss_limit: 500
    """
  end

  defp content_placeholder("toml") do
    """
    [strategy]
    name = "My Strategy"
    trading_pair = "BTC/USD"
    timeframe = "1h"

    [[indicators]]
    type = "sma"
    period = 20

    [[indicators]]
    type = "rsi"
    period = 14

    [risk_management]
    max_position_size = 1000
    stop_loss_pct = 0.02
    daily_loss_limit = 500
    """
  end

  defp content_placeholder(_), do: ""

  defp get_field_value(form, field) do
    case Map.get(form.source.changes, field) do
      nil -> Map.get(form.source.data, field)
      value -> value
    end
  end

  defp changeset_to_params(changeset) do
    changeset.changes
    |> Enum.into(%{}, fn {k, v} -> {to_string(k), v} end)
  end
end
