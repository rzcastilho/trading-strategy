defmodule TradingStrategy.Strategies.DSL.Validator do
  @moduledoc """
  Main DSL validator that coordinates all validation steps for strategy definitions.

  Validates:
  - Required fields presence
  - Field types and formats
  - Indicator definitions
  - Entry/exit/stop conditions
  - Position sizing configuration
  - Risk parameters

  Returns detailed error messages for debugging.
  """

  alias TradingStrategy.Strategies.DSL.{
    IndicatorValidator,
    EntryConditionValidator,
    ExitConditionValidator,
    RiskValidator
  }

  @required_fields [
    "name",
    "trading_pair",
    "timeframe",
    "indicators",
    "entry_conditions",
    "exit_conditions",
    "stop_conditions",
    "position_sizing",
    "risk_parameters"
  ]

  @valid_timeframes ["1m", "5m", "15m", "1h", "4h", "1d"]

  @doc """
  Validates a complete strategy definition.

  Performs all validation checks in order:
  1. Required fields
  2. Basic field formats
  3. Indicator definitions
  4. Condition expressions
  5. Risk parameters

  ## Parameters
    - `strategy`: Map containing parsed strategy definition

  ## Returns
    - `{:ok, strategy}` if all validations pass
    - `{:error, errors}` where errors is a list of validation error messages

  ## Examples

      iex> strategy = %{
      ...>   "name" => "Test Strategy",
      ...>   "trading_pair" => "BTC/USD",
      ...>   "timeframe" => "1h",
      ...>   "indicators" => [%{"type" => "rsi", "name" => "rsi_14", "parameters" => %{"period" => 14}}],
      ...>   "entry_conditions" => "rsi_14 < 30",
      ...>   "exit_conditions" => "rsi_14 > 70",
      ...>   "stop_conditions" => "rsi_14 < 25",
      ...>   "position_sizing" => %{"type" => "percentage", "percentage_of_capital" => 0.10},
      ...>   "risk_parameters" => %{"max_daily_loss" => 0.03, "max_drawdown" => 0.15}
      ...> }
      iex> Validator.validate(strategy)
      {:ok, strategy}
  """
  @spec validate(map()) :: {:ok, map()} | {:error, list(String.t())}
  def validate(strategy) when is_map(strategy) do
    with {:ok, _} <- validate_required_fields(strategy),
         {:ok, _} <- validate_name(strategy),
         {:ok, _} <- validate_trading_pair(strategy),
         {:ok, _} <- validate_timeframe(strategy),
         {:ok, _} <- IndicatorValidator.validate_indicators(strategy),
         {:ok, _} <- validate_conditions(strategy),
         {:ok, _} <- validate_position_sizing(strategy),
         {:ok, _} <- RiskValidator.validate_risk_parameters(strategy) do
      {:ok, strategy}
    else
      {:error, errors} when is_list(errors) ->
        {:error, errors}

      {:error, error} ->
        {:error, [error]}
    end
  end

  def validate(_) do
    {:error, ["Strategy must be a map"]}
  end

  # Private validation functions

  defp validate_required_fields(strategy) do
    missing_fields =
      Enum.filter(@required_fields, fn field ->
        not Map.has_key?(strategy, field) or is_nil(strategy[field])
      end)

    case missing_fields do
      [] ->
        {:ok, strategy}

      fields ->
        {:error, ["Missing required fields: #{Enum.join(fields, ", ")}"]}
    end
  end

  defp validate_name(%{"name" => name}) when is_binary(name) do
    cond do
      String.length(name) < 1 ->
        {:error, ["Name must be at least 1 character"]}

      String.length(name) > 100 ->
        {:error, ["Name must be at most 100 characters"]}

      true ->
        {:ok, name}
    end
  end

  defp validate_name(_) do
    {:error, ["Name must be a string"]}
  end

  defp validate_trading_pair(%{"trading_pair" => pair}) when is_binary(pair) do
    case String.split(pair, "/") do
      [base, quote] when byte_size(base) > 0 and byte_size(quote) > 0 ->
        {:ok, pair}

      _ ->
        {:error, ["Trading pair must be in format 'BASE/QUOTE' (e.g., 'BTC/USD')"]}
    end
  end

  defp validate_trading_pair(_) do
    {:error, ["Trading pair must be a string"]}
  end

  defp validate_timeframe(%{"timeframe" => timeframe}) when timeframe in @valid_timeframes do
    {:ok, timeframe}
  end

  defp validate_timeframe(%{"timeframe" => timeframe}) do
    {:error,
     [
       "Invalid timeframe '#{timeframe}'. Must be one of: #{Enum.join(@valid_timeframes, ", ")}"
     ]}
  end

  defp validate_timeframe(_) do
    {:error, ["Timeframe must be a string"]}
  end

  defp validate_conditions(strategy) do
    errors =
      []
      |> validate_entry_conditions(strategy)
      |> validate_exit_conditions(strategy)
      |> validate_stop_conditions(strategy)

    case errors do
      [] -> {:ok, strategy}
      _ -> {:error, errors}
    end
  end

  defp validate_entry_conditions(errors, %{
         "entry_conditions" => conditions,
         "indicators" => indicators
       }) do
    case EntryConditionValidator.validate(conditions, indicators) do
      {:ok, _} -> errors
      {:error, error} when is_binary(error) -> [error | errors]
      {:error, error_list} when is_list(error_list) -> error_list ++ errors
    end
  end

  defp validate_entry_conditions(errors, _), do: ["Entry conditions validation failed" | errors]

  defp validate_exit_conditions(errors, %{
         "exit_conditions" => conditions,
         "indicators" => indicators
       }) do
    case ExitConditionValidator.validate(conditions, indicators) do
      {:ok, _} -> errors
      {:error, error} when is_binary(error) -> [error | errors]
      {:error, error_list} when is_list(error_list) -> error_list ++ errors
    end
  end

  defp validate_exit_conditions(errors, _), do: ["Exit conditions validation failed" | errors]

  defp validate_stop_conditions(errors, %{
         "stop_conditions" => conditions,
         "indicators" => indicators
       }) do
    case ExitConditionValidator.validate(conditions, indicators) do
      {:ok, _} -> errors
      {:error, error} when is_binary(error) -> [error | errors]
      {:error, error_list} when is_list(error_list) -> error_list ++ errors
    end
  end

  defp validate_stop_conditions(errors, _), do: ["Stop conditions validation failed" | errors]

  defp validate_position_sizing(%{"position_sizing" => sizing}) when is_map(sizing) do
    case Map.get(sizing, "type") do
      "percentage" ->
        validate_percentage_sizing(sizing)

      "fixed_amount" ->
        validate_fixed_amount_sizing(sizing)

      "risk_based" ->
        validate_risk_based_sizing(sizing)

      nil ->
        {:error, ["Position sizing type is required"]}

      type ->
        {:error,
         [
           "Invalid position sizing type '#{type}'. Must be: percentage, fixed_amount, or risk_based"
         ]}
    end
  end

  defp validate_position_sizing(_) do
    {:error, ["Position sizing must be a map"]}
  end

  defp validate_percentage_sizing(sizing) do
    errors =
      []
      |> validate_percentage_field(sizing, "percentage_of_capital", 0.01, 1.0)
      |> validate_percentage_field(sizing, "max_position_size", 0.01, 1.0, false)

    case errors do
      [] -> {:ok, sizing}
      _ -> {:error, errors}
    end
  end

  defp validate_fixed_amount_sizing(sizing) do
    case Map.get(sizing, "fixed_amount") do
      amount when is_number(amount) and amount > 0 ->
        {:ok, sizing}

      nil ->
        {:error, ["Fixed amount is required for fixed_amount sizing type"]}

      _ ->
        {:error, ["Fixed amount must be a positive number"]}
    end
  end

  defp validate_risk_based_sizing(sizing) do
    {:ok, sizing}
  end

  defp validate_percentage_field(errors, map, field, min, max, required \\ true) do
    case Map.get(map, field) do
      nil when required ->
        ["#{field} is required" | errors]

      nil ->
        errors

      value when is_number(value) ->
        cond do
          value < min ->
            ["#{field} must be at least #{min}" | errors]

          value > max ->
            ["#{field} must be at most #{max}" | errors]

          true ->
            errors
        end

      _ ->
        ["#{field} must be a number" | errors]
    end
  end
end
