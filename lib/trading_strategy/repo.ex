defmodule TradingStrategy.Repo do
  use Ecto.Repo,
    otp_app: :trading_strategy,
    adapter: Ecto.Adapters.Postgres
end
