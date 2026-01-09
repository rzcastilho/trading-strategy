defmodule TradingStrategy.Strategies.SignalGenerator do
  @moduledoc """
  Behaviour for generating trading signals.

  This behaviour defines the contract for signal generation engines that
  evaluate indicator values and strategy conditions to produce trading signals.
  """

  @doc """
  Generates trading signals based on indicator values and strategy conditions.

  ## Parameters
    - strategy: %Strategy{} - The strategy configuration
    - indicators_data: map() - Calculated indicator values

  ## Returns
    - {:ok, signals} - List of generated signals
    - {:error, reason} - If signal generation fails
  """
  @callback generate(strategy :: struct(), indicators_data :: map()) ::
              {:ok, list()} | {:error, term()}
end
