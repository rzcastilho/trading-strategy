defmodule TradingStrategy.Repo.Migrations.CreateTradingSessions do
  use Ecto.Migration

  def change do
    create table(:trading_sessions, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :strategy_id, references(:strategies, type: :uuid, on_delete: :delete_all), null: false
      add :mode, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :initial_capital, :decimal, precision: 20, scale: 8, null: false
      add :current_capital, :decimal, precision: 20, scale: 8
      add :started_at, :utc_datetime_usec
      add :ended_at, :utc_datetime_usec
      add :config, :map, default: %{}
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:trading_sessions, [:strategy_id])
    create index(:trading_sessions, [:mode])
    create index(:trading_sessions, [:status])
    create index(:trading_sessions, [:started_at])
  end
end
