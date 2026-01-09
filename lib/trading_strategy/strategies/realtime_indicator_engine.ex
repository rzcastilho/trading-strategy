defmodule TradingStrategy.Strategies.RealtimeIndicatorEngine do
  @moduledoc """
  Real-time indicator calculation engine for paper trading.

  Updates indicators incrementally on each new market data tick, maintaining
  a rolling window of candles for efficient recalculation. Reuses the existing
  IndicatorEngine for calculation logic.

  Designed for real-time performance with minimal latency.
  """

  use GenServer
  require Logger

  alias TradingStrategy.Strategies.IndicatorEngine
  alias TradingStrategy.MarketData.Cache

  @default_window_size 500
  @default_update_interval 1000

  defstruct [
    :strategy,
    :symbol,
    :timeframe,
    :window_size,
    :candle_buffer,
    :latest_indicators,
    :subscribers,
    :update_interval,
    :last_update
  ]

  # Client API

  @doc """
  Starts a real-time indicator engine for a strategy.

  ## Parameters
    - `opts`: Options
      - `:strategy` - Strategy definition (required)
      - `:symbol` - Trading pair symbol (required)
      - `:timeframe` - Candle timeframe, e.g., "1m", "5m" (default: "1m")
      - `:window_size` - Number of candles to maintain (default: 500)
      - `:update_interval` - Min ms between updates (default: 1000)
      - `:name` - GenServer name (optional)
  """
  def start_link(opts) do
    name = Keyword.get(opts, :name)

    if name,
      do: GenServer.start_link(__MODULE__, opts, name: name),
      else: GenServer.start_link(__MODULE__, opts)
  end

  @doc """
  Updates the engine with a new candle.

  ## Parameters
    - `engine`: Engine PID or name
    - `candle`: New OHLCV candle data

  ## Returns
    - `{:ok, indicator_values}` - Updated indicator values
    - `{:error, reason}` - Update error
  """
  def update_candle(engine, candle) do
    GenServer.call(engine, {:update_candle, candle})
  end

  @doc """
  Updates the engine with the latest price (creates/updates current candle).

  For tick-by-tick updates when full candles aren't available yet.

  ## Parameters
    - `engine`: Engine PID or name
    - `price`: Current price
    - `timestamp`: Price timestamp (optional, defaults to now)
  """
  def update_price(engine, price, timestamp \\ nil) do
    GenServer.call(engine, {:update_price, price, timestamp || DateTime.utc_now()})
  end

  @doc """
  Gets the current indicator values without triggering an update.

  ## Parameters
    - `engine`: Engine PID or name

  ## Returns
    - `{:ok, indicator_values}` - Current values
    - `{:error, :not_ready}` - Not enough data yet
  """
  def get_current_indicators(engine) do
    GenServer.call(engine, :get_current_indicators)
  end

  @doc """
  Subscribes a process to receive indicator update notifications.

  Notifications sent as: `{:indicator_update, symbol, indicator_values}`

  ## Parameters
    - `engine`: Engine PID or name
    - `subscriber_pid`: Process to notify (defaults to caller)
  """
  def subscribe(engine, subscriber_pid \\ nil) do
    subscriber = subscriber_pid || self()
    GenServer.call(engine, {:subscribe, subscriber})
  end

  @doc """
  Unsubscribes a process from indicator updates.
  """
  def unsubscribe(engine, subscriber_pid \\ nil) do
    subscriber = subscriber_pid || self()
    GenServer.call(engine, {:unsubscribe, subscriber})
  end

  @doc """
  Gets the current candle buffer (for debugging/analysis).
  """
  def get_candle_buffer(engine) do
    GenServer.call(engine, :get_candle_buffer)
  end

  @doc """
  Preloads historical candles into the buffer.

  Useful for initializing the engine with past data before starting real-time updates.

  ## Parameters
    - `engine`: Engine PID or name
    - `historical_candles`: List of OHLCV candles (sorted oldest to newest)
  """
  def preload_history(engine, historical_candles) do
    GenServer.call(engine, {:preload_history, historical_candles})
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    strategy = Keyword.fetch!(opts, :strategy)
    symbol = Keyword.fetch!(opts, :symbol)
    timeframe = Keyword.get(opts, :timeframe, "1m")
    window_size = Keyword.get(opts, :window_size, @default_window_size)
    update_interval = Keyword.get(opts, :update_interval, @default_update_interval)

    state = %__MODULE__{
      strategy: strategy,
      symbol: symbol,
      timeframe: timeframe,
      window_size: window_size,
      candle_buffer: [],
      latest_indicators: nil,
      subscribers: MapSet.new(),
      update_interval: update_interval,
      last_update: nil
    }

    Logger.info(
      "[RealtimeIndicatorEngine] Started for #{symbol} (#{timeframe}), " <>
        "window=#{window_size}, interval=#{update_interval}ms"
    )

    {:ok, state}
  end

  @impl true
  def handle_call({:update_candle, candle}, _from, state) do
    # Add candle to buffer
    updated_buffer = add_candle_to_buffer(state.candle_buffer, candle, state.window_size)

    # Check if enough time has passed since last update (rate limiting)
    should_calculate = should_recalculate?(state)

    if should_calculate do
      case calculate_indicators(state.strategy, updated_buffer) do
        {:ok, indicators} ->
          new_state = %{
            state
            | candle_buffer: updated_buffer,
              latest_indicators: indicators,
              last_update: DateTime.utc_now()
          }

          # Notify subscribers
          notify_subscribers(new_state, indicators)

          {:reply, {:ok, indicators}, new_state}

        {:error, reason} ->
          # Keep buffer but don't update indicators
          new_state = %{state | candle_buffer: updated_buffer}
          {:reply, {:error, reason}, new_state}
      end
    else
      # Update buffer but don't recalculate yet
      new_state = %{state | candle_buffer: updated_buffer}
      {:reply, {:ok, state.latest_indicators}, new_state}
    end
  end

  @impl true
  def handle_call({:update_price, price, timestamp}, _from, state) do
    # Create or update the current candle based on latest price
    updated_buffer =
      case state.candle_buffer do
        [] ->
          # First candle
          [create_candle_from_price(state.symbol, price, timestamp)]

        [latest | rest] ->
          # Check if this price belongs to current candle or new candle
          if same_candle_period?(latest, timestamp, state.timeframe) do
            # Update current candle
            updated_candle = update_candle_with_price(latest, price, timestamp)
            [updated_candle | rest]
          else
            # New candle period
            new_candle = create_candle_from_price(state.symbol, price, timestamp)
            add_candle_to_buffer(state.candle_buffer, new_candle, state.window_size)
          end
      end

    # Recalculate if enough time passed
    should_calculate = should_recalculate?(state)

    if should_calculate do
      case calculate_indicators(state.strategy, updated_buffer) do
        {:ok, indicators} ->
          new_state = %{
            state
            | candle_buffer: updated_buffer,
              latest_indicators: indicators,
              last_update: DateTime.utc_now()
          }

          notify_subscribers(new_state, indicators)
          {:reply, {:ok, indicators}, new_state}

        {:error, reason} ->
          new_state = %{state | candle_buffer: updated_buffer}
          {:reply, {:error, reason}, new_state}
      end
    else
      new_state = %{state | candle_buffer: updated_buffer}
      {:reply, {:ok, state.latest_indicators}, new_state}
    end
  end

  @impl true
  def handle_call(:get_current_indicators, _from, state) do
    case state.latest_indicators do
      nil -> {:reply, {:error, :not_ready}, state}
      indicators -> {:reply, {:ok, indicators}, state}
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
  def handle_call(:get_candle_buffer, _from, state) do
    {:reply, {:ok, state.candle_buffer}, state}
  end

  @impl true
  def handle_call({:preload_history, historical_candles}, _from, state) do
    # Take only the most recent candles up to window_size
    buffer =
      historical_candles
      |> Enum.take(-state.window_size)

    # Calculate initial indicators
    case calculate_indicators(state.strategy, buffer) do
      {:ok, indicators} ->
        new_state = %{
          state
          | candle_buffer: buffer,
            latest_indicators: indicators,
            last_update: DateTime.utc_now()
        }

        Logger.info(
          "[RealtimeIndicatorEngine] Preloaded #{length(buffer)} candles for #{state.symbol}"
        )

        {:reply, {:ok, indicators}, new_state}

      {:error, reason} ->
        Logger.warning(
          "[RealtimeIndicatorEngine] Failed to calculate indicators on preload: #{inspect(reason)}"
        )

        new_state = %{state | candle_buffer: buffer}
        {:reply, {:error, reason}, new_state}
    end
  end

  # Private Functions

  defp add_candle_to_buffer(buffer, candle, max_size) do
    updated_buffer = [candle | buffer]

    if length(updated_buffer) > max_size do
      Enum.take(updated_buffer, max_size)
    else
      updated_buffer
    end
  end

  defp calculate_indicators(strategy, candle_buffer) do
    # Reverse buffer to oldest-first for indicator calculation
    candles = Enum.reverse(candle_buffer)

    case IndicatorEngine.calculate_all(strategy, candles) do
      {:ok, results} ->
        # Extract latest values from each indicator
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

  defp extract_latest_value(%{values: values}) when is_list(values), do: List.last(values)
  defp extract_latest_value(%{value: value}), do: value
  defp extract_latest_value(value) when is_number(value), do: value
  defp extract_latest_value(values) when is_list(values), do: List.last(values)
  defp extract_latest_value(result) when is_map(result), do: result
  defp extract_latest_value(other), do: other

  defp should_recalculate?(%{last_update: nil}), do: true

  defp should_recalculate?(state) do
    elapsed = DateTime.diff(DateTime.utc_now(), state.last_update, :millisecond)
    elapsed >= state.update_interval
  end

  defp notify_subscribers(state, indicators) do
    Enum.each(state.subscribers, fn subscriber ->
      send(subscriber, {:indicator_update, state.symbol, indicators})
    end)
  end

  defp create_candle_from_price(symbol, price, timestamp) do
    %{
      symbol: symbol,
      timestamp: timestamp,
      open: price / 1.0,
      high: price / 1.0,
      low: price / 1.0,
      close: price / 1.0,
      volume: 0.0
    }
  end

  defp update_candle_with_price(candle, price, timestamp) do
    %{
      candle
      | high: max(candle.high, price),
        low: min(candle.low, price),
        close: price / 1.0,
        timestamp: timestamp
    }
  end

  defp same_candle_period?(candle, new_timestamp, timeframe) do
    candle_time = get_timestamp(candle)
    period_seconds = parse_timeframe_to_seconds(timeframe)

    # Check if timestamps fall in same period
    candle_period = div(DateTime.to_unix(candle_time), period_seconds)
    new_period = div(DateTime.to_unix(new_timestamp), period_seconds)

    candle_period == new_period
  end

  defp parse_timeframe_to_seconds(timeframe) do
    # Parse timeframes like "1m", "5m", "1h", "1d"
    case Regex.run(~r/^(\d+)([smhd])$/, timeframe) do
      [_, num_str, unit] ->
        num = String.to_integer(num_str)

        case unit do
          "s" -> num
          "m" -> num * 60
          "h" -> num * 60 * 60
          "d" -> num * 60 * 60 * 24
        end

      _ ->
        # Default to 1 minute if can't parse
        60
    end
  end

  defp get_timestamp(%{timestamp: timestamp}), do: timestamp
  defp get_timestamp(%{"timestamp" => timestamp}), do: timestamp
end
