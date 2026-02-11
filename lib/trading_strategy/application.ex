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
      # NEW: Backtesting infrastructure GenServers (Phase 2)
      TradingStrategy.Backtesting.ProgressTracker,
      TradingStrategy.Backtesting.ConcurrencyManager,
      TradingStrategy.Backtesting.Supervisor,
      TradingStrategy.PaperTrading.Supervisor,
      TradingStrategy.LiveTrading.Supervisor,
      # Feature 005: Strategy Editor - Undo/Redo History
      TradingStrategy.StrategyEditor.EditHistory,
      # Start to serve requests, typically the last entry
      TradingStrategyWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: TradingStrategy.Supervisor]

    case Supervisor.start_link(children, opts) do
      {:ok, pid} = result ->
        # Detect and mark stale running sessions from previous application run
        # Skip in test environment to avoid DBConnection.OwnershipError with Sandbox
        if Mix.env() != :test do
          Task.start(fn ->
            # Wait a bit for the database connection to be ready
            Process.sleep(1000)
            TradingStrategy.Backtesting.detect_and_mark_stale_sessions()
          end)
        end

        result

      error ->
        error
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    TradingStrategyWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
