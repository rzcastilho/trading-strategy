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
    field :lock_version, :integer, default: 1
    field :metadata, :map

    belongs_to :user, TradingStrategy.Accounts.User, type: :id

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
  - Unique strategy name and version combination (scoped to user)
  - Optimistic locking via lock_version
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
      :version,
      :user_id,
      :metadata
    ])
    |> validate_required([:name, :format, :content, :trading_pair, :timeframe, :user_id],
      message: "can't be blank - please provide a value"
    )
    |> validate_length(:name,
      min: 3,
      max: 200,
      message: "must be between 3 and 200 characters"
    )
    |> validate_inclusion(:format, ["yaml", "toml"],
      message: "must be either 'yaml' or 'toml'"
    )
    |> validate_inclusion(:status, ["draft", "active", "inactive", "archived"],
      message: "must be one of: draft, active, inactive, archived"
    )
    |> validate_inclusion(:timeframe, ["1m", "5m", "15m", "30m", "1h", "4h", "1d", "1w"],
      message: "must be a valid timeframe (1m, 5m, 15m, 30m, 1h, 4h, 1d, or 1w)"
    )
    |> validate_dsl_content()
    |> foreign_key_constraint(:user_id,
      message: "user account not found - please log in again"
    )
    |> unsafe_validate_unique([:user_id, :name, :version], TradingStrategy.Repo,
      message: "a strategy with this name already exists - please choose a different name"
    )
    |> unique_constraint([:user_id, :name, :version],
      message: "a strategy with this name already exists - please choose a different name"
    )
    |> optimistic_lock(:lock_version)
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
            add_error(
              changeset,
              :content,
              "Invalid #{String.upcase(format)} syntax - #{format_parse_error(reason)}"
            )
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
          add_error(acc, :content, format_validation_error(error))
        end)

      {:error, error} ->
        add_error(changeset, :content, format_validation_error(error))
    end
  end

  defp format_parse_error(reason) when is_binary(reason) do
    "#{reason}. Please check your syntax and try again."
  end

  defp format_parse_error(reason) do
    "#{inspect(reason)}. Please check your syntax and try again."
  end

  defp format_validation_error(error) when is_binary(error) do
    "Validation error: #{error}"
  end

  defp format_validation_error(error) do
    "Validation error: #{inspect(error)}"
  end
end
