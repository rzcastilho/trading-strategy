defmodule TradingStrategy.Backtesting.TradingSession do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "trading_sessions" do
    field :mode, :string
    field :status, :string, default: "pending"
    field :initial_capital, :decimal
    field :current_capital, :decimal
    field :started_at, :utc_datetime_usec
    field :ended_at, :utc_datetime_usec
    field :config, :map
    field :metadata, :map

    belongs_to :strategy, TradingStrategy.Strategies.Strategy
    has_many :positions, TradingStrategy.Orders.Position
    has_many :signals, TradingStrategy.Strategies.Signal
    has_many :performance_metrics, TradingStrategy.Backtesting.PerformanceMetrics

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(trading_session, attrs) do
    trading_session
    |> cast(attrs, [
      :mode,
      :status,
      :initial_capital,
      :current_capital,
      :started_at,
      :ended_at,
      :config,
      :metadata,
      :strategy_id
    ])
    |> validate_required([:mode, :initial_capital, :strategy_id])
    |> validate_inclusion(:mode, ["backtest", "paper", "live"])
    |> validate_inclusion(:status, [
      "pending",
      "running",
      "paused",
      "completed",
      "stopped",
      "error"
    ])
    |> validate_number(:initial_capital, greater_than: 0)
    |> validate_number(:current_capital, greater_than: 0)
    |> foreign_key_constraint(:strategy_id)
  end
end
