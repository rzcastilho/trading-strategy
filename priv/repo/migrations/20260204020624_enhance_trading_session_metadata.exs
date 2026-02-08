defmodule TradingStrategy.Repo.Migrations.EnhanceTradingSessionMetadata do
  use Ecto.Migration

  def change do
    alter table(:trading_sessions) do
      add :queued_at, :utc_datetime_usec
    end

    # Add index for finding stale "running" sessions on restart
    create index(:trading_sessions, [:status, :updated_at])
  end
end
