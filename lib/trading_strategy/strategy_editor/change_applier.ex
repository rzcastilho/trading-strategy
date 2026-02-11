defmodule TradingStrategy.StrategyEditor.ChangeApplier do
  @moduledoc """
  Applies ChangeEvents to BuilderState structures.

  This module handles the actual modification of BuilderState based on
  ChangeEvent operations (add, remove, update indicators, conditions, etc.).

  ## Architecture

  - Immutable transformations: Always returns a new BuilderState
  - Path-based updates: Uses JSON-like path arrays to target nested fields
  - Type-safe: Validates operation types and paths before applying

  ## Usage

      builder_state = BuilderState.new()

      event = ChangeEvent.new(%{
        source: :builder,
        operation_type: :add_indicator,
        path: ["indicators"],
        delta: {nil, %Indicator{type: "rsi", name: "rsi_14", ...}}
      })

      {:ok, updated_state} = ChangeApplier.apply_change(builder_state, event)
  """

  alias TradingStrategy.StrategyEditor.{BuilderState, ChangeEvent}

  @doc """
  Apply a ChangeEvent to a BuilderState, returning the updated state.

  Returns {:ok, updated_state} or {:error, reason}.
  """
  def apply_change(%BuilderState{} = state, %ChangeEvent{} = event) do
    case event.operation_type do
      :add_indicator ->
        apply_add_indicator(state, event)

      :remove_indicator ->
        apply_remove_indicator(state, event)

      :update_indicator ->
        apply_update_indicator(state, event)

      :update_entry_condition ->
        apply_update_field(state, :entry_conditions, event)

      :update_exit_condition ->
        apply_update_field(state, :exit_conditions, event)

      :update_stop_condition ->
        apply_update_field(state, :stop_conditions, event)

      :update_position_sizing ->
        apply_update_field(state, :position_sizing, event)

      :update_risk_parameters ->
        apply_update_field(state, :risk_parameters, event)

      :update_dsl_text ->
        # DSL text changes require full re-parsing
        # This is handled by Synchronizer.dsl_to_builder
        {:ok, state}

      :full_replace ->
        # Full replacement (e.g., paste new strategy)
        apply_full_replace(state, event)

      _ ->
        {:error, {:unknown_operation, event.operation_type}}
    end
  end

  # Private Functions

  defp apply_add_indicator(state, event) do
    {_old, new_indicator} = event.delta
    updated_indicators = state.indicators ++ [new_indicator]

    {:ok, %BuilderState{state | indicators: updated_indicators}}
  end

  defp apply_remove_indicator(state, event) do
    case event.path do
      ["indicators", index] when is_integer(index) ->
        updated_indicators = List.delete_at(state.indicators, index)
        {:ok, %BuilderState{state | indicators: updated_indicators}}

      _ ->
        {:error, {:invalid_path, event.path}}
    end
  end

  defp apply_update_indicator(state, event) do
    case event.path do
      ["indicators", index | rest] when is_integer(index) ->
        case Enum.at(state.indicators, index) do
          nil ->
            {:error, {:indicator_not_found, index}}

          indicator ->
            updated_indicator = update_nested(indicator, rest, event.delta)
            updated_indicators = List.replace_at(state.indicators, index, updated_indicator)
            {:ok, %BuilderState{state | indicators: updated_indicators}}
        end

      _ ->
        {:error, {:invalid_path, event.path}}
    end
  end

  defp apply_update_field(state, field, event) do
    {_old, new_value} = event.delta
    {:ok, Map.put(state, field, new_value)}
  end

  defp apply_full_replace(state, event) do
    {_old, new_state} = event.delta

    case new_state do
      %BuilderState{} = new_builder_state ->
        {:ok, new_builder_state}

      _ ->
        {:error, {:invalid_replacement, "Expected BuilderState"}}
    end
  end

  # Helper to update nested fields in a struct/map
  defp update_nested(data, [], {_old, new_value}) do
    new_value
  end

  defp update_nested(data, [key | rest], delta) when is_map(data) do
    current_value = Map.get(data, String.to_existing_atom(key))
    updated_value = update_nested(current_value, rest, delta)
    Map.put(data, String.to_existing_atom(key), updated_value)
  end

  defp update_nested(data, [key | rest], delta) when is_struct(data) do
    current_value = Map.get(data, String.to_existing_atom(key))
    updated_value = update_nested(current_value, rest, delta)
    Map.put(data, String.to_existing_atom(key), updated_value)
  end

  defp update_nested(_data, _path, {_old, new_value}) do
    # Fallback: just use the new value
    new_value
  end
end
