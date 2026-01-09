defmodule TradingStrategy.Strategies.Indicators.ParamValidator do
  @moduledoc """
  Validates indicator parameters using TradingIndicators.Behaviour.parameter_metadata/0.

  Dynamically validates parameter types, ranges, and required fields based on
  the indicator module's metadata.
  """

  require Logger

  @doc """
  Validates parameters against an indicator module's metadata schema.

  ## Parameters
    - `indicator_module`: TradingIndicators module (e.g., TradingIndicators.Momentum.RSI)
    - `params`: Map of parameter name => value (string keys)

  ## Returns
    - `{:ok, validated_params}` - Map with atom keys and converted values
    - `{:error, errors}` - List of validation error messages

  ## Examples

      iex> ParamValidator.validate(TradingIndicators.Momentum.RSI, %{"period" => 14})
      {:ok, %{period: 14}}

      iex> ParamValidator.validate(TradingIndicators.Momentum.RSI, %{"period" => "invalid"})
      {:error, ["Parameter 'period' must be an integer, got: \"invalid\""]}
  """
  @spec validate(module(), map()) :: {:ok, map()} | {:error, list(String.t())}
  def validate(indicator_module, params) when is_map(params) do
    # Get parameter metadata from the indicator module
    metadata_list = indicator_module.parameter_metadata()

    # Convert metadata list to map indexed by parameter name
    metadata_map =
      metadata_list
      |> Enum.map(fn param_meta -> {param_meta.name, param_meta} end)
      |> Map.new()

    # Validate each provided parameter
    {valid_params, errors} =
      Enum.reduce(params, {%{}, []}, fn {param_name, value}, {acc_params, acc_errors} ->
        param_atom = atomize_key(param_name)

        case Map.get(metadata_map, param_atom) do
          nil ->
            # Unknown parameter
            available =
              metadata_map
              |> Map.keys()
              |> Enum.map(&to_string/1)
              |> Enum.join(", ")

            error = "Unknown parameter '#{param_name}'. Available: #{available}"
            {acc_params, [error | acc_errors]}

          param_schema ->
            # Validate against schema
            case validate_parameter(param_name, value, param_schema) do
              {:ok, converted_value} ->
                {Map.put(acc_params, param_atom, converted_value), acc_errors}

              {:error, error} ->
                {acc_params, [error | acc_errors]}
            end
        end
      end)

    # Check for missing required parameters
    required_params =
      metadata_map
      |> Enum.filter(fn {_key, schema} -> schema.required end)
      |> Enum.map(fn {key, _} -> key end)

    provided_keys = Map.keys(valid_params)
    missing_params = required_params -- provided_keys

    errors =
      if length(missing_params) > 0 do
        missing_names = Enum.map(missing_params, &to_string/1) |> Enum.join(", ")
        ["Missing required parameters: #{missing_names}" | errors]
      else
        errors
      end

    # Return result
    case errors do
      [] -> {:ok, valid_params}
      _ -> {:error, Enum.reverse(errors)}
    end
  end

  def validate(_indicator_module, params) do
    {:error, ["Parameters must be a map, got: #{inspect(params)}"]}
  end

  # Private Functions

  defp validate_parameter(param_name, value, schema) do
    with {:ok, converted} <- convert_type(param_name, value, schema),
         :ok <- validate_range(param_name, converted, schema),
         :ok <- validate_options(param_name, converted, schema) do
      {:ok, converted}
    end
  end

  defp convert_type(param_name, value, %{type: :integer}) when is_integer(value) do
    {:ok, value}
  end

  defp convert_type(param_name, value, %{type: :integer}) when is_binary(value) do
    case Integer.parse(value) do
      {int_value, ""} -> {:ok, int_value}
      _ -> {:error, "Parameter '#{param_name}' must be an integer, got: #{inspect(value)}"}
    end
  end

  defp convert_type(param_name, value, %{type: :integer}) do
    {:error, "Parameter '#{param_name}' must be an integer, got: #{inspect(value)}"}
  end

  defp convert_type(param_name, value, %{type: :float})
       when is_float(value) or is_integer(value) do
    {:ok, value / 1.0}
  end

  defp convert_type(param_name, value, %{type: :float}) when is_binary(value) do
    case Float.parse(value) do
      {float_value, ""} -> {:ok, float_value}
      _ -> {:error, "Parameter '#{param_name}' must be a float, got: #{inspect(value)}"}
    end
  end

  defp convert_type(param_name, value, %{type: :float}) do
    {:error, "Parameter '#{param_name}' must be a float, got: #{inspect(value)}"}
  end

  defp convert_type(_param_name, value, %{type: :string}) when is_binary(value) do
    {:ok, value}
  end

  defp convert_type(param_name, value, %{type: :string}) do
    {:error, "Parameter '#{param_name}' must be a string, got: #{inspect(value)}"}
  end

  defp convert_type(_param_name, value, %{type: :atom}) when is_atom(value) do
    {:ok, value}
  end

  defp convert_type(_param_name, value, %{type: :atom}) when is_binary(value) do
    {:ok, String.to_atom(value)}
  end

  defp convert_type(param_name, value, %{type: :atom}) do
    {:error, "Parameter '#{param_name}' must be an atom, got: #{inspect(value)}"}
  end

  defp convert_type(_param_name, value, %{type: :boolean}) when is_boolean(value) do
    {:ok, value}
  end

  defp convert_type(_param_name, value, %{type: :boolean}) when is_binary(value) do
    case String.downcase(value) do
      "true" -> {:ok, true}
      "false" -> {:ok, false}
      _ -> {:error, "Parameter must be a boolean (true/false)"}
    end
  end

  defp convert_type(param_name, value, %{type: type}) do
    {:error,
     "Parameter '#{param_name}' has unsupported type #{type}, got value: #{inspect(value)}"}
  end

  defp validate_range(_param_name, value, %{min: nil, max: nil}), do: :ok

  defp validate_range(param_name, value, %{min: min, max: nil}) when not is_nil(min) do
    if value >= min do
      :ok
    else
      {:error, "Parameter '#{param_name}' must be >= #{min}, got: #{value}"}
    end
  end

  defp validate_range(param_name, value, %{min: nil, max: max}) when not is_nil(max) do
    if value <= max do
      :ok
    else
      {:error, "Parameter '#{param_name}' must be <= #{max}, got: #{value}"}
    end
  end

  defp validate_range(param_name, value, %{min: min, max: max})
       when not is_nil(min) and not is_nil(max) do
    if value >= min and value <= max do
      :ok
    else
      {:error, "Parameter '#{param_name}' must be between #{min} and #{max}, got: #{value}"}
    end
  end

  defp validate_options(_param_name, _value, %{options: nil}), do: :ok

  defp validate_options(param_name, value, %{options: options}) when is_list(options) do
    if value in options do
      :ok
    else
      options_str = Enum.map(options, &inspect/1) |> Enum.join(", ")

      {:error,
       "Parameter '#{param_name}' must be one of [#{options_str}], got: #{inspect(value)}"}
    end
  end

  defp atomize_key(key) when is_atom(key), do: key
  defp atomize_key(key) when is_binary(key), do: String.to_atom(key)
end
