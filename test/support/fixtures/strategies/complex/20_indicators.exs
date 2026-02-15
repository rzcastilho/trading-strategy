# Complex 20-Indicator Strategy Fixture
# Purpose: Performance validation tests (US5)
# Complexity: Complex (20 indicators)
# Expected DSL Lines: ~350-400
# Target: Synchronization within 500ms (SC-001, FR-012)

%{
  name: "Complex 20 Indicator Strategy",
  description: "Advanced multi-indicator strategy for performance target testing",
  trading_pair: "BTC/USD",
  timeframe: "1h",

  # Comprehensive indicator suite covering trend, momentum, volatility
  indicators: [
    # Moving Averages - Trend identification
    %{type: :sma, name: "sma_10", parameters: %{period: 10, source: :close}},
    %{type: :sma, name: "sma_20", parameters: %{period: 20, source: :close}},
    %{type: :sma, name: "sma_50", parameters: %{period: 50, source: :close}},
    %{type: :sma, name: "sma_100", parameters: %{period: 100, source: :close}},
    %{type: :sma, name: "sma_200", parameters: %{period: 200, source: :close}},

    # Exponential Moving Averages - Faster trend signals
    %{type: :ema, name: "ema_9", parameters: %{period: 9, source: :close}},
    %{type: :ema, name: "ema_12", parameters: %{period: 12, source: :close}},
    %{type: :ema, name: "ema_26", parameters: %{period: 26, source: :close}},
    %{type: :ema, name: "ema_50", parameters: %{period: 50, source: :close}},

    # Momentum Indicators
    %{type: :rsi, name: "rsi_7", parameters: %{period: 7, source: :close}},
    %{type: :rsi, name: "rsi_14", parameters: %{period: 14, source: :close}},
    %{type: :rsi, name: "rsi_21", parameters: %{period: 21, source: :close}},

    # MACD - Trend and momentum
    %{
      type: :macd,
      name: "macd",
      parameters: %{fast_period: 12, slow_period: 26, signal_period: 9}
    },

    # Volatility Indicators
    %{type: :atr, name: "atr_14", parameters: %{period: 14}},
    %{type: :atr, name: "atr_21", parameters: %{period: 21}},
    %{
      type: :bollinger_bands,
      name: "bb_20",
      parameters: %{period: 20, std_dev: 2.0, source: :close}
    },

    # Trend Strength
    %{type: :adx, name: "adx_14", parameters: %{period: 14}},

    # Volume Indicators
    %{type: :vwap, name: "vwap", parameters: %{}},

    # Pivot Points
    %{type: :pivot_points, name: "pivots", parameters: %{type: :standard}},

    # Stochastic
    %{
      type: :stochastic,
      name: "stoch_14",
      parameters: %{k_period: 14, d_period: 3, smooth: 3}
    }
  ],

  # Complex entry logic using multiple confirmations
  entry_conditions: """
  # Multi-timeframe trend confirmation
  close > sma_200 and
  sma_20 > sma_50 and
  sma_50 > sma_100 and

  # Momentum confirmation
  rsi_14 > 50 and
  rsi_14 < 70 and
  macd.line > macd.signal and

  # Trend strength
  adx_14 > 25 and

  # Volatility filter
  atr_14 > atr_14[1] and

  # Price action
  close > bb_20.middle and
  close < bb_20.upper
  """,

  # Multi-condition exit strategy
  exit_conditions: """
  # Trend reversal signals
  close < sma_20 or
  sma_20 < sma_50 or

  # Momentum exhaustion
  rsi_14 > 80 or
  rsi_14 < 30 or
  macd.line < macd.signal or

  # Volatility spike (potential reversal)
  atr_14 > atr_14[1] * 1.5 or

  # Price reaching extreme
  close > bb_20.upper
  """,

  # Dynamic position sizing based on volatility
  position_sizing: %{
    type: :percentage,
    percentage: 2.0,
    volatility_adjusted: true,
    atr_reference: "atr_14"
  },

  # Comprehensive risk management
  risk_management: %{
    stop_loss: %{
      type: :atr,
      multiplier: 2.0,
      reference: "atr_14"
    },
    take_profit: %{
      type: :atr,
      multiplier: 4.0,
      reference: "atr_14"
    },
    trailing_stop: %{
      enabled: true,
      activation_profit: 2.0,
      trail_distance: 1.5
    }
  }
}
