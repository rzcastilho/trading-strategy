defmodule TradingStrategy.Strategies do
  @moduledoc """
  The Strategies context.

  Provides functions for managing trading strategy definitions including:
  - Creating, reading, updating, and deleting strategies
  - Parsing and validating DSL content
  - Managing strategy versions
  """

  import Ecto.Query, warn: false
  alias TradingStrategy.Repo
  alias TradingStrategy.Strategies.Strategy

  @doc """
  Returns the list of strategies.

  ## Parameters
    - `opts`: Keyword list of options
      - `:status` - Filter by status (default: all statuses)
      - `:limit` - Limit number of results
      - `:offset` - Offset for pagination

  ## Examples

      iex> list_strategies()
      [%Strategy{}, ...]

      iex> list_strategies(status: "active", limit: 10)
      [%Strategy{}, ...]
  """
  def list_strategies(opts \\ []) do
    query = from(s in Strategy, order_by: [desc: s.inserted_at])

    query
    |> maybe_filter_by_status(opts[:status])
    |> maybe_limit(opts[:limit])
    |> maybe_offset(opts[:offset])
    |> Repo.all()
  end

  @doc """
  Gets a single strategy.

  Raises `Ecto.NoResultsError` if the Strategy does not exist.

  ## Examples

      iex> get_strategy!(123)
      %Strategy{}

      iex> get_strategy!(456)
      ** (Ecto.NoResultsError)
  """
  def get_strategy!(id), do: Repo.get!(Strategy, id)

  @doc """
  Gets a single strategy, returns nil if not found.

  ## Examples

      iex> get_strategy(123)
      %Strategy{}

      iex> get_strategy(456)
      nil
  """
  def get_strategy(id), do: Repo.get(Strategy, id)

  @doc """
  Gets a strategy by name and optional version.

  ## Examples

      iex> get_strategy_by_name("RSI Mean Reversion")
      %Strategy{}

      iex> get_strategy_by_name("RSI Mean Reversion", 2)
      %Strategy{}
  """
  def get_strategy_by_name(name, version \\ nil) do
    query = from(s in Strategy, where: s.name == ^name)

    query =
      if version do
        from(s in query, where: s.version == ^version)
      else
        from(s in query, order_by: [desc: s.version], limit: 1)
      end

    Repo.one(query)
  end

  @doc """
  Creates a strategy.

  ## Examples

      iex> create_strategy(%{name: "Test Strategy", format: "yaml", content: "..."})
      {:ok, %Strategy{}}

      iex> create_strategy(%{name: nil})
      {:error, %Ecto.Changeset{}}
  """
  def create_strategy(attrs \\ %{}) do
    %Strategy{}
    |> Strategy.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a strategy.

  ## Examples

      iex> update_strategy(strategy, %{name: "Updated Name"})
      {:ok, %Strategy{}}

      iex> update_strategy(strategy, %{name: nil})
      {:error, %Ecto.Changeset{}}
  """
  def update_strategy(%Strategy{} = strategy, attrs) do
    strategy
    |> Strategy.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a strategy.

  ## Examples

      iex> delete_strategy(strategy)
      {:ok, %Strategy{}}

      iex> delete_strategy(strategy)
      {:error, %Ecto.Changeset{}}
  """
  def delete_strategy(%Strategy{} = strategy) do
    Repo.delete(strategy)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking strategy changes.

  ## Examples

      iex> change_strategy(strategy)
      %Ecto.Changeset{data: %Strategy{}}
  """
  def change_strategy(%Strategy{} = strategy, attrs \\ %{}) do
    Strategy.changeset(strategy, attrs)
  end

  @doc """
  Activates a strategy by changing its status to "active".

  ## Examples

      iex> activate_strategy(strategy)
      {:ok, %Strategy{status: "active"}}
  """
  def activate_strategy(%Strategy{} = strategy) do
    update_strategy(strategy, %{status: "active"})
  end

  @doc """
  Deactivates a strategy by changing its status to "inactive".

  ## Examples

      iex> deactivate_strategy(strategy)
      {:ok, %Strategy{status: "inactive"}}
  """
  def deactivate_strategy(%Strategy{} = strategy) do
    update_strategy(strategy, %{status: "inactive"})
  end

  @doc """
  Archives a strategy by changing its status to "archived".

  ## Examples

      iex> archive_strategy(strategy)
      {:ok, %Strategy{status: "archived"}}
  """
  def archive_strategy(%Strategy{} = strategy) do
    update_strategy(strategy, %{status: "archived"})
  end

  @doc """
  Creates a new version of a strategy.

  The new version will have the same name but incremented version number.

  ## Examples

      iex> create_new_version(strategy, %{content: "updated content"})
      {:ok, %Strategy{version: 2}}
  """
  def create_new_version(%Strategy{} = strategy, attrs) do
    next_version = (strategy.version || 1) + 1

    attrs
    |> Map.put(:name, strategy.name)
    |> Map.put(:version, next_version)
    |> create_strategy()
  end

  # Private query helpers

  defp maybe_filter_by_status(query, nil), do: query

  defp maybe_filter_by_status(query, status) when is_binary(status) do
    from(s in query, where: s.status == ^status)
  end

  defp maybe_limit(query, nil), do: query
  defp maybe_limit(query, limit) when is_integer(limit), do: from(s in query, limit: ^limit)

  defp maybe_offset(query, nil), do: query
  defp maybe_offset(query, offset) when is_integer(offset), do: from(s in query, offset: ^offset)
end
