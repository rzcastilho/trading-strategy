# Large 50-Indicator Strategy Fixture
# Purpose: Stress testing and performance validation (US5)
# Complexity: Large (50 indicators)
# Expected DSL Lines: 1000+
# Target: Synchronization within 500ms even with large strategies (FR-015)

%{
  name: "Large 50 Indicator Comprehensive Strategy",
  description: "Stress test strategy with 50 indicators to validate performance at scale",
  trading_pair: "BTC/USD",
  timeframe: "1h",

  indicators: [
    # SMA Suite (10 indicators) - Multiple trend timeframes
    %{type: :sma, name: "sma_5", parameters: %{period: 5, source: :close}},
    %{type: :sma, name: "sma_10", parameters: %{period: 10, source: :close}},
    %{type: :sma, name: "sma_15", parameters: %{period: 15, source: :close}},
    %{type: :sma, name: "sma_20", parameters: %{period: 20, source: :close}},
    %{type: :sma, name: "sma_30", parameters: %{period: 30, source: :close}},
    %{type: :sma, name: "sma_50", parameters: %{period: 50, source: :close}},
    %{type: :sma, name: "sma_75", parameters: %{period: 75, source: :close}},
    %{type: :sma, name: "sma_100", parameters: %{period: 100, source: :close}},
    %{type: :sma, name: "sma_150", parameters: %{period: 150, source: :close}},
    %{type: :sma, name: "sma_200", parameters: %{period: 200, source: :close}},

    # EMA Suite (10 indicators) - Faster trend signals
    %{type: :ema, name: "ema_5", parameters: %{period: 5, source: :close}},
    %{type: :ema, name: "ema_8", parameters: %{period: 8, source: :close}},
    %{type: :ema, name: "ema_12", parameters: %{period: 12, source: :close}},
    %{type: :ema, name: "ema_21", parameters: %{period: 21, source: :close}},
    %{type: :ema, name: "ema_26", parameters: %{period: 26, source: :close}},
    %{type: :ema, name: "ema_34", parameters: %{period: 34, source: :close}},
    %{type: :ema, name: "ema_50", parameters: %{period: 50, source: :close}},
    %{type: :ema, name: "ema_89", parameters: %{period: 89, source: :close}},
    %{type: :ema, name: "ema_144", parameters: %{period: 144, source: :close}},
    %{type: :ema, name: "ema_200", parameters: %{period: 200, source: :close}},

    # RSI Suite (6 indicators) - Multiple momentum timeframes
    %{type: :rsi, name: "rsi_5", parameters: %{period: 5, source: :close}},
    %{type: :rsi, name: "rsi_7", parameters: %{period: 7, source: :close}},
    %{type: :rsi, name: "rsi_9", parameters: %{period: 9, source: :close}},
    %{type: :rsi, name: "rsi_14", parameters: %{period: 14, source: :close}},
    %{type: :rsi, name: "rsi_21", parameters: %{period: 21, source: :close}},
    %{type: :rsi, name: "rsi_25", parameters: %{period: 25, source: :close}},

    # MACD Suite (3 variants)
    %{type: :macd, name: "macd_fast", parameters: %{fast_period: 8, slow_period: 17, signal_period: 9}},
    %{type: :macd, name: "macd_standard", parameters: %{fast_period: 12, slow_period: 26, signal_period: 9}},
    %{type: :macd, name: "macd_slow", parameters: %{fast_period: 19, slow_period: 39, signal_period: 9}},

    # ATR Suite (4 indicators) - Volatility measurement
    %{type: :atr, name: "atr_7", parameters: %{period: 7}},
    %{type: :atr, name: "atr_14", parameters: %{period: 14}},
    %{type: :atr, name: "atr_21", parameters: %{period: 21}},
    %{type: :atr, name: "atr_28", parameters: %{period: 28}},

    # Bollinger Bands Suite (3 variants)
    %{type: :bollinger_bands, name: "bb_10", parameters: %{period: 10, std_dev: 2.0, source: :close}},
    %{type: :bollinger_bands, name: "bb_20", parameters: %{period: 20, std_dev: 2.0, source: :close}},
    %{type: :bollinger_bands, name: "bb_30", parameters: %{period: 30, std_dev: 2.5, source: :close}},

    # ADX Suite (3 indicators) - Trend strength
    %{type: :adx, name: "adx_7", parameters: %{period: 7}},
    %{type: :adx, name: "adx_14", parameters: %{period: 14}},
    %{type: :adx, name: "adx_21", parameters: %{period: 21}},

    # Stochastic Suite (3 variants)
    %{type: :stochastic, name: "stoch_fast", parameters: %{k_period: 5, d_period: 3, smooth: 1}},
    %{type: :stochastic, name: "stoch_standard", parameters: %{k_period: 14, d_period: 3, smooth: 3}},
    %{type: :stochastic, name: "stoch_slow", parameters: %{k_period: 21, d_period: 5, smooth: 5}},

    # Volume Indicators (3 types)
    %{type: :vwap, name: "vwap", parameters: %{}},
    %{type: :volume_ma, name: "vol_ma_20", parameters: %{period: 20, source: :volume}},
    %{type: :obv, name: "obv", parameters: %{}},

    # Pivot Points (2 types)
    %{type: :pivot_points, name: "pivots_standard", parameters: %{type: :standard}},
    %{type: :pivot_points, name: "pivots_fibonacci", parameters: %{type: :fibonacci}},

    # Additional Oscillators (2 indicators)
    %{type: :cci, name: "cci_20", parameters: %{period: 20}},
    %{type: :williams_r, name: "williams_r_14", parameters: %{period: 14}},

    # Ichimoku Cloud
    %{type: :ichimoku, name: "ichimoku", parameters: %{
      tenkan_period: 9,
      kijun_period: 26,
      senkou_b_period: 52,
      displacement: 26
    }}
  ],

  # Comprehensive entry conditions using multiple confirmations
  entry_conditions: """
  # Primary Trend Confirmation (Long-term MAs)
  close > sma_200 and
  sma_50 > sma_100 and
  sma_100 > sma_200 and
  ema_50 > ema_200 and

  # Short-term Trend Alignment
  close > sma_20 and
  sma_10 > sma_20 and
  ema_12 > ema_26 and
  crossover(ema_5, ema_8) and

  # Momentum Confirmation (Multiple RSIs)
  rsi_14 > 50 and
  rsi_14 < 70 and
  rsi_7 > rsi_14 and
  rsi_21 > 50 and

  # MACD Triple Confirmation
  macd_fast.line > macd_fast.signal and
  macd_standard.line > macd_standard.signal and
  macd_slow.line > macd_slow.signal and

  # Trend Strength Validation (ADX)
  adx_14 > 25 and
  adx_7 > adx_14 and

  # Volatility Context (ATR)
  atr_14 > atr_14[5] and
  atr_7 > atr_14 and

  # Bollinger Band Position
  close > bb_20.middle and
  close < bb_20.upper and
  bb_10.width > bb_20.width[10] and

  # Stochastic Confirmation
  stoch_standard.k > 20 and
  stoch_standard.k < 80 and
  stoch_standard.k > stoch_standard.d and

  # Volume Confirmation
  volume > vol_ma_20 * 1.2 and
  obv > obv[1] and
  close > vwap and

  # Ichimoku Confirmation
  close > ichimoku.tenkan and
  ichimoku.tenkan > ichimoku.kijun and
  close > ichimoku.senkou_a
  """,

  # Multi-layered exit conditions
  exit_conditions: """
  # Trend Reversal Signals
  close < sma_20 or
  crossunder(ema_5, ema_8) or
  sma_10 < sma_20 or
  crossunder(ema_12, ema_26) or

  # Momentum Exhaustion
  rsi_7 > 85 or
  rsi_14 > 75 or
  rsi_5 < 20 or

  # MACD Reversal
  macd_fast.line < macd_fast.signal or
  macd_standard.line < macd_standard.signal or

  # Volatility Spike Warning
  atr_7 > atr_14 * 1.8 or
  bb_10.width > bb_10.width[5] * 2.0 or

  # Trend Strength Deterioration
  adx_14 < 20 or
  adx_7 < adx_14 * 0.8 or

  # Stochastic Overbought
  stoch_fast.k > 90 or
  (stoch_standard.k > 80 and crossunder(stoch_standard.k, stoch_standard.d)) or

  # Volume Divergence
  close > close[1] and volume < vol_ma_20 * 0.7 or

  # Ichimoku Exit Signals
  close < ichimoku.tenkan or
  ichimoku.tenkan < ichimoku.kijun
  """,

  # Complex position sizing logic
  position_sizing: %{
    type: :adaptive,
    base_percentage: 2.0,
    max_percentage: 5.0,
    volatility_adjusted: true,
    atr_reference: "atr_14",
    trend_strength_multiplier: %{
      enabled: true,
      adx_reference: "adx_14",
      weak_trend_threshold: 20,
      strong_trend_threshold: 40
    },
    momentum_filter: %{
      enabled: true,
      rsi_reference: "rsi_14",
      min_rsi: 40,
      max_rsi: 70
    }
  },

  # Comprehensive risk management
  risk_management: %{
    stop_loss: %{
      type: :adaptive,
      primary: %{type: :atr, multiplier: 2.0, reference: "atr_14"},
      secondary: %{type: :percent, value: 3.0},
      use_minimum: true
    },
    take_profit: %{
      type: :multiple_targets,
      targets: [
        %{percentage: 40, profit_level: 1.5, move_stop_to_breakeven: true},
        %{percentage: 30, profit_level: 3.0, trailing_enabled: true},
        %{percentage: 20, profit_level: 5.0, trailing_enabled: true},
        %{percentage: 10, profit_level: 8.0, trailing_enabled: true}
      ]
    },
    trailing_stop: %{
      enabled: true,
      activation_profit: 2.0,
      trail_distance: %{type: :atr, multiplier: 1.5, reference: "atr_14"},
      step_size: 0.5,
      lock_profit_at: [3.0, 5.0, 7.0]
    },
    time_based_exit: %{
      enabled: true,
      max_holding_period_bars: 168,
      weekend_close: true
    }
  },

  # Additional metadata
  metadata: %{
    complexity_level: "large",
    indicator_count: 50,
    expected_dsl_lines: 1000,
    performance_target_ms: 500,
    created_for: "stress_testing",
    test_scenarios: ["US5.006", "SC-003", "FR-015"]
  }
}
