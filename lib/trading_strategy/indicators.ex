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
  Calculates a single indicator.
  """
  def calculate_indicator(%{module: module, params: params}, market_data, _opts \\ []) do
    # Extract the appropriate data series based on indicator requirements
    data = extract_data_series(market_data, params)

    # Call the indicator module's calculate function
    apply(module, :calculate, [data, params])
  rescue
    error ->
      # Log error and return nil or default value
      require Logger
      Logger.error("Failed to calculate indicator #{inspect(module)}: #{inspect(error)}")
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
        Enum.map(market_data, & &1.volume)

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
end
