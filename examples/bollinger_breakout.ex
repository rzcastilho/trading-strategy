defmodule Examples.BollingerBreakout do
  @moduledoc """
  A Bollinger Bands breakout strategy with volume confirmation.

  This strategy enters when price breaks out of the Bollinger Bands
  and is confirmed by above-average volume.

  ## Entry Rules (Long)
  - Price closes above upper Bollinger Band
  - Volume is above SMA of volume

  ## Entry Rules (Short)
  - Price closes below lower Bollinger Band
  - Volume is above SMA of volume

  ## Exit Rules
  - Price returns to middle band (SMA)

  ## Parameters
  - Bollinger Bands: 20 periods, 2 standard deviations
  - Volume SMA: 20 periods
  """

  use TradingStrategy.DSL

  defstrategy :bollinger_breakout do
    description "Bollinger Bands breakout with volume confirmation"

    # Define indicators
    indicator :bb, TradingIndicators.Volatility.BollingerBands, period: 20, deviation: 2, source: :close
    indicator :volume_sma, TradingIndicators.Trend.SMA, period: 20, source: :volume

    # Long entry signal (upper band breakout)
    entry_signal :long do
      when_all do
        indicator(:close) > indicator(:bb, :upper_band)
        indicator(:volume) > indicator(:volume_sma)
      end
    end

    # Short entry signal (lower band breakout)
    entry_signal :short do
      when_all do
        indicator(:close) < indicator(:bb, :lower_band)
        indicator(:volume) > indicator(:volume_sma)
      end
    end

    # Exit signal (return to middle band)
    exit_signal do
      when_any do
        # Long exit: price falls back to middle band
        when_all do
          cross_below(:close, indicator(:bb, :middle_band))
        end
        # Short exit: price rises back to middle band
        when_all do
          cross_above(:close, indicator(:bb, :middle_band))
        end
      end
    end
  end
end
