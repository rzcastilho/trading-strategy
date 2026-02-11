defmodule TradingStrategyWeb.StrategyLive.Components.ValidationErrors do
  @moduledoc """
  Component for displaying inline validation errors with line/column numbers (T059, FR-004).

  Shows syntax and semantic errors in a clear, actionable format with:
  - Error type (syntax, semantic, parser_crash)
  - Line and column numbers when available
  - Clear error messages
  - Severity indicators (error vs warning)
  """

  use Phoenix.Component
  import TradingStrategyWeb.CoreComponents

  alias TradingStrategy.StrategyEditor.ValidationResult

  @doc """
  Renders validation errors inline.

  ## Attributes
  - validation_result: ValidationResult struct with errors
  - class: Additional CSS classes

  ## Examples

      <.validation_errors validation_result={@validation_result} />
  """
  attr :validation_result, ValidationResult, required: true
  attr :class, :string, default: ""

  def validation_errors(assigns) do
    ~H"""
    <div :if={not @validation_result.valid} class={["validation-errors space-y-2", @class]}>
      <div
        :for={error <- @validation_result.errors}
        class="alert alert-error shadow-lg"
        role="alert"
      >
        <div class="flex-1">
          <div class="flex items-start gap-2">
            <!-- Error icon -->
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
                d="M10 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2m7-2a9 9 0 11-18 0 9 9 0 0118 0z"
              />
            </svg>

            <div class="flex-1">
              <!-- Error type badge -->
              <span class={[
                "badge badge-sm mr-2",
                error_type_class(error.type)
              ]}>
                <%= format_error_type(error.type) %>
              </span>

              <!-- Line/column info -->
              <span :if={error.line} class="text-xs opacity-75">
                Line <%= error.line %><%= if error.column, do: ", Column #{error.column}" %>
              </span>

              <!-- Error message -->
              <div class="text-sm mt-1">
                <%= error.message %>
              </div>

              <!-- Path info (for semantic errors) -->
              <div :if={error.path && length(error.path) > 0} class="text-xs opacity-75 mt-1">
                Path: <%= Enum.join(error.path, " → ") %>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- Error summary -->
      <div class="text-sm opacity-75 mt-2">
        <%= length(@validation_result.errors) %> <%= if length(@validation_result.errors) == 1,
          do: "error",
          else: "errors" %> found
      </div>
    </div>
    """
  end

  @doc """
  Renders a compact error count badge.

  ## Examples

      <.error_count validation_result={@validation_result} />
  """
  attr :validation_result, ValidationResult, required: true

  def error_count(assigns) do
    ~H"""
    <span
      :if={not @validation_result.valid}
      class="badge badge-error badge-sm"
      title={"#{length(@validation_result.errors)} validation errors"}
    >
      <%= length(@validation_result.errors) %>
    </span>
    """
  end

  @doc """
  Renders error details in a collapsible section.

  ## Examples

      <.error_details validation_result={@validation_result} />
  """
  attr :validation_result, ValidationResult, required: true
  attr :id, :string, default: "error-details"

  def error_details(assigns) do
    ~H"""
    <div :if={not @validation_result.valid} class="collapse collapse-arrow bg-base-200 mt-2">
      <input type="checkbox" id={@id} />
      <div class="collapse-title text-sm font-medium">
        <span class="badge badge-error badge-sm mr-2">
          <%= length(@validation_result.errors) %>
        </span>
        Show error details
      </div>
      <div class="collapse-content">
        <div class="space-y-2 mt-2">
          <div :for={{error, idx} <- Enum.with_index(@validation_result.errors)} class="text-sm">
            <div class="font-semibold">
              Error <%= idx + 1 %>:
              <span class={["badge badge-xs ml-1", error_type_class(error.type)]}>
                <%= format_error_type(error.type) %>
              </span>
            </div>
            <div class="ml-4 mt-1">
              <div :if={error.line} class="text-xs opacity-75">
                Line <%= error.line %><%= if error.column, do: ", Column #{error.column}" %>
              </div>
              <div class="mt-1"><%= error.message %></div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Private helpers

  defp error_type_class(:syntax), do: "badge-error"
  defp error_type_class(:semantic), do: "badge-warning"
  defp error_type_class(:parser_crash), do: "badge-error"
  defp error_type_class(_), do: "badge-info"

  defp format_error_type(:syntax), do: "Syntax"
  defp format_error_type(:semantic), do: "Semantic"
  defp format_error_type(:parser_crash), do: "Parser Crash"
  defp format_error_type(type), do: type |> to_string() |> String.capitalize()
end
