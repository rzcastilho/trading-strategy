defmodule TradingStrategy.Strategies.StrategyExecutor do
  @moduledoc """
  Behaviour for executing trading strategies.

  This behaviour defines the contract for strategy execution engines that process
  market data and generate trading signals based on a strategy definition.
  """

  @doc """
  Executes the strategy against the given market data.

  ## Parameters
    - strategy: %Strategy{} - The strategy to execute
    - market_data: list(%MarketData{}) - Market data to process

  ## Returns
    - {:ok, signals} - List of generated signals
    - {:error, reason} - If execution fails
  """
  @callback execute(strategy :: struct(), market_data :: list()) ::
              {:ok, list()} | {:error, term()}

  @doc """
  Validates the strategy configuration.

  ## Parameters
    - strategy: %Strategy{} - The strategy to validate

  ## Returns
    - :ok - If strategy is valid
    - {:error, reasons} - List of validation errors
  """
  @callback validate(strategy :: struct()) :: :ok | {:error, list(String.t())}
end
