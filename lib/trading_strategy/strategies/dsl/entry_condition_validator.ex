defmodule TradingStrategy.Strategies.DSL.EntryConditionValidator do
  @moduledoc """
  Validates entry condition expressions in strategy DSL.

  Ensures:
  - Condition syntax is valid
  - All referenced indicators exist
  - Operators are supported
  - Condition can be evaluated
  """

  @supported_operators ["<", ">", "<=", ">=", "==", "!=", "AND", "OR", "and", "or"]
  @reserved_variables ["close", "open", "high", "low", "volume"]

  @doc """
  Validates entry conditions against the defined indicators.

  ## Parameters
    - `conditions`: String expression for entry conditions
    - `indicators`: List of indicator definitions from strategy

  ## Returns
    - `{:ok, conditions}` if validation passes
    - `{:error, error_message}` if validation fails

  ## Examples

      iex> indicators = [%{"name" => "rsi_14", "type" => "rsi"}]
      iex> EntryConditionValidator.validate("rsi_14 < 30", indicators)
      {:ok, "rsi_14 < 30"}

      iex> indicators = [%{"name" => "rsi_14", "type" => "rsi"}]
      iex> EntryConditionValidator.validate("unknown_indicator < 30", indicators)
      {:error, "Undefined variable in entry conditions: unknown_indicator"}
  """
  @spec validate(String.t(), list(map())) :: {:ok, String.t()} | {:error, String.t()}
  def validate(conditions, indicators) when is_binary(conditions) and is_list(indicators) do
    indicator_names = Enum.map(indicators, & &1["name"])

    with :ok <- validate_syntax(conditions),
         :ok <- validate_variables(conditions, indicator_names) do
      {:ok, conditions}
    end
  end

  def validate(conditions, _indicators) when not is_binary(conditions) do
    {:error, "Entry conditions must be a string"}
  end

  def validate(_conditions, _indicators) do
    {:error, "Indicators must be a list"}
  end

  # Private Functions

  defp validate_syntax(conditions) do
    # Basic syntax validation:
    # 1. Check for balanced parentheses
    # 2. Check for valid operators
    # 3. Check for empty conditions

    cond do
      String.trim(conditions) == "" ->
        {:error, "Entry conditions cannot be empty"}

      not balanced_parentheses?(conditions) ->
        {:error, "Unbalanced parentheses in entry conditions"}

      not valid_operators?(conditions) ->
        {:error,
         "Invalid operators in entry conditions. Supported: #{Enum.join(@supported_operators, ", ")}"}

      true ->
        :ok
    end
  end

  defp validate_variables(conditions, indicator_names) do
    # Extract all potential variable names from the condition string
    # Variables are alphanumeric+underscore sequences that aren't numbers
    variables =
      Regex.scan(~r/[a-zA-Z_][a-zA-Z0-9_]*/, conditions)
      |> List.flatten()
      |> Enum.uniq()
      |> Enum.reject(&operator_keyword?/1)

    allowed_variables = @reserved_variables ++ indicator_names
    undefined_variables = variables -- allowed_variables

    case undefined_variables do
      [] ->
        :ok

      [var] ->
        {:error, "Undefined variable in entry conditions: #{var}"}

      vars ->
        {:error, "Undefined variables in entry conditions: #{Enum.join(vars, ", ")}"}
    end
  end

  defp balanced_parentheses?(str) do
    str
    |> String.graphemes()
    |> Enum.reduce(0, fn
      "(", acc -> acc + 1
      ")", acc -> acc - 1
      _, acc -> acc
    end)
    |> Kernel.==(0)
  end

  defp valid_operators?(conditions) do
    # Check that we don't have obvious syntax errors with operators
    # This is a simplified check - full validation happens at runtime
    not String.contains?(conditions, ["<<", ">>", "===", "!=="])
  end

  defp operator_keyword?(word) do
    String.upcase(word) in ["AND", "OR", "NOT"]
  end
end
