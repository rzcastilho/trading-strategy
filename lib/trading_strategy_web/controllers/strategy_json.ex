defmodule TradingStrategyWeb.StrategyJSON do
  alias TradingStrategy.Strategies.Strategy

  @doc """
  Renders a list of strategies.
  """
  def index(%{strategies: strategies}) do
    %{data: for(strategy <- strategies, do: data(strategy))}
  end

  @doc """
  Renders a single strategy.
  """
  def show(%{strategy: strategy}) do
    %{data: data(strategy)}
  end

  defp data(%Strategy{} = strategy) do
    %{
      id: strategy.id,
      name: strategy.name,
      description: strategy.description,
      format: strategy.format,
      content: strategy.content,
      trading_pair: strategy.trading_pair,
      timeframe: strategy.timeframe,
      status: strategy.status,
      version: strategy.version,
      inserted_at: strategy.inserted_at,
      updated_at: strategy.updated_at
    }
  end
end
