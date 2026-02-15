# Large Strategy with Extensive Comments Fixture
# Purpose: Comment preservation stress testing (US3)
# Complexity: Large (50 indicators)
# Expected DSL Lines: 1000+
# Comment Blocks: 20+ comment blocks throughout for preservation rate testing

%{
  name: "Large Strategy with Extensive Comments",
  description: "Comprehensive multi-indicator strategy with 50 indicators and extensive documentation for comment preservation testing",
  trading_pair: "BTC/USD",
  timeframe: "1h",

  # ========================================================================
  # SECTION 1: TREND FOLLOWING INDICATORS (10 indicators)
  # ========================================================================
  # This section contains moving averages of various periods to identify
  # trend direction across multiple timeframes. We use both SMA and EMA
  # to capture different aspects of price movement.
  indicators: [
    # --- Short-term Moving Averages (1-5) ---
    # These capture immediate price trends and provide quick signals
    %{
      type: :sma,
      name: "sma_10",
      parameters: %{period: 10, source: :close}
    },
    %{
      type: :sma,
      name: "sma_20",
      parameters: %{period: 20, source: :close}
    },
    %{
      type: :ema,
      name: "ema_9",
      parameters: %{period: 9, source: :close}
    },
    %{
      type: :ema,
      name: "ema_12",
      parameters: %{period: 12, source: :close}
    },
    %{
      type: :ema,
      name: "ema_26",
      parameters: %{period: 26, source: :close}
    },

    # --- Medium-term Moving Averages (6-10) ---
    # These confirm trends and filter out noise from short-term fluctuations
    %{
      type: :sma,
      name: "sma_50",
      parameters: %{period: 50, source: :close}
    },
    %{
      type: :sma,
      name: "sma_100",
      parameters: %{period: 100, source: :close}
    },
    %{
      type: :ema,
      name: "ema_50",
      parameters: %{period: 50, source: :close}
    },
    %{
      type: :sma,
      name: "sma_200",
      parameters: %{period: 200, source: :close}
    },
    %{
      type: :ema,
      name: "ema_200",
      parameters: %{period: 200, source: :close}
    },

    # ========================================================================
    # SECTION 2: MOMENTUM INDICATORS (10 indicators)
    # ========================================================================
    # Momentum indicators help identify overbought/oversold conditions
    # and measure the strength of price movements

    # --- RSI Indicators (11-15) ---
    # Multiple RSI periods to capture momentum at different timeframes
    %{
      type: :rsi,
      name: "rsi_7",
      parameters: %{period: 7, source: :close}
    },
    %{
      type: :rsi,
      name: "rsi_14",
      parameters: %{period: 14, source: :close}
    },
    %{
      type: :rsi,
      name: "rsi_21",
      parameters: %{period: 21, source: :close}
    },
    # RSI on high/low provides additional context
    %{
      type: :rsi,
      name: "rsi_high",
      parameters: %{period: 14, source: :high}
    },
    %{
      type: :rsi,
      name: "rsi_low",
      parameters: %{period: 14, source: :low}
    },

    # --- MACD Indicators (16-20) ---
    # MACD with different parameters for multi-timeframe analysis
    %{
      type: :macd,
      name: "macd_standard",
      parameters: %{fast_period: 12, slow_period: 26, signal_period: 9}
    },
    %{
      type: :macd,
      name: "macd_fast",
      parameters: %{fast_period: 5, slow_period: 13, signal_period: 5}
    },
    %{
      type: :macd,
      name: "macd_slow",
      parameters: %{fast_period: 19, slow_period: 39, signal_period: 9}
    },
    # Stochastic oscillators for additional momentum confirmation
    %{
      type: :stochastic,
      name: "stoch_fast",
      parameters: %{k_period: 14, d_period: 3}
    },
    %{
      type: :stochastic,
      name: "stoch_slow",
      parameters: %{k_period: 14, d_period: 5}
    },

    # ========================================================================
    # SECTION 3: VOLATILITY INDICATORS (10 indicators)
    # ========================================================================
    # These indicators measure market volatility and help with position sizing
    # and stop loss placement

    # --- ATR Indicators (21-25) ---
    # Average True Range for volatility measurement
    %{
      type: :atr,
      name: "atr_7",
      parameters: %{period: 7}
    },
    %{
      type: :atr,
      name: "atr_14",
      parameters: %{period: 14}
    },
    %{
      type: :atr,
      name: "atr_21",
      parameters: %{period: 21}
    },
    # Bollinger Bands with different standard deviations
    %{
      type: :bollinger_bands,
      name: "bb_20_2",
      parameters: %{period: 20, std_dev: 2.0}
    },
    %{
      type: :bollinger_bands,
      name: "bb_20_3",
      parameters: %{period: 20, std_dev: 3.0}
    },

    # --- Keltner Channels (26-30) ---
    # Alternative volatility bands using ATR
    %{
      type: :keltner_channel,
      name: "kc_20",
      parameters: %{period: 20, atr_period: 10, multiplier: 2.0}
    },
    %{
      type: :keltner_channel,
      name: "kc_50",
      parameters: %{period: 50, atr_period: 10, multiplier: 2.0}
    },
    # Donchian Channels for breakout identification
    %{
      type: :donchian_channel,
      name: "dc_20",
      parameters: %{period: 20}
    },
    %{
      type: :donchian_channel,
      name: "dc_50",
      parameters: %{period: 50}
    },
    # Standard deviation for direct volatility measurement
    %{
      type: :std_dev,
      name: "stddev_20",
      parameters: %{period: 20}
    },

    # ========================================================================
    # SECTION 4: TREND STRENGTH INDICATORS (10 indicators)
    # ========================================================================
    # These indicators measure the strength and quality of trends

    # --- ADX Indicators (31-35) ---
    # Average Directional Index measures trend strength
    %{
      type: :adx,
      name: "adx_14",
      parameters: %{period: 14}
    },
    %{
      type: :adx,
      name: "adx_20",
      parameters: %{period: 20}
    },
    # Aroon indicator for trend identification
    %{
      type: :aroon,
      name: "aroon_25",
      parameters: %{period: 25}
    },
    # Parabolic SAR for trend following
    %{
      type: :parabolic_sar,
      name: "psar",
      parameters: %{acceleration: 0.02, maximum: 0.2}
    },
    # Ichimoku Cloud components
    %{
      type: :ichimoku,
      name: "ichimoku",
      parameters: %{tenkan: 9, kijun: 26, senkou_b: 52}
    },

    # --- SuperTrend Indicators (36-40) ---
    # SuperTrend with different ATR multipliers
    %{
      type: :supertrend,
      name: "st_10_2",
      parameters: %{period: 10, multiplier: 2.0}
    },
    %{
      type: :supertrend,
      name: "st_10_3",
      parameters: %{period: 10, multiplier: 3.0}
    },
    %{
      type: :supertrend,
      name: "st_14_2",
      parameters: %{period: 14, multiplier: 2.0}
    },
    # VWAP for institutional trading levels
    %{
      type: :vwap,
      name: "vwap",
      parameters: %{}
    },
    # Linear regression for trend prediction
    %{
      type: :linear_regression,
      name: "linreg_50",
      parameters: %{period: 50}
    },

    # ========================================================================
    # SECTION 5: VOLUME INDICATORS (10 indicators)
    # ========================================================================
    # Volume indicators confirm price movements and identify accumulation/distribution

    # --- Volume Moving Averages (41-45) ---
    # Simple moving averages of volume
    %{
      type: :sma,
      name: "vol_sma_20",
      parameters: %{period: 20, source: :volume}
    },
    %{
      type: :sma,
      name: "vol_sma_50",
      parameters: %{period: 50, source: :volume}
    },
    # On-Balance Volume (OBV) for accumulation tracking
    %{
      type: :obv,
      name: "obv",
      parameters: %{}
    },
    # Accumulation/Distribution Line
    %{
      type: :ad_line,
      name: "ad_line",
      parameters: %{}
    },
    # Chaikin Money Flow
    %{
      type: :cmf,
      name: "cmf_20",
      parameters: %{period: 20}
    },

    # --- Volume Oscillators (46-50) ---
    # Volume Rate of Change
    %{
      type: :volume_roc,
      name: "vol_roc_12",
      parameters: %{period: 12}
    },
    # Force Index combining price and volume
    %{
      type: :force_index,
      name: "fi_13",
      parameters: %{period: 13}
    },
    # Ease of Movement indicator
    %{
      type: :ease_of_movement,
      name: "eom_14",
      parameters: %{period: 14}
    },
    # Volume Weighted Average Price
    %{
      type: :vwma,
      name: "vwma_20",
      parameters: %{period: 20}
    },
    # Money Flow Index (volume-weighted RSI)
    %{
      type: :mfi,
      name: "mfi_14",
      parameters: %{period: 14}
    }
  ],

  # ========================================================================
  # ENTRY CONDITIONS
  # ========================================================================
  # Complex multi-factor entry logic combining trend, momentum, and volume
  #
  # Entry requirements:
  # 1. TREND: Price must be in uptrend (above key moving averages)
  # 2. MOMENTUM: RSI showing strength but not overbought
  # 3. TREND STRENGTH: ADX confirming strong trend
  # 4. VOLUME: Above-average volume confirming move
  # 5. VOLATILITY: Within acceptable range (not too high)
  entry_conditions: """
  # Primary trend filter - must be in confirmed uptrend
  close > sma_20 and
  sma_20 > sma_50 and
  sma_50 > sma_200 and

  # Momentum confirmation - RSI showing strength
  rsi_14 > 50 and rsi_14 < 70 and

  # Trend strength - ADX above threshold
  adx_14 > 25 and

  # MACD crossover signal
  macd_standard.line > macd_standard.signal and

  # Volume confirmation - above average
  volume > vol_sma_20 and

  # Volatility filter - not too extreme
  atr_14 < atr_21 * 1.5
  """,

  # ========================================================================
  # EXIT CONDITIONS
  # ========================================================================
  # Protect profits and limit losses with multi-factor exit logic
  #
  # Exit triggers:
  # 1. Trend reversal (price crosses below moving averages)
  # 2. Momentum exhaustion (RSI overbought or bearish divergence)
  # 3. Volatility spike (risk management)
  # 4. Volume decline (weakening move)
  exit_conditions: """
  # Trend reversal signal
  close < sma_20 or

  # Momentum exhaustion
  rsi_14 > 70 or

  # MACD bearish crossover
  macd_standard.line < macd_standard.signal or

  # Weak trend strength
  adx_14 < 20 or

  # Volume drying up
  volume < vol_sma_50 * 0.5
  """,

  # ========================================================================
  # POSITION SIZING
  # ========================================================================
  # Risk-based position sizing using ATR for volatility adjustment
  # This ensures consistent risk across different market conditions
  position_sizing: %{
    type: :risk_based,
    risk_percent: 2.0,      # Risk 2% of account per trade
    atr_multiplier: 2.0,    # Use 2x ATR for stop distance
    max_position_size: 10.0 # Cap at 10% of account
  },

  # ========================================================================
  # RISK MANAGEMENT
  # ========================================================================
  # Dynamic risk management based on volatility (ATR)
  # Stop loss and take profit adjust to market conditions
  risk_management: %{
    # Stop loss at 2x ATR below entry
    stop_loss_type: :atr_based,
    stop_loss_atr_multiplier: 2.0,

    # Take profit at 4x ATR above entry (2:1 reward/risk)
    take_profit_type: :atr_based,
    take_profit_atr_multiplier: 4.0,

    # Trailing stop using Parabolic SAR
    trailing_stop: :parabolic_sar,

    # Maximum drawdown limit
    max_drawdown: 10.0  # Stop trading if drawdown exceeds 10%
  }
}
