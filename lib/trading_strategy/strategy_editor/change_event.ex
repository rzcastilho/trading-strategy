defmodule TradingStrategy.StrategyEditor.ChangeEvent do
  @moduledoc """
  Immutable event representing a single change in the editor.

  Both builder and DSL changes emit ChangeEvents into a shared timeline.
  These events are used for undo/redo functionality.
  """

  defstruct [
    :id,
    :session_id,
    :timestamp,
    :source,
    :operation_type,
    :path,
    :delta,
    :inverse,
    :user_id,
    :version
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          session_id: String.t(),
          timestamp: integer(),
          source: :builder | :dsl,
          operation_type: operation_type(),
          path: [String.t() | integer()],
          delta: {any(), any()},
          inverse: {any(), any()},
          user_id: integer() | nil,
          version: integer()
        }

  @type operation_type ::
          :add_indicator
          | :remove_indicator
          | :update_indicator
          | :update_entry_condition
          | :update_exit_condition
          | :update_stop_condition
          | :update_position_sizing
          | :update_risk_parameters
          | :update_dsl_text
          | :full_replace

  @doc """
  Create a new ChangeEvent from a builder or DSL modification.

  ## Examples

      iex> ChangeEvent.new(%{
      ...>   session_id: "session-123",
      ...>   source: :builder,
      ...>   operation_type: :update_indicator,
      ...>   path: ["indicators", 0, "parameters", "period"],
      ...>   delta: {14, 21},
      ...>   user_id: 1
      ...> })
      %ChangeEvent{...}
  """
  def new(attrs) do
    %__MODULE__{
      id: generate_id(),
      session_id: attrs[:session_id],
      timestamp: System.monotonic_time(:millisecond),
      source: attrs[:source],
      operation_type: attrs[:operation_type],
      path: attrs[:path] || [],
      delta: attrs[:delta],
      inverse: invert_delta(attrs[:delta]),
      user_id: attrs[:user_id],
      version: attrs[:version] || 1
    }
  end

  @doc """
  Create the inverse event for undo functionality.

  ## Examples

      iex> event = ChangeEvent.new(%{...})
      iex> ChangeEvent.undo_event(event)
      %ChangeEvent{delta: {new, old}, inverse: {old, new}}
  """
  def undo_event(%__MODULE__{} = event) do
    %__MODULE__{
      event
      | id: generate_id(),
        timestamp: System.monotonic_time(:millisecond),
        delta: event.inverse,
        inverse: event.delta,
        version: event.version + 1
    }
  end

  @doc """
  Apply the change represented by this event to a BuilderState.
  Delegates to ChangeApplier module.
  """
  def apply(%__MODULE__{} = event, builder_state) do
    TradingStrategy.StrategyEditor.ChangeApplier.apply_change(builder_state, event)
  end

  # Private Functions

  defp generate_id do
    # Generate a simple unique ID (UUID would be better in production)
    :crypto.strong_rand_bytes(16) |> Base.encode64(padding: false)
  end

  defp invert_delta({old, new}), do: {new, old}
  defp invert_delta(nil), do: nil
end
