defmodule TradingStrategy.Repo.Migrations.AddEquityCurveToPerformanceMetrics do
  use Ecto.Migration

  def change do
    alter table(:performance_metrics) do
      add :equity_curve, :jsonb, default: "[]"
      add :equity_curve_metadata, :map, default: %{}
    end

    create index(:performance_metrics, [:equity_curve], using: :gin)
  end
end
