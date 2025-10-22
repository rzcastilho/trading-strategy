defmodule TradingStrategy.ConditionEvaluator do
  @moduledoc """
  Evaluates trading conditions against market data and indicator values.

  Supports boolean logic (AND/OR/NOT), cross-indicator comparisons,
  and pattern matching.
  """

  @doc """
  Evaluates a condition tree against the current context.

  The context should contain:
  - `:indicators` - Map of indicator names to their current values
  - `:historical_indicators` - Map of indicator names to their historical values (for cross detection)
  - `:candles` - Current and recent candle data
  - `:patterns` - Detected patterns in current market data
  """
  def evaluate(condition, context)

  # Boolean Logic: AND
  def evaluate(%{type: :when_all, conditions: conditions}, context) do
    Enum.all?(conditions, fn cond -> evaluate(cond, context) end)
  end

  # Boolean Logic: OR
  def evaluate(%{type: :when_any, conditions: conditions}, context) do
    Enum.any?(conditions, fn cond -> evaluate(cond, context) end)
  end

  # Boolean Logic: NOT
  def evaluate(%{type: :when_not, condition: condition}, context) do
    not evaluate(condition, context)
  end

  # Cross Above: Check if indicator1 crosses above indicator2
  def evaluate(%{type: :cross_above, indicator1: ind1, indicator2: ind2}, context) do
    current_val1 = resolve_indicator_or_value(ind1, context)
    current_val2 = resolve_indicator_or_value(ind2, context)
    previous_val1 = resolve_previous_indicator_or_value(ind1, context)
    previous_val2 = resolve_previous_indicator_or_value(ind2, context)

    # Cross above: was below or equal, now above
    compare_values(previous_val1, previous_val2, :<=) and compare_values(current_val1, current_val2, :>)
  end

  # Cross Below: Check if indicator1 crosses below indicator2
  def evaluate(%{type: :cross_below, indicator1: ind1, indicator2: ind2}, context) do
    current_val1 = resolve_indicator_or_value(ind1, context)
    current_val2 = resolve_indicator_or_value(ind2, context)
    previous_val1 = resolve_previous_indicator_or_value(ind1, context)
    previous_val2 = resolve_previous_indicator_or_value(ind2, context)

    # Cross below: was above or equal, now below
    compare_values(previous_val1, previous_val2, :>=) and compare_values(current_val1, current_val2, :<)
  end

  # Pattern Match
  def evaluate(%{type: :pattern, name: pattern_name}, context) do
    patterns = Map.get(context, :patterns, [])
    pattern_name in patterns
  end

  # Comparison: Greater Than
  def evaluate({:>, _, [left, right]}, context) do
    compare_values(eval_value(left, context), eval_value(right, context), :>)
  end

  # Comparison: Greater Than or Equal
  def evaluate({:>=, _, [left, right]}, context) do
    compare_values(eval_value(left, context), eval_value(right, context), :>=)
  end

  # Comparison: Less Than
  def evaluate({:<, _, [left, right]}, context) do
    compare_values(eval_value(left, context), eval_value(right, context), :<)
  end

  # Comparison: Less Than or Equal
  def evaluate({:<=, _, [left, right]}, context) do
    compare_values(eval_value(left, context), eval_value(right, context), :<=)
  end

  # Comparison: Equal
  def evaluate({:==, _, [left, right]}, context) do
    compare_values(eval_value(left, context), eval_value(right, context), :==)
  end

  # Comparison: Not Equal
  def evaluate({:!=, _, [left, right]}, context) do
    compare_values(eval_value(left, context), eval_value(right, context), :!=)
  end

  # Literal boolean
  def evaluate(true, _context), do: true
  def evaluate(false, _context), do: false

  # Fallback
  def evaluate(_condition, _context), do: false

  @doc """
  Evaluates a value expression (for use in comparisons).
  """
  def eval_value(%{type: :indicator_ref} = ref, context) do
    get_indicator_value(ref, context)
  end

  def eval_value(value, _context) when is_number(value), do: value
  def eval_value(value, _context) when is_boolean(value), do: value

  # Support nested expressions
  def eval_value({op, _, [left, right]}, context) when op in [:+, :-, :*, :/] do
    left_val = eval_value(left, context)
    right_val = eval_value(right, context)
    apply(Kernel, op, [left_val, right_val])
  end

  def eval_value(value, _context), do: value

  @doc """
  Gets the current value of an indicator from the context.

  Supports both single-value indicators and component access for multi-value indicators.
  """
  def get_indicator_value(%{name: name, component: component}, context) do
    indicators = Map.get(context, :indicators, %{})
    value = Map.get(indicators, name)

    case value do
      # Component exists and is a Decimal
      %{^component => comp_value} when is_struct(comp_value, Decimal) ->
        comp_value

      # Component exists and is a number
      %{^component => comp_value} when is_number(comp_value) ->
        Decimal.new("#{comp_value}")

      # Value is a map but component doesn't exist
      map when is_map(map) and not is_struct(map, Decimal) ->
        available = Map.keys(map) |> Enum.map(&inspect/1) |> Enum.join(", ")

        raise ArgumentError, """
        Invalid component #{inspect(component)} for indicator #{inspect(name)}.
        Available components: #{available}

        Example usage: indicator(:#{name}, :#{Map.keys(map) |> List.first})
        """

      # Value is not a map (single-value indicator being accessed with component)
      _ ->
        raise ArgumentError, """
        Indicator #{inspect(name)} is not a multi-value indicator.
        Use indicator(:#{name}) instead of indicator(:#{name}, :#{component})
        """
    end
  end

  # Handle indicator ref maps without component (single-value indicators)
  def get_indicator_value(%{name: name} = _ref, context) do
    get_indicator_value(name, context)
  end

  def get_indicator_value(indicator_name, context) when is_atom(indicator_name) do
    indicators = Map.get(context, :indicators, %{})
    value = Map.get(indicators, indicator_name, 0.0)

    # Check if this is a multi-value indicator being accessed without component
    if is_map(value) and not is_struct(value, Decimal) do
      available = Map.keys(value) |> Enum.map(&inspect/1) |> Enum.join(", ")

      raise ArgumentError, """
      Indicator #{inspect(indicator_name)} returns multiple values: #{available}

      You must specify which component to use:
        indicator(:#{indicator_name}, :component_name)

      Example: indicator(:#{indicator_name}, :#{Map.keys(value) |> List.first})
      """
    end

    value
  end

  @doc """
  Gets the previous value of an indicator from the context.

  Supports both single-value indicators and component access for multi-value indicators.
  """
  def get_previous_indicator_value(%{name: name, component: component}, context) do
    historical = Map.get(context, :historical_indicators, %{})
    values = Map.get(historical, name, [])

    case values do
      [prev | _] when is_map(prev) ->
        # Multi-value indicator - extract component
        case Map.get(prev, component) do
          nil ->
            0.0

          comp_value when is_struct(comp_value, Decimal) ->
            comp_value

          comp_value when is_number(comp_value) ->
            Decimal.new("#{comp_value}")

          _ ->
            0.0
        end

      [prev | _] ->
        # Single value
        prev

      [] ->
        0.0
    end
  end

  # Handle indicator ref maps without component (single-value indicators)
  def get_previous_indicator_value(%{name: name} = _ref, context) do
    get_previous_indicator_value(name, context)
  end

  def get_previous_indicator_value(indicator_name, context) when is_atom(indicator_name) do
    historical = Map.get(context, :historical_indicators, %{})
    values = Map.get(historical, indicator_name, [])

    case values do
      [prev | _] -> prev
      [] -> 0.0
    end
  end

  @doc """
  Builds an evaluation context from market data and calculated indicators.
  """
  def build_context(market_data, indicator_values, opts \\ []) do
    %{
      indicators: indicator_values,
      historical_indicators: Keyword.get(opts, :historical_indicators, %{}),
      candles: market_data,
      patterns: Keyword.get(opts, :patterns, []),
      timestamp: Keyword.get(opts, :timestamp, DateTime.utc_now())
    }
  end

  # Helper functions for cross detection

  defp resolve_indicator_or_value(%{type: :indicator_ref} = ref, context) do
    get_indicator_value(ref, context)
  end

  defp resolve_indicator_or_value(indicator_name, context) when is_atom(indicator_name) do
    get_indicator_value(indicator_name, context)
  end

  defp resolve_previous_indicator_or_value(%{type: :indicator_ref} = ref, context) do
    get_previous_indicator_value(ref, context)
  end

  defp resolve_previous_indicator_or_value(indicator_name, context)
       when is_atom(indicator_name) do
    get_previous_indicator_value(indicator_name, context)
  end

  # Compare two values, handling Decimal comparisons properly
  defp compare_values(left, right, op) do
    # Convert to comparable values
    left_val = to_comparable(left)
    right_val = to_comparable(right)

    case op do
      :> -> left_val > right_val
      :>= -> left_val >= right_val
      :< -> left_val < right_val
      :<= -> left_val <= right_val
      :== -> left_val == right_val
      :!= -> left_val != right_val
    end
  end

  # Convert Decimal to float for comparison, leave other types as-is
  defp to_comparable(%Decimal{} = decimal), do: Decimal.to_float(decimal)
  defp to_comparable(value) when is_number(value), do: value
  defp to_comparable(value), do: value
end
