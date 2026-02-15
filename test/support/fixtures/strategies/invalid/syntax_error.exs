# Invalid Syntax Strategy Fixture
# Purpose: Error handling tests (US6) - syntax error validation
# Error Type: Missing closing bracket in entry conditions
# Expected Behavior: Parser should detect missing '}' and report syntax error

%{
  name: "Invalid Syntax Strategy",
  description: "Strategy with intentional syntax error for error handling testing",
  trading_pair: "BTC/USD",
  timeframe: "1h",
  indicators: [
    %{
      type: :rsi,
      name: "rsi_14",
      parameters: %{
        period: 14
      }
    }
  ],
  entry_conditions: """
  # Entry with intentional syntax error - missing closing bracket
  rsi_14 < 30 and close > sma_20
  # Missing closing bracket here: {
  """,
  exit_conditions: """
  # Exit when RSI overbought
  rsi_14 > 70
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
