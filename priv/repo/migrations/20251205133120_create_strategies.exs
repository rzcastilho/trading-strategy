defmodule TradingStrategy.Repo.Migrations.CreateStrategies do
  use Ecto.Migration

  def change do
    create table(:strategies, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :name, :string, null: false
      add :description, :text
      add :format, :string, null: false
      add :content, :text, null: false
      add :trading_pair, :string, null: false
      add :timeframe, :string, null: false
      add :status, :string, null: false, default: "draft"
      add :version, :integer, null: false, default: 1

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:strategies, [:name, :version])
    create index(:strategies, [:status])
    create index(:strategies, [:trading_pair])
  end
end
