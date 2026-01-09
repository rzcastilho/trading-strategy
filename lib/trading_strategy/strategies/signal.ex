defmodule TradingStrategy.Strategies.Signal do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "signals" do
    field :signal_type, :string
    field :timestamp, :utc_datetime_usec
    field :price, :decimal
    field :indicators_data, :map
    field :confidence, :decimal
    field :metadata, :map

    belongs_to :strategy, TradingStrategy.Strategies.Strategy
    belongs_to :trading_session, TradingStrategy.Backtesting.TradingSession
    has_many :trades, TradingStrategy.Orders.Trade

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(signal, attrs) do
    signal
    |> cast(attrs, [
      :signal_type,
      :timestamp,
      :price,
      :indicators_data,
      :confidence,
      :metadata,
      :strategy_id,
      :trading_session_id
    ])
    |> validate_required([:signal_type, :timestamp, :price, :indicators_data, :strategy_id])
    |> validate_inclusion(:signal_type, [
      "buy",
      "sell",
      "entry",
      "exit",
      "stop_loss",
      "take_profit"
    ])
    |> validate_number(:price, greater_than: 0)
    |> validate_number(:confidence, greater_than_or_equal_to: 0, less_than_or_equal_to: 1)
    |> foreign_key_constraint(:strategy_id)
    |> foreign_key_constraint(:trading_session_id)
  end
end
