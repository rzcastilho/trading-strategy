defmodule TradingStrategy.Repo.Migrations.AddPerformanceIndexes do
  use Ecto.Migration

  def change do
    # Index for filtering and sorting trades by profitability
    create_if_not_exists index(:trades, [:pnl])

    # Composite index for finding stale running sessions on restart
    create_if_not_exists index(:trading_sessions, [:status, :updated_at])

    # Index for position-trade relationship queries
    create_if_not_exists index(:trades, [:position_id, :timestamp])
  end
end
