defmodule TradingStrategy.Orders.Position do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "positions" do
    field :symbol, :string
    field :side, :string
    field :quantity, :decimal
    field :entry_price, :decimal
    field :exit_price, :decimal
    field :stop_loss, :decimal
    field :take_profit, :decimal
    field :status, :string, default: "open"
    field :opened_at, :utc_datetime_usec
    field :closed_at, :utc_datetime_usec
    field :realized_pnl, :decimal
    field :unrealized_pnl, :decimal
    field :fees, :decimal
    field :metadata, :map

    belongs_to :trading_session, TradingStrategy.Backtesting.TradingSession
    belongs_to :strategy, TradingStrategy.Strategies.Strategy
    has_many :trades, TradingStrategy.Orders.Trade

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(position, attrs) do
    position
    |> cast(attrs, [
      :symbol,
      :side,
      :quantity,
      :entry_price,
      :exit_price,
      :stop_loss,
      :take_profit,
      :status,
      :opened_at,
      :closed_at,
      :realized_pnl,
      :unrealized_pnl,
      :fees,
      :metadata,
      :trading_session_id,
      :strategy_id
    ])
    |> validate_required([
      :symbol,
      :side,
      :quantity,
      :entry_price,
      :opened_at,
      :trading_session_id,
      :strategy_id
    ])
    |> validate_inclusion(:side, ["long", "short"])
    |> validate_inclusion(:status, ["open", "closed", "partial"])
    |> validate_number(:quantity, greater_than: 0)
    |> validate_number(:entry_price, greater_than: 0)
    |> validate_number(:exit_price, greater_than: 0)
    |> validate_number(:stop_loss, greater_than: 0)
    |> validate_number(:take_profit, greater_than: 0)
    |> foreign_key_constraint(:trading_session_id)
    |> foreign_key_constraint(:strategy_id)
  end
end
