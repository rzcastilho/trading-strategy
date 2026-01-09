defmodule TradingStrategy.Strategies.IndicatorEngine do
  @moduledoc """
  Orchestrates calculation of multiple technical indicators for a strategy.

  Coordinates indicator calculations, manages dependencies, and provides
  efficient batch processing of indicators over market data.
  """

  alias TradingStrategy.Strategies.Indicators.{Adapter, Registry}
  alias TradingStrategy.MarketData
  require Logger

  @doc """
  Calculates all indicators defined in a strategy for given market data.

  ## Parameters
    - `strategy`: Strategy definition map with "indicators" field
    - `market_data`: List of OHLCV bars (maps or structs)

  ## Returns
    - `{:ok, indicator_results}` - Map of indicator_name => calculated values
    - `{:error, reason}` - Calculation failure

  ## Examples

      iex> strategy = %{
      ...>   "indicators" => [
      ...>     %{"type" => "rsi", "name" => "rsi_14", "parameters" => %{"period" => 14}},
      ...>     %{"type" => "sma", "name" => "sma_50", "parameters" => %{"period" => 50}}
      ...>   ]
      ...> }
      iex> IndicatorEngine.calculate_all(strategy, market_data)
      {:ok, %{
        "rsi_14" => %{values: [...], signals: ...},
        "sma_50" => %{values: [...]}
      }}
  """
  @spec calculate_all(map(), list(map())) :: {:ok, map()} | {:error, term()}
  def calculate_all(%{"indicators" => indicators}, market_data)
      when is_list(indicators) and is_list(market_data) do
    # Validate we have enough data
    case validate_data_sufficiency(indicators, market_data) do
      :ok ->
        # Calculate all indicators in batch
        Adapter.calculate_batch(indicators, market_data)

      {:error, _} = error ->
        error
    end
  end

  def calculate_all(_strategy, _market_data) do
    {:error, "Strategy must have 'indicators' field and market_data must be a list"}
  end

  @doc """
  Calculates indicators for a specific time window within market data.

  Useful for backtesting where we need indicators at specific points in time.

  ## Parameters
    - `strategy`: Strategy definition
    - `market_data`: Full market data list
    - `timestamp`: Calculate indicators up to this timestamp
    - `opts`: Options (include_current: boolean)

  ## Returns
    - `{:ok, indicator_values}` - Map of indicator_name => value at timestamp
    - `{:error, reason}` - Error tuple

  ## Examples

      iex> IndicatorEngine.calculate_at_timestamp(strategy, market_data, ~U[2023-01-15 12:00:00Z])
      {:ok, %{
        "rsi_14" => 45.2,
        "sma_50" => 42000.50
      }}
  """
  @spec calculate_at_timestamp(map(), list(map()), DateTime.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def calculate_at_timestamp(strategy, market_data, timestamp, opts \\ []) do
    include_current = Keyword.get(opts, :include_current, true)

    # Filter market data up to timestamp
    filtered_data =
      if include_current do
        Enum.filter(market_data, fn bar ->
          get_timestamp(bar) <= timestamp
        end)
      else
        Enum.filter(market_data, fn bar ->
          get_timestamp(bar) < timestamp
        end)
      end

    # Calculate indicators with filtered data
    case calculate_all(strategy, filtered_data) do
      {:ok, results} ->
        # Extract the latest value from each indicator result
        latest_values =
          Enum.reduce(results, %{}, fn {name, result}, acc ->
            latest = extract_latest_value(result)
            Map.put(acc, name, latest)
          end)

        {:ok, latest_values}

      error ->
        error
    end
  end

  @doc """
  Gets the minimum number of bars required to calculate all indicators in a strategy.

  ## Parameters
    - `strategy`: Strategy definition with indicators

  ## Returns
    - `{:ok, min_bars}` - Minimum bars needed
    - `{:error, reason}` - Error

  ## Examples

      iex> strategy = %{
      ...>   "indicators" => [
      ...>     %{"type" => "rsi", "parameters" => %{"period" => 14}},
      ...>     %{"type" => "sma", "parameters" => %{"period" => 50}}
      ...>   ]
      ...> }
      iex> IndicatorEngine.get_minimum_bars_required(strategy)
      {:ok, 50}  # Maximum of all indicator requirements
  """
  @spec get_minimum_bars_required(map()) :: {:ok, integer()} | {:error, term()}
  def get_minimum_bars_required(%{"indicators" => indicators}) when is_list(indicators) do
    requirements =
      Enum.map(indicators, fn indicator ->
        get_indicator_bar_requirement(indicator)
      end)

    # Check for errors
    errors =
      Enum.filter(requirements, fn
        {:error, _} -> true
        _ -> false
      end)

    case errors do
      [] ->
        max_requirement =
          requirements
          |> Enum.map(fn {:ok, count} -> count end)
          |> Enum.max()

        {:ok, max_requirement}

      [error | _] ->
        error
    end
  end

  def get_minimum_bars_required(_) do
    {:error, "Strategy must have 'indicators' field"}
  end

  @doc """
  Validates that indicator names in a strategy are unique.

  ## Parameters
    - `strategy`: Strategy definition

  ## Returns
    - `:ok` - All names are unique
    - `{:error, duplicates}` - List of duplicate names

  ## Examples

      iex> strategy = %{
      ...>   "indicators" => [
      ...>     %{"name" => "rsi_14", ...},
      ...>     %{"name" => "rsi_14", ...}  # Duplicate!
      ...>   ]
      ...> }
      iex> IndicatorEngine.validate_unique_names(strategy)
      {:error, ["Duplicate indicator name: rsi_14"]}
  """
  @spec validate_unique_names(map()) :: :ok | {:error, list(String.t())}
  def validate_unique_names(%{"indicators" => indicators}) when is_list(indicators) do
    names = Enum.map(indicators, & &1["name"])
    unique_names = Enum.uniq(names)

    if length(names) == length(unique_names) do
      :ok
    else
      duplicates = names -- unique_names
      {:error, Enum.map(duplicates, fn name -> "Duplicate indicator name: #{name}" end)}
    end
  end

  # Private Functions

  defp validate_data_sufficiency(indicators, market_data) do
    data_count = length(market_data)

    insufficient =
      Enum.filter(indicators, fn indicator ->
        case get_indicator_bar_requirement(indicator) do
          {:ok, required} -> data_count < required
          {:error, _} -> true
        end
      end)

    if length(insufficient) > 0 do
      indicator_names = Enum.map(insufficient, & &1["name"]) |> Enum.join(", ")

      {:error,
       "Insufficient data for indicators: #{indicator_names}. " <>
         "Have #{data_count} bars, need more for calculation."}
    else
      :ok
    end
  end

  defp get_indicator_bar_requirement(%{"type" => type, "parameters" => params}) do
    with {:ok, module} <- Registry.get_indicator_module(type) do
      # Most indicators require period + warmup bars
      # For indicators with a period parameter, use that
      period = Map.get(params, "period", 1)

      # Some indicators need extra warmup (e.g., EMA, MACD)
      warmup = get_warmup_requirement(type)

      {:ok, period + warmup}
    end
  end

  defp get_indicator_bar_requirement(%{"type" => type}) do
    # No parameters specified, use defaults
    case Registry.get_indicator_module(type) do
      {:ok, module} ->
        # Get default period from metadata
        metadata = module.parameter_metadata()

        period_meta = Enum.find(metadata, fn meta -> meta.name == :period end)

        period = if period_meta, do: period_meta.default, else: 1
        warmup = get_warmup_requirement(type)

        {:ok, period + warmup}

      error ->
        error
    end
  end

  defp get_warmup_requirement(type) do
    # Some indicators need additional bars beyond their period for accuracy
    case String.downcase(type) do
      "ema" -> 10
      "macd" -> 26
      "rsi" -> 1
      "bb" -> 0
      "bollinger_bands" -> 0
      "atr" -> 1
      _ -> 0
    end
  end

  defp extract_latest_value(%{values: values}) when is_list(values) do
    List.last(values)
  end

  defp extract_latest_value(%{value: value}) do
    value
  end

  defp extract_latest_value(value) when is_number(value) do
    value
  end

  defp extract_latest_value(values) when is_list(values) do
    List.last(values)
  end

  defp extract_latest_value(result) when is_map(result) do
    # For complex results, return the whole map
    result
  end

  defp extract_latest_value(other) do
    other
  end

  defp get_timestamp(%{timestamp: timestamp}), do: timestamp
  defp get_timestamp(%{"timestamp" => timestamp}), do: timestamp

  defp get_timestamp(bar) when is_map(bar) do
    Map.get(bar, :timestamp) || Map.get(bar, "timestamp")
  end
end
