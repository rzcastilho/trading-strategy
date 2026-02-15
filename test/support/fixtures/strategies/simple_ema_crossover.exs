# Simple EMA Crossover Strategy Fixture
# Purpose: Crossover logic tests (US1, US2)
# Complexity: Simple (2 indicators)
# Expected DSL Lines: ~25-30

%{
  name: "EMA Crossover Strategy",
  description: "Classic EMA crossover with fast and slow EMAs",
  trading_pair: "ETH/USD",
  timeframe: "4h",
  indicators: [
    %{
      type: :ema,
      name: "ema_fast",
      parameters: %{
        period: 12,
        source: :close
      }
    },
    %{
      type: :ema,
      name: "ema_slow",
      parameters: %{
        period: 26,
        source: :close
      }
    }
  ],
  entry_conditions: """
  # Golden cross - fast EMA crosses above slow EMA
  crossover(ema_fast, ema_slow)
  """,
  exit_conditions: """
  # Death cross - fast EMA crosses below slow EMA
  crossunder(ema_fast, ema_slow)
  """,
  position_sizing: %{
    type: :percentage,
    amount: 10.0  # 10% of portfolio
  },
  risk_management: %{
    stop_loss: 1.5,
    take_profit: 3.0
  }
}
