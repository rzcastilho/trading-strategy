# Complex Multi-Timeframe Strategy Fixture
# Purpose: Performance validation tests (US5)
# Complexity: Complex (20+ indicators across multiple timeframes)
# Expected DSL Lines: ~300-350
# Target: Synchronization within 500ms

%{
  name: "Multi-Timeframe Adaptive Strategy",
  description: "Strategy using multiple timeframes for comprehensive market analysis",
  trading_pair: "BTC/USD",
  timeframe: "1h",

  # Multi-timeframe indicator configuration
  indicators: [
    # Higher Timeframe (4h) - Trend context
    %{
      type: :sma,
      name: "sma_200_4h",
      parameters: %{period: 200, source: :close, timeframe: "4h"}
    },
    %{
      type: :ema,
      name: "ema_50_4h",
      parameters: %{period: 50, source: :close, timeframe: "4h"}
    },
    %{
      type: :rsi,
      name: "rsi_14_4h",
      parameters: %{period: 14, source: :close, timeframe: "4h"}
    },
    %{
      type: :macd,
      name: "macd_4h",
      parameters: %{fast_period: 12, slow_period: 26, signal_period: 9, timeframe: "4h"}
    },

    # Current Timeframe (1h) - Entry/exit signals
    %{type: :sma, name: "sma_20", parameters: %{period: 20, source: :close}},
    %{type: :sma, name: "sma_50", parameters: %{period: 50, source: :close}},
    %{type: :sma, name: "sma_100", parameters: %{period: 100, source: :close}},
    %{type: :ema, name: "ema_12", parameters: %{period: 12, source: :close}},
    %{type: :ema, name: "ema_26", parameters: %{period: 26, source: :close}},
    %{type: :rsi, name: "rsi_14", parameters: %{period: 14, source: :close}},
    %{
      type: :macd,
      name: "macd",
      parameters: %{fast_period: 12, slow_period: 26, signal_period: 9}
    },
    %{type: :adx, name: "adx_14", parameters: %{period: 14}},
    %{type: :atr, name: "atr_14", parameters: %{period: 14}},
    %{
      type: :bollinger_bands,
      name: "bb_20",
      parameters: %{period: 20, std_dev: 2.0, source: :close}
    },

    # Lower Timeframe (15m) - Precise entry timing
    %{
      type: :ema,
      name: "ema_9_15m",
      parameters: %{period: 9, source: :close, timeframe: "15m"}
    },
    %{
      type: :ema,
      name: "ema_21_15m",
      parameters: %{period: 21, source: :close, timeframe: "15m"}
    },
    %{
      type: :rsi,
      name: "rsi_7_15m",
      parameters: %{period: 7, source: :close, timeframe: "15m"}
    },
    %{
      type: :stochastic,
      name: "stoch_15m",
      parameters: %{k_period: 14, d_period: 3, smooth: 3, timeframe: "15m"}
    },

    # Volume confirmation
    %{type: :vwap, name: "vwap", parameters: %{}},
    %{
      type: :volume_ma,
      name: "vol_ma_20",
      parameters: %{period: 20, source: :volume}
    }
  ],

  # Multi-timeframe entry logic
  entry_conditions: """
  # Higher timeframe trend confirmation (4h)
  close > sma_200_4h and
  ema_50_4h > sma_200_4h and
  rsi_14_4h > 50 and
  macd_4h.line > macd_4h.signal and

  # Current timeframe confirmation (1h)
  close > sma_100 and
  sma_20 > sma_50 and
  ema_12 > ema_26 and
  rsi_14 > 50 and
  rsi_14 < 70 and
  macd.line > macd.signal and
  adx_14 > 25 and

  # Lower timeframe timing (15m)
  close > ema_21_15m and
  crossover(ema_9_15m, ema_21_15m) and
  rsi_7_15m > 40 and
  stoch_15m.k > 20 and

  # Volume confirmation
  volume > vol_ma_20 * 1.2
  """,

  # Multi-timeframe exit logic
  exit_conditions: """
  # Higher timeframe reversal (4h)
  rsi_14_4h < 40 or
  macd_4h.line < macd_4h.signal or

  # Current timeframe signals (1h)
  close < sma_20 or
  crossunder(ema_12, ema_26) or
  rsi_14 > 80 or
  rsi_14 < 30 or

  # Lower timeframe exit signal (15m)
  crossunder(ema_9_15m, ema_21_15m) or
  stoch_15m.k > 80 or

  # Stop loss hit
  close < entry_price * 0.98
  """,

  # Adaptive position sizing
  position_sizing: %{
    type: :percentage,
    percentage: 2.0,
    max_position: 5.0,
    volatility_adjusted: true,
    atr_reference: "atr_14"
  },

  # Risk management with trailing stops
  risk_management: %{
    stop_loss: %{
      type: :atr,
      multiplier: 2.5,
      reference: "atr_14"
    },
    take_profit: %{
      type: :multiple_targets,
      targets: [
        %{percentage: 50, profit_level: 2.0},
        %{percentage: 30, profit_level: 4.0},
        %{percentage: 20, profit_level: 6.0}
      ]
    },
    trailing_stop: %{
      enabled: true,
      activation_profit: 2.0,
      trail_distance: 1.5,
      step_size: 0.5
    }
  },

  # Additional metadata for multi-timeframe coordination
  timeframe_config: %{
    primary: "1h",
    higher: "4h",
    lower: "15m",
    sync_on_bar_close: true
  }
}
