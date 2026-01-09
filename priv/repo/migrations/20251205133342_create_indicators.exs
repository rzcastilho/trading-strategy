defmodule TradingStrategy.Repo.Migrations.CreateIndicators do
  use Ecto.Migration

  def change do
    create table(:indicators, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :strategy_id, references(:strategies, type: :uuid, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :type, :string, null: false
      add :parameters, :map, null: false, default: %{}
      add :output_key, :string, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:indicators, [:strategy_id])
    create index(:indicators, [:type])
    create unique_index(:indicators, [:strategy_id, :name])
  end
end
