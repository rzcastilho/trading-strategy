defmodule Examples.RsiReversal do
  @moduledoc """
  An RSI-based mean reversion strategy with pattern confirmation.

  This strategy looks for oversold/overbought conditions indicated by RSI
  and confirms entries with bullish/bearish candlestick patterns.

  ## Entry Rules (Long)
  - RSI is below 30 (oversold)
  - Hammer or Bullish Engulfing pattern detected

  ## Entry Rules (Short)
  - RSI is above 70 (overbought)
  - Shooting Star or Bearish Engulfing pattern detected

  ## Exit Rules
  - RSI returns to midpoint (45-55 range)

  ## Parameters
  - RSI: 14 periods
  - Pattern lookback: 3 candles
  """

  use TradingStrategy.DSL

  defstrategy :rsi_reversal do
    description "RSI reversal strategy with candlestick pattern confirmation"

    # Define indicators
    indicator :rsi, TradingIndicators.RSI, period: 14

    # Long entry signal (oversold reversal)
    entry_signal :long do
      when_all do
        indicator(:rsi) < 30
        when_any do
          pattern(:hammer)
          pattern(:bullish_engulfing)
        end
      end
    end

    # Short entry signal (overbought reversal)
    entry_signal :short do
      when_all do
        indicator(:rsi) > 70
        when_any do
          pattern(:shooting_star)
          pattern(:bearish_engulfing)
        end
      end
    end

    # Exit signal (RSI returns to neutral)
    exit_signal do
      when_all do
        indicator(:rsi) > 45
        indicator(:rsi) < 55
      end
    end
  end
end
