defmodule TradingStrategy.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      TradingStrategyWeb.Telemetry,
      TradingStrategy.Repo,
      {DNSCluster, query: Application.get_env(:trading_strategy, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: TradingStrategy.PubSub},
      # Trading Strategy Supervisors
      TradingStrategy.Strategies.Supervisor,
      TradingStrategy.MarketData.Supervisor,
      TradingStrategy.Backtesting.Supervisor,
      TradingStrategy.PaperTrading.Supervisor,
      TradingStrategy.LiveTrading.Supervisor,
      # Start to serve requests, typically the last entry
      TradingStrategyWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: TradingStrategy.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    TradingStrategyWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
