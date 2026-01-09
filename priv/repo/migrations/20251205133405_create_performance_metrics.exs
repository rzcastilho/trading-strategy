defmodule TradingStrategy.Repo.Migrations.CreatePerformanceMetrics do
  use Ecto.Migration

  def change do
    create table(:performance_metrics, primary_key: false) do
      add :id, :uuid, primary_key: true

      add :trading_session_id, references(:trading_sessions, type: :uuid, on_delete: :delete_all),
        null: false

      add :total_return, :decimal, precision: 10, scale: 4
      add :total_return_pct, :decimal, precision: 10, scale: 4
      add :sharpe_ratio, :decimal, precision: 10, scale: 4
      add :max_drawdown, :decimal, precision: 10, scale: 4
      add :max_drawdown_pct, :decimal, precision: 10, scale: 4
      add :win_rate, :decimal, precision: 10, scale: 4
      add :profit_factor, :decimal, precision: 10, scale: 4
      add :total_trades, :integer, default: 0
      add :winning_trades, :integer, default: 0
      add :losing_trades, :integer, default: 0
      add :avg_win, :decimal, precision: 20, scale: 8
      add :avg_loss, :decimal, precision: 20, scale: 8
      add :largest_win, :decimal, precision: 20, scale: 8
      add :largest_loss, :decimal, precision: 20, scale: 8
      add :calculated_at, :utc_datetime_usec, null: false
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:performance_metrics, [:trading_session_id])
    create unique_index(:performance_metrics, [:trading_session_id, :calculated_at])
  end
end
