defmodule TradingStrategyWeb.StrategyLive.Index do
  use TradingStrategyWeb, :live_view

  alias TradingStrategy.Strategies

  @impl true
  def mount(_params, _session, socket) do
    current_user = socket.assigns.current_scope.user

    if connected?(socket) do
      # Subscribe to strategy updates for real-time updates
      Phoenix.PubSub.subscribe(
        TradingStrategy.PubSub,
        "strategies:user:#{current_user.id}"
      )
    end

    {:ok,
     socket
     |> assign(:page_title, "Strategies")
     |> assign(:strategies, Strategies.list_strategies(current_user))
     |> assign(:status_filter, nil)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    status_filter = params["status"]
    current_user = socket.assigns.current_scope.user

    strategies =
      if status_filter do
        Strategies.list_strategies(current_user, status: status_filter)
      else
        Strategies.list_strategies(current_user)
      end

    {:noreply,
     socket
     |> assign(:status_filter, status_filter)
     |> assign(:strategies, strategies)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
      <div class="flex justify-between items-center mb-6">
        <h1 class="text-3xl font-bold text-gray-900">Strategies</h1>
        <.link navigate={~p"/strategies/new"} class="btn btn-primary">
          New Strategy
        </.link>
      </div>

      <!-- Filter tabs -->
      <div class="mb-6 border-b border-gray-200">
        <nav class="flex space-x-8">
          <.link
            navigate={~p"/strategies"}
            class={[
              "py-4 px-1 border-b-2 font-medium text-sm",
              if(@status_filter == nil,
                do: "border-blue-500 text-blue-600",
                else: "border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300"
              )
            ]}
          >
            All
          </.link>
          <.link
            navigate={~p"/strategies?status=draft"}
            class={[
              "py-4 px-1 border-b-2 font-medium text-sm",
              if(@status_filter == "draft",
                do: "border-blue-500 text-blue-600",
                else: "border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300"
              )
            ]}
          >
            Drafts
          </.link>
          <.link
            navigate={~p"/strategies?status=active"}
            class={[
              "py-4 px-1 border-b-2 font-medium text-sm",
              if(@status_filter == "active",
                do: "border-blue-500 text-blue-600",
                else: "border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300"
              )
            ]}
          >
            Active
          </.link>
          <.link
            navigate={~p"/strategies?status=inactive"}
            class={[
              "py-4 px-1 border-b-2 font-medium text-sm",
              if(@status_filter == "inactive",
                do: "border-blue-500 text-blue-600",
                else: "border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300"
              )
            ]}
          >
            Inactive
          </.link>
        </nav>
      </div>

      <!-- Strategy grid -->
      <%= if Enum.empty?(@strategies) do %>
        <div class="text-center py-12">
          <svg
            class="mx-auto h-12 w-12 text-gray-400"
            fill="none"
            viewBox="0 0 24 24"
            stroke="currentColor"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"
            />
          </svg>
          <h3 class="mt-2 text-sm font-medium text-gray-900">No strategies</h3>
          <p class="mt-1 text-sm text-gray-500">Get started by creating a new strategy.</p>
          <div class="mt-6">
            <.link navigate={~p"/strategies/new"} class="btn btn-primary">
              New Strategy
            </.link>
          </div>
        </div>
      <% else %>
        <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
          <%= for strategy <- @strategies do %>
            <div class="bg-white overflow-hidden shadow rounded-lg hover:shadow-lg transition-shadow">
              <.link navigate={~p"/strategies/#{strategy.id}"} class="block">
                <div class="px-4 py-5 sm:p-6">
                  <div class="flex items-center justify-between mb-2">
                    <h3 class="text-lg font-medium text-gray-900 truncate">
                      <%= strategy.name %>
                    </h3>
                    <.badge color={status_color(strategy.status)}>
                      <%= strategy.status %>
                    </.badge>
                  </div>

                  <%= if strategy.description do %>
                    <p class="mt-1 text-sm text-gray-500 line-clamp-2">
                      <%= strategy.description %>
                    </p>
                  <% end %>

                  <div class="mt-4 flex items-center text-sm text-gray-500">
                    <span class="inline-flex items-center">
                      <svg
                        class="mr-1.5 h-4 w-4 text-gray-400"
                        fill="none"
                        viewBox="0 0 24 24"
                        stroke="currentColor"
                      >
                        <path
                          stroke-linecap="round"
                          stroke-linejoin="round"
                          stroke-width="2"
                          d="M7 12l3-3 3 3 4-4M8 21l4-4 4 4M3 4h18M4 4h16v12a1 1 0 01-1 1H5a1 1 0 01-1-1V4z"
                        />
                      </svg>
                      <%= strategy.trading_pair %>
                    </span>
                    <span class="ml-4">
                      <%= strategy.timeframe %>
                    </span>
                    <span class="ml-4 text-xs text-gray-400">
                      v<%= strategy.version %>
                    </span>
                  </div>
                </div>
              </.link>
              <div class="px-4 py-3 bg-gray-50 border-t border-gray-200">
                <button
                  phx-click="duplicate_strategy"
                  phx-value-id={strategy.id}
                  class="text-sm text-blue-600 hover:text-blue-800 font-medium"
                >
                  Duplicate
                </button>
              </div>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  @impl true
  def handle_event("duplicate_strategy", %{"id" => strategy_id}, socket) do
    current_user = socket.assigns.current_scope.user

    case Strategies.get_strategy(strategy_id, current_user) do
      nil ->
        {:noreply,
         socket
         |> put_flash(:error, "Strategy not found")
         |> assign(:strategies, Strategies.list_strategies(current_user))}

      strategy ->
        case Strategies.duplicate_strategy(strategy, current_user) do
          {:ok, duplicate} ->
            {:noreply,
             socket
             |> put_flash(:info, "Strategy duplicated successfully as '#{duplicate.name}'")
             |> assign(:strategies, Strategies.list_strategies(current_user))}

          {:error, :not_found} ->
            {:noreply,
             socket
             |> put_flash(:error, "Strategy not found or you don't have permission to duplicate it")
             |> assign(:strategies, Strategies.list_strategies(current_user))}

          {:error, changeset} ->
            error_msg = format_errors(changeset)

            {:noreply,
             socket
             |> put_flash(:error, "Failed to duplicate strategy: #{error_msg}")
             |> assign(:strategies, Strategies.list_strategies(current_user))}
        end
    end
  end

  @impl true
  def handle_info({:strategy_created, _id}, socket) do
    current_user = socket.assigns.current_scope.user
    {:noreply, assign(socket, :strategies, Strategies.list_strategies(current_user))}
  end

  def handle_info({:strategy_updated, _id}, socket) do
    current_user = socket.assigns.current_scope.user
    {:noreply, assign(socket, :strategies, Strategies.list_strategies(current_user))}
  end

  def handle_info({:strategy_deleted, _id}, socket) do
    current_user = socket.assigns.current_scope.user
    {:noreply, assign(socket, :strategies, Strategies.list_strategies(current_user))}
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
