defmodule TradingStrategyWeb.PaperTradingLive do
  @moduledoc """
  LiveView dashboard for paper trading sessions.

  Displays real-time updates for:
  - Active paper trading sessions
  - Live position tracking
  - P&L charts (unrealized and realized)
  - Recent trade history
  - Session controls (start/stop/pause/resume)

  All updates are pushed via Phoenix PubSub for reactive UI.
  """

  use TradingStrategyWeb, :live_view
  require Logger

  alias TradingStrategy.PaperTrading

  @impl true
  def mount(_params, _session, socket) do
    # Subscribe to all paper trading updates
    if connected?(socket) do
      Phoenix.PubSub.subscribe(TradingStrategy.PubSub, "paper_trading:updates")
    end

    # Load initial data
    {:ok, sessions} = PaperTrading.list_paper_sessions(status: :active, limit: 50)

    socket =
      socket
      |> assign(:sessions, sessions)
      |> assign(:selected_session_id, nil)
      |> assign(:session_details, nil)
      |> assign(:trades, [])
      |> assign(:metrics, %{})
      |> assign(:loading, false)
      |> assign(:error, nil)

    {:ok, socket}
  end

  @impl true
  def handle_params(%{"session_id" => session_id}, _uri, socket) do
    socket = load_session_details(socket, session_id)
    {:noreply, socket}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50">
      <!-- Header -->
      <header class="bg-white shadow-sm border-b border-gray-200">
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-4">
          <h1 class="text-2xl font-bold text-gray-900">Paper Trading Dashboard</h1>
          <p class="text-sm text-gray-600 mt-1">Real-time simulated trading sessions</p>
        </div>
      </header>

      <!-- Main Content -->
      <main class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <!-- Error Alert -->
        <%= if @error do %>
          <div class="mb-6 bg-red-50 border border-red-200 rounded-lg p-4">
            <div class="flex">
              <div class="flex-shrink-0">
                <svg class="h-5 w-5 text-red-400" viewBox="0 0 20 20" fill="currentColor">
                  <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z" clip-rule="evenodd" />
                </svg>
              </div>
              <div class="ml-3">
                <h3 class="text-sm font-medium text-red-800">Error</h3>
                <p class="text-sm text-red-700 mt-1"><%= @error %></p>
              </div>
              <div class="ml-auto pl-3">
                <button phx-click="clear_error" class="text-red-400 hover:text-red-600">
                  <svg class="h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
                    <path fill-rule="evenodd" d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z" clip-rule="evenodd" />
                  </svg>
                </button>
              </div>
            </div>
          </div>
        <% end %>

        <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
          <!-- Sessions List -->
          <div class="lg:col-span-1">
            <div class="bg-white rounded-lg shadow">
              <div class="px-4 py-5 border-b border-gray-200 sm:px-6">
                <h3 class="text-lg font-medium text-gray-900">Active Sessions</h3>
                <p class="mt-1 text-sm text-gray-500"><%= length(@sessions) %> active</p>
              </div>
              <div class="divide-y divide-gray-200 max-h-96 overflow-y-auto">
                <%= if Enum.empty?(@sessions) do %>
                  <div class="px-4 py-8 text-center text-gray-500">
                    <p class="text-sm">No active sessions</p>
                    <p class="text-xs mt-1">Start a new paper trading session to begin</p>
                  </div>
                <% else %>
                  <%= for session <- @sessions do %>
                    <div
                      phx-click="select_session"
                      phx-value-session_id={session.session_id}
                      class={"px-4 py-4 hover:bg-gray-50 cursor-pointer transition-colors " <> if(@selected_session_id == session.session_id, do: "bg-blue-50", else: "")}
                    >
                      <div class="flex items-center justify-between">
                        <div class="flex-1 min-w-0">
                          <p class="text-sm font-medium text-gray-900 truncate">
                            <%= session[:trading_pair] || "Unknown Pair" %>
                          </p>
                          <p class="text-xs text-gray-500 mt-1">
                            <%= format_session_id(session.session_id) %>
                          </p>
                        </div>
                        <div class="ml-4 flex-shrink-0">
                          <span class={"inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium " <> status_color(session[:status])}>
                            <%= session[:status] || :active %>
                          </span>
                        </div>
                      </div>
                      <div class="mt-2 grid grid-cols-2 gap-2 text-xs">
                        <div>
                          <span class="text-gray-500">Equity:</span>
                          <span class="ml-1 font-medium text-gray-900">
                            $<%= format_decimal(session[:current_equity]) %>
                          </span>
                        </div>
                        <div>
                          <span class="text-gray-500">P&L:</span>
                          <span class={"ml-1 font-medium " <> pnl_color(session[:realized_pnl])}>
                            <%= format_pnl(session[:realized_pnl]) %>
                          </span>
                        </div>
                      </div>
                    </div>
                  <% end %>
                <% end %>
              </div>
            </div>
          </div>

          <!-- Session Details -->
          <div class="lg:col-span-2">
            <%= if @session_details do %>
              <div class="space-y-6">
                <!-- Session Info Card -->
                <div class="bg-white rounded-lg shadow">
                  <div class="px-4 py-5 border-b border-gray-200 sm:px-6">
                    <div class="flex items-center justify-between">
                      <div>
                        <h3 class="text-lg font-medium text-gray-900">Session Details</h3>
                        <p class="mt-1 text-sm text-gray-500">
                          Started <%= format_relative_time(@session_details.started_at) %>
                        </p>
                      </div>
                      <div class="flex space-x-2">
                        <%= if @session_details.status == :active do %>
                          <button
                            phx-click="pause_session"
                            class="inline-flex items-center px-3 py-2 border border-gray-300 shadow-sm text-sm font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
                          >
                            Pause
                          </button>
                        <% end %>
                        <%= if @session_details.status == :paused do %>
                          <button
                            phx-click="resume_session"
                            class="inline-flex items-center px-3 py-2 border border-gray-300 shadow-sm text-sm font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-green-500"
                          >
                            Resume
                          </button>
                        <% end %>
                        <%= if @session_details.status != :stopped do %>
                          <button
                            phx-click="stop_session"
                            class="inline-flex items-center px-3 py-2 border border-transparent shadow-sm text-sm font-medium rounded-md text-white bg-red-600 hover:bg-red-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-red-500"
                          >
                            Stop
                          </button>
                        <% end %>
                      </div>
                    </div>
                  </div>

                  <!-- P&L Metrics -->
                  <div class="px-4 py-5 sm:px-6">
                    <dl class="grid grid-cols-1 gap-5 sm:grid-cols-3">
                      <div class="bg-gray-50 px-4 py-5 rounded-lg">
                        <dt class="text-sm font-medium text-gray-500">Current Equity</dt>
                        <dd class="mt-1 text-2xl font-semibold text-gray-900">
                          $<%= format_decimal(@session_details.current_equity) %>
                        </dd>
                      </div>
                      <div class="bg-gray-50 px-4 py-5 rounded-lg">
                        <dt class="text-sm font-medium text-gray-500">Realized P&L</dt>
                        <dd class={"mt-1 text-2xl font-semibold " <> pnl_color(@session_details.realized_pnl)}>
                          <%= format_pnl(@session_details.realized_pnl) %>
                        </dd>
                      </div>
                      <div class="bg-gray-50 px-4 py-5 rounded-lg">
                        <dt class="text-sm font-medium text-gray-500">Unrealized P&L</dt>
                        <dd class={"mt-1 text-2xl font-semibold " <> pnl_color(@session_details.unrealized_pnl)}>
                          <%= format_pnl(@session_details.unrealized_pnl) %>
                        </dd>
                      </div>
                    </dl>
                  </div>

                  <!-- Open Positions -->
                  <%= if length(@session_details.open_positions) > 0 do %>
                    <div class="px-4 py-5 border-t border-gray-200 sm:px-6">
                      <h4 class="text-sm font-medium text-gray-900 mb-3">Open Positions</h4>
                      <div class="space-y-2">
                        <%= for position <- @session_details.open_positions do %>
                          <div class="bg-gray-50 rounded-lg p-3">
                            <div class="flex items-center justify-between">
                              <div>
                                <span class="text-sm font-medium text-gray-900">
                                  <%= position[:trading_pair] || position["trading_pair"] %>
                                </span>
                                <span class={"ml-2 inline-flex items-center px-2 py-0.5 rounded text-xs font-medium " <> side_color(position[:side] || position["side"])}>
                                  <%= position[:side] || position["side"] %>
                                </span>
                              </div>
                              <span class={"text-sm font-semibold " <> pnl_color(position[:unrealized_pnl] || position["unrealized_pnl"])}>
                                <%= format_pnl(position[:unrealized_pnl] || position["unrealized_pnl"]) %>
                              </span>
                            </div>
                            <div class="mt-2 grid grid-cols-3 gap-2 text-xs text-gray-600">
                              <div>
                                Entry: $<%= format_decimal(position[:entry_price] || position["entry_price"]) %>
                              </div>
                              <div>
                                Current: $<%= format_decimal(position[:current_price] || position["current_price"]) %>
                              </div>
                              <div>
                                Qty: <%= format_decimal(position[:quantity] || position["quantity"]) %>
                              </div>
                            </div>
                          </div>
                        <% end %>
                      </div>
                    </div>
                  <% end %>
                </div>

                <!-- Recent Trades -->
                <div class="bg-white rounded-lg shadow">
                  <div class="px-4 py-5 border-b border-gray-200 sm:px-6">
                    <h3 class="text-lg font-medium text-gray-900">Recent Trades</h3>
                    <p class="mt-1 text-sm text-gray-500"><%= @session_details.trades_count %> total trades</p>
                  </div>
                  <div class="overflow-x-auto">
                    <%= if Enum.empty?(@trades) do %>
                      <div class="px-4 py-8 text-center text-gray-500">
                        <p class="text-sm">No trades yet</p>
                      </div>
                    <% else %>
                      <table class="min-w-full divide-y divide-gray-200">
                        <thead class="bg-gray-50">
                          <tr>
                            <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Time</th>
                            <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Side</th>
                            <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Type</th>
                            <th class="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase">Price</th>
                            <th class="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase">Quantity</th>
                            <th class="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase">P&L</th>
                          </tr>
                        </thead>
                        <tbody class="bg-white divide-y divide-gray-200">
                          <%= for trade <- Enum.take(@trades, 10) do %>
                            <tr class="hover:bg-gray-50">
                              <td class="px-4 py-3 whitespace-nowrap text-sm text-gray-500">
                                <%= format_time(trade[:timestamp] || trade["timestamp"]) %>
                              </td>
                              <td class="px-4 py-3 whitespace-nowrap text-sm">
                                <span class={"inline-flex items-center px-2 py-0.5 rounded text-xs font-medium " <> trade_side_color(trade[:side] || trade["side"])}>
                                  <%= trade[:side] || trade["side"] %>
                                </span>
                              </td>
                              <td class="px-4 py-3 whitespace-nowrap text-sm text-gray-900">
                                <%= trade[:signal_type] || trade["signal_type"] %>
                              </td>
                              <td class="px-4 py-3 whitespace-nowrap text-sm text-gray-900 text-right">
                                $<%= format_decimal(trade[:price] || trade["price"]) %>
                              </td>
                              <td class="px-4 py-3 whitespace-nowrap text-sm text-gray-900 text-right">
                                <%= format_decimal(trade[:quantity] || trade["quantity"]) %>
                              </td>
                              <td class={"px-4 py-3 whitespace-nowrap text-sm font-medium text-right " <> pnl_color(trade[:pnl] || trade["pnl"])}>
                                <%= format_pnl(trade[:pnl] || trade["pnl"]) %>
                              </td>
                            </tr>
                          <% end %>
                        </tbody>
                      </table>
                    <% end %>
                  </div>
                </div>
              </div>
            <% else %>
              <div class="bg-white rounded-lg shadow">
                <div class="px-4 py-12 text-center">
                  <svg class="mx-auto h-12 w-12 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z" />
                  </svg>
                  <h3 class="mt-2 text-sm font-medium text-gray-900">No session selected</h3>
                  <p class="mt-1 text-sm text-gray-500">Select a session from the list to view details</p>
                </div>
              </div>
            <% end %>
          </div>
        </div>
      </main>
    </div>
    """
  end

  # Event Handlers

  @impl true
  def handle_event("select_session", %{"session_id" => session_id}, socket) do
    socket = load_session_details(socket, session_id)
    {:noreply, socket}
  end

  def handle_event("pause_session", _params, socket) do
    case PaperTrading.pause_paper_session(socket.assigns.selected_session_id) do
      :ok ->
        socket = load_session_details(socket, socket.assigns.selected_session_id)
        {:noreply, put_flash(socket, :info, "Session paused")}

      {:error, reason} ->
        {:noreply, assign(socket, :error, "Failed to pause: #{reason}")}
    end
  end

  def handle_event("resume_session", _params, socket) do
    case PaperTrading.resume_paper_session(socket.assigns.selected_session_id) do
      :ok ->
        socket = load_session_details(socket, socket.assigns.selected_session_id)
        {:noreply, put_flash(socket, :info, "Session resumed")}

      {:error, reason} ->
        {:noreply, assign(socket, :error, "Failed to resume: #{reason}")}
    end
  end

  def handle_event("stop_session", _params, socket) do
    case PaperTrading.stop_paper_session(socket.assigns.selected_session_id) do
      {:ok, _results} ->
        socket =
          socket
          |> assign(:selected_session_id, nil)
          |> assign(:session_details, nil)
          |> put_flash(:info, "Session stopped")

        {:ok, sessions} = PaperTrading.list_paper_sessions(status: :active, limit: 50)
        {:noreply, assign(socket, :sessions, sessions)}

      {:error, reason} ->
        {:noreply, assign(socket, :error, "Failed to stop: #{reason}")}
    end
  end

  def handle_event("clear_error", _params, socket) do
    {:noreply, assign(socket, :error, nil)}
  end

  # PubSub message handlers

  @impl true
  def handle_info({:session_update, session_id}, socket) do
    # Reload session list if update affects current view
    {:ok, sessions} = PaperTrading.list_paper_sessions(status: :active, limit: 50)

    socket = assign(socket, :sessions, sessions)

    socket =
      if socket.assigns.selected_session_id == session_id do
        load_session_details(socket, session_id)
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  # Private helper functions

  defp load_session_details(socket, session_id) do
    with {:ok, session_details} <- PaperTrading.get_paper_session_status(session_id),
         {:ok, trades} <- PaperTrading.get_paper_session_trades(session_id, limit: 20) do
      # Subscribe to session-specific updates
      if socket.assigns.selected_session_id != session_id do
        Phoenix.PubSub.subscribe(TradingStrategy.PubSub, "paper_trading:#{session_id}")
      end

      socket
      |> assign(:selected_session_id, session_id)
      |> assign(:session_details, session_details)
      |> assign(:trades, trades)
      |> assign(:error, nil)
    else
      {:error, :not_found} ->
        assign(socket, :error, "Session not found")

      {:error, reason} ->
        assign(socket, :error, "Error loading session: #{inspect(reason)}")
    end
  end

  # Formatting helpers

  defp format_session_id(session_id) do
    String.slice(session_id, 0..11) <> "..."
  end

  defp format_decimal(nil), do: "0.00"

  defp format_decimal(%Decimal{} = decimal) do
    decimal
    |> Decimal.round(2)
    |> Decimal.to_string()
  end

  defp format_decimal(value) when is_number(value) do
    :erlang.float_to_binary(value * 1.0, decimals: 2)
  end

  defp format_decimal(_), do: "0.00"

  defp format_pnl(nil), do: "$0.00"

  defp format_pnl(%Decimal{} = decimal) do
    value = Decimal.to_float(decimal)
    sign = if value >= 0, do: "+", else: ""
    "#{sign}$#{format_decimal(decimal)}"
  end

  defp format_pnl(value) when is_number(value) do
    sign = if value >= 0, do: "+", else: ""
    "#{sign}$#{:erlang.float_to_binary(abs(value), decimals: 2)}"
  end

  defp format_pnl(_), do: "$0.00"

  defp format_relative_time(%DateTime{} = datetime) do
    diff_seconds = DateTime.diff(DateTime.utc_now(), datetime, :second)

    cond do
      diff_seconds < 60 -> "#{diff_seconds}s ago"
      diff_seconds < 3600 -> "#{div(diff_seconds, 60)}m ago"
      diff_seconds < 86400 -> "#{div(diff_seconds, 3600)}h ago"
      true -> "#{div(diff_seconds, 86400)}d ago"
    end
  end

  defp format_relative_time(_), do: "Unknown"

  defp format_time(%DateTime{} = datetime) do
    Calendar.strftime(datetime, "%H:%M:%S")
  end

  defp format_time(_), do: "-"

  # Color helpers for Tailwind classes

  defp status_color(:active), do: "bg-green-100 text-green-800"
  defp status_color(:paused), do: "bg-yellow-100 text-yellow-800"
  defp status_color(:stopped), do: "bg-gray-100 text-gray-800"
  defp status_color(_), do: "bg-gray-100 text-gray-800"

  defp pnl_color(nil), do: "text-gray-900"

  defp pnl_color(%Decimal{} = decimal) do
    if Decimal.positive?(decimal), do: "text-green-600", else: "text-red-600"
  end

  defp pnl_color(value) when is_number(value) do
    if value >= 0, do: "text-green-600", else: "text-red-600"
  end

  defp pnl_color(_), do: "text-gray-900"

  defp side_color(:long), do: "bg-green-100 text-green-800"
  defp side_color(:short), do: "bg-red-100 text-red-800"
  defp side_color("long"), do: "bg-green-100 text-green-800"
  defp side_color("short"), do: "bg-red-100 text-red-800"
  defp side_color(_), do: "bg-gray-100 text-gray-800"

  defp trade_side_color(:buy), do: "bg-green-100 text-green-800"
  defp trade_side_color(:sell), do: "bg-red-100 text-red-800"
  defp trade_side_color("buy"), do: "bg-green-100 text-green-800"
  defp trade_side_color("sell"), do: "bg-red-100 text-red-800"
  defp trade_side_color(_), do: "bg-gray-100 text-gray-800"
end
