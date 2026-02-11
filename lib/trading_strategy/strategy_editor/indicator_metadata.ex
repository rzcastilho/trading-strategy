defmodule TradingStrategy.StrategyEditor.IndicatorMetadata do
  @moduledoc """
  Helper module for querying indicator metadata from the TradingIndicators library.

  Provides convenient access to both parameter metadata (input configuration)
  and output field metadata (available values for use in conditions).

  Uses lazy persistent_term caching for performance (0.0006ms retrieval).
  Metadata is immutable at runtime and only changes with library version upgrades.

  ## Usage

      # Get complete metadata for an indicator
      {:ok, metadata} = IndicatorMetadata.get("bollinger_bands")

      # metadata contains:
      # %{
      #   module: TradingIndicators.Volatility.BollingerBands,
      #   category: :volatility,
      #   parameters: [...],      # Input parameters
      #   output_fields: %{...}   # Output field structure
      # }

      # Quick check: Is this a multi-value indicator?
      IndicatorMetadata.multi_value?("bollinger_bands")  # true
      IndicatorMetadata.multi_value?("sma")              # false

      # Get just the output fields
      {:ok, fields} = IndicatorMetadata.get_output_fields("macd")
      # fields.type => :multi_value
      # fields.fields => [%{name: :macd, ...}, %{name: :signal, ...}, ...]
  """

  require Logger
  alias TradingStrategy.Strategies.Indicators.Registry

  @doc """
  Get complete metadata for an indicator.

  ## Parameters

    - `indicator_type` - Indicator name (e.g., "sma", "bollinger_bands", "macd")

  ## Returns

    - `{:ok, metadata}` - Map with module, category, parameters, and output fields
    - `{:error, reason}` - Unknown indicator or missing metadata

  ## Examples

      iex> IndicatorMetadata.get("sma")
      {:ok, %{
        module: TradingIndicators.Trend.SMA,
        category: :trend,
        parameters: [...],
        output_fields: %{type: :single_value, ...}
      }}
  """
  @spec get(String.t()) :: {:ok, map()} | {:error, String.t()}
  def get(indicator_type) when is_binary(indicator_type) do
    with {:ok, module} <- Registry.get_indicator_module(indicator_type),
         {:ok, registry_metadata} <- Registry.get_indicator_metadata(indicator_type),
         {:ok, output_fields} <- get_output_fields_from_module(module) do
      metadata =
        registry_metadata
        |> Map.put(:output_fields, output_fields)

      {:ok, metadata}
    end
  end

  @doc """
  Get only the output field metadata for an indicator.

  ## Parameters

    - `indicator_type` - Indicator name

  ## Returns

    - `{:ok, output_field_metadata}` - OutputFieldMetadata struct
    - `{:error, reason}` - Unknown indicator or missing metadata

  ## Examples

      iex> {:ok, fields} = IndicatorMetadata.get_output_fields("bollinger_bands")
      iex> fields.type
      :multi_value
      iex> length(fields.fields)
      5
  """
  @spec get_output_fields(String.t()) :: {:ok, map()} | {:error, String.t()}
  def get_output_fields(indicator_type) when is_binary(indicator_type) do
    with {:ok, module} <- Registry.get_indicator_module(indicator_type) do
      get_output_fields_from_module(module)
    end
  end

  @doc """
  Check if an indicator returns multiple values (requires field access).

  ## Parameters

    - `indicator_type` - Indicator name

  ## Returns

    - `true` if multi-value (e.g., Bollinger Bands, MACD)
    - `false` if single-value (e.g., SMA, RSI)
    - `{:error, reason}` if indicator not found

  ## Examples

      iex> IndicatorMetadata.multi_value?("bollinger_bands")
      true

      iex> IndicatorMetadata.multi_value?("sma")
      false
  """
  @spec multi_value?(String.t()) :: boolean() | {:error, String.t()}
  def multi_value?(indicator_type) do
    case get_output_fields(indicator_type) do
      {:ok, %{type: :multi_value}} -> true
      {:ok, %{type: :single_value}} -> false
      error -> error
    end
  end

  @doc """
  Validate that a field reference is valid for an indicator.

  ## Parameters

    - `indicator_type` - Indicator name
    - `field_name` - Field name (nil for single-value indicators)

  ## Returns

    - `:ok` if valid
    - `{:error, reason}` if invalid

  ## Examples

      iex> IndicatorMetadata.validate_field("bollinger_bands", "upper_band")
      :ok

      iex> IndicatorMetadata.validate_field("bollinger_bands", "invalid_field")
      {:error, "Field 'invalid_field' not found. Available: upper_band, middle_band, lower_band, percent_b, bandwidth"}

      iex> IndicatorMetadata.validate_field("sma", nil)
      :ok

      iex> IndicatorMetadata.validate_field("sma", "some_field")
      {:error, "SMA is a single-value indicator. Use 'sma_20' directly without field access."}
  """
  @spec validate_field(String.t(), String.t() | nil) :: :ok | {:error, String.t()}
  def validate_field(indicator_type, field_name) when is_binary(indicator_type) do
    case get_output_fields(indicator_type) do
      {:ok, %{type: :single_value}} ->
        if is_nil(field_name) do
          :ok
        else
          {:error,
           "#{String.upcase(indicator_type)} is a single-value indicator. Use '#{indicator_type}_X' directly without field access."}
        end

      {:ok, %{type: :multi_value, fields: fields}} ->
        field_atom = if is_binary(field_name), do: String.to_atom(field_name), else: field_name
        available_fields = Enum.map(fields, & &1.name)

        if field_atom in available_fields do
          :ok
        else
          available_str = Enum.map_join(available_fields, ", ", &to_string/1)
          {:error, "Field '#{field_name}' not found. Available: #{available_str}"}
        end

      error ->
        error
    end
  end

  @doc """
  Get a formatted help text for an indicator's output fields.

  Useful for tooltips or documentation in the UI.

  ## Parameters

    - `indicator_type` - Indicator name

  ## Returns

    - `{:ok, help_text}` - Formatted string describing the output
    - `{:error, reason}` - Unknown indicator

  ## Examples

      iex> {:ok, help} = IndicatorMetadata.format_help("bollinger_bands")
      iex> IO.puts(help)
      Bollinger Bands (multi-value indicator)

      Available fields:
        • upper_band (price) - Upper Bollinger Band (SMA + multiplier × standard deviation)
        • middle_band (price) - Middle Bollinger Band (Simple Moving Average)
        • lower_band (price) - Lower Bollinger Band (SMA - multiplier × standard deviation)
        • percent_b (%) - %B indicator - price position relative to bands
        • bandwidth (%) - Bandwidth - distance between upper and lower bands

      Example usage:
        close > bb_20.upper_band or close < bb_20.lower_band
  """
  @spec format_help(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def format_help(indicator_type) do
    case get_output_fields(indicator_type) do
      {:ok, %{type: :single_value} = metadata} ->
        text = """
        #{metadata.description || String.upcase(indicator_type)} (single-value indicator)

        Usage: Reference the indicator name directly in conditions

        Example:
          #{metadata.example || "#{indicator_type}_20 > close"}
        """

        {:ok, text}

      {:ok, %{type: :multi_value, fields: fields} = metadata} ->
        field_list =
          fields
          |> Enum.map(fn field ->
            unit = if field[:unit], do: " (#{field.unit})", else: ""
            "  • #{field.name}#{unit} - #{field.description || "Value"}"
          end)
          |> Enum.join("\n")

        text = """
        #{metadata.description || String.upcase(indicator_type)} (multi-value indicator)

        Available fields:
        #{field_list}

        Example usage:
          #{metadata.example || "#{indicator_type}_X.field_name"}
        """

        {:ok, text}

      error ->
        error
    end
  end

  @doc """
  List all indicators with their output types.

  Returns a summary of all available indicators and whether they're
  single-value or multi-value.

  ## Examples

      iex> IndicatorMetadata.list_all() |> Enum.take(3)
      [
        %{indicator: "atr", type: :single_value},
        %{indicator: "bollinger_bands", type: :multi_value},
        %{indicator: "ema", type: :single_value}
      ]
  """
  @spec list_all() :: list(map())
  def list_all do
    Registry.list_available_indicators()
    |> Enum.map(fn indicator_type ->
      case get_output_fields(indicator_type) do
        {:ok, metadata} ->
          %{
            indicator: indicator_type,
            type: metadata.type,
            description: metadata.description
          }

        {:error, _} ->
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(& &1.indicator)
  end

  # Private Functions

  # Cache the output fields using persistent_term for fast lookup
  # Built on first access and cached for subsequent calls (0.0006ms retrieval)
  defp get_output_fields_from_module(module) do
    cache_key = {:indicator_output_fields, module}

    case :persistent_term.get(cache_key, nil) do
      nil ->
        # First access - fetch and cache
        result = fetch_output_fields_metadata(module)

        case result do
          {:ok, metadata} ->
            :persistent_term.put(cache_key, metadata)
            {:ok, metadata}

          error ->
            error
        end

      cached_metadata ->
        # Cache hit
        {:ok, cached_metadata}
    end
  end

  # Fetch output fields metadata from indicator module
  defp fetch_output_fields_metadata(module) do
    # Ensure module is loaded before checking function existence
    Code.ensure_loaded(module)

    if function_exported?(module, :output_fields_metadata, 0) do
      try do
        metadata = module.output_fields_metadata()
        validate_metadata_structure(metadata, module)
      rescue
        error ->
          Logger.error(
            "Error fetching metadata for #{inspect(module)}: #{Exception.message(error)}"
          )

          {:error, "Failed to get output fields metadata: #{Exception.message(error)}"}
      end
    else
      Logger.warning("No metadata function for indicator #{inspect(module)}")
      {:error, "Module #{inspect(module)} does not implement output_fields_metadata/0"}
    end
  end

  # Validate metadata structure has required fields
  defp validate_metadata_structure(%{type: type} = metadata, _module)
       when type in [:single_value, :multi_value] do
    {:ok, metadata}
  end

  defp validate_metadata_structure(metadata, module) do
    Logger.error("Invalid metadata structure for #{inspect(module)}: #{inspect(metadata)}")
    {:error, "Invalid metadata structure - missing or invalid :type field"}
  end
end
