# Medium Trend Following Strategy Fixture
#
# This fixture is used for edge case testing (Phase 9).
# It features complex entry/exit logic with multiple indicators
# to test synchronization behavior with moderate complexity.
#
# Complexity: Medium (8 indicators)
# DSL Output: ~120 lines
# Use Cases: Edge case testing, synchronization stress testing

%{
  name: "Trend Following Strategy",
  trading_pair: "BTC/USD",
  timeframe: "1h",
  indicators: [
    # Moving Averages for trend identification
    %{
      type: :sma,
      name: "sma_20",
      parameters: %{period: 20}
    },
    %{
      type: :sma,
      name: "sma_50",
      parameters: %{period: 50}
    },
    %{
      type: :sma,
      name: "sma_200",
      parameters: %{period: 200}
    },
    # Momentum indicators
    %{
      type: :rsi,
      name: "rsi_14",
      parameters: %{period: 14}
    },
    %{
      type: :macd,
      name: "macd",
      parameters: %{
        fast_period: 12,
        slow_period: 26,
        signal_period: 9
      }
    },
    # Trend strength
    %{
      type: :adx,
      name: "adx_14",
      parameters: %{period: 14}
    },
    # Volatility
    %{
      type: :atr,
      name: "atr_14",
      parameters: %{period: 14}
    },
    # Price channels
    %{
      type: :bollinger_bands,
      name: "bb_20",
      parameters: %{
        period: 20,
        std_dev: 2.0
      }
    }
  ],
  entry_conditions: """
  close > sma_200 and
  sma_20 > sma_50 and
  macd.line > macd.signal and
  rsi_14 > 50 and
  adx_14 > 25
  """,
  exit_conditions: """
  close < sma_20 or
  macd.line < macd.signal or
  rsi_14 < 40
  """,
  position_sizing: %{
    type: :fixed,
    amount: 1000
  },
  comments: []
}
