defmodule Examples.MovingAverageCrossover do
  @moduledoc """
  A simple moving average crossover strategy.

  This strategy generates buy signals when a fast moving average crosses
  above a slow moving average, and sell signals when it crosses below.
  Additional confirmation is provided by RSI to avoid overbought/oversold conditions.

  ## Entry Rules (Long)
  - Fast SMA crosses above Slow SMA
  - RSI is above 30 (not oversold)

  ## Exit Rules
  - Fast SMA crosses below Slow SMA
  - OR RSI exceeds 70 (overbought)

  ## Parameters
  - Fast SMA: 10 periods
  - Slow SMA: 30 periods
  - RSI: 14 periods
  """

  use TradingStrategy.DSL

  defstrategy :ma_crossover do
    description "Moving average crossover with RSI confirmation"

    # Define indicators
    indicator :sma_fast, TradingIndicators.SMA, period: 10
    indicator :sma_slow, TradingIndicators.SMA, period: 30
    indicator :rsi, TradingIndicators.RSI, period: 14

    # Long entry signal
    entry_signal :long do
      when_all do
        cross_above(:sma_fast, :sma_slow)
        indicator(:rsi) > 30
      end
    end

    # Exit signal
    exit_signal do
      when_any do
        cross_below(:sma_fast, :sma_slow)
        indicator(:rsi) > 70
      end
    end
  end
end
