defmodule TradingStrategy.Strategies.DSL.ExitConditionValidator do
  @moduledoc """
  Validates exit and stop condition expressions in strategy DSL.

  Reuses the same validation logic as entry conditions since the syntax is identical.
  Exit/stop conditions can reference:
  - Indicator values
  - Market data (close, open, high, low, volume)
  - Position-specific variables (unrealized_pnl, unrealized_pnl_pct, drawdown)
  """

  alias TradingStrategy.Strategies.DSL.EntryConditionValidator

  @position_variables ["unrealized_pnl", "unrealized_pnl_pct", "drawdown", "position_age"]

  @doc """
  Validates exit conditions against the defined indicators.

  ## Parameters
    - `conditions`: String expression for exit conditions
    - `indicators`: List of indicator definitions from strategy

  ## Returns
    - `{:ok, conditions}` if validation passes
    - `{:error, error_message}` if validation fails

  ## Examples

      iex> indicators = [%{"name" => "rsi_14", "type" => "rsi"}]
      iex> ExitConditionValidator.validate("rsi_14 > 70", indicators)
      {:ok, "rsi_14 > 70"}

      iex> indicators = [%{"name" => "rsi_14", "type" => "rsi"}]
      iex> ExitConditionValidator.validate("unrealized_pnl_pct > 0.10", indicators)
      {:ok, "unrealized_pnl_pct > 0.10"}
  """
  @spec validate(String.t(), list(map())) :: {:ok, String.t()} | {:error, String.t()}
  def validate(conditions, indicators) when is_binary(conditions) and is_list(indicators) do
    # Exit conditions can reference indicators + position-specific variables
    indicator_names = Enum.map(indicators, & &1["name"])

    # First validate using the entry condition validator logic
    case EntryConditionValidator.validate(conditions, indicators) do
      {:ok, _} ->
        {:ok, conditions}

      # If it failed, check if it's because of position variables (which are valid for exit/stop)
      {:error, error_msg} ->
        if String.contains?(error_msg, "Undefined variable") do
          validate_with_position_variables(conditions, indicator_names)
        else
          {:error, String.replace(error_msg, "entry conditions", "exit/stop conditions")}
        end
    end
  end

  def validate(conditions, _indicators) when not is_binary(conditions) do
    {:error, "Exit/stop conditions must be a string"}
  end

  def validate(_conditions, _indicators) do
    {:error, "Indicators must be a list"}
  end

  # Private Functions

  defp validate_with_position_variables(conditions, indicator_names) do
    # Extract all variables
    variables =
      Regex.scan(~r/[a-zA-Z_][a-zA-Z0-9_]*/, conditions)
      |> List.flatten()
      |> Enum.uniq()
      |> Enum.reject(&operator_keyword?/1)

    reserved_variables = ["close", "open", "high", "low", "volume"]
    allowed_variables = reserved_variables ++ indicator_names ++ @position_variables
    undefined_variables = variables -- allowed_variables

    case undefined_variables do
      [] ->
        {:ok, conditions}

      [var] ->
        {:error, "Undefined variable in exit/stop conditions: #{var}"}

      vars ->
        {:error, "Undefined variables in exit/stop conditions: #{Enum.join(vars, ", ")}"}
    end
  end

  defp operator_keyword?(word) do
    String.upcase(word) in ["AND", "OR", "NOT"]
  end
end
