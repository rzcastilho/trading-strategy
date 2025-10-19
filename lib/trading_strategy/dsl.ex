defmodule TradingStrategy.DSL do
  @moduledoc """
  Provides a declarative DSL for defining trading strategies.

  ## Example

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
  """

  alias TradingStrategy.Definition

  defmacro __using__(_opts) do
    quote do
      import TradingStrategy.DSL
      Module.register_attribute(__MODULE__, :strategy_definition, accumulate: false)
    end
  end

  @doc """
  Defines a new trading strategy.

  The strategy name should be an atom, and the body contains
  the strategy configuration using the DSL.
  """
  defmacro defstrategy(name, do: block) do
    quote do
      @strategy_definition Definition.new(unquote(name))
      unquote(block)

      def strategy_definition do
        @strategy_definition
      end

      def name do
        unquote(name)
      end
    end
  end

  @doc """
  Sets the strategy description.
  """
  defmacro description(text) do
    quote do
      @strategy_definition %{@strategy_definition | description: unquote(text)}
    end
  end

  @doc """
  Defines an indicator to be used in the strategy.

  ## Examples

      indicator :sma, TradingIndicators.SMA, period: 20
      indicator :rsi, TradingIndicators.RSI, period: 14, source: :close
  """
  defmacro indicator(name, module, params \\ []) do
    quote do
      @strategy_definition Definition.add_indicator(
                             @strategy_definition,
                             unquote(name),
                             unquote(module),
                             unquote(params)
                           )
    end
  end

  @doc """
  Defines an entry signal for the strategy.

  ## Examples

      entry_signal :long do
        when_all do
          cross_above(:sma_fast, :sma_slow)
          indicator(:rsi) > 30
        end
      end
  """
  defmacro entry_signal(direction \\ :long, do: block) do
    quote do
      condition = unquote(block)

      @strategy_definition Definition.add_entry_signal(
                             @strategy_definition,
                             unquote(direction),
                             condition
                           )
    end
  end

  @doc """
  Defines an exit signal for the strategy.

  ## Examples

      exit_signal do
        when_any do
          cross_below(:sma_fast, :sma_slow)
          indicator(:rsi) > 70
        end
      end
  """
  defmacro exit_signal(do: block) do
    quote do
      condition = unquote(block)
      @strategy_definition Definition.add_exit_signal(@strategy_definition, condition)
    end
  end

  @doc """
  Combines multiple conditions with AND logic.
  All conditions must be true for the signal to trigger.
  """
  defmacro when_all(do: block) do
    conditions = extract_conditions(block)

    quote do
      %{
        type: :when_all,
        conditions: unquote(conditions)
      }
    end
  end

  @doc """
  Combines multiple conditions with OR logic.
  At least one condition must be true for the signal to trigger.
  """
  defmacro when_any(do: block) do
    conditions = extract_conditions(block)

    quote do
      %{
        type: :when_any,
        conditions: unquote(conditions)
      }
    end
  end

  @doc """
  Negates a condition.
  The signal triggers when the condition is false.
  """
  defmacro when_not(do: block) do
    quote do
      %{
        type: :when_not,
        condition: unquote(block)
      }
    end
  end

  @doc """
  Checks if one indicator crosses above another.
  """
  defmacro cross_above(indicator1, indicator2) do
    quote do
      %{
        type: :cross_above,
        indicator1: unquote(indicator1),
        indicator2: unquote(indicator2)
      }
    end
  end

  @doc """
  Checks if one indicator crosses below another.
  """
  defmacro cross_below(indicator1, indicator2) do
    quote do
      %{
        type: :cross_below,
        indicator1: unquote(indicator1),
        indicator2: unquote(indicator2)
      }
    end
  end

  @doc """
  References an indicator value in a condition.

  ## Examples

      indicator(:rsi) > 70
      indicator(:sma_fast) < indicator(:sma_slow)
  """
  defmacro indicator(name) do
    quote do
      %{
        type: :indicator_ref,
        name: unquote(name)
      }
    end
  end

  @doc """
  Defines a timeframe for multi-timeframe analysis.

  ## Examples

      on_timeframe "1d" do
        indicator(:sma_daily, TradingIndicators.SMA, period: 50)
      end
  """
  defmacro on_timeframe(timeframe, do: block) do
    quote do
      # Store current timeframe context
      current_timeframe = unquote(timeframe)
      unquote(block)
    end
  end

  @doc """
  Defines a pattern to match.

  ## Examples

      pattern :hammer
      pattern :bullish_engulfing
  """
  defmacro pattern(name) do
    quote do
      %{
        type: :pattern,
        name: unquote(name)
      }
    end
  end

  # Helper function to extract conditions from a block
  defp extract_conditions({:__block__, _, conditions}), do: conditions
  defp extract_conditions(single_condition), do: [single_condition]
end
