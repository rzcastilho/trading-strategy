defmodule TradingStrategy.Strategies.DSL.IndicatorValidator do
  @moduledoc """
  Validates indicator definitions in strategy DSL.

  Uses TradingIndicators.Behaviour.parameter_metadata/0 to dynamically validate:
  - Indicator type exists
  - Parameters match schema (type, min/max ranges, required fields)
  - Indicator names are unique within strategy
  """

  @doc """
  Validates all indicator definitions in a strategy.

  ## Parameters
    - `strategy`: Map containing the full strategy definition with "indicators" key

  ## Returns
    - `{:ok, strategy}` if all indicators are valid
    - `{:error, errors}` where errors is a list of validation error messages

  ## Examples

      iex> strategy = %{
      ...>   "indicators" => [
      ...>     %{"type" => "rsi", "name" => "rsi_14", "parameters" => %{"period" => 14}}
      ...>   ]
      ...> }
      iex> IndicatorValidator.validate_indicators(strategy)
      {:ok, strategy}
  """
  @spec validate_indicators(map()) :: {:ok, map()} | {:error, list(String.t())}
  def validate_indicators(%{"indicators" => indicators} = strategy) when is_list(indicators) do
    errors =
      []
      |> validate_indicator_list(indicators)
      |> validate_unique_names(indicators)

    case errors do
      [] -> {:ok, strategy}
      _ -> {:error, errors}
    end
  end

  def validate_indicators(%{"indicators" => _}) do
    {:error, ["Indicators must be a list"]}
  end

  def validate_indicators(_) do
    {:error, ["Indicators field is required"]}
  end

  # Private Functions

  defp validate_indicator_list(errors, indicators) do
    indicators
    |> Enum.with_index()
    |> Enum.reduce(errors, fn {indicator, index}, acc ->
      case validate_indicator(indicator) do
        :ok ->
          acc

        {:error, indicator_errors} ->
          prefixed_errors =
            indicator_errors
            |> List.wrap()
            |> Enum.map(fn err -> "Indicator #{index + 1}: #{err}" end)

          prefixed_errors ++ acc
      end
    end)
  end

  defp validate_indicator(indicator) when is_map(indicator) do
    with {:ok, _} <- validate_indicator_type(indicator),
         {:ok, _} <- validate_indicator_name(indicator),
         {:ok, _} <- validate_indicator_parameters(indicator) do
      :ok
    end
  end

  defp validate_indicator(_) do
    {:error, ["Indicator must be a map"]}
  end

  defp validate_indicator_type(%{"type" => type}) when is_binary(type) do
    case get_indicator_module(type) do
      {:ok, _module} ->
        {:ok, type}

      {:error, reason} ->
        {:error, [reason]}
    end
  end

  defp validate_indicator_type(%{"type" => _}) do
    {:error, ["Indicator type must be a string"]}
  end

  defp validate_indicator_type(_) do
    {:error, ["Indicator type is required"]}
  end

  defp validate_indicator_name(%{"name" => name}) when is_binary(name) do
    cond do
      String.length(name) < 1 ->
        {:error, ["Indicator name must be at least 1 character"]}

      String.length(name) > 50 ->
        {:error, ["Indicator name must be at most 50 characters"]}

      not String.match?(name, ~r/^[a-zA-Z0-9_]+$/) ->
        {:error, ["Indicator name must contain only alphanumeric characters and underscores"]}

      true ->
        {:ok, name}
    end
  end

  defp validate_indicator_name(%{"name" => _}) do
    {:error, ["Indicator name must be a string"]}
  end

  defp validate_indicator_name(_) do
    {:error, ["Indicator name is required"]}
  end

  defp validate_indicator_parameters(%{"type" => type, "parameters" => parameters})
       when is_map(parameters) do
    with {:ok, module} <- get_indicator_module(type) do
      validate_parameters_against_metadata(module, parameters)
    end
  end

  defp validate_indicator_parameters(%{"parameters" => _}) do
    {:error, ["Indicator parameters must be a map"]}
  end

  defp validate_indicator_parameters(_) do
    {:error, ["Indicator parameters are required"]}
  end

  defp validate_unique_names(errors, indicators) do
    names = Enum.map(indicators, & &1["name"])
    duplicates = names -- Enum.uniq(names)

    case Enum.uniq(duplicates) do
      [] ->
        errors

      dups ->
        ["Duplicate indicator names: #{Enum.join(dups, ", ")}" | errors]
    end
  end

  # Get the indicator module from TradingIndicators library
  defp get_indicator_module(type) when is_binary(type) do
    # Note: This will use the registry we build in the indicator_engine
    # For now, we'll use a simplified mapping
    indicator_map = %{
      "rsi" => TradingIndicators.Momentum.RSI,
      "macd" => TradingIndicators.Trend.MACD,
      "sma" => TradingIndicators.Trend.SMA,
      "ema" => TradingIndicators.Trend.EMA,
      "wma" => TradingIndicators.Trend.WMA,
      "hma" => TradingIndicators.Trend.HMA,
      "kama" => TradingIndicators.Trend.KAMA,
      "bb" => TradingIndicators.Volatility.BollingerBands,
      "bollinger_bands" => TradingIndicators.Volatility.BollingerBands,
      "atr" => TradingIndicators.Volatility.ATR,
      "std_dev" => TradingIndicators.Volatility.StandardDeviation,
      "volatility_index" => TradingIndicators.Volatility.VolatilityIndex,
      "obv" => TradingIndicators.Volume.OBV,
      "vwap" => TradingIndicators.Volume.VWAP,
      "ad_line" => TradingIndicators.Volume.ADLine,
      "cmf" => TradingIndicators.Volume.CMF,
      "stochastic" => TradingIndicators.Momentum.Stochastic,
      "williams_r" => TradingIndicators.Momentum.WilliamsR,
      "cci" => TradingIndicators.Momentum.CCI,
      "roc" => TradingIndicators.Momentum.ROC,
      "momentum" => TradingIndicators.Momentum.Momentum
    }

    case Map.get(indicator_map, String.downcase(type)) do
      nil ->
        available = Map.keys(indicator_map) |> Enum.sort() |> Enum.join(", ")

        {:error, "Unknown indicator type '#{type}'. Available indicators: #{available}"}

      module ->
        {:ok, module}
    end
  end

  # Validate parameters against the indicator's metadata schema
  defp validate_parameters_against_metadata(module, parameters) do
    # Get the parameter metadata from the indicator module
    metadata_result = module.parameter_metadata()

    # Convert to a map indexed by parameter name
    metadata_map =
      if is_list(metadata_result) do
        Enum.into(metadata_result, %{}, fn param_meta ->
          {param_meta.name, param_meta}
        end)
      else
        # If it's already a map, use it directly
        metadata_result
      end

    errors =
      Enum.reduce(parameters, [], fn {param_name, value}, acc ->
        case Map.get(metadata_map, String.to_atom(param_name)) do
          nil ->
            available_params =
              metadata_map
              |> Map.keys()
              |> Enum.map(&to_string/1)
              |> Enum.join(", ")

            [
              "Unknown parameter '#{param_name}'. Available parameters: #{available_params}"
              | acc
            ]

          param_schema ->
            case validate_parameter_value(param_name, value, param_schema) do
              :ok -> acc
              {:error, error} -> [error | acc]
            end
        end
      end)

    # Check for missing required parameters
    required_params =
      metadata_map
      |> Enum.filter(fn {_key, schema} ->
        schema.required
      end)
      |> Enum.map(fn {key, _} -> to_string(key) end)

    provided_params = Map.keys(parameters)
    missing_params = required_params -- provided_params

    errors =
      case missing_params do
        [] -> errors
        missing -> ["Missing required parameters: #{Enum.join(missing, ", ")}" | errors]
      end

    case errors do
      [] -> {:ok, parameters}
      _ -> {:error, errors}
    end
  end

  defp validate_parameter_value(param_name, value, schema) do
    with :ok <- validate_type(param_name, value, schema),
         :ok <- validate_range(param_name, value, schema) do
      :ok
    end
  end

  defp validate_type(_param_name, value, %{type: :integer}) when is_integer(value), do: :ok

  defp validate_type(param_name, value, %{type: :integer}) do
    {:error, "Parameter '#{param_name}' must be an integer, got: #{inspect(value)}"}
  end

  defp validate_type(_param_name, value, %{type: :float})
       when is_float(value) or is_integer(value),
       do: :ok

  defp validate_type(param_name, value, %{type: :float}) do
    {:error, "Parameter '#{param_name}' must be a number, got: #{inspect(value)}"}
  end

  defp validate_type(_param_name, value, %{type: :string}) when is_binary(value), do: :ok

  defp validate_type(param_name, value, %{type: :string}) do
    {:error, "Parameter '#{param_name}' must be a string, got: #{inspect(value)}"}
  end

  defp validate_type(_param_name, _value, _schema), do: :ok

  defp validate_range(param_name, value, %{min: min}) when value < min do
    {:error, "Parameter '#{param_name}' must be >= #{min}, got: #{value}"}
  end

  defp validate_range(param_name, value, %{max: max}) when value > max do
    {:error, "Parameter '#{param_name}' must be <= #{max}, got: #{value}"}
  end

  defp validate_range(_param_name, _value, _schema), do: :ok
end
