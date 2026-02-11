defmodule TradingStrategy.StrategyEditor.StrategyDefinition do
  @moduledoc """
  Schema for strategy definitions that can be edited in either builder or DSL format.

  This module represents the root entity for bidirectional editor synchronization.
  Strategies can be modified through the visual builder or manual DSL editor.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias TradingStrategy.Accounts.User

  schema "strategy_definitions" do
    field :name, :string
    field :dsl_text, :string
    field :builder_state, :map
    field :last_modified_editor, Ecto.Enum, values: [:builder, :dsl]
    field :last_modified_at, :utc_datetime_usec
    field :validation_status, :map
    field :comments, {:array, :map}

    belongs_to :user, User

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for strategy definition creation.
  """
  def changeset(strategy, attrs) do
    strategy
    |> cast(attrs, [
      :name,
      :dsl_text,
      :builder_state,
      :last_modified_editor,
      :last_modified_at,
      :validation_status,
      :comments,
      :user_id
    ])
    |> validate_required([:name, :user_id])
    |> validate_length(:name, min: 1, max: 255)
    |> validate_editor_consistency()
    |> foreign_key_constraint(:user_id)
  end

  @doc """
  Changeset for updating a strategy definition.
  Validates that changes come from a consistent editor source.
  """
  def update_changeset(strategy, attrs) do
    strategy
    |> cast(attrs, [
      :name,
      :dsl_text,
      :builder_state,
      :last_modified_editor,
      :last_modified_at,
      :validation_status,
      :comments
    ])
    |> validate_length(:name, min: 1, max: 255)
    |> validate_editor_consistency()
  end

  # Private Functions

  defp validate_editor_consistency(changeset) do
    # Ensure last_modified_editor matches the field being changed
    dsl_changed? = get_change(changeset, :dsl_text)
    builder_changed? = get_change(changeset, :builder_state)

    cond do
      dsl_changed? && is_nil(builder_changed?) ->
        put_change(changeset, :last_modified_editor, :dsl)
        |> put_change(:last_modified_at, DateTime.utc_now(:microsecond))

      builder_changed? && is_nil(dsl_changed?) ->
        put_change(changeset, :last_modified_editor, :builder)
        |> put_change(:last_modified_at, DateTime.utc_now(:microsecond))

      dsl_changed? && builder_changed? ->
        # Both changed - last_modified_editor must be explicitly set in attrs
        changeset

      true ->
        changeset
    end
  end
end
