defmodule TradingStrategy.Strategies.Indicators.Adapter do
  @moduledoc """
  Generic adapter for calculating technical indicators using the TradingIndicators library.

  Dynamically dispatches to TradingIndicators modules based on indicator type,
  following the TradingIndicators.Behaviour pattern.
  """

  alias TradingStrategy.Strategies.Indicators.Registry
  alias TradingStrategy.Strategies.Indicators.ParamValidator
  require Logger

  @doc """
  Calculates an indicator for the given market data.

  ## Parameters
    - `indicator_type`: Indicator name (e.g., "rsi", "sma", "macd")
    - `market_data`: List of market data maps with OHLCV fields
    - `params`: Map of indicator-specific parameters

  ## Returns
    - `{:ok, result}` - Calculation result (format depends on indicator)
    - `{:error, reason}` - Error tuple

  ## Examples

      iex> data = [%{close: 100}, %{close: 102}, ...]
      iex> Adapter.calculate("rsi", data, %{"period" => 14})
      {:ok, %{values: [30.5, 35.2, ...], signals: %{overbought: false, oversold: true}}}
  """
  @spec calculate(String.t(), list(map()), map()) ::
          {:ok, term()} | {:error, term()}
  def calculate(indicator_type, market_data, params) when is_list(market_data) do
    with {:ok, module} <- Registry.get_indicator_module(indicator_type),
         {:ok, validated_params} <- ParamValidator.validate(module, params),
         {:ok, converted_data} <- convert_market_data(market_data),
         {:ok, result} <- execute_calculation(module, converted_data, validated_params) do
      {:ok, result}
    else
      {:error, reason} = error ->
        Logger.error("Indicator calculation failed for #{indicator_type}: #{inspect(reason)}")

        error
    end
  end

  def calculate(_indicator_type, _market_data, _params) do
    {:error, "Market data must be a list"}
  end

  @doc """
  Calculates multiple indicators in batch for the same market data.

  More efficient than calling calculate/3 multiple times when indicators
  share the same data source.

  ## Parameters
    - `indicators`: List of %{type: type, name: name, params: params} maps
    - `market_data`: List of market data maps

  ## Returns
    - `{:ok, results}` - Map of indicator_name => result
    - `{:error, reason}` - Error tuple

  ## Examples

      iex> indicators = [
      ...>   %{type: "rsi", name: "rsi_14", params: %{"period" => 14}},
      ...>   %{type: "sma", name: "sma_50", params: %{"period" => 50}}
      ...> ]
      iex> Adapter.calculate_batch(indicators, market_data)
      {:ok, %{
        "rsi_14" => %{values: [...], signals: ...},
        "sma_50" => %{values: [...]}
      }}
  """
  @spec calculate_batch(list(map()), list(map())) ::
          {:ok, map()} | {:error, term()}
  def calculate_batch(indicators, market_data) when is_list(indicators) do
    results =
      Enum.reduce_while(indicators, %{}, fn indicator, acc ->
        case calculate(indicator["type"], market_data, indicator["parameters"] || %{}) do
          {:ok, result} ->
            {:cont, Map.put(acc, indicator["name"], result)}

          {:error, reason} ->
            {:halt, {:error, "Failed to calculate #{indicator["name"]}: #{inspect(reason)}"}}
        end
      end)

    case results do
      {:error, _} = error -> error
      results when is_map(results) -> {:ok, results}
    end
  end

  @doc """
  Initializes a streaming indicator for real-time calculation.

  Some indicators support incremental updates without recalculating
  from scratch on each new bar.

  ## Parameters
    - `indicator_type`: Indicator name
    - `params`: Indicator parameters
    - `initial_data`: Optional initial historical data for warm-up

  ## Returns
    - `{:ok, stream_state}` - Initialized stream state
    - `{:error, reason}` - Error tuple

  ## Examples

      iex> Adapter.init_stream("rsi", %{"period" => 14}, initial_data)
      {:ok, %{module: TradingIndicators.Momentum.RSI, state: ...}}
  """
  @spec init_stream(String.t(), map(), list(map())) ::
          {:ok, map()} | {:error, term()}
  def init_stream(indicator_type, params, initial_data \\ []) do
    with {:ok, module} <- Registry.get_indicator_module(indicator_type),
         {:ok, validated_params} <- ParamValidator.validate(module, params) do
      # Check if module supports streaming
      if function_exported?(module, :init_stream, 2) do
        case convert_market_data(initial_data) do
          {:ok, converted_data} ->
            case module.init_stream(converted_data, validated_params) do
              {:ok, state} ->
                {:ok, %{module: module, params: validated_params, state: state}}

              error ->
                error
            end

          error ->
            error
        end
      else
        {:error, "Indicator #{indicator_type} does not support streaming"}
      end
    end
  end

  @doc """
  Updates a streaming indicator with a new market data point.

  ## Parameters
    - `stream_state`: State from init_stream/3 or previous update
    - `new_data`: New market data point

  ## Returns
    - `{:ok, result, new_state}` - Updated result and state
    - `{:error, reason}` - Error tuple

  ## Examples

      iex> {:ok, stream_state} = Adapter.init_stream("rsi", params, historical_data)
      iex> Adapter.update_stream(stream_state, new_bar)
      {:ok, %{value: 45.2, ...}, updated_state}
  """
  @spec update_stream(map(), map()) ::
          {:ok, term(), map()} | {:error, term()}
  def update_stream(%{module: module, params: params, state: state}, new_data) do
    with {:ok, converted_data} <- convert_single_bar(new_data) do
      case module.update_stream(state, converted_data, params) do
        {:ok, result, new_state} ->
          {:ok, result, %{module: module, params: params, state: new_state}}

        error ->
          error
      end
    end
  end

  # Private Functions

  defp execute_calculation(module, market_data, params) do
    # Convert params map to keyword list for TradingIndicators library
    params_list =
      case params do
        params when is_map(params) -> Enum.into(params, [])
        params when is_list(params) -> params
        _ -> []
      end

    # Most indicators use calculate/2, but some might have different signatures
    case module.calculate(market_data, params_list) do
      {:ok, _result} = success ->
        success

      {:error, _reason} = error ->
        error

      # Some indicators might return the result directly
      result when is_map(result) or is_list(result) ->
        {:ok, result}

      other ->
        Logger.warning("Unexpected indicator result format: #{inspect(other)}")
        {:ok, other}
    end
  rescue
    error ->
      Logger.error("Indicator calculation error: #{Exception.message(error)}")
      {:error, Exception.message(error)}
  end

  defp convert_market_data([]), do: {:ok, []}

  defp convert_market_data(market_data) when is_list(market_data) do
    # Convert our market data format to TradingIndicators format
    # TradingIndicators expects maps with atom keys: :open, :high, :low, :close, :volume
    converted =
      Enum.map(market_data, fn bar ->
        %{
          timestamp: get_field(bar, "timestamp") || get_field(bar, :timestamp),
          open: to_decimal(get_field(bar, "open") || get_field(bar, :open)),
          high: to_decimal(get_field(bar, "high") || get_field(bar, :high)),
          low: to_decimal(get_field(bar, "low") || get_field(bar, :low)),
          close: to_decimal(get_field(bar, "close") || get_field(bar, :close)),
          volume: to_decimal(get_field(bar, "volume") || get_field(bar, :volume))
        }
      end)

    {:ok, converted}
  rescue
    error ->
      {:error, "Failed to convert market data: #{Exception.message(error)}"}
  end

  defp convert_single_bar(bar) when is_map(bar) do
    converted = %{
      timestamp: get_field(bar, "timestamp") || get_field(bar, :timestamp),
      open: to_decimal(get_field(bar, "open") || get_field(bar, :open)),
      high: to_decimal(get_field(bar, "high") || get_field(bar, :high)),
      low: to_decimal(get_field(bar, "low") || get_field(bar, :low)),
      close: to_decimal(get_field(bar, "close") || get_field(bar, :close)),
      volume: to_decimal(get_field(bar, "volume") || get_field(bar, :volume))
    }

    {:ok, converted}
  rescue
    error ->
      {:error, "Failed to convert bar: #{Exception.message(error)}"}
  end

  defp get_field(map, key) when is_map(map) do
    Map.get(map, key)
  end

  defp get_field(struct, key) do
    Map.get(struct, key)
  end

  defp to_decimal(nil), do: Decimal.new("0")
  defp to_decimal(%Decimal{} = d), do: d
  defp to_decimal(value) when is_number(value), do: Decimal.new(to_string(value))
  defp to_decimal(value) when is_binary(value), do: Decimal.new(value)
end
