defmodule TradingStrategy.MixProject do
  use Mix.Project

  def project do
    [
      app: :trading_strategy,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {TradingStrategy.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:decimal, "~> 2.0"},
      {:trading_indicators, git: "https://github.com/rzcastilho/trading-indicators.git", branch: "main"}
    ]
  end
end
