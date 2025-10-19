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
    current_val1 = get_indicator_value(ind1, context)
    current_val2 = get_indicator_value(ind2, context)
    previous_val1 = get_previous_indicator_value(ind1, context)
    previous_val2 = get_previous_indicator_value(ind2, context)

    # Cross above: was below, now above
    previous_val1 <= previous_val2 and current_val1 > current_val2
  end

  # Cross Below: Check if indicator1 crosses below indicator2
  def evaluate(%{type: :cross_below, indicator1: ind1, indicator2: ind2}, context) do
    current_val1 = get_indicator_value(ind1, context)
    current_val2 = get_indicator_value(ind2, context)
    previous_val1 = get_previous_indicator_value(ind1, context)
    previous_val2 = get_previous_indicator_value(ind2, context)

    # Cross below: was above, now below
    previous_val1 >= previous_val2 and current_val1 < current_val2
  end

  # Pattern Match
  def evaluate(%{type: :pattern, name: pattern_name}, context) do
    patterns = Map.get(context, :patterns, [])
    pattern_name in patterns
  end

  # Comparison: Greater Than
  def evaluate({:>, _, [left, right]}, context) do
    eval_value(left, context) > eval_value(right, context)
  end

  # Comparison: Greater Than or Equal
  def evaluate({:>=, _, [left, right]}, context) do
    eval_value(left, context) >= eval_value(right, context)
  end

  # Comparison: Less Than
  def evaluate({:<, _, [left, right]}, context) do
    eval_value(left, context) < eval_value(right, context)
  end

  # Comparison: Less Than or Equal
  def evaluate({:<=, _, [left, right]}, context) do
    eval_value(left, context) <= eval_value(right, context)
  end

  # Comparison: Equal
  def evaluate({:==, _, [left, right]}, context) do
    eval_value(left, context) == eval_value(right, context)
  end

  # Comparison: Not Equal
  def evaluate({:!=, _, [left, right]}, context) do
    eval_value(left, context) != eval_value(right, context)
  end

  # Literal boolean
  def evaluate(true, _context), do: true
  def evaluate(false, _context), do: false

  # Fallback
  def evaluate(_condition, _context), do: false

  @doc """
  Evaluates a value expression (for use in comparisons).
  """
  def eval_value(%{type: :indicator_ref, name: name}, context) do
    get_indicator_value(name, context)
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
  """
  def get_indicator_value(indicator_name, context) do
    indicators = Map.get(context, :indicators, %{})
    Map.get(indicators, indicator_name, 0.0)
  end

  @doc """
  Gets the previous value of an indicator from the context.
  """
  def get_previous_indicator_value(indicator_name, context) do
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
end
