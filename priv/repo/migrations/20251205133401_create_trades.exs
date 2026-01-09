defmodule TradingStrategy.Repo.Migrations.CreateTrades do
  use Ecto.Migration

  def change do
    create table(:trades, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :position_id, references(:positions, type: :uuid, on_delete: :delete_all), null: false
      add :signal_id, references(:signals, type: :uuid, on_delete: :nilify_all)
      add :order_id, :string
      add :side, :string, null: false
      add :quantity, :decimal, precision: 20, scale: 8, null: false
      add :price, :decimal, precision: 20, scale: 8, null: false
      add :fee, :decimal, precision: 20, scale: 8, default: "0.0"
      add :fee_currency, :string
      add :timestamp, :utc_datetime_usec, null: false
      add :exchange, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:trades, [:position_id])
    create index(:trades, [:signal_id])
    create index(:trades, [:order_id])
    create index(:trades, [:timestamp])
    create index(:trades, [:status])
  end
end
