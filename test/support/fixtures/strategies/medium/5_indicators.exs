# Medium 5-Indicator Strategy Fixture
# Purpose: Comment preservation tests (US3)
# Complexity: Medium (5 indicators)
# Expected DSL Lines: ~80-100
# Comment Blocks: 10+ inline comments for preservation testing

alias TradingStrategy.StrategyEditor.BuilderState
alias TradingStrategy.StrategyEditor.BuilderState.{Indicator, PositionSizing}

%BuilderState{
  name: "Medium 5 Indicator Strategy",
  description: "Strategy with 5 indicators and extensive comments for comment preservation testing",
  trading_pair: "BTC/USD",
  timeframe: "1h",

  # Trend following indicators
  # SMA indicators help identify overall trend direction
  indicators: [
    # Short-term moving average for quick trend detection
    %Indicator{
      type: "sma",
      name: "sma_20",
      parameters: %{
        "period" => 20,
        "source" => "close"
      },
      _id: "test-sma-20"
    },
    # Medium-term moving average for trend confirmation
    %Indicator{
      type: "sma",
      name: "sma_50",
      parameters: %{
        "period" => 50,
        "source" => "close"
      },
      _id: "test-sma-50"
    },
    # Fast EMA for crossover signals
    %Indicator{
      type: "ema",
      name: "ema_12",
      parameters: %{
        "period" => 12,
        "source" => "close"
      },
      _id: "test-ema-12"
    },
    # Slow EMA for crossover confirmation
    %Indicator{
      type: "ema",
      name: "ema_26",
      parameters: %{
        "period" => 26,
        "source" => "close"
      },
      _id: "test-ema-26"
    },
    # RSI for overbought/oversold conditions
    # Values above 70 indicate overbought
    # Values below 30 indicate oversold
    %Indicator{
      type: "rsi",
      name: "rsi_14",
      parameters: %{
        "period" => 14,
        "source" => "close"
      },
      _id: "test-rsi-14"
    }
  ],

  # Entry logic combines trend and momentum
  # We want to enter when:
  # 1. Price is above short-term MA (uptrend)
  # 2. RSI shows oversold conditions (good entry point)
  entry_conditions: """
  # Enter on uptrend with oversold RSI
  close > sma_20 and rsi_14 < 30
  """,

  # Exit logic protects profits and cuts losses
  # Exit when:
  # 1. Trend reverses (price below SMA)
  # 2. RSI becomes overbought (momentum exhausted)
  exit_conditions: """
  # Exit when trend reverses or RSI overbought
  close < sma_20 or rsi_14 > 70
  """,

  stop_conditions: nil,

  # Fixed position sizing for simplicity
  position_sizing: %PositionSizing{
    type: "fixed",
    fixed_amount: 1.0,
    percentage_of_capital: nil,
    _id: "test-pos-sizing"
  },

  # Risk management parameters are not part of BuilderState in current implementation
  # They would go in risk_parameters field if needed
  risk_parameters: nil,

  _comments: [],
  _version: 1,
  _last_sync_at: nil
}
