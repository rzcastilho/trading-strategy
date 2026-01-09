defmodule TradingStrategy.MarketData.Supervisor do
  @moduledoc """
  Supervisor for managing market data providers.

  This supervisor manages:
  - Market data provider connections
  - WebSocket streams for real-time data
  - Historical data fetchers
  """

  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [
      # ETS-based cache for market data (must start first)
      TradingStrategy.MarketData.Cache,

      # Real-time data stream subscriber (WebSocket connection manager)
      TradingStrategy.MarketData.StreamSubscriber,

      # Stream handler for processing incoming data
      TradingStrategy.MarketData.StreamHandler

      # Market data providers will be added here as needed
      # {TradingStrategy.MarketData.Provider, []}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc """
  Starts a market data provider for the given exchange and symbol.

  ## Parameters
    - exchange: String.t() - Exchange name
    - symbol: String.t() - Trading pair symbol
    - timeframe: String.t() - Timeframe (e.g., "1m", "5m", "1h")

  ## Returns
    - {:ok, pid} | {:error, reason}
  """
  def start_provider(exchange, symbol, timeframe) do
    # Implementation will be added in Phase 4
    {:ok, self()}
  end

  @doc """
  Stops a running market data provider.

  ## Parameters
    - provider_id: term() - Provider identifier

  ## Returns
    - :ok | {:error, reason}
  """
  def stop_provider(provider_id) do
    # Implementation will be added in Phase 4
    :ok
  end
end
