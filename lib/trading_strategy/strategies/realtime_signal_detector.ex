defmodule TradingStrategy.Strategies.RealtimeSignalDetector do
  @moduledoc """
  Real-time signal detection for paper trading.

  Evaluates entry/exit/stop conditions on each indicator update and emits
  signal events when conditions are met. Reuses the existing SignalEvaluator
  and ConditionParser from backtesting.

  Designed for low-latency real-time signal generation.
  """

  use GenServer
  require Logger

  alias TradingStrategy.Strategies.SignalEvaluator
  alias TradingStrategy.Strategies.ConditionParser

  defstruct [
    :strategy,
    :symbol,
    :current_bar,
    :latest_indicators,
    :subscribers,
    :last_signals,
    :signal_history
  ]

  @max_signal_history 100

  # Client API

  @doc """
  Starts a real-time signal detector for a strategy.

  ## Parameters
    - `opts`: Options
      - `:strategy` - Strategy definition (required)
      - `:symbol` - Trading pair symbol (required)
      - `:name` - GenServer name (optional)
  """
  def start_link(opts) do
    name = Keyword.get(opts, :name)

    if name,
      do: GenServer.start_link(__MODULE__, opts, name: name),
      else: GenServer.start_link(__MODULE__, opts)
  end

  @doc """
  Updates the detector with new indicator values and current bar.

  Evaluates all signal conditions and notifies subscribers if signals are generated.

  ## Parameters
    - `detector`: Detector PID or name
    - `indicator_values`: Map of indicator_name => value
    - `current_bar`: Current OHLCV bar data

  ## Returns
    - `{:ok, signals}` - Evaluation result with entry/exit/stop booleans
    - `{:error, reason}` - Evaluation error
  """
  def evaluate(detector, indicator_values, current_bar) do
    GenServer.call(detector, {:evaluate, indicator_values, current_bar})
  end

  @doc """
  Subscribes a process to receive signal notifications.

  Notifications sent as:
  - `{:signal_detected, :entry, signal_data}` - Entry signal
  - `{:signal_detected, :exit, signal_data}` - Exit signal
  - `{:signal_detected, :stop, signal_data}` - Stop signal

  ## Parameters
    - `detector`: Detector PID or name
    - `subscriber_pid`: Process to notify (defaults to caller)
  """
  def subscribe(detector, subscriber_pid \\ nil) do
    subscriber = subscriber_pid || self()
    GenServer.call(detector, {:subscribe, subscriber})
  end

  @doc """
  Unsubscribes a process from signal notifications.
  """
  def unsubscribe(detector, subscriber_pid \\ nil) do
    subscriber = subscriber_pid || self()
    GenServer.call(detector, {:unsubscribe, subscriber})
  end

  @doc """
  Gets the last evaluated signals (without triggering re-evaluation).
  """
  def get_last_signals(detector) do
    GenServer.call(detector, :get_last_signals)
  end

  @doc """
  Gets the signal history (recent signals that were generated).
  """
  def get_signal_history(detector) do
    GenServer.call(detector, :get_signal_history)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    strategy = Keyword.fetch!(opts, :strategy)
    symbol = Keyword.fetch!(opts, :symbol)

    state = %__MODULE__{
      strategy: strategy,
      symbol: symbol,
      current_bar: nil,
      latest_indicators: nil,
      subscribers: MapSet.new(),
      last_signals: nil,
      signal_history: []
    }

    Logger.info("[RealtimeSignalDetector] Started for #{symbol}")

    {:ok, state}
  end

  @impl true
  def handle_call({:evaluate, indicator_values, current_bar}, _from, state) do
    # Build evaluation context
    context = build_context(current_bar, indicator_values)

    # Evaluate all conditions
    result =
      with {:ok, entry} <- evaluate_condition(state.strategy["entry_conditions"], context),
           {:ok, exit} <- evaluate_condition(state.strategy["exit_conditions"], context),
           {:ok, stop} <- evaluate_condition(state.strategy["stop_conditions"], context) do
        signals = %{
          entry: entry,
          exit: exit,
          stop: stop,
          context: context,
          timestamp: get_timestamp(current_bar),
          symbol: state.symbol
        }

        {:ok, signals}
      end

    case result do
      {:ok, signals} ->
        # Check for conflicts
        case SignalEvaluator.detect_conflicts(signals) do
          :ok ->
            # Update state
            new_state = %{
              state
              | latest_indicators: indicator_values,
                current_bar: current_bar,
                last_signals: signals
            }

            # Notify subscribers of any triggered signals
            new_state = notify_and_record_signals(new_state, signals)

            {:reply, {:ok, signals}, new_state}

          {:error, conflict_reason} ->
            Logger.warning("[RealtimeSignalDetector] #{state.symbol}: #{conflict_reason}")

            # Still update state but report conflict
            new_state = %{
              state
              | latest_indicators: indicator_values,
                current_bar: current_bar,
                last_signals: signals
            }

            {:reply, {:ok, Map.put(signals, :conflict, conflict_reason)}, new_state}
        end

      {:error, reason} = error ->
        Logger.error(
          "[RealtimeSignalDetector] #{state.symbol}: Evaluation failed: #{inspect(reason)}"
        )

        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:subscribe, subscriber}, _from, state) do
    new_state = %{state | subscribers: MapSet.put(state.subscribers, subscriber)}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:unsubscribe, subscriber}, _from, state) do
    new_state = %{state | subscribers: MapSet.delete(state.subscribers, subscriber)}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:get_last_signals, _from, state) do
    case state.last_signals do
      nil -> {:reply, {:error, :no_signals}, state}
      signals -> {:reply, {:ok, signals}, state}
    end
  end

  @impl true
  def handle_call(:get_signal_history, _from, state) do
    {:reply, {:ok, Enum.reverse(state.signal_history)}, state}
  end

  # Private Functions

  defp evaluate_condition(nil, _context), do: {:ok, false}

  defp evaluate_condition(condition, context) when is_binary(condition) do
    case ConditionParser.evaluate(condition, context) do
      {:ok, result} when is_boolean(result) ->
        {:ok, result}

      {:ok, result} ->
        Logger.warning(
          "[RealtimeSignalDetector] Condition evaluated to non-boolean: #{inspect(result)}"
        )

        {:ok, false}

      {:error, _} = error ->
        error
    end
  end

  defp build_context(current_bar, indicator_values) do
    # Merge indicator values with current bar OHLCV data
    base_context = %{
      "open" => normalize_value(get_field(current_bar, :open) || get_field(current_bar, "open")),
      "high" => normalize_value(get_field(current_bar, :high) || get_field(current_bar, "high")),
      "low" => normalize_value(get_field(current_bar, :low) || get_field(current_bar, "low")),
      "close" =>
        normalize_value(get_field(current_bar, :close) || get_field(current_bar, "close")),
      "volume" =>
        normalize_value(get_field(current_bar, :volume) || get_field(current_bar, "volume")),
      "price" =>
        normalize_value(get_field(current_bar, :close) || get_field(current_bar, "close")),
      "symbol" => get_field(current_bar, :symbol) || get_field(current_bar, "symbol")
    }

    # Add indicator values
    indicator_context =
      Enum.reduce(indicator_values, %{}, fn {name, value}, acc ->
        Map.put(acc, name, normalize_value(value))
      end)

    Map.merge(base_context, indicator_context)
  end

  defp notify_and_record_signals(state, signals) do
    # Check each signal type and notify if triggered
    triggered_signals =
      [:entry, :exit, :stop]
      |> Enum.filter(fn type -> Map.get(signals, type) == true end)

    if Enum.empty?(triggered_signals) do
      state
    else
      # Notify subscribers
      Enum.each(triggered_signals, fn signal_type ->
        signal_data = build_signal_data(signal_type, signals, state)

        Enum.each(state.subscribers, fn subscriber ->
          send(subscriber, {:signal_detected, signal_type, signal_data})
        end)

        Logger.info(
          "[RealtimeSignalDetector] #{state.symbol}: #{signal_type} signal detected at " <>
            "price=#{Map.get(signals.context, "close")}"
        )
      end)

      # Record in history
      new_history =
        Enum.reduce(triggered_signals, state.signal_history, fn signal_type, acc ->
          signal_data = build_signal_data(signal_type, signals, state)
          [signal_data | acc]
        end)
        |> Enum.take(@max_signal_history)

      %{state | signal_history: new_history}
    end
  end

  defp build_signal_data(signal_type, signals, state) do
    %{
      signal_type: signal_type,
      symbol: state.symbol,
      timestamp: signals.timestamp,
      price: Map.get(signals.context, "close"),
      indicator_values: extract_indicator_values(signals.context),
      conditions_met: %{
        entry: signals.entry,
        exit: signals.exit,
        stop: signals.stop
      }
    }
  end

  defp extract_indicator_values(context) do
    # Remove reserved variables, keep only indicators
    reserved = ~w(open high low close volume price timestamp symbol)

    context
    |> Enum.reject(fn {key, _value} -> key in reserved end)
    |> Map.new()
  end

  defp get_field(map, key) when is_map(map) do
    Map.get(map, key)
  end

  defp get_field(_, _), do: nil

  defp get_timestamp(%{timestamp: ts}), do: ts
  defp get_timestamp(%{"timestamp" => ts}), do: ts
  defp get_timestamp(_), do: DateTime.utc_now()

  defp normalize_value(%Decimal{} = d), do: Decimal.to_float(d)
  defp normalize_value(value), do: value
end
