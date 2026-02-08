defmodule TradingStrategy.Backtesting.PerformanceMetrics do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "performance_metrics" do
    field :total_return, :decimal
    field :total_return_pct, :decimal
    field :sharpe_ratio, :decimal
    field :max_drawdown, :decimal
    field :max_drawdown_pct, :decimal
    field :win_rate, :decimal
    field :profit_factor, :decimal
    field :total_trades, :integer
    field :winning_trades, :integer
    field :losing_trades, :integer
    field :avg_win, :decimal
    field :avg_loss, :decimal
    field :largest_win, :decimal
    field :largest_loss, :decimal
    field :calculated_at, :utc_datetime_usec
    field :metadata, :map

    # NEW FIELDS for Phase 2
    field :equity_curve, {:array, :map}
    field :equity_curve_metadata, :map

    belongs_to :trading_session, TradingStrategy.Backtesting.TradingSession

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(performance_metrics, attrs) do
    performance_metrics
    |> cast(attrs, [
      :total_return,
      :total_return_pct,
      :sharpe_ratio,
      :max_drawdown,
      :max_drawdown_pct,
      :win_rate,
      :profit_factor,
      :total_trades,
      :winning_trades,
      :losing_trades,
      :avg_win,
      :avg_loss,
      :largest_win,
      :largest_loss,
      :calculated_at,
      :metadata,
      :trading_session_id,
      :equity_curve,
      :equity_curve_metadata
    ])
    |> validate_required([:calculated_at, :trading_session_id])
    |> validate_number(:win_rate, greater_than_or_equal_to: 0, less_than_or_equal_to: 1)
    |> validate_number(:total_trades, greater_than_or_equal_to: 0)
    |> validate_number(:winning_trades, greater_than_or_equal_to: 0)
    |> validate_number(:losing_trades, greater_than_or_equal_to: 0)
    |> validate_equity_curve()
    |> foreign_key_constraint(:trading_session_id)
    |> unique_constraint([:trading_session_id, :calculated_at])
  end

  defp validate_equity_curve(changeset) do
    curve = get_field(changeset, :equity_curve)

    if curve && length(curve) > 1000 do
      add_error(changeset, :equity_curve, "cannot exceed 1000 points")
    else
      changeset
    end
  end
end
