defmodule TradingStrategy.MarketData.MarketData do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false

  schema "market_data" do
    field :symbol, :string, primary_key: true
    field :exchange, :string, primary_key: true
    field :timeframe, :string, primary_key: true
    field :timestamp, :utc_datetime_usec, primary_key: true
    field :open, :decimal
    field :high, :decimal
    field :low, :decimal
    field :close, :decimal
    field :volume, :decimal

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(market_data, attrs) do
    market_data
    |> cast(attrs, [
      :symbol,
      :exchange,
      :timeframe,
      :timestamp,
      :open,
      :high,
      :low,
      :close,
      :volume
    ])
    |> validate_required([
      :symbol,
      :exchange,
      :timeframe,
      :timestamp,
      :open,
      :high,
      :low,
      :close,
      :volume
    ])
    |> validate_number(:open, greater_than: 0)
    |> validate_number(:high, greater_than: 0)
    |> validate_number(:low, greater_than: 0)
    |> validate_number(:close, greater_than: 0)
    |> validate_number(:volume, greater_than_or_equal_to: 0)
  end
end
