defmodule TradingStrategy.Repo.Migrations.CreateStrategyDefinitions do
  use Ecto.Migration

  def change do
    create table(:strategy_definitions) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :name, :string, size: 255, null: false
      add :dsl_text, :text
      add :builder_state, :jsonb
      add :last_modified_editor, :string, size: 20
      add :last_modified_at, :utc_datetime_usec
      add :validation_status, :jsonb
      add :comments, :jsonb

      timestamps(type: :utc_datetime_usec)
    end

    create index(:strategy_definitions, [:user_id])
    create index(:strategy_definitions, [:last_modified_at])
  end
end
