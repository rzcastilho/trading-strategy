defmodule TradingStrategy.Strategies do
  @moduledoc """
  The Strategies context.

  Provides functions for managing trading strategy definitions including:
  - Creating, reading, updating, and deleting strategies
  - Parsing and validating DSL content
  - Managing strategy versions
  - User-scoped queries and authorization
  """

  import Ecto.Query, warn: false
  alias TradingStrategy.Repo
  alias TradingStrategy.Strategies.Strategy
  alias TradingStrategy.Accounts.User

  @doc """
  Returns the list of strategies for a specific user.

  ## Parameters
    - `user`: User struct or user_id (binary_id)
    - `opts`: Keyword list of options
      - `:status` - Filter by status (default: all statuses)
      - `:limit` - Limit number of results (default: 50)
      - `:offset` - Offset for pagination

  ## Examples

      iex> list_strategies(%User{id: user_id})
      [%Strategy{}, ...]

      iex> list_strategies(%User{id: user_id}, status: "active", limit: 10)
      [%Strategy{}, ...]
  """
  def list_strategies(%User{id: user_id}, opts \\ []) do
    query =
      from(s in Strategy,
        where: s.user_id == ^user_id,
        order_by: [desc: s.inserted_at]
      )

    query
    |> maybe_filter_by_status(opts[:status])
    |> maybe_limit(opts[:limit] || 50)
    |> maybe_offset(opts[:offset])
    |> Repo.all()
  end

  @doc """
  Returns the list of all strategies (admin use only, not user-scoped).

  ## Parameters
    - `opts`: Keyword list of options
      - `:status` - Filter by status (default: all statuses)
      - `:limit` - Limit number of results
      - `:offset` - Offset for pagination

  ## Examples

      iex> list_all_strategies()
      [%Strategy{}, ...]

      iex> list_all_strategies(status: "active", limit: 10)
      [%Strategy{}, ...]
  """
  def list_all_strategies(opts \\ []) do
    query = from(s in Strategy, order_by: [desc: s.inserted_at])

    query
    |> maybe_filter_by_status(opts[:status])
    |> maybe_limit(opts[:limit])
    |> maybe_offset(opts[:offset])
    |> Repo.all()
  end

  @doc """
  Gets a single strategy for a specific user.

  Returns nil if the strategy does not exist or does not belong to the user.

  ## Examples

      iex> get_strategy("strategy-id", %User{id: user_id})
      %Strategy{}

      iex> get_strategy("strategy-id", %User{id: user_id})
      nil
  """
  def get_strategy(id, %User{id: user_id}) do
    Repo.one(
      from s in Strategy,
        where: s.id == ^id and s.user_id == ^user_id
    )
  end

  @doc """
  Gets a single strategy for a specific user.

  Raises `Ecto.NoResultsError` if the Strategy does not exist or does not belong to the user.

  ## Examples

      iex> get_strategy!("strategy-id", %User{id: user_id})
      %Strategy{}

      iex> get_strategy!("strategy-id", %User{id: user_id})
      ** (Ecto.NoResultsError)
  """
  def get_strategy!(id, %User{id: user_id}) do
    Repo.one!(
      from s in Strategy,
        where: s.id == ^id and s.user_id == ^user_id
    )
  end

  @doc """
  Gets a single strategy by ID (admin use only, not user-scoped).

  Raises `Ecto.NoResultsError` if the Strategy does not exist.

  ## Examples

      iex> get_strategy_admin!(123)
      %Strategy{}

      iex> get_strategy_admin!(456)
      ** (Ecto.NoResultsError)
  """
  def get_strategy_admin!(id), do: Repo.get!(Strategy, id)

  @doc """
  Gets a single strategy by ID (admin use only, not user-scoped).

  Returns nil if not found.

  ## Examples

      iex> get_strategy_admin(123)
      %Strategy{}

      iex> get_strategy_admin(456)
      nil
  """
  def get_strategy_admin(id), do: Repo.get(Strategy, id)

  @doc """
  Gets a strategy by name and optional version for a specific user.

  Returns the latest version if version is not specified.

  ## Examples

      iex> get_strategy_by_name("RSI Mean Reversion", %User{id: user_id})
      %Strategy{}

      iex> get_strategy_by_name("RSI Mean Reversion", %User{id: user_id}, 2)
      %Strategy{}
  """
  def get_strategy_by_name(name, %User{id: user_id}, version \\ nil) do
    query =
      from(s in Strategy,
        where: s.name == ^name and s.user_id == ^user_id
      )

    query =
      if version do
        from(s in query, where: s.version == ^version)
      else
        from(s in query, order_by: [desc: s.version], limit: 1)
      end

    Repo.one(query)
  end

  @doc """
  Creates a strategy for a specific user.

  ## Examples

      iex> create_strategy(%{name: "Test Strategy", format: "yaml", content: "..."}, %User{id: user_id})
      {:ok, %Strategy{}}

      iex> create_strategy(%{name: nil}, %User{id: user_id})
      {:error, %Ecto.Changeset{}}
  """
  def create_strategy(attrs, %User{id: user_id}) do
    # Ensure consistent key format - use string keys for form params compatibility
    attrs =
      attrs
      |> stringify_keys()
      |> Map.delete("user_id")
      |> Map.put("user_id", user_id)

    %Strategy{}
    |> Strategy.changeset(attrs)
    |> Repo.insert()
    |> broadcast_strategy_change(:strategy_created, user_id)
  end

  @doc """
  Creates a strategy (admin use only, not user-scoped).

  NOTE: This function is for API/admin use only. User ID must be provided in attrs.
  For user-scoped creation, use create_strategy/2 instead.

  ## Examples

      iex> create_strategy_admin(%{name: "Test Strategy", user_id: user_id, format: "yaml", content: "..."})
      {:ok, %Strategy{}}
  """
  def create_strategy_admin(attrs) do
    attrs = stringify_keys(attrs)

    %Strategy{}
    |> Strategy.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, strategy} = result ->
        if strategy.user_id do
          broadcast_strategy_change(result, :strategy_created, strategy.user_id)
        else
          result
        end

      error ->
        error
    end
  end

  @doc """
  Updates a strategy for a specific user.

  Verifies that the strategy belongs to the user before updating.

  ## Examples

      iex> update_strategy(strategy, %{name: "Updated Name"}, %User{id: user_id})
      {:ok, %Strategy{}}

      iex> update_strategy(strategy, %{name: nil}, %User{id: user_id})
      {:error, %Ecto.Changeset{}}
  """
  def update_strategy(%Strategy{user_id: user_id} = strategy, attrs, %User{id: user_id}) do
    strategy
    |> Strategy.changeset(attrs)
    |> Repo.update()
    |> broadcast_strategy_change(:strategy_updated, user_id)
  end

  def update_strategy(%Strategy{}, _attrs, %User{}) do
    {:error, :unauthorized}
  end

  @doc """
  Deletes a strategy for a specific user.

  Verifies that the strategy belongs to the user before deleting.

  ## Examples

      iex> delete_strategy(strategy, %User{id: user_id})
      {:ok, %Strategy{}}

      iex> delete_strategy(strategy, %User{id: user_id})
      {:error, %Ecto.Changeset{}}
  """
  def delete_strategy(%Strategy{user_id: user_id} = strategy, %User{id: user_id}) do
    Repo.delete(strategy)
    |> broadcast_strategy_change(:strategy_deleted, user_id)
  end

  def delete_strategy(%Strategy{}, %User{}) do
    {:error, :unauthorized}
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
  Checks if a strategy can be edited.

  Strategies can be edited when in "draft" or "inactive" status.
  Active and archived strategies cannot be edited.

  ## Examples

      iex> can_edit?(%Strategy{status: "draft"})
      true

      iex> can_edit?(%Strategy{status: "active"})
      false
  """
  def can_edit?(%Strategy{status: status}) do
    status in ["draft", "inactive"]
  end

  @doc """
  Checks if a strategy can be activated.

  Returns {:ok, :allowed} if the strategy can be activated,
  or {:error, reason} if it cannot.

  ## Examples

      iex> can_activate?(%Strategy{status: "draft", content: "..."})
      {:ok, :allowed}

      iex> can_activate?(%Strategy{status: "archived"})
      {:error, "Cannot activate archived strategy"}
  """
  def can_activate?(%Strategy{status: "active"}), do: {:error, "Strategy is already active"}

  def can_activate?(%Strategy{status: "archived"}),
    do: {:error, "Cannot activate archived strategy"}

  def can_activate?(%Strategy{content: content}) when content in [nil, ""],
    do: {:error, "Strategy content is required"}

  def can_activate?(%Strategy{}), do: {:ok, :allowed}

  @doc """
  Activates a strategy by changing its status to "active".

  Validates that the strategy can be activated before changing status.

  ## Examples

      iex> activate_strategy(strategy, %User{id: user_id})
      {:ok, %Strategy{status: "active"}}

      iex> activate_strategy(archived_strategy, %User{id: user_id})
      {:error, "Cannot activate archived strategy"}
  """
  def activate_strategy(%Strategy{user_id: user_id} = strategy, %User{id: user_id}) do
    case can_activate?(strategy) do
      {:ok, :allowed} ->
        strategy
        |> Strategy.changeset(%{status: "active"})
        |> Repo.update()

      {:error, reason} ->
        {:error, reason}
    end
  end

  def activate_strategy(%Strategy{}, %User{}) do
    {:error, :unauthorized}
  end

  @doc """
  Deactivates a strategy by changing its status to "inactive".

  ## Examples

      iex> deactivate_strategy(strategy, %User{id: user_id})
      {:ok, %Strategy{status: "inactive"}}
  """
  def deactivate_strategy(%Strategy{user_id: user_id} = strategy, %User{id: user_id}) do
    strategy
    |> Strategy.changeset(%{status: "inactive"})
    |> Repo.update()
  end

  def deactivate_strategy(%Strategy{}, %User{}) do
    {:error, :unauthorized}
  end

  @doc """
  Archives a strategy by changing its status to "archived".

  Active strategies cannot be archived directly - they must be deactivated first.

  ## Examples

      iex> archive_strategy(strategy, %User{id: user_id})
      {:ok, %Strategy{status: "archived"}}

      iex> archive_strategy(active_strategy, %User{id: user_id})
      {:error, "Cannot archive active strategy. Deactivate it first."}
  """
  def archive_strategy(%Strategy{status: "active"}, %User{}) do
    {:error, "Cannot archive active strategy. Deactivate it first."}
  end

  def archive_strategy(%Strategy{user_id: user_id} = strategy, %User{id: user_id}) do
    strategy
    |> Strategy.changeset(%{status: "archived"})
    |> Repo.update()
  end

  def archive_strategy(%Strategy{}, %User{}) do
    {:error, :unauthorized}
  end

  @doc """
  Gets all versions of a strategy for a specific user.

  Returns strategies ordered by version (descending).

  ## Examples

      iex> get_strategy_versions("RSI Mean Reversion", %User{id: user_id})
      [%Strategy{version: 3}, %Strategy{version: 2}, %Strategy{version: 1}]
  """
  def get_strategy_versions(strategy_name, %User{id: user_id}) do
    Repo.all(
      from s in Strategy,
        where: s.name == ^strategy_name and s.user_id == ^user_id,
        order_by: [desc: s.version]
    )
  end

  @doc """
  Creates a new version of a strategy.

  The new version will have the same name but incremented version number.

  ## Examples

      iex> create_new_version(strategy, %{content: "updated content"})
      {:ok, %Strategy{version: 2}}
  """
  def create_new_version(%Strategy{user_id: user_id} = strategy, attrs) do
    next_version = (strategy.version || 1) + 1

    attrs
    |> Map.put(:name, strategy.name)
    |> Map.put(:version, next_version)
    |> Map.put(:user_id, user_id)
    |> Map.put(:status, "draft")
    |> then(&create_strategy(&1, %User{id: user_id}))
  end

  @doc """
  Duplicates an existing strategy for the given user.

  Creates a copy of the strategy with " - Copy" appended to the name.
  If a strategy with that name already exists, increments the suffix
  (e.g., " - Copy 2", " - Copy 3").

  The duplicate strategy is always created with "draft" status,
  regardless of the original strategy's status.

  ## Parameters
    - `strategy`: Strategy struct to duplicate
    - `user`: User struct who will own the duplicate

  ## Returns
    - `{:ok, %Strategy{}}` - Successfully created duplicate
    - `{:error, :not_found}` - Strategy doesn't belong to user
    - `{:error, changeset}` - Validation errors

  ## Examples

      iex> duplicate_strategy(strategy, user)
      {:ok, %Strategy{name: "Original Strategy - Copy"}}

      iex> duplicate_strategy(other_users_strategy, user)
      {:error, :not_found}
  """
  @spec duplicate_strategy(Strategy.t(), User.t()) ::
          {:ok, Strategy.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def duplicate_strategy(%Strategy{user_id: strategy_user_id} = strategy, %User{id: user_id}) do
    # Verify the user owns this strategy
    if strategy_user_id != user_id do
      {:error, :not_found}
    else
      # Generate unique name with " - Copy" suffix
      duplicate_name = generate_unique_copy_name(strategy.name, user_id)

      # Create duplicate with all fields except identity
      attrs = %{
        name: duplicate_name,
        description: strategy.description,
        format: strategy.format,
        content: strategy.content,
        trading_pair: strategy.trading_pair,
        timeframe: strategy.timeframe,
        # Always create as draft
        status: "draft",
        # New strategy starts at version 1
        version: 1,
        metadata: strategy.metadata
      }

      create_strategy(attrs, %User{id: user_id})
    end
  end

  @doc """
  Tests strategy syntax without saving to database.

  Parses and validates the DSL content to provide immediate feedback on syntax errors.
  This is faster than creating a full backtest and useful for development/debugging.

  ## Parameters
    - `content`: String containing the strategy DSL definition
    - `format`: Atom indicating the format (:yaml or :toml)

  ## Returns
    - `{:ok, result}` where result contains:
      - `:parsed` - The parsed and validated strategy map
      - `:summary` - A human-readable summary of the strategy
    - `{:error, errors}` where errors is a list of validation error messages or a string

  ## Examples

      iex> test_strategy_syntax(valid_yaml_content, :yaml)
      {:ok, %{parsed: %{...}, summary: %{...}}}

      iex> test_strategy_syntax("invalid: [yaml", :yaml)
      {:error, "Failed to parse YAML: ..."}

  ## Performance
  This operation should complete in <3 seconds for strategies with up to 10 indicators (SC-005).
  """
  @spec test_strategy_syntax(String.t(), atom()) ::
          {:ok, %{parsed: map(), summary: map()}} | {:error, String.t() | list(String.t())}
  def test_strategy_syntax(content, format) when format in [:yaml, :toml] do
    # Emit telemetry start event
    start_time = System.monotonic_time()
    metadata = %{format: format, content_size: byte_size(content)}

    :telemetry.execute(
      [:trading_strategy, :strategies, :syntax_test, :start],
      %{system_time: System.system_time()},
      metadata
    )

    result =
      with {:ok, parsed} <- TradingStrategy.Strategies.DSL.Parser.parse(content, format),
           {:ok, validated} <- TradingStrategy.Strategies.DSL.Validator.validate(parsed) do
        summary = generate_strategy_summary(validated)
        {:ok, %{parsed: validated, summary: summary}}
      else
        {:error, error} when is_binary(error) ->
          {:error, error}

        {:error, errors} when is_list(errors) ->
          {:error, errors}

        error ->
          {:error, "Unexpected error during syntax test: #{inspect(error)}"}
      end

    # Emit telemetry stop event
    duration = System.monotonic_time() - start_time

    :telemetry.execute(
      [:trading_strategy, :strategies, :syntax_test, :stop],
      %{duration: duration},
      Map.put(metadata, :result, elem(result, 0))
    )

    result
  end

  def test_strategy_syntax(_content, format) do
    {:error, "Unsupported format: #{inspect(format)}. Supported formats are :yaml and :toml"}
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

  # PubSub broadcasting helpers

  defp broadcast_strategy_change({:ok, strategy} = result, event, user_id) do
    Phoenix.PubSub.broadcast(
      TradingStrategy.PubSub,
      "strategies:user:#{user_id}",
      {event, strategy.id}
    )

    result
  end

  defp broadcast_strategy_change(error, _event, _user_id), do: error

  # Helper to ensure all keys are strings for consistent handling
  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn
      {key, value} when is_atom(key) -> {Atom.to_string(key), value}
      {key, value} -> {key, value}
    end)
  end

  # Generate unique copy name with " - Copy" suffix
  defp generate_unique_copy_name(original_name, user_id) do
    base_name = "#{original_name} - Copy"
    max_name_length = 200

    # If base name fits, check if it's unique
    if String.length(base_name) <= max_name_length do
      find_unique_name(base_name, original_name, user_id, 2)
    else
      # Truncate original name to fit " - Copy" suffix
      max_original_length = max_name_length - String.length(" - Copy")
      truncated = String.slice(original_name, 0, max_original_length)
      find_unique_name("#{truncated} - Copy", truncated, user_id, 2)
    end
  end

  defp find_unique_name(candidate_name, original_name, user_id, counter) do
    # Check if name exists for this user
    existing =
      Repo.one(
        from s in Strategy,
          where: s.user_id == ^user_id and s.name == ^candidate_name,
          select: count(s.id)
      )

    if existing == 0 do
      candidate_name
    else
      # Generate next candidate name
      next_candidate = "#{original_name} - Copy #{counter}"

      # Ensure it fits within max length
      if String.length(next_candidate) <= 200 do
        find_unique_name(next_candidate, original_name, user_id, counter + 1)
      else
        # Truncate and try again
        max_original_length = 200 - String.length(" - Copy #{counter}")
        truncated = String.slice(original_name, 0, max_original_length)
        find_unique_name("#{truncated} - Copy #{counter}", truncated, user_id, counter + 1)
      end
    end
  end

  # Generate a human-readable summary of a validated strategy
  defp generate_strategy_summary(strategy) when is_map(strategy) do
    indicators = get_in(strategy, ["indicators"]) || []
    entry_conditions = get_in(strategy, ["entry_conditions"]) || []
    exit_conditions = get_in(strategy, ["exit_conditions"]) || []
    stop_conditions = get_in(strategy, ["stop_conditions"]) || []

    %{
      name: strategy["name"],
      trading_pair: strategy["trading_pair"],
      timeframe: strategy["timeframe"],
      indicator_count: length(indicators),
      indicators: Enum.map(indicators, &extract_indicator_name/1),
      entry_condition_count: count_conditions(entry_conditions),
      exit_condition_count: count_conditions(exit_conditions),
      stop_condition_count: count_conditions(stop_conditions),
      has_risk_parameters: Map.has_key?(strategy, "risk_parameters"),
      has_position_sizing: Map.has_key?(strategy, "position_sizing")
    }
  end

  defp extract_indicator_name(indicator) when is_map(indicator) do
    indicator["name"] || indicator["type"] || "unknown"
  end

  defp extract_indicator_name(_), do: "unknown"

  defp count_conditions(conditions) when is_list(conditions), do: length(conditions)
  defp count_conditions(condition) when is_binary(condition), do: 1
  defp count_conditions(_), do: 0
end
