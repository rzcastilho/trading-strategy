defmodule TradingStrategy.Strategies.DSL.RiskValidator do
  @moduledoc """
  Validates risk parameters in strategy DSL.

  Ensures risk management settings are:
  - Within valid ranges
  - Properly configured
  - Conservative (as recommended by constitution)
  """

  @doc """
  Validates risk parameters from strategy definition.

  ## Parameters
    - `strategy`: Map containing the full strategy with "risk_parameters" key

  ## Returns
    - `{:ok, strategy}` if validation passes
    - `{:error, errors}` where errors is a list of validation error messages

  ## Required Fields
    - `max_daily_loss`: Maximum daily loss as percentage (0.01 to 1.0)
    - `max_drawdown`: Maximum drawdown threshold (0.01 to 1.0)

  ## Optional Fields
    - `stop_loss_percentage`: Stop loss percentage below entry (0.01 to 1.0)
    - `take_profit_percentage`: Take profit percentage above entry (0.01 to 1.0)

  ## Examples

      iex> strategy = %{
      ...>   "risk_parameters" => %{
      ...>     "max_daily_loss" => 0.03,
      ...>     "max_drawdown" => 0.15
      ...>   }
      ...> }
      iex> RiskValidator.validate_risk_parameters(strategy)
      {:ok, strategy}
  """
  @spec validate_risk_parameters(map()) :: {:ok, map()} | {:error, list(String.t())}
  def validate_risk_parameters(%{"risk_parameters" => params} = strategy)
      when is_map(params) do
    errors =
      []
      |> validate_required_field(params, "max_daily_loss")
      |> validate_required_field(params, "max_drawdown")
      |> validate_optional_field(params, "stop_loss_percentage")
      |> validate_optional_field(params, "take_profit_percentage")
      |> validate_risk_conservativeness(params)

    case errors do
      [] -> {:ok, strategy}
      _ -> {:error, errors}
    end
  end

  def validate_risk_parameters(%{"risk_parameters" => _}) do
    {:error, ["Risk parameters must be a map"]}
  end

  def validate_risk_parameters(_) do
    {:error, ["Risk parameters are required"]}
  end

  # Private Functions

  defp validate_required_field(errors, params, field) do
    case Map.get(params, field) do
      nil ->
        ["Risk parameter '#{field}' is required" | errors]

      value when is_number(value) ->
        validate_percentage_range(errors, field, value)

      _ ->
        ["Risk parameter '#{field}' must be a number" | errors]
    end
  end

  defp validate_optional_field(errors, params, field) do
    case Map.get(params, field) do
      nil ->
        errors

      value when is_number(value) ->
        validate_percentage_range(errors, field, value)

      _ ->
        ["Risk parameter '#{field}' must be a number" | errors]
    end
  end

  defp validate_percentage_range(errors, field, value) do
    cond do
      value < 0.01 ->
        ["Risk parameter '#{field}' must be at least 0.01 (1%)" | errors]

      value > 1.0 ->
        ["Risk parameter '#{field}' cannot exceed 1.0 (100%)" | errors]

      true ->
        errors
    end
  end

  # Validates that risk parameters are conservative (per Constitution Principle III)
  defp validate_risk_conservativeness(errors, params) do
    max_daily_loss = Map.get(params, "max_daily_loss", 0)
    max_drawdown = Map.get(params, "max_drawdown", 0)

    cond do
      # Warn if total risk exposure seems high
      max_daily_loss + max_drawdown > 0.30 ->
        [
          "Warning: Combined max_daily_loss (#{format_pct(max_daily_loss)}) + max_drawdown (#{format_pct(max_drawdown)}) = #{format_pct(max_daily_loss + max_drawdown)}. " <>
            "Constitution recommends sum < 30% for conservative risk management"
          | errors
        ]

      # Warn if max_daily_loss is too aggressive
      max_daily_loss > 0.05 ->
        [
          "Warning: max_daily_loss of #{format_pct(max_daily_loss)} is aggressive. " <>
            "Consider reducing to 3-5% for better risk management"
          | errors
        ]

      true ->
        errors
    end
  end

  defp format_pct(value) when is_number(value) do
    "#{Float.round(value * 100, 1)}%"
  end

  defp format_pct(_), do: "N/A"
end
