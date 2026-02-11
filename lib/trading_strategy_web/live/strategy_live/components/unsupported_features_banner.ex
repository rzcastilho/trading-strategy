defmodule TradingStrategyWeb.StrategyLive.Components.UnsupportedFeaturesBanner do
  @moduledoc """
  Persistent warning banner for unsupported DSL features (T060, FR-009).

  Displays when the DSL contains features that work but aren't supported by the visual builder,
  such as:
  - Custom Elixir functions
  - Complex control flow (if/case/cond)
  - Advanced pattern matching
  """

  use Phoenix.Component
  import TradingStrategyWeb.CoreComponents

  alias TradingStrategy.StrategyEditor.ValidationResult

  @doc """
  Renders a persistent warning banner for unsupported features.

  ## Attributes
  - validation_result: ValidationResult struct with warnings
  - class: Additional CSS classes

  ## Examples

      <.unsupported_features_banner validation_result={@validation_result} />
  """
  attr :validation_result, ValidationResult, required: true
  attr :class, :string, default: ""

  def unsupported_features_banner(assigns) do
    ~H"""
    <div
      :if={@validation_result.valid and ValidationResult.has_unsupported?(@validation_result)}
      class={["alert alert-warning shadow-lg mb-4", @class]}
      role="alert"
    >
      <div class="flex-1">
        <div class="flex items-start gap-3">
          <!-- Warning icon -->
          <svg
            xmlns="http://www.w3.org/2000/svg"
            class="stroke-current flex-shrink-0 h-6 w-6"
            fill="none"
            viewBox="0 0 24 24"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"
            />
          </svg>

          <div class="flex-1">
            <h3 class="font-bold">Unsupported Features Detected</h3>
            <div class="text-sm mt-2">
              Your strategy contains DSL features that work correctly but cannot be edited in the visual builder.
            </div>

            <!-- List of unsupported features -->
            <div :if={length(@validation_result.unsupported) > 0} class="mt-2">
              <details class="text-sm">
                <summary class="cursor-pointer font-medium">
                  View <%= length(@validation_result.unsupported) %> unsupported <%= if length(
                    @validation_result.unsupported
                  ) == 1,
                    do: "feature",
                    else: "features" %>
                </summary>
                <ul class="list-disc list-inside mt-2 ml-4 space-y-1">
                  <li :for={feature <- @validation_result.unsupported}>
                    <code class="text-xs bg-base-300 px-1 py-0.5 rounded"><%= feature %></code>
                  </li>
                </ul>
              </details>
            </div>

            <!-- Warnings with suggestions -->
            <div :if={length(@validation_result.warnings) > 0} class="mt-3 space-y-2">
              <div :for={warning <- @validation_result.warnings} class="text-sm">
                <div class="font-medium"><%= warning.message %></div>
                <div :if={warning.suggestion} class="text-xs opacity-75 mt-1">
                  💡 <%= warning.suggestion %>
                </div>
              </div>
            </div>

            <!-- Action buttons -->
            <div class="mt-4 flex gap-2">
              <button
                class="btn btn-sm btn-ghost"
                onclick="document.getElementById('dsl-editor-tab').click()"
              >
                Edit in DSL Mode
              </button>
              <button class="btn btn-sm btn-ghost" onclick="this.closest('.alert').remove()">
                Dismiss
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders a compact warning badge for unsupported features.

  ## Examples

      <.unsupported_badge validation_result={@validation_result} />
  """
  attr :validation_result, ValidationResult, required: true

  def unsupported_badge(assigns) do
    ~H"""
    <span
      :if={ValidationResult.has_unsupported?(@validation_result)}
      class="badge badge-warning badge-sm"
      title={"#{length(@validation_result.unsupported)} unsupported features"}
    >
      ⚠️ <%= length(@validation_result.unsupported) %>
    </span>
    """
  end

  @doc """
  Renders a minimal inline warning for unsupported features.

  ## Examples

      <.unsupported_inline validation_result={@validation_result} />
  """
  attr :validation_result, ValidationResult, required: true
  attr :class, :string, default: ""

  def unsupported_inline(assigns) do
    ~H"""
    <div
      :if={ValidationResult.has_unsupported?(@validation_result)}
      class={["flex items-center gap-2 text-sm text-warning", @class]}
    >
      <svg
        xmlns="http://www.w3.org/2000/svg"
        class="h-5 w-5"
        fill="none"
        viewBox="0 0 24 24"
        stroke="currentColor"
      >
        <path
          stroke-linecap="round"
          stroke-linejoin="round"
          stroke-width="2"
          d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"
        />
      </svg>
      <span>
        <%= length(@validation_result.unsupported) %> unsupported <%= if length(
          @validation_result.unsupported
        ) == 1,
          do: "feature",
          else: "features" %>
      </span>
    </div>
    """
  end

  @doc """
  Renders a tooltip with unsupported features info.

  ## Examples

      <.unsupported_tooltip validation_result={@validation_result} />
  """
  attr :validation_result, ValidationResult, required: true
  attr :id, :string, default: "unsupported-tooltip"

  def unsupported_tooltip(assigns) do
    ~H"""
    <div
      :if={ValidationResult.has_unsupported?(@validation_result)}
      class="tooltip tooltip-warning"
      data-tip={
        "#{length(@validation_result.unsupported)} unsupported features: #{Enum.join(@validation_result.unsupported, ", ")}"
      }
    >
      <span class="badge badge-warning badge-xs">⚠️</span>
    </div>
    """
  end
end
