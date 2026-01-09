defmodule TradingStrategy.Strategies.SignalEvaluator do
  @moduledoc """
  Evaluates trading signals based on strategy conditions and indicator values.

  Generates entry, exit, and stop signals by evaluating condition expressions
  from the strategy DSL against current market data and calculated indicators.
  """

  alias TradingStrategy.Strategies.ConditionParser
  alias TradingStrategy.Strategies.IndicatorEngine
  require Logger

  @doc """
  Evaluates all signal conditions for a strategy at a specific point in time.

  ## Parameters
    - `strategy`: Strategy definition with entry_conditions, exit_conditions, stop_conditions
    - `market_data`: Historical market data up to evaluation point
    - `current_bar`: Current OHLCV bar
    - `indicator_values`: Pre-calculated indicator values (optional)

  ## Returns
    - `{:ok, signals}` - Map with entry, exit, stop boolean values
    - `{:error, reason}` - Evaluation error

  ## Examples

      iex> strategy = %{
      ...>   "entry_conditions" => "rsi_14 < 30 AND close > sma_50",
      ...>   "exit_conditions" => "rsi_14 > 70",
      ...>   "stop_conditions" => "rsi_14 < 25"
      ...> }
      iex> SignalEvaluator.evaluate_signals(strategy, market_data, current_bar)
      {:ok, %{
        entry: true,
        exit: false,
        stop: false,
        context: %{"rsi_14" => 25, "sma_50" => 42000, ...}
      }}
  """
  @spec evaluate_signals(map(), list(map()), map(), map() | nil) ::
          {:ok, map()} | {:error, term()}
  def evaluate_signals(strategy, market_data, current_bar, indicator_values \\ nil) do
    # Calculate indicators if not provided
    with {:ok, indicators} <-
           get_or_calculate_indicators(strategy, market_data, current_bar, indicator_values) do
      # Build evaluation context with indicators and current bar data
      context = build_context(current_bar, indicators)

      # Evaluate each condition type
      with {:ok, entry} <- evaluate_condition(strategy["entry_conditions"], context),
           {:ok, exit} <- evaluate_condition(strategy["exit_conditions"], context),
           {:ok, stop} <- evaluate_condition(strategy["stop_conditions"], context) do
        {:ok,
         %{
           entry: entry,
           exit: exit,
           stop: stop,
           context: context,
           timestamp: get_timestamp(current_bar)
         }}
      end
    end
  end

  defp get_or_calculate_indicators(_strategy, _market_data, _current_bar, indicators)
       when not is_nil(indicators) do
    {:ok, indicators}
  end

  defp get_or_calculate_indicators(strategy, market_data, current_bar, nil) do
    case IndicatorEngine.calculate_at_timestamp(
           strategy,
           market_data,
           get_timestamp(current_bar)
         ) do
      {:ok, values} -> {:ok, values}
      {:error, reason} -> {:error, "Failed to calculate indicators: #{inspect(reason)}"}
    end
  end

  @doc """
  Generates a signal record when conditions are met.

  Creates a detailed signal with trigger information for audit trail.

  ## Parameters
    - `signal_type`: :entry, :exit, or :stop
    - `strategy_id`: Strategy UUID
    - `session_id`: Trading session UUID
    - `evaluation_result`: Result from evaluate_signals/4

  ## Returns
    - `{:ok, signal}` - Signal map ready for database insert
    - `{:error, reason}` - Error tuple

  ## Examples

      iex> result = %{entry: true, context: %{"rsi_14" => 25, ...}, timestamp: ~U[...]}
      iex> SignalEvaluator.generate_signal(:entry, strategy_id, session_id, result)
      {:ok, %{
        signal_type: "entry",
        strategy_id: strategy_id,
        session_id: session_id,
        timestamp: ~U[...],
        trigger_conditions: %{entry_conditions: true},
        indicator_values: %{"rsi_14" => 25, ...},
        price_at_signal: 42100.0
      }}
  """
  @spec generate_signal(atom(), String.t(), String.t(), map()) ::
          {:ok, map()} | {:error, term()}
  def generate_signal(signal_type, strategy_id, session_id, evaluation_result) do
    %{context: context, timestamp: timestamp} = evaluation_result

    # Determine which conditions triggered
    triggered =
      case signal_type do
        :entry -> evaluation_result[:entry]
        :exit -> evaluation_result[:exit]
        :stop -> evaluation_result[:stop]
      end

    if triggered do
      signal = %{
        signal_type: Atom.to_string(signal_type),
        strategy_id: strategy_id,
        session_id: session_id,
        timestamp: timestamp,
        trigger_conditions: build_trigger_conditions(signal_type, evaluation_result),
        indicator_values: extract_indicator_values(context),
        price_at_signal: get_price(context),
        trading_pair: context["symbol"] || "UNKNOWN"
      }

      {:ok, signal}
    else
      {:error, "Signal conditions not met for #{signal_type}"}
    end
  end

  @doc """
  Validates that strategy conditions reference only defined indicators.

  ## Parameters
    - `strategy`: Strategy definition
    - `defined_indicators`: List of indicator names from strategy

  ## Returns
    - `:ok` - All conditions are valid
    - `{:error, errors}` - List of validation errors

  ## Examples

      iex> strategy = %{
      ...>   "entry_conditions" => "rsi_14 < 30",
      ...>   "indicators" => [%{"name" => "rsi_14", ...}]
      ...> }
      iex> SignalEvaluator.validate_conditions(strategy)
      :ok
  """
  @spec validate_conditions(map()) :: :ok | {:error, list(String.t())}
  def validate_conditions(strategy) do
    indicator_names =
      (strategy["indicators"] || [])
      |> Enum.map(& &1["name"])

    conditions = [
      {"entry_conditions", strategy["entry_conditions"]},
      {"exit_conditions", strategy["exit_conditions"]},
      {"stop_conditions", strategy["stop_conditions"]}
    ]

    errors =
      Enum.reduce(conditions, [], fn {name, condition}, acc ->
        case validate_single_condition(condition, indicator_names) do
          :ok -> acc
          {:error, errs} -> [{name, errs} | acc]
        end
      end)

    case errors do
      [] -> :ok
      _ -> {:error, format_validation_errors(errors)}
    end
  end

  @doc """
  Detects conflicting conditions (entry and exit both true simultaneously).

  ## Parameters
    - `evaluation_result`: Result from evaluate_signals/4

  ## Returns
    - `:ok` - No conflicts
    - `{:error, reason}` - Conflict detected

  ## Examples

      iex> result = %{entry: true, exit: true, stop: false}
      iex> SignalEvaluator.detect_conflicts(result)
      {:error, "Conflicting signals: entry and exit both triggered"}
  """
  @spec detect_conflicts(map()) :: :ok | {:error, String.t()}
  def detect_conflicts(%{entry: true, exit: true}) do
    {:error, "Conflicting signals: entry and exit both triggered"}
  end

  def detect_conflicts(%{entry: true, stop: true}) do
    {:error, "Conflicting signals: entry and stop both triggered"}
  end

  def detect_conflicts(_), do: :ok

  # Private Functions

  defp evaluate_condition(nil, _context) do
    {:ok, false}
  end

  defp evaluate_condition(condition, context) when is_binary(condition) do
    case ConditionParser.evaluate(condition, context) do
      {:ok, result} when is_boolean(result) ->
        {:ok, result}

      {:ok, result} ->
        Logger.warning("Condition evaluated to non-boolean: #{inspect(result)}")
        {:ok, false}

      {:error, _} = error ->
        error
    end
  end

  defp build_context(current_bar, indicator_values) do
    # Merge indicator values with current bar OHLCV data
    base_context = %{
      "open" => normalize_value(get_field(current_bar, "open")),
      "high" => normalize_value(get_field(current_bar, "high")),
      "low" => normalize_value(get_field(current_bar, "low")),
      "close" => normalize_value(get_field(current_bar, "close")),
      "volume" => normalize_value(get_field(current_bar, "volume")),
      "price" => normalize_value(get_field(current_bar, "close")),
      "symbol" => get_field(current_bar, "symbol") || get_field(current_bar, :symbol)
    }

    # Add indicator values
    indicator_context =
      Enum.reduce(indicator_values, %{}, fn {name, value}, acc ->
        Map.put(acc, name, normalize_value(value))
      end)

    Map.merge(base_context, indicator_context)
  end

  defp build_trigger_conditions(signal_type, evaluation_result) do
    %{
      "#{signal_type}_conditions" => true,
      "evaluated_at" => evaluation_result[:timestamp]
    }
  end

  defp extract_indicator_values(context) do
    # Remove reserved variables, keep only indicators
    reserved = ~w(open high low close volume price timestamp symbol)

    context
    |> Enum.reject(fn {key, _value} -> key in reserved end)
    |> Map.new()
  end

  defp get_price(context) do
    context["close"] || context["price"] || 0.0
  end

  defp get_field(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, String.to_atom(key))
  end

  defp get_field(struct, key) do
    Map.get(struct, key)
  end

  defp get_timestamp(%{timestamp: ts}), do: ts
  defp get_timestamp(%{"timestamp" => ts}), do: ts
  defp get_timestamp(_), do: DateTime.utc_now()

  defp normalize_value(%Decimal{} = d), do: Decimal.to_float(d)
  defp normalize_value(value), do: value

  defp validate_single_condition(condition, indicator_names) when is_binary(condition) do
    ConditionParser.validate_variables(condition, indicator_names)
  end

  defp validate_single_condition(nil, _indicator_names), do: :ok

  defp format_validation_errors(errors) do
    Enum.flat_map(errors, fn {condition_name, errs} ->
      Enum.map(errs, fn err -> "#{condition_name}: #{err}" end)
    end)
  end
end
