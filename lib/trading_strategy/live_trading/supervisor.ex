defmodule TradingStrategy.LiveTrading.Supervisor do
  @moduledoc """
  Supervisor for live trading components.

  Manages:
  - Credentials manager
  - Health monitor
  - Resilience monitor
  - Order tracker
  - Session registry
  - Session supervisor (for dynamic session management)
  """

  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [
      # Credentials manager (stores API keys in memory only)
      {TradingStrategy.Exchanges.Credentials, []},

      # Health and resilience monitoring
      {TradingStrategy.Exchanges.HealthMonitor, []},
      {TradingStrategy.Exchanges.ResilienceMonitor, []},

      # Order tracking
      {TradingStrategy.Orders.OrderTracker, []},

      # Balance and connectivity monitoring
      {TradingStrategy.LiveTrading.BalanceMonitor, []},
      {TradingStrategy.LiveTrading.ConnectivityMonitor, []},

      # Session registry (for named process lookup)
      {Registry, keys: :unique, name: TradingStrategy.LiveTrading.SessionRegistry},

      # Dynamic supervisor for live trading sessions
      {DynamicSupervisor,
       strategy: :one_for_one, name: TradingStrategy.LiveTrading.SessionSupervisor}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
