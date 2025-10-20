defmodule TradingStrategy.Engine do
  @moduledoc """
  GenServer-based strategy execution engine with Decimal precision.

  Provides real-time strategy execution, managing state, processing market
  data, generating trading signals, and tracking positions. All market data
  and calculations use Decimal precision for accurate signal generation.

  ## Features

  - **Real-time Processing**: Process market data as it arrives
  - **State Management**: Track positions, signals, and indicators
  - **Signal Generation**: Automatic entry/exit signal evaluation
  - **Position Tracking**: Manage open and closed positions
  - **Process Registry**: Support multiple concurrent strategy engines
  - **Decimal Precision**: All price calculations use Decimal

  ## Architecture

  Each strategy runs in its own GenServer process, providing:

  - Isolated state per strategy
  - Concurrent execution of multiple strategies
  - Fault tolerance through OTP supervision
  - Message-based communication

  ## Usage

      alias TradingStrategy.{Engine, Types}

      # Start an engine
      {:ok, engine} = Engine.start_link(
        strategy: my_strategy,
        symbol: "BTCUSD",
        initial_capital: 10_000,
        max_positions: 3
      )

      # Process new market data with Decimal precision
      new_candle = Types.new_ohlcv(50000, 51000, 49500, 50500, 1000)
      {:ok, result} = Engine.process_market_data(engine, new_candle)

      # Check generated signals
      case result.signals do
        [] -> :no_signals
        signals -> handle_signals(signals)
      end

      # Get current state
      state = Engine.get_state(engine)

      # Stop engine
      Engine.stop(engine)

  ## State Structure

  The engine maintains:

  - `:strategy` - Strategy definition
  - `:positions` - Open and closed positions
  - `:signals` - All generated signals
  - `:market_data` - Historical candle data
  - `:indicator_values` - Current indicator values (Decimal)
  - `:historical_indicators` - Past indicator values for cross detection
  - `:indicator_states` - Streaming state for indicators that support it
  - `:config` - Engine configuration (capital, position size, etc.)

  All market data and indicator values use Decimal for exact precision.
  """

  use GenServer
  require Logger

  alias TradingStrategy.{
    Definition,
    Signal,
    Position,
    Indicators,
    ConditionEvaluator
  }

  @type state :: %{
          strategy: Definition.t(),
          positions: list(Position.t()),
          signals: list(Signal.t()),
          market_data: list(map()),
          indicator_values: map(),
          historical_indicators: map(),
          indicator_states: map(),
          config: map()
        }

  # Client API

  @doc """
  Starts a strategy engine.

  ## Options

    * `:strategy` - The strategy definition to execute (required)
    * `:symbol` - Trading symbol (e.g., "BTCUSD")
    * `:initial_capital` - Starting capital for position sizing
    * `:max_positions` - Maximum number of concurrent positions
    * `:position_size` - Position size (fixed or percentage)
  """
  def start_link(opts) do
    strategy = Keyword.fetch!(opts, :strategy)
    name = Keyword.get(opts, :name, strategy.name)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(name))
  end

  @doc """
  Processes new market data through the strategy.
  """
  def process_market_data(engine, market_data) do
    GenServer.call(engine, {:process_market_data, market_data})
  end

  @doc """
  Gets the current state of the engine.
  """
  def get_state(engine) do
    GenServer.call(engine, :get_state)
  end

  @doc """
  Gets all open positions.
  """
  def get_open_positions(engine) do
    GenServer.call(engine, :get_open_positions)
  end

  @doc """
  Gets all generated signals.
  """
  def get_signals(engine) do
    GenServer.call(engine, :get_signals)
  end

  @doc """
  Stops the engine.
  """
  def stop(engine) do
    GenServer.stop(engine)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    strategy = Keyword.fetch!(opts, :strategy)
    symbol = Keyword.get(opts, :symbol, "UNKNOWN")
    initial_capital = Keyword.get(opts, :initial_capital, 10_000.0)
    max_positions = Keyword.get(opts, :max_positions, 1)
    position_size = Keyword.get(opts, :position_size, 1.0)

    # Initialize streaming state for indicators that support it
    indicator_states = initialize_indicator_states(strategy)

    state = %{
      strategy: strategy,
      positions: [],
      signals: [],
      market_data: [],
      indicator_values: %{},
      historical_indicators: %{},
      indicator_states: indicator_states,
      config: %{
        symbol: symbol,
        initial_capital: initial_capital,
        max_positions: max_positions,
        position_size: position_size
      }
    }

    Logger.info("Strategy engine started: #{strategy.name}")

    {:ok, state}
  end

  @impl true
  def handle_call({:process_market_data, new_data}, _from, state) do
    # Append new market data
    updated_market_data = state.market_data ++ [new_data]

    # Update indicators (using streaming when available, batch otherwise)
    {indicator_values, updated_indicator_states} =
      update_indicators(state.strategy, new_data, updated_market_data, state.indicator_states)

    # Calculate historical indicators for cross detection
    historical_indicators = Indicators.calculate_historical(state.strategy, updated_market_data)

    # Build evaluation context
    context =
      ConditionEvaluator.build_context(new_data, indicator_values,
        historical_indicators: historical_indicators
      )

    # Evaluate entry signals
    entry_signals = evaluate_entry_signals(state.strategy, context, state)

    # Evaluate exit signals for open positions
    exit_signals = evaluate_exit_signals(state.strategy, context, state)

    # Update positions based on signals
    {updated_positions, all_signals} =
      process_signals(state.positions, entry_signals ++ exit_signals, new_data, state)

    # Update state
    new_state = %{
      state
      | market_data: updated_market_data,
        indicator_values: indicator_values,
        historical_indicators: historical_indicators,
        indicator_states: updated_indicator_states,
        positions: updated_positions,
        signals: state.signals ++ all_signals
    }

    result = %{
      signals: all_signals,
      open_positions: Enum.filter(updated_positions, &Position.open?/1),
      closed_positions: Enum.filter(updated_positions, &Position.closed?/1)
    }

    {:reply, {:ok, result}, new_state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call(:get_open_positions, _from, state) do
    open_positions = Enum.filter(state.positions, &Position.open?/1)
    {:reply, open_positions, state}
  end

  @impl true
  def handle_call(:get_signals, _from, state) do
    {:reply, state.signals, state}
  end

  # Private Functions

  defp evaluate_entry_signals(%Definition{entry_signals: entry_signals}, context, state) do
    # Only generate entry signals if we have room for more positions
    open_positions_count =
      state.positions
      |> Enum.filter(&Position.open?/1)
      |> length()

    if open_positions_count < state.config.max_positions do
      Enum.filter(entry_signals, fn signal_config ->
        ConditionEvaluator.evaluate(signal_config.condition, context)
      end)
      |> Enum.map(fn signal_config ->
        %{
          type: :entry,
          direction: signal_config.direction,
          timestamp: context.timestamp,
          price: context.candles.close
        }
      end)
    else
      []
    end
  end

  defp evaluate_exit_signals(%Definition{exit_signals: exit_signals}, context, state) do
    # Only evaluate exit signals if we have open positions
    if Enum.any?(state.positions, &Position.open?/1) do
      Enum.filter(exit_signals, fn signal_config ->
        ConditionEvaluator.evaluate(signal_config.condition, context)
      end)
      |> Enum.map(fn _signal_config ->
        %{
          type: :exit,
          timestamp: context.timestamp,
          price: context.candles.close
        }
      end)
    else
      []
    end
  end

  defp process_signals(positions, signals, _market_data, state) do
    Enum.reduce(signals, {positions, []}, fn signal_data, {pos_acc, sig_acc} ->
      case signal_data.type do
        :entry ->
          # Create new position
          signal =
            Signal.new(
              :entry,
              signal_data.direction,
              state.config.symbol,
              signal_data.price,
              timestamp: signal_data.timestamp,
              strategy: state.strategy.name
            )

          position = Position.open(signal, state.config.position_size)
          {pos_acc ++ [position], sig_acc ++ [signal]}

        :exit ->
          # Close open positions
          {closed_positions, exit_signals} = close_open_positions(pos_acc, signal_data, state)
          {closed_positions, sig_acc ++ exit_signals}
      end
    end)
  end

  defp close_open_positions(positions, signal_data, state) do
    Enum.reduce(positions, {[], []}, fn position, {pos_acc, sig_acc} ->
      if Position.open?(position) do
        signal =
          Signal.new(
            :exit,
            position.direction,
            state.config.symbol,
            signal_data.price,
            timestamp: signal_data.timestamp,
            strategy: state.strategy.name
          )

        closed_position = Position.close(position, signal)
        {pos_acc ++ [closed_position], sig_acc ++ [signal]}
      else
        {pos_acc ++ [position], sig_acc}
      end
    end)
  end

  defp via_tuple(name) do
    {:via, Registry, {TradingStrategy.EngineRegistry, name}}
  end

  # Streaming indicator support

  @doc false
  defp initialize_indicator_states(%Definition{indicators: indicators}) do
    Enum.reduce(indicators, %{}, fn {name, config}, acc ->
      if Indicators.supports_streaming?(config.module) do
        # Try init_state/1 first, then init_state/0
        result =
          cond do
            function_exported?(config.module, :init_state, 1) ->
              apply(config.module, :init_state, [config.params])

            function_exported?(config.module, :init_state, 0) ->
              apply(config.module, :init_state, [])

            true ->
              {:error, :no_init_state}
          end

        case result do
          {:ok, state} ->
            Map.put(acc, name, state)

          state when is_map(state) ->
            # Some indicators return state directly without {:ok, state} tuple
            Map.put(acc, name, state)

          {:error, reason} ->
            Logger.warning(
              "Failed to initialize streaming for #{inspect(config.module)}: #{inspect(reason)}"
            )

            acc

          _ ->
            acc
        end
      else
        acc
      end
    end)
  end

  @doc false
  defp update_indicators(strategy, new_data, all_market_data, indicator_states) do
    Enum.reduce(strategy.indicators, {%{}, indicator_states}, fn {name, config},
                                                                  {values_acc, states_acc} ->
      # Try streaming update first if state exists
      case Map.get(states_acc, name) do
        nil ->
          # No streaming state - use batch calculation
          value = Indicators.calculate_indicator(config, all_market_data)
          {Map.put(values_acc, name, value), states_acc}

        streaming_state ->
          # Try streaming update - pass the entire candle, not just the price
          # The indicator will extract the appropriate price based on :source parameter
          case apply(config.module, :update_state, [streaming_state, new_data]) do
            {:ok, new_state, indicator_result} ->
              # Extract value from indicator result
              value =
                case indicator_result do
                  %{value: v} -> v
                  v when is_struct(v, Decimal) -> v
                  v when is_number(v) -> Decimal.new("#{v}")
                  _ -> nil
                end

              {Map.put(values_acc, name, value), Map.put(states_acc, name, new_state)}

            {:error, reason} ->
              Logger.warning(
                "Streaming update failed for #{inspect(config.module)}: #{inspect(reason)}, falling back to batch"
              )

              # Fall back to batch calculation
              value = Indicators.calculate_indicator(config, all_market_data)
              {Map.put(values_acc, name, value), Map.delete(states_acc, name)}

            _ ->
              # Unexpected return - fall back to batch
              value = Indicators.calculate_indicator(config, all_market_data)
              {Map.put(values_acc, name, value), Map.delete(states_acc, name)}
          end
      end
    end)
  end

end
