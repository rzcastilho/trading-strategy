defmodule TradingStrategy.Indicators do
  @moduledoc """
  Integration layer for trading indicators with Decimal precision.

  This module provides the bridge between the TradingStrategy library and the
  trading-indicators library, handling:

  - Indicator calculation for strategies
  - Data series extraction with Decimal support
  - Multi-timeframe analysis
  - Market data validation
  - Caching for performance

  ## Decimal Integration

  All price data is processed using Decimal for exact precision. The module:

  - Extracts Decimal values from OHLCV data
  - Performs Decimal arithmetic for derived series (hl2, hlc3, ohlc4)
  - Returns Decimal values to indicators
  - Preserves precision throughout calculations

  ## Data Series

  Supports multiple data series types:

  - `:close` - Closing prices (Decimal)
  - `:open` - Opening prices (Decimal)
  - `:high` - High prices (Decimal)
  - `:low` - Low prices (Decimal)
  - `:hl2` - (High + Low) / 2 (Decimal)
  - `:hlc3` - (High + Low + Close) / 3 (Decimal)
  - `:ohlc4` - (Open + High + Low + Close) / 4 (Decimal)

  ## Examples

      # Extract close prices as Decimal values
      alias TradingStrategy.Types
      market_data = [
        Types.new_ohlcv(100, 105, 95, 102, 1000),
        Types.new_ohlcv(102, 108, 100, 106, 1100)
      ]

      close_prices = Indicators.extract_data_series(market_data, source: :close)
      # => [#Decimal<102>, #Decimal<106>]

  See `TradingStrategy.Types` for OHLCV data format details.
  """

  alias TradingStrategy.{Definition, Types}
  require Logger

  @doc """
  Calculates all indicators defined in a strategy for given market data.

  Returns a map of indicator names to their calculated values.

  ## Examples

      iex> market_data = [
      ...>   %{close: 100, high: 105, low: 95, open: 98, volume: 1000},
      ...>   %{close: 102, high: 106, low: 96, open: 100, volume: 1100}
      ...> ]
      iex> TradingStrategy.Indicators.calculate_all(strategy_def, market_data)
      %{
        sma_fast: 101.0,
        sma_slow: 100.5,
        rsi: 55.2
      }
  """
  def calculate_all(%Definition{indicators: indicators}, market_data, opts \\ []) do
    Enum.reduce(indicators, %{}, fn {name, config}, acc ->
      value = calculate_indicator(config, market_data, opts)
      Map.put(acc, name, value)
    end)
  end

  @doc """
  Calculates a single indicator using trading-indicators library behaviour.

  Properly handles the indicator contract:
  1. Validates parameters using `validate_params/1`
  2. Checks data sufficiency using `required_periods/0` or `required_periods/1`
  3. Handles `{:ok, results}` and `{:error, reason}` tuples
  4. Extracts value from result struct

  Special handling for volume data:
  - When `source: :volume` is specified, the source is removed from validation params
    since most indicators only accept price-based sources
  - Volume data is extracted and passed directly to the indicator
  """
  def calculate_indicator(%{module: module, params: params}, market_data, _opts \\ []) do
    # Special handling for volume source: don't validate it as most indicators
    # only accept price sources. Instead, extract volume data and remove source from params.
    validation_params =
      case Keyword.get(params, :source) do
        :volume ->
          # Remove source from validation params since indicators expect price sources
          # The data series will be volume anyway due to extract_data_series
          Keyword.delete(params, :source)

        _ ->
          # For price sources, use params as-is for both validation and calculation
          params
      end

    with {:ok, _} <- validate_indicator_params(module, validation_params),
         :ok <- check_sufficient_data(module, market_data, params),
         data <- extract_data_series(market_data, params) do
      # Call the indicator's calculate function
      # Use validation_params (without volume source) to avoid parameter errors
      case apply(module, :calculate, [data, validation_params]) do
        {:ok, results} ->
          # Real indicator that follows TradingIndicators.Behaviour
          extract_indicator_value(results)

        {:error, %{message: message}} ->
          Logger.error("Failed to calculate #{inspect(module)}: #{message}")
          nil

        {:error, reason} ->
          Logger.error("Failed to calculate #{inspect(module)}: #{inspect(reason)}")
          nil

        result ->
          # Test indicator that returns plain value (Decimal or number)
          extract_indicator_value(result)
      end
    else
      {:error, %{message: message}} ->
        Logger.error("Failed to calculate #{inspect(module)}: #{message}")
        nil

      {:error, reason} ->
        Logger.error("Failed to calculate #{inspect(module)}: #{inspect(reason)}")
        nil

      :insufficient_data ->
        Logger.debug("Insufficient data for #{inspect(module)}")
        nil
    end
  rescue
    error ->
      Logger.error("Exception calculating #{inspect(module)}: #{inspect(error)}")
      nil
  end

  @doc """
  Calculates historical values for indicators (for cross detection).

  Returns a map of indicator names to lists of historical values.
  """
  def calculate_historical(%Definition{indicators: indicators}, market_data, lookback \\ 2) do
    # For each indicator, calculate values for the last N periods
    Enum.reduce(indicators, %{}, fn {name, config}, acc ->
      values = calculate_historical_values(config, market_data, lookback)
      Map.put(acc, name, values)
    end)
  end

  @doc """
  Calculates indicator values for multiple timeframes.
  """
  def calculate_multi_timeframe(%Definition{} = definition, market_data_by_timeframe) do
    Enum.reduce(market_data_by_timeframe, %{}, fn {timeframe, data}, acc ->
      indicators = calculate_all(definition, data)
      Map.put(acc, timeframe, indicators)
    end)
  end

  @doc """
  Extracts the appropriate data series from market data based on indicator parameters.

  Converts Decimal values to the format expected by indicators (typically floats or Decimals).
  """
  def extract_data_series(market_data, params) do
    source = Keyword.get(params, :source, :close)

    case source do
      :close ->
        Enum.map(market_data, &Types.to_decimal(&1.close))

      :open ->
        Enum.map(market_data, &Types.to_decimal(&1.open))

      :high ->
        Enum.map(market_data, &Types.to_decimal(&1.high))

      :low ->
        Enum.map(market_data, &Types.to_decimal(&1.low))

      :volume ->
        # Convert volume to Decimal for precision consistency
        Enum.map(market_data, fn candle ->
          Decimal.new(candle.volume)
        end)

      :hl2 ->
        Enum.map(market_data, fn candle ->
          high = Types.to_decimal(candle.high)
          low = Types.to_decimal(candle.low)
          Decimal.div(Decimal.add(high, low), Decimal.new("2"))
        end)

      :hlc3 ->
        Enum.map(market_data, fn candle ->
          high = Types.to_decimal(candle.high)
          low = Types.to_decimal(candle.low)
          close = Types.to_decimal(candle.close)

          Decimal.div(
            Decimal.add(Decimal.add(high, low), close),
            Decimal.new("3")
          )
        end)

      :ohlc4 ->
        Enum.map(market_data, fn candle ->
          open = Types.to_decimal(candle.open)
          high = Types.to_decimal(candle.high)
          low = Types.to_decimal(candle.low)
          close = Types.to_decimal(candle.close)

          sum =
            Decimal.add(
              Decimal.add(open, high),
              Decimal.add(low, close)
            )

          Decimal.div(sum, Decimal.new("4"))
        end)

      _ ->
        Enum.map(market_data, &Types.to_decimal(&1.close))
    end
  end

  # Calculates historical indicator values for cross detection and trend analysis.
  defp calculate_historical_values(config, market_data, lookback) do
    data_length = length(market_data)

    if data_length < lookback do
      []
    else
      # Calculate indicator for each historical period
      Enum.map((data_length - lookback)..(data_length - 1), fn idx ->
        historical_data = Enum.take(market_data, idx + 1)
        calculate_indicator(config, historical_data)
      end)
      |> Enum.reverse()
    end
  end

  @doc """
  Caches indicator calculations for performance optimization.

  This is useful when running backtests or processing large amounts of data.
  """
  def with_cache(cache_key, calculation_fn) do
    case get_from_cache(cache_key) do
      {:ok, value} ->
        value

      :miss ->
        value = calculation_fn.()
        put_in_cache(cache_key, value)
        value
    end
  end

  # Simple in-memory cache using process dictionary
  # In production, consider using ETS or a dedicated caching library
  defp get_from_cache(key) do
    case Process.get({:indicator_cache, key}) do
      nil -> :miss
      value -> {:ok, value}
    end
  end

  defp put_in_cache(key, value) do
    Process.put({:indicator_cache, key}, value)
  end

  @doc """
  Clears the indicator cache.
  """
  def clear_cache do
    Process.get_keys()
    |> Enum.filter(fn
      {:indicator_cache, _} -> true
      _ -> false
    end)
    |> Enum.each(&Process.delete/1)
  end

  @doc """
  Validates that all required data fields are present in market data.
  """
  def validate_market_data(market_data) when is_list(market_data) do
    required_fields = [:open, :high, :low, :close]

    Enum.all?(market_data, fn candle ->
      Enum.all?(required_fields, &Map.has_key?(candle, &1))
    end)
  end

  def validate_market_data(_), do: false

  @doc """
  Validates indicator parameters using the indicator module's validate_params/1 callback.

  ## Parameters

  - `indicator_module` - The indicator module (e.g., TradingIndicators.Trend.SMA)
  - `params` - Keyword list of parameters

  ## Returns

  - `{:ok, :valid}` if parameters are valid or if validation not available
  - `{:error, reason}` if parameters are invalid
  """
  def validate_indicator_params(indicator_module, params) do
    if function_exported?(indicator_module, :validate_params, 1) do
      case apply(indicator_module, :validate_params, [params]) do
        :ok -> {:ok, :valid}
        {:error, _reason} = error -> error
      end
    else
      # Module doesn't implement validation (e.g., test mocks) - assume valid
      {:ok, :valid}
    end
  rescue
    _error -> {:ok, :valid}
  end

  @doc """
  Checks if there is sufficient market data for indicator calculation.

  Uses the indicator's `required_periods/0` or `required_periods/1` callback.

  ## Parameters

  - `indicator_module` - The indicator module
  - `market_data` - List of OHLCV data
  - `params` - Keyword list of parameters (some indicators use period from params)

  ## Returns

  - `:ok` if sufficient data
  - `:insufficient_data` if not enough data
  """
  def check_sufficient_data(indicator_module, market_data, params) do
    required =
      if function_exported?(indicator_module, :required_periods, 1) do
        apply(indicator_module, :required_periods, [params])
      else
        apply(indicator_module, :required_periods, [])
      end

    if length(market_data) >= required do
      :ok
    else
      :insufficient_data
    end
  rescue
    _error -> :ok
  end

  @doc """
  Gets parameter metadata from an indicator module.

  ## Parameters

  - `indicator_module` - The indicator module

  ## Returns

  - List of `TradingIndicators.Types.ParamMetadata` structs

  ## Example

      metadata = get_parameter_metadata(TradingIndicators.Trend.SMA)
      # => [%ParamMetadata{name: :period, type: :integer, ...}, ...]
  """
  def get_parameter_metadata(indicator_module) do
    Code.ensure_loaded(indicator_module)

    if function_exported?(indicator_module, :parameter_metadata, 0) do
      apply(indicator_module, :parameter_metadata, [])
    else
      []
    end
  rescue
    _error -> []
  end

  @doc """
  Checks if an indicator supports streaming (real-time updates).

  ## Parameters

  - `indicator_module` - The indicator module

  ## Returns

  - `true` if indicator implements `init_state/1` and `update_state/2`
  - `false` otherwise
  """
  def supports_streaming?(indicator_module) do
    Code.ensure_loaded(indicator_module)

    # Streaming functions: init_state/0 or init_state/1, and update_state/2
    (function_exported?(indicator_module, :init_state, 0) or
       function_exported?(indicator_module, :init_state, 1)) and
      function_exported?(indicator_module, :update_state, 2)
  rescue
    _error -> false
  end

  # Private helpers for ensuring Decimal precision

  # Ensures a value is converted to Decimal for precision
  defp ensure_decimal(%Decimal{} = value), do: value
  defp ensure_decimal(value) when is_integer(value), do: Decimal.new(value)
  defp ensure_decimal(value) when is_float(value), do: Decimal.from_float(value)
  defp ensure_decimal(value) when is_binary(value), do: Decimal.new(value)
  defp ensure_decimal(_), do: nil

  # Ensures all values in a map are Decimal
  defp ensure_decimal_components(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {k, ensure_decimal(v)} end)
  end

  # Private helper: Extract indicator value from result
  defp extract_indicator_value([]), do: nil

  defp extract_indicator_value(results) when is_list(results) do
    case List.last(results) do
      # Standard single-value indicator with :value key
      %{value: value} ->
        # Ensure the value is Decimal regardless of what the indicator returned
        ensure_decimal(value)

      # Multi-value indicator (e.g., BollingerBands, MACD)
      # These have component keys directly in the map (no :value wrapper)
      %{timestamp: _, metadata: _} = result ->
        # Remove timestamp and metadata, ensure all components are Decimal
        result
        |> Map.delete(:timestamp)
        |> Map.delete(:metadata)
        |> ensure_decimal_components()

      # Plain Decimal value
      value when is_struct(value, Decimal) -> value

      # Plain number - convert to Decimal
      value when is_number(value) -> ensure_decimal(value)

      _ -> nil
    end
  end

  defp extract_indicator_value(value) when is_struct(value, Decimal), do: value
  defp extract_indicator_value(value) when is_number(value), do: ensure_decimal(value)
  defp extract_indicator_value(_), do: nil
end
