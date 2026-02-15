# Simple SMA Strategy Fixture
# Purpose: Basic synchronization tests (US1, US2)
# Complexity: Simple (1 indicator)
# Expected DSL Lines: ~15-20

%{
  name: "Simple SMA Strategy",
  description: "Basic strategy with single SMA indicator for sync testing",
  trading_pair: "BTC/USD",
  timeframe: "1h",
  indicators: [
    %{
      type: :sma,
      name: "sma_20",
      parameters: %{
        period: 20,
        source: :close
      }
    }
  ],
  entry_conditions: """
  # Entry when price crosses above SMA
  close > sma_20
  """,
  exit_conditions: """
  # Exit when price crosses below SMA
  close < sma_20
  """,
  position_sizing: %{
    type: :fixed,
    amount: 1.0
  },
  risk_management: %{
    stop_loss: 2.0,
    take_profit: 4.0
  }
}
