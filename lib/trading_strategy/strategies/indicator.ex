defmodule TradingStrategy.Strategies.Indicator do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "indicators" do
    field :name, :string
    field :type, :string
    field :parameters, :map
    field :output_key, :string

    belongs_to :strategy, TradingStrategy.Strategies.Strategy

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(indicator, attrs) do
    indicator
    |> cast(attrs, [:name, :type, :parameters, :output_key, :strategy_id])
    |> validate_required([:name, :type, :parameters, :output_key, :strategy_id])
    |> foreign_key_constraint(:strategy_id)
    |> unique_constraint([:strategy_id, :name])
  end
end
