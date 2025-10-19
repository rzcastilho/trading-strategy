defmodule TradingStrategy do
  @moduledoc """
  A comprehensive library for defining and executing trading strategies in Elixir.

  TradingStrategy provides a declarative DSL for creating trading strategies,
  a powerful execution engine for real-time signal generation, and a backtesting
  framework for testing strategies against historical data.

  ## Features

  - **Declarative DSL**: Define strategies using an intuitive, macro-based syntax
  - **Indicator Integration**: Seamless integration with trading-indicators library
  - **Decimal Precision**: All price calculations use Decimal for exact precision
  - **Boolean Logic**: Combine conditions with AND/OR/NOT operators
  - **Pattern Recognition**: Detect 11 candlestick patterns automatically
  - **Multi-timeframe Analysis**: Analyze multiple timeframes simultaneously
  - **GenServer-based Engine**: Real-time strategy execution with state management
  - **Backtesting**: Comprehensive performance metrics and equity curves
  - **Position Management**: Track open/closed positions with P&L calculations

  ## Data Precision

  All OHLCV price values (open, high, low, close) use `Decimal.t()` for exact
  precision, eliminating floating-point rounding errors common in financial
  calculations. This ensures accurate backtesting results and reliable signal
  generation.

  Use `TradingStrategy.Types.new_ohlcv/6` to create properly formatted candle data:

      alias TradingStrategy.Types
      candle = Types.new_ohlcv(50000, 51000, 49500, 50500, 1000)
      # => %{open: #Decimal<50000>, high: #Decimal<51000>, ...}

  ## Quick Start

  Define a strategy using the DSL:

      defmodule MyStrategy do
        use TradingStrategy.DSL

        defstrategy :ma_crossover do
          description "Moving average crossover strategy"

          indicator :sma_fast, TradingIndicators.SMA, period: 10
          indicator :sma_slow, TradingIndicators.SMA, period: 30
          indicator :rsi, TradingIndicators.RSI, period: 14

          entry_signal :long do
            when_all do
              cross_above(:sma_fast, :sma_slow)
              indicator(:rsi) > 30
            end
          end

          exit_signal do
            when_any do
              cross_below(:sma_fast, :sma_slow)
              indicator(:rsi) > 70
            end
          end
        end
      end

  Run a backtest:

      alias TradingStrategy.Types

      # Create market data with Decimal precision
      market_data = [
        Types.new_ohlcv(100, 105, 95, 102, 1000, ~U[2025-01-01 00:00:00Z]),
        Types.new_ohlcv(102, 108, 100, 106, 1100, ~U[2025-01-01 01:00:00Z])
        # ... more candles
      ]

      strategy = MyStrategy.strategy_definition()

      result = TradingStrategy.backtest(
        strategy: strategy,
        market_data: market_data,
        symbol: "BTCUSD",
        initial_capital: 10_000
      )

      TradingStrategy.print_report(result)

  Start a live strategy engine:

      {:ok, engine} = TradingStrategy.start_strategy(
        strategy: strategy,
        symbol: "BTCUSD"
      )

      # Process new market data with Decimal precision
      new_candle = Types.new_ohlcv(50000, 51000, 49500, 50500, 1000)
      TradingStrategy.process_data(engine, new_candle)

  ## OHLCV Data Format

  All market data must follow this structure with Decimal price values:

      %{
        open: Decimal.t(),
        high: Decimal.t(),
        low: Decimal.t(),
        close: Decimal.t(),
        volume: non_neg_integer(),
        timestamp: DateTime.t()
      }

  See `TradingStrategy.Types` for helper functions.
  """

  alias TradingStrategy.{
    Engine,
    Backtest,
    Definition,
    Indicators,
    Patterns,
    ConditionEvaluator
  }

  # Re-export commonly used modules for convenience
  defdelegate start_link(opts), to: Engine
  defdelegate process_market_data(engine, data), to: Engine
  defdelegate get_state(engine), to: Engine
  defdelegate get_open_positions(engine), to: Engine
  defdelegate get_signals(engine), to: Engine
  defdelegate stop(engine), to: Engine

  @doc """
  Starts a strategy engine for real-time execution.

  ## Options

    * `:strategy` - Strategy definition (required)
    * `:symbol` - Trading symbol
    * `:initial_capital` - Starting capital
    * `:position_size` - Position size per trade
    * `:name` - Process name (optional)

  ## Examples

      strategy = MyStrategy.strategy_definition()

      {:ok, engine} = TradingStrategy.start_strategy(
        strategy: strategy,
        symbol: "BTCUSD",
        initial_capital: 10_000
      )
  """
  def start_strategy(opts) do
    Engine.start_link(opts)
  end

  @doc """
  Processes new market data through a running strategy engine.

  ## Examples

      candle = %{
        open: 50000,
        high: 51000,
        low: 49500,
        close: 50500,
        volume: 1000,
        timestamp: DateTime.utc_now()
      }

      {:ok, result} = TradingStrategy.process_data(engine, candle)
  """
  def process_data(engine, market_data) do
    Engine.process_market_data(engine, market_data)
  end

  @doc """
  Runs a backtest on historical market data.

  ## Options

    * `:strategy` - Strategy definition (required)
    * `:market_data` - Historical candles (required)
    * `:symbol` - Trading symbol
    * `:initial_capital` - Starting capital
    * `:commission` - Trading commission (decimal, e.g., 0.001 = 0.1%)
    * `:slippage` - Slippage per trade

  ## Examples

      result = TradingStrategy.backtest(
        strategy: strategy,
        market_data: historical_candles,
        symbol: "BTCUSD",
        initial_capital: 10_000,
        commission: 0.001
      )
  """
  def backtest(opts) do
    Backtest.run(opts)
  end

  @doc """
  Prints a formatted backtest report.

  ## Examples

      result = TradingStrategy.backtest(...)
      TradingStrategy.print_report(result)
  """
  def print_report(backtest_result) do
    Backtest.print_report(backtest_result)
  end

  @doc """
  Detects candlestick patterns in market data.

  ## Examples

      patterns = TradingStrategy.detect_patterns(candles)
      # [:hammer, :bullish_engulfing]
  """
  def detect_patterns(candles) do
    Patterns.detect_all(candles)
  end

  @doc """
  Calculates all indicators for a strategy.

  ## Examples

      indicators = TradingStrategy.calculate_indicators(strategy, market_data)
      # %{sma_fast: 101.0, sma_slow: 100.5, rsi: 55.2}
  """
  def calculate_indicators(strategy, market_data) do
    Indicators.calculate_all(strategy, market_data)
  end

  @doc """
  Evaluates a condition against a context.

  ## Examples

      condition = %{type: :when_all, conditions: [...]}
      context = %{indicators: %{rsi: 55}, ...}

      TradingStrategy.evaluate_condition(condition, context)
      # true or false
  """
  def evaluate_condition(condition, context) do
    ConditionEvaluator.evaluate(condition, context)
  end

  @doc """
  Creates a new strategy definition programmatically.

  ## Examples

      strategy = TradingStrategy.new_strategy(:my_strategy,
        description: "A custom strategy"
      )
  """
  def new_strategy(name, opts \\ []) do
    Definition.new(name, opts)
  end

  @doc """
  Validates a strategy definition.

  ## Examples

      {:ok, strategy} = TradingStrategy.validate_strategy(strategy)
  """
  def validate_strategy(strategy) do
    Definition.validate(strategy)
  end
end
