defmodule TradingStrategy.Repo.Migrations.CreatePositions do
  use Ecto.Migration

  def change do
    create table(:positions, primary_key: false) do
      add :id, :uuid, primary_key: true

      add :trading_session_id, references(:trading_sessions, type: :uuid, on_delete: :delete_all),
        null: false

      add :strategy_id, references(:strategies, type: :uuid, on_delete: :delete_all), null: false
      add :symbol, :string, null: false
      add :side, :string, null: false
      add :quantity, :decimal, precision: 20, scale: 8, null: false
      add :entry_price, :decimal, precision: 20, scale: 8, null: false
      add :exit_price, :decimal, precision: 20, scale: 8
      add :stop_loss, :decimal, precision: 20, scale: 8
      add :take_profit, :decimal, precision: 20, scale: 8
      add :status, :string, null: false, default: "open"
      add :opened_at, :utc_datetime_usec, null: false
      add :closed_at, :utc_datetime_usec
      add :realized_pnl, :decimal, precision: 20, scale: 8
      add :unrealized_pnl, :decimal, precision: 20, scale: 8
      add :fees, :decimal, precision: 20, scale: 8, default: "0.0"
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:positions, [:trading_session_id])
    create index(:positions, [:strategy_id])
    create index(:positions, [:status])
    create index(:positions, [:symbol])
    create index(:positions, [:opened_at])
  end
end
