defmodule TradingStrategy.Strategies.Indicators.Registry do
  @moduledoc """
  Registry for mapping indicator names to TradingIndicators modules.

  Dynamically discovers all 22 indicators from TradingIndicators library
  using TradingIndicators.categories/0 and builds a DSL name → module mapping.

  Example mappings:
    "rsi" → TradingIndicators.Momentum.RSI
    "sma" → TradingIndicators.Trend.SMA
    "bollinger_bands" → TradingIndicators.Volatility.BollingerBands
  """

  require Logger

  @doc """
  Builds the complete indicator registry from TradingIndicators library.

  Discovers all indicators across all categories and creates name mappings.

  ## Returns
    - Map of indicator_name (lowercase string) => module

  ## Examples

      iex> registry = Registry.build_registry()
      iex> Map.keys(registry)
      ["rsi", "macd", "sma", "ema", "bb", "bollinger_bands", ...]
  """
  @spec build_registry() :: map()
  def build_registry do
    get_cached_registry()
  end

  @doc """
  Gets the indicator module for a given indicator type name.

  Uses cached registry for performance.

  ## Parameters
    - `indicator_type`: Indicator name (e.g., "rsi", "sma", "macd")

  ## Returns
    - `{:ok, module}` - TradingIndicators module
    - `{:error, reason}` - Unknown indicator type

  ## Examples

      iex> Registry.get_indicator_module("rsi")
      {:ok, TradingIndicators.Momentum.RSI}

      iex> Registry.get_indicator_module("unknown")
      {:error, "Unknown indicator type 'unknown'. Available: ..."}
  """
  @spec get_indicator_module(String.t()) :: {:ok, module()} | {:error, String.t()}
  def get_indicator_module(indicator_type) when is_binary(indicator_type) do
    registry = get_cached_registry()

    case Map.get(registry, String.downcase(indicator_type)) do
      nil ->
        available =
          registry
          |> Map.keys()
          |> Enum.sort()
          |> Enum.join(", ")

        {:error, "Unknown indicator type '#{indicator_type}'. Available indicators: #{available}"}

      module ->
        {:ok, module}
    end
  end

  @doc """
  Lists all available indicator types.

  ## Returns
    - List of indicator name strings (sorted)

  ## Examples

      iex> Registry.list_available_indicators()
      ["atr", "bb", "bollinger_bands", "cci", ...]
  """
  @spec list_available_indicators() :: list(String.t())
  def list_available_indicators do
    get_cached_registry()
    |> Map.keys()
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc """
  Gets metadata for a specific indicator.

  ## Parameters
    - `indicator_type`: Indicator name

  ## Returns
    - `{:ok, metadata}` - Map with category, description, parameters
    - `{:error, reason}` - Unknown indicator

  ## Examples

      iex> Registry.get_indicator_metadata("rsi")
      {:ok, %{
        module: TradingIndicators.Momentum.RSI,
        category: :momentum,
        parameters: [%{name: :period, type: :integer, ...}]
      }}
  """
  @spec get_indicator_metadata(String.t()) ::
          {:ok, map()} | {:error, String.t()}
  def get_indicator_metadata(indicator_type) do
    with {:ok, module} <- get_indicator_module(indicator_type) do
      metadata = %{
        module: module,
        category: get_category(module),
        parameters: module.parameter_metadata()
      }

      {:ok, metadata}
    end
  end

  # Private Functions

  # Cache the registry using persistent_term for fast lookup
  # Built on first access and cached for subsequent calls
  defp get_cached_registry do
    case :persistent_term.get(__MODULE__, nil) do
      nil ->
        registry = build_registry_internal()
        :persistent_term.put(__MODULE__, registry)
        registry

      registry ->
        registry
    end
  end

  defp build_registry_internal do
    TradingIndicators.categories()
    |> Enum.flat_map(fn category_module ->
      category_module.available_indicators()
      |> Enum.flat_map(fn indicator_module ->
        # Extract indicator name from module (e.g., TradingIndicators.Momentum.RSI → "rsi")
        name = extract_indicator_name(indicator_module)

        # Create mappings for both the name and common aliases
        aliases = get_aliases(name)

        Enum.map([name | aliases], fn alias_name ->
          {String.downcase(alias_name), indicator_module}
        end)
      end)
    end)
    |> Map.new()
  end

  defp extract_indicator_name(module) do
    # Extract the last part of the module name
    # E.g., TradingIndicators.Momentum.RSI → "RSI"
    module
    |> Module.split()
    |> List.last()
    |> to_string()
  end

  defp get_category(module) do
    # Extract category from module path
    # E.g., TradingIndicators.Momentum.RSI → :momentum
    module_parts = Module.split(module)

    if length(module_parts) >= 2 do
      module_parts
      |> Enum.at(-2)
      |> String.downcase()
      |> String.to_atom()
    else
      :unknown
    end
  end

  defp get_aliases(name) do
    # Define common aliases for indicators
    case String.downcase(name) do
      "bollingerbands" -> ["bb", "bollinger_bands"]
      "bb" -> ["bollinger_bands", "bollingerbands"]
      "bollinger_bands" -> ["bb", "bollingerbands"]
      "macd" -> ["moving_average_convergence_divergence"]
      "rsi" -> ["relative_strength_index"]
      "ema" -> ["exponential_moving_average"]
      "sma" -> ["simple_moving_average"]
      "wma" -> ["weighted_moving_average"]
      "hma" -> ["hull_moving_average"]
      "kama" -> ["kaufman_adaptive_moving_average"]
      "atr" -> ["average_true_range"]
      "obv" -> ["on_balance_volume"]
      "vwap" -> ["volume_weighted_average_price"]
      "cci" -> ["commodity_channel_index"]
      "roc" -> ["rate_of_change"]
      "mfi" -> ["money_flow_index"]
      "adline" -> ["ad_line", "accumulation_distribution"]
      "ad_line" -> ["adline", "accumulation_distribution"]
      "cmf" -> ["chaikin_money_flow"]
      "standarddeviation" -> ["std_dev", "stddev"]
      "std_dev" -> ["standarddeviation", "stddev"]
      "volatilityindex" -> ["volatility_index", "vol_index"]
      "williamsr" -> ["williams_r", "williams_%r"]
      _ -> []
    end
  end
end
