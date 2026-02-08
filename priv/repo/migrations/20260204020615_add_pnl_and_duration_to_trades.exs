defmodule TradingStrategy.Repo.Migrations.AddPnlAndDurationToTrades do
  use Ecto.Migration

  def change do
    alter table(:trades) do
      add :pnl, :decimal, precision: 20, scale: 8, default: 0
      add :duration_seconds, :integer
      add :entry_price, :decimal, precision: 20, scale: 8
      add :exit_price, :decimal, precision: 20, scale: 8
    end

    create index(:trades, [:pnl])
  end
end
