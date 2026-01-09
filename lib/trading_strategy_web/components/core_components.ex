defmodule TradingStrategyWeb.CoreComponents do
  @moduledoc """
  Provides core UI components for the TradingStrategy web application.
  """

  use Phoenix.Component

  import Phoenix.Controller,
    only: [get_csrf_token: 0, view_module: 1, view_template: 1]

  alias Phoenix.LiveView.JS

  @doc """
  Renders flash notices.
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :title, :string, default: nil
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  def flash(assigns) do
    ~H"""
    <div
      :if={msg = Phoenix.Flash.get(@flash, @kind)}
      id={"flash-#{@kind}"}
      phx-click="lv:clear-flash"
      phx-value-key={@kind}
      role="alert"
      class={[
        "fixed top-4 right-4 z-50 max-w-sm w-full rounded-lg shadow-lg p-4",
        @kind == :info && "bg-blue-50 text-blue-900 border border-blue-200",
        @kind == :error && "bg-red-50 text-red-900 border border-red-200"
      ]}
      {@rest}
    >
      <div class="flex items-start">
        <div class="flex-shrink-0">
          <svg :if={@kind == :info} class="h-5 w-5 text-blue-400" viewBox="0 0 20 20" fill="currentColor">
            <path fill-rule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clip-rule="evenodd" />
          </svg>
          <svg :if={@kind == :error} class="h-5 w-5 text-red-400" viewBox="0 0 20 20" fill="currentColor">
            <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z" clip-rule="evenodd" />
          </svg>
        </div>
        <div class="ml-3 flex-1">
          <p :if={@title} class="text-sm font-medium">
            <%= @title %>
          </p>
          <p class="text-sm">
            <%= msg %>
          </p>
        </div>
        <div class="ml-4 flex-shrink-0 flex">
          <button
            type="button"
            class="inline-flex rounded-md focus:outline-none focus:ring-2 focus:ring-offset-2"
            phx-click="lv:clear-flash"
            phx-value-key={@kind}
          >
            <span class="sr-only">Close</span>
            <svg class="h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
              <path fill-rule="evenodd" d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z" clip-rule="evenodd" />
            </svg>
          </button>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  def flash_group(assigns) do
    ~H"""
    <.flash kind={:info} title="Success!" flash={@flash} />
    <.flash kind={:error} title="Error!" flash={@flash} />
    """
  end

end
