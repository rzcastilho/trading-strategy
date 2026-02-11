defmodule TradingStrategy.Repo.Migrations.CreateEditHistories do
  use Ecto.Migration

  def change do
    create table(:edit_histories) do
      add :session_id, :string, null: false
      add :strategy_id, references(:strategy_definitions, on_delete: :delete_all), null: false
      add :undo_stack, :jsonb
      add :redo_stack, :jsonb
      add :max_size, :integer, default: 100

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:edit_histories, [:session_id])
    create index(:edit_histories, [:strategy_id])
    create index(:edit_histories, [:updated_at])
  end
end
