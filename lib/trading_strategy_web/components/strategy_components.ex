defmodule TradingStrategyWeb.StrategyComponents do
  @moduledoc """
  Provides reusable UI components for displaying and managing trading strategies.
  """

  use Phoenix.Component
  import TradingStrategyWeb.CoreComponents

  @doc """
  Renders a strategy card component.

  Displays a strategy in a card format with name, description, status badge,
  version, and trading pair information.

  ## Examples

      <.strategy_card strategy={@strategy} />

  ## Attributes

    * `strategy` (required) - The strategy struct to display
    * `class` (optional) - Additional CSS classes for the card container
  """
  attr :strategy, :map, required: true
  attr :class, :string, default: nil

  def strategy_card(assigns) do
    ~H"""
    <div class={[
      "bg-white rounded-lg shadow p-4 hover:shadow-lg transition-shadow",
      @class
    ]}>
      <h3 class="text-lg font-semibold text-gray-900"><%= @strategy.name %></h3>

      <%= if @strategy.description do %>
        <p class="text-sm text-gray-600 mt-1 line-clamp-2"><%= @strategy.description %></p>
      <% end %>

      <div class="mt-3 flex items-center gap-2 flex-wrap">
        <.status_badge status={@strategy.status} />
        <span class="text-xs text-gray-500">v<%= @strategy.version %></span>
        <span class="text-xs text-gray-500"><%= @strategy.trading_pair %></span>
        <span class="text-xs text-gray-500"><%= @strategy.timeframe %></span>
      </div>
    </div>
    """
  end

  @doc """
  Renders a status badge component.

  Displays a colored badge based on the strategy status.

  ## Examples

      <.status_badge status="active" />
      <.status_badge status="draft" />

  ## Attributes

    * `status` (required) - The status string ("draft", "active", "inactive", "archived")
  """
  attr :status, :string, required: true

  def status_badge(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium",
      status_badge_class(@status)
    ]}>
      <%= String.capitalize(@status) %>
    </span>
    """
  end

  # Helper function to determine badge color based on status
  defp status_badge_class("active"), do: "bg-green-100 text-green-800"
  defp status_badge_class("draft"), do: "bg-gray-100 text-gray-800"
  defp status_badge_class("inactive"), do: "bg-yellow-100 text-yellow-800"
  defp status_badge_class("archived"), do: "bg-red-100 text-red-800"
  defp status_badge_class(_), do: "bg-gray-100 text-gray-800"
end
