defmodule TradingStrategy.Repo.Migrations.AddUserFieldsToStrategies do
  use Ecto.Migration

  def change do
    # Delete existing strategies (development only - they don't have users yet)
    execute "DELETE FROM strategies", "INSERT INTO strategies SELECT * FROM strategies_backup"

    alter table(:strategies) do
      add :user_id, references(:users, on_delete: :delete_all),
          null: false
      add :lock_version, :integer, default: 1, null: false
      add :metadata, :map
    end

    create index(:strategies, [:user_id])

    # Update unique constraint to scope by user
    drop_if_exists unique_index(:strategies, [:name, :version])
    create unique_index(:strategies, [:user_id, :name, :version])
  end
end
