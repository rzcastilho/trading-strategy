defmodule TradingStrategy.Strategies.ConditionParser do
  @moduledoc """
  Parses and evaluates trading signal conditions from DSL expressions.

  Supports comparison operators (>, <, >=, <=, ==, !=) and logical operators (AND, OR, NOT).
  Evaluates conditions against indicator values and reserved variables (open, high, low, close, volume).

  ## Examples

      iex> condition = "rsi_14 < 30 AND close > sma_50"
      iex> context = %{"rsi_14" => 25, "sma_50" => 42000, "close" => 42100}
      iex> ConditionParser.evaluate(condition, context)
      {:ok, true}
  """

  require Logger

  # Reserved variable names that are always available
  @reserved_variables ~w(open high low close volume timestamp price)

  @doc """
  Parses a condition string into an abstract syntax tree (AST).

  ## Parameters
    - `condition`: Condition string (e.g., "rsi_14 < 30")

  ## Returns
    - `{:ok, ast}` - Parsed AST
    - `{:error, reason}` - Parse error

  ## Examples

      iex> ConditionParser.parse("rsi_14 < 30")
      {:ok, {:less_than, {:variable, "rsi_14"}, {:literal, 30}}}
  """
  @spec parse(String.t()) :: {:ok, term()} | {:error, String.t()}
  def parse(condition) when is_binary(condition) do
    condition
    |> String.trim()
    |> tokenize()
    |> build_ast()
  rescue
    error ->
      {:error, "Failed to parse condition: #{Exception.message(error)}"}
  end

  @doc """
  Evaluates a parsed condition AST against a context.

  ## Parameters
    - `condition`: Condition string or AST
    - `context`: Map of variable_name => value

  ## Returns
    - `{:ok, boolean}` - Evaluation result
    - `{:error, reason}` - Evaluation error

  ## Examples

      iex> ConditionParser.evaluate("rsi_14 < 30", %{"rsi_14" => 25})
      {:ok, true}
  """
  @spec evaluate(String.t() | term(), map()) :: {:ok, boolean()} | {:error, String.t()}
  def evaluate(condition, context) when is_binary(condition) do
    with {:ok, ast} <- parse(condition) do
      evaluate_ast(ast, context)
    end
  end

  def evaluate(ast, context) when is_tuple(ast) do
    evaluate_ast(ast, context)
  end

  @doc """
  Validates that all variables in a condition are defined.

  Checks that variables reference either:
  - Reserved variables (open, high, low, close, volume)
  - Indicators defined in the strategy

  ## Parameters
    - `condition`: Condition string
    - `defined_indicators`: List of indicator names

  ## Returns
    - `:ok` - All variables are defined
    - `{:error, undefined}` - List of undefined variables

  ## Examples

      iex> ConditionParser.validate_variables("rsi_14 < 30", ["rsi_14"])
      :ok

      iex> ConditionParser.validate_variables("unknown < 30", ["rsi_14"])
      {:error, ["Undefined variable: unknown"]}
  """
  @spec validate_variables(String.t(), list(String.t())) ::
          :ok | {:error, list(String.t())}
  def validate_variables(condition, defined_indicators) when is_binary(condition) do
    with {:ok, ast} <- parse(condition) do
      variables = extract_variables(ast)
      defined_set = MapSet.new(defined_indicators ++ @reserved_variables)
      undefined = Enum.reject(variables, &MapSet.member?(defined_set, &1))

      case undefined do
        [] -> :ok
        vars -> {:error, Enum.map(vars, fn var -> "Undefined variable: #{var}" end)}
      end
    end
  end

  # Private Functions - Tokenization

  defp tokenize(condition) do
    # Replace operators with tokens
    condition
    |> String.replace(">=", " >= ")
    |> String.replace("<=", " <= ")
    |> String.replace("!=", " != ")
    |> String.replace("==", " == ")
    |> String.replace(">", " > ")
    |> String.replace("<", " < ")
    |> String.replace("(", " ( ")
    |> String.replace(")", " ) ")
    |> String.split()
    |> Enum.reject(&(&1 == ""))
  end

  # Private Functions - AST Building

  defp build_ast(tokens) do
    case parse_or_expression(tokens) do
      {ast, []} -> {:ok, ast}
      {_ast, remaining} -> {:error, "Unexpected tokens: #{inspect(remaining)}"}
      {:error, _} = error -> error
    end
  end

  # Parse OR expressions (lowest precedence)
  defp parse_or_expression(tokens) do
    case parse_and_expression(tokens) do
      {left, ["OR" | rest]} ->
        {right, remaining} = parse_or_expression(rest)
        {{:or, left, right}, remaining}

      {left, ["||" | rest]} ->
        {right, remaining} = parse_or_expression(rest)
        {{:or, left, right}, remaining}

      result ->
        result
    end
  end

  # Parse AND expressions
  defp parse_and_expression(tokens) do
    case parse_not_expression(tokens) do
      {left, ["AND" | rest]} ->
        {right, remaining} = parse_and_expression(rest)
        {{:and, left, right}, remaining}

      {left, ["&&" | rest]} ->
        {right, remaining} = parse_and_expression(rest)
        {{:and, left, right}, remaining}

      result ->
        result
    end
  end

  # Parse NOT expressions
  defp parse_not_expression(["NOT" | tokens]) do
    {expr, remaining} = parse_comparison_expression(tokens)
    {{:not, expr}, remaining}
  end

  defp parse_not_expression(["!" | tokens]) do
    {expr, remaining} = parse_comparison_expression(tokens)
    {{:not, expr}, remaining}
  end

  defp parse_not_expression(tokens) do
    parse_comparison_expression(tokens)
  end

  # Parse comparison expressions (>, <, ==, etc.)
  defp parse_comparison_expression(tokens) do
    {left, rest} = parse_primary_expression(tokens)

    case rest do
      [op | remaining] when op in ["<", ">", "<=", ">=", "==", "!="] ->
        {right, final} = parse_primary_expression(remaining)
        operator = comparison_operator(op)
        {{operator, left, right}, final}

      _ ->
        {left, rest}
    end
  end

  defp comparison_operator("<"), do: :less_than
  defp comparison_operator(">"), do: :greater_than
  defp comparison_operator("<="), do: :less_than_or_equal
  defp comparison_operator(">="), do: :greater_than_or_equal
  defp comparison_operator("=="), do: :equal
  defp comparison_operator("!="), do: :not_equal

  # Parse primary expressions (literals, variables, parentheses)
  defp parse_primary_expression(["(" | tokens]) do
    {expr, [")" | remaining]} = parse_or_expression(tokens)
    {expr, remaining}
  end

  defp parse_primary_expression([token | remaining]) do
    cond do
      # Number literal
      is_number_token?(token) ->
        {{:literal, parse_number(token)}, remaining}

      # Boolean literal
      token in ["true", "false"] ->
        {{:literal, token == "true"}, remaining}

      # Variable reference
      true ->
        {{:variable, token}, remaining}
    end
  end

  defp is_number_token?(token) do
    case Float.parse(token) do
      {_num, ""} -> true
      _ -> false
    end
  end

  defp parse_number(token) do
    case Integer.parse(token) do
      {int, ""} -> int
      _ -> String.to_float(token)
    end
  end

  # Private Functions - AST Evaluation

  defp evaluate_ast({:or, left, right}, context) do
    with {:ok, left_val} <- evaluate_ast(left, context),
         {:ok, right_val} <- evaluate_ast(right, context) do
      {:ok, left_val or right_val}
    end
  end

  defp evaluate_ast({:and, left, right}, context) do
    with {:ok, left_val} <- evaluate_ast(left, context),
         {:ok, right_val} <- evaluate_ast(right, context) do
      {:ok, left_val and right_val}
    end
  end

  defp evaluate_ast({:not, expr}, context) do
    with {:ok, val} <- evaluate_ast(expr, context) do
      {:ok, not val}
    end
  end

  defp evaluate_ast({:less_than, left, right}, context) do
    with {:ok, left_val} <- evaluate_ast(left, context),
         {:ok, right_val} <- evaluate_ast(right, context) do
      {:ok, compare(left_val, right_val) == :lt}
    end
  end

  defp evaluate_ast({:greater_than, left, right}, context) do
    with {:ok, left_val} <- evaluate_ast(left, context),
         {:ok, right_val} <- evaluate_ast(right, context) do
      {:ok, compare(left_val, right_val) == :gt}
    end
  end

  defp evaluate_ast({:less_than_or_equal, left, right}, context) do
    with {:ok, left_val} <- evaluate_ast(left, context),
         {:ok, right_val} <- evaluate_ast(right, context) do
      result = compare(left_val, right_val)
      {:ok, result == :lt or result == :eq}
    end
  end

  defp evaluate_ast({:greater_than_or_equal, left, right}, context) do
    with {:ok, left_val} <- evaluate_ast(left, context),
         {:ok, right_val} <- evaluate_ast(right, context) do
      result = compare(left_val, right_val)
      {:ok, result == :gt or result == :eq}
    end
  end

  defp evaluate_ast({:equal, left, right}, context) do
    with {:ok, left_val} <- evaluate_ast(left, context),
         {:ok, right_val} <- evaluate_ast(right, context) do
      {:ok, compare(left_val, right_val) == :eq}
    end
  end

  defp evaluate_ast({:not_equal, left, right}, context) do
    with {:ok, left_val} <- evaluate_ast(left, context),
         {:ok, right_val} <- evaluate_ast(right, context) do
      {:ok, compare(left_val, right_val) != :eq}
    end
  end

  defp evaluate_ast({:literal, value}, _context) do
    {:ok, value}
  end

  defp evaluate_ast({:variable, name}, context) do
    case Map.get(context, name) do
      nil ->
        {:error, "Variable '#{name}' not found in context"}

      value ->
        {:ok, normalize_value(value)}
    end
  end

  # Helper to compare values (handles Decimal, numbers, etc.)
  defp compare(left, right) do
    left_norm = to_comparable(left)
    right_norm = to_comparable(right)

    cond do
      left_norm < right_norm -> :lt
      left_norm > right_norm -> :gt
      true -> :eq
    end
  end

  defp to_comparable(%Decimal{} = d), do: Decimal.to_float(d)
  defp to_comparable(n) when is_number(n), do: n / 1.0
  defp to_comparable(other), do: other

  defp normalize_value(%Decimal{} = d), do: Decimal.to_float(d)
  defp normalize_value(value), do: value

  # Private Functions - Variable Extraction

  defp extract_variables({:variable, name}), do: [name]
  defp extract_variables({:literal, _}), do: []

  defp extract_variables({_op, left, right}) do
    extract_variables(left) ++ extract_variables(right)
  end

  defp extract_variables({_op, expr}) do
    extract_variables(expr)
  end
end
