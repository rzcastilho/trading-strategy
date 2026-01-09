defmodule TradingStrategy.Repo.Migrations.CreateSignals do
  use Ecto.Migration

  def change do
    create table(:signals, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :strategy_id, references(:strategies, type: :uuid, on_delete: :delete_all), null: false
      add :trading_session_id, references(:trading_sessions, type: :uuid, on_delete: :delete_all)
      add :signal_type, :string, null: false
      add :timestamp, :utc_datetime_usec, null: false
      add :price, :decimal, precision: 20, scale: 8, null: false
      add :indicators_data, :map, null: false, default: %{}
      add :confidence, :decimal, precision: 5, scale: 2
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:signals, [:strategy_id, :timestamp])
    create index(:signals, [:trading_session_id])
    create index(:signals, [:signal_type])
    create index(:signals, [:timestamp])
  end
end
