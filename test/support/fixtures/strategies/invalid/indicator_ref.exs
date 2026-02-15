# Invalid Indicator Reference Strategy Fixture
# Purpose: Error handling tests (US6) - validation error testing
# Error Type: Reference to undefined indicator in entry conditions
# Expected Behavior: Validator should detect undefined indicator and report validation error

%{
  name: "Invalid Indicator Reference Strategy",
  description: "Strategy with undefined indicator reference for validation error testing",
  trading_pair: "ETH/USD",
  timeframe: "4h",
  indicators: [
    %{
      type: :sma,
      name: "sma_50",
      parameters: %{
        period: 50,
        source: :close
      }
    },
    %{
      type: :ema,
      name: "ema_20",
      parameters: %{
        period: 20,
        source: :close
      }
    }
  ],
  entry_conditions: """
  # Entry conditions reference undefined indicator 'macd_signal'
  # This indicator was never defined in the indicators list
  close > sma_50 and ema_20 > sma_50 and macd_signal > 0
  """,
  exit_conditions: """
  # Exit when price crosses below EMA
  close < ema_20
  """,
  position_sizing: %{
    type: :percentage,
    percentage: 5.0
  },
  risk_management: %{
    stop_loss: 1.5,
    take_profit: 3.0
  }
}
