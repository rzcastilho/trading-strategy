defmodule TradingStrategy.Strategies.IndicatorCalculator do
  @moduledoc """
  Behaviour for calculating technical indicators.

  This behaviour defines the contract for indicator calculation engines that
  process market data and compute indicator values.
  """

  @doc """
  Calculates the indicator values for the given market data.

  ## Parameters
    - indicator: %Indicator{} - The indicator configuration
    - market_data: list(%MarketData{}) - Market data to process

  ## Returns
    - {:ok, values} - Map of calculated indicator values
    - {:error, reason} - If calculation fails
  """
  @callback calculate(indicator :: struct(), market_data :: list()) ::
              {:ok, map()} | {:error, term()}
end
