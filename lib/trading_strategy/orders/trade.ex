defmodule TradingStrategy.Orders.Trade do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "trades" do
    field :order_id, :string
    field :side, :string
    field :quantity, :decimal
    field :price, :decimal
    field :fee, :decimal
    field :fee_currency, :string
    field :timestamp, :utc_datetime_usec
    field :exchange, :string
    field :status, :string, default: "pending"
    field :metadata, :map

    belongs_to :position, TradingStrategy.Orders.Position
    belongs_to :signal, TradingStrategy.Strategies.Signal

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(trade, attrs) do
    trade
    |> cast(attrs, [
      :order_id,
      :side,
      :quantity,
      :price,
      :fee,
      :fee_currency,
      :timestamp,
      :exchange,
      :status,
      :metadata,
      :position_id,
      :signal_id
    ])
    |> validate_required([:side, :quantity, :price, :timestamp, :exchange, :position_id])
    |> validate_inclusion(:side, ["buy", "sell"])
    |> validate_inclusion(:status, ["pending", "filled", "partial", "cancelled", "rejected"])
    |> validate_number(:quantity, greater_than: 0)
    |> validate_number(:price, greater_than: 0)
    |> validate_number(:fee, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:position_id)
    |> foreign_key_constraint(:signal_id)
  end
end
