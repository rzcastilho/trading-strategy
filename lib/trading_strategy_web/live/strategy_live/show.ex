defmodule TradingStrategyWeb.StrategyLive.Show do
  use TradingStrategyWeb, :live_view

  alias TradingStrategy.Strategies

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    current_user = socket.assigns.current_scope.user

    case Strategies.get_strategy(id, current_user) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Strategy not found")
         |> push_navigate(to: ~p"/strategies")}

      strategy ->
        {:ok,
         socket
         |> assign(:page_title, strategy.name)
         |> assign(:strategy, strategy)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
      <!-- Header -->
      <div class="mb-8">
        <div class="flex items-center justify-between">
          <div class="flex items-center space-x-4">
            <.link navigate={~p"/strategies"} class="text-gray-400 hover:text-gray-600">
              <svg class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M10 19l-7-7m0 0l7-7m-7 7h18"
                />
              </svg>
            </.link>
            <h1 class="text-3xl font-bold text-gray-900">
              <%= @strategy.name %>
            </h1>
            <.badge color={status_color(@strategy.status)}>
              <%= @strategy.status %>
            </.badge>
          </div>

          <div class="flex space-x-3">
            <%= if Strategies.can_edit?(@strategy) do %>
              <.link navigate={~p"/strategies/#{@strategy.id}/edit"} class="btn btn-secondary">
                Edit
              </.link>
            <% else %>
              <button class="btn btn-secondary opacity-50 cursor-not-allowed" disabled>
                Edit (Active)
              </button>
            <% end %>

            <button phx-click="duplicate" class="btn btn-secondary">
              Duplicate
            </button>

            <%= if @strategy.status == "active" do %>
              <button phx-click="deactivate" class="btn btn-warning">
                Deactivate
              </button>
            <% else %>
              <%= if @strategy.status not in ["archived"] do %>
                <button phx-click="activate" class="btn btn-success">
                  Activate
                </button>
              <% end %>
            <% end %>
          </div>
        </div>

        <%= if @strategy.description do %>
          <p class="mt-2 text-gray-600">
            <%= @strategy.description %>
          </p>
        <% end %>
      </div>

      <!-- Strategy Details -->
      <div class="bg-white shadow overflow-hidden sm:rounded-lg mb-6">
        <div class="px-4 py-5 sm:px-6">
          <h3 class="text-lg leading-6 font-medium text-gray-900">
            Strategy Information
          </h3>
        </div>
        <div class="border-t border-gray-200">
          <dl>
            <div class="bg-gray-50 px-4 py-5 sm:grid sm:grid-cols-3 sm:gap-4 sm:px-6">
              <dt class="text-sm font-medium text-gray-500">Trading Pair</dt>
              <dd class="mt-1 text-sm text-gray-900 sm:mt-0 sm:col-span-2">
                <%= @strategy.trading_pair %>
              </dd>
            </div>
            <div class="bg-white px-4 py-5 sm:grid sm:grid-cols-3 sm:gap-4 sm:px-6">
              <dt class="text-sm font-medium text-gray-500">Timeframe</dt>
              <dd class="mt-1 text-sm text-gray-900 sm:mt-0 sm:col-span-2">
                <%= @strategy.timeframe %>
              </dd>
            </div>
            <div class="bg-gray-50 px-4 py-5 sm:grid sm:grid-cols-3 sm:gap-4 sm:px-6">
              <dt class="text-sm font-medium text-gray-500">Format</dt>
              <dd class="mt-1 text-sm text-gray-900 sm:mt-0 sm:col-span-2">
                <%= String.upcase(@strategy.format) %>
              </dd>
            </div>
            <div class="bg-white px-4 py-5 sm:grid sm:grid-cols-3 sm:gap-4 sm:px-6">
              <dt class="text-sm font-medium text-gray-500">Version</dt>
              <dd class="mt-1 text-sm text-gray-900 sm:mt-0 sm:col-span-2">
                <%= @strategy.version %>
              </dd>
            </div>
            <div class="bg-gray-50 px-4 py-5 sm:grid sm:grid-cols-3 sm:gap-4 sm:px-6">
              <dt class="text-sm font-medium text-gray-500">Created</dt>
              <dd class="mt-1 text-sm text-gray-900 sm:mt-0 sm:col-span-2">
                <%= Calendar.strftime(@strategy.inserted_at, "%Y-%m-%d %H:%M:%S") %>
              </dd>
            </div>
            <div class="bg-white px-4 py-5 sm:grid sm:grid-cols-3 sm:gap-4 sm:px-6">
              <dt class="text-sm font-medium text-gray-500">Last Updated</dt>
              <dd class="mt-1 text-sm text-gray-900 sm:mt-0 sm:col-span-2">
                <%= Calendar.strftime(@strategy.updated_at, "%Y-%m-%d %H:%M:%S") %>
              </dd>
            </div>
          </dl>
        </div>
      </div>

      <!-- Strategy Content -->
      <div class="bg-white shadow overflow-hidden sm:rounded-lg">
        <div class="px-4 py-5 sm:px-6">
          <h3 class="text-lg leading-6 font-medium text-gray-900">
            Strategy Definition
          </h3>
        </div>
        <div class="border-t border-gray-200 px-4 py-5 sm:px-6">
          <pre class="bg-gray-50 rounded-lg p-4 overflow-x-auto text-sm"><code><%= @strategy.content %></code></pre>
        </div>
      </div>
    </div>
    """
  end

  # Event Handlers

  @impl true
  def handle_event("activate", _params, socket) do
    current_user = socket.assigns.current_scope.user
    strategy = socket.assigns.strategy

    case Strategies.can_activate?(strategy) do
      {:ok, :allowed} ->
        case Strategies.activate_strategy(strategy, current_user) do
          {:ok, updated_strategy} ->
            {:noreply,
             socket
             |> assign(:strategy, updated_strategy)
             |> put_flash(:info, "Strategy activated successfully")}

          {:error, %Ecto.Changeset{} = changeset} ->
            errors = format_errors(changeset)

            {:noreply,
             socket
             |> put_flash(:error, "Failed to activate strategy: #{errors}")}
        end

      {:error, reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Cannot activate strategy: #{reason}")}
    end
  end

  @impl true
  def handle_event("deactivate", _params, socket) do
    strategy = socket.assigns.strategy

    case Strategies.update_strategy(
           strategy,
           %{status: "inactive"},
           socket.assigns.current_scope.user
         ) do
      {:ok, updated_strategy} ->
        {:noreply,
         socket
         |> assign(:strategy, updated_strategy)
         |> put_flash(:info, "Strategy deactivated successfully")}

      {:error, %Ecto.Changeset{} = changeset} ->
        errors = format_errors(changeset)

        {:noreply,
         socket
         |> put_flash(:error, "Failed to deactivate strategy: #{errors}")}

      {:error, :unauthorized} ->
        {:noreply,
         socket
         |> put_flash(:error, "You are not authorized to modify this strategy")}
    end
  end

  @impl true
  def handle_event("duplicate", _params, socket) do
    current_user = socket.assigns.current_scope.user
    strategy = socket.assigns.strategy

    case Strategies.duplicate_strategy(strategy, current_user) do
      {:ok, duplicate} ->
        {:noreply,
         socket
         |> put_flash(:info, "Strategy duplicated successfully as '#{duplicate.name}'")
         |> push_navigate(to: ~p"/strategies")}

      {:error, :not_found} ->
        {:noreply,
         socket
         |> put_flash(:error, "Strategy not found or you don't have permission to duplicate it")
         |> push_navigate(to: ~p"/strategies")}

      {:error, changeset} ->
        error_msg = format_errors(changeset)

        {:noreply,
         socket
         |> put_flash(:error, "Failed to duplicate strategy: #{error_msg}")}
    end
  end

  # Helper functions

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map(fn {key, errors} -> "#{key}: #{Enum.join(errors, ", ")}" end)
    |> Enum.join("; ")
  end

  defp status_color("draft"), do: :gray
  defp status_color("active"), do: :green
  defp status_color("inactive"), do: :yellow
  defp status_color("archived"), do: :red
  defp status_color(_), do: :gray

  attr :color, :atom, default: :gray
  slot :inner_block, required: true

  defp badge(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium",
      badge_class(@color)
    ]}>
      <%= render_slot(@inner_block) %>
    </span>
    """
  end

  defp badge_class(:gray), do: "bg-gray-100 text-gray-800"
  defp badge_class(:green), do: "bg-green-100 text-green-800"
  defp badge_class(:yellow), do: "bg-yellow-100 text-yellow-800"
  defp badge_class(:red), do: "bg-red-100 text-red-800"
  defp badge_class(_), do: "bg-gray-100 text-gray-800"
end
