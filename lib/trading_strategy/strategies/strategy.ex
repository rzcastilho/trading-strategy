defmodule TradingStrategy.Strategies.Strategy do
  use Ecto.Schema
  import Ecto.Changeset

  alias TradingStrategy.Strategies.DSL.{Parser, Validator}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "strategies" do
    field :name, :string
    field :description, :string
    field :format, :string
    field :content, :string
    field :trading_pair, :string
    field :timeframe, :string
    field :status, :string, default: "draft"
    field :version, :integer, default: 1

    has_many :indicators, TradingStrategy.Strategies.Indicator
    has_many :signals, TradingStrategy.Strategies.Signal
    has_many :trading_sessions, TradingStrategy.Backtesting.TradingSession
    has_many :positions, TradingStrategy.Orders.Position

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Creates a changeset for a new or existing strategy.

  Validates:
  - Required fields
  - Format and status enums
  - DSL content parsing and validation
  - Unique strategy name and version combination
  """
  def changeset(strategy, attrs) do
    strategy
    |> cast(attrs, [
      :name,
      :description,
      :format,
      :content,
      :trading_pair,
      :timeframe,
      :status,
      :version
    ])
    |> validate_required([:name, :format, :content, :trading_pair, :timeframe])
    |> validate_inclusion(:format, ["yaml", "toml"])
    |> validate_inclusion(:status, ["draft", "active", "inactive", "archived"])
    |> validate_dsl_content()
    |> unique_constraint([:name, :version])
  end

  # Private Functions

  defp validate_dsl_content(changeset) do
    content = get_field(changeset, :content)
    format = get_field(changeset, :format)

    case {content, format} do
      {nil, _} ->
        changeset

      {_, nil} ->
        changeset

      {content, format} when is_binary(content) and format in ["yaml", "toml"] ->
        format_atom = String.to_existing_atom(format)

        case Parser.parse(content, format_atom) do
          {:ok, parsed_strategy} ->
            validate_parsed_strategy(changeset, parsed_strategy)

          {:error, reason} ->
            add_error(changeset, :content, "Failed to parse #{format}: #{reason}")
        end

      _ ->
        changeset
    end
  end

  defp validate_parsed_strategy(changeset, parsed_strategy) do
    case Validator.validate(parsed_strategy) do
      {:ok, _validated} ->
        changeset

      {:error, errors} when is_list(errors) ->
        Enum.reduce(errors, changeset, fn error, acc ->
          add_error(acc, :content, error)
        end)

      {:error, error} ->
        add_error(changeset, :content, error)
    end
  end
end
