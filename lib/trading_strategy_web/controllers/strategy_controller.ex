defmodule TradingStrategyWeb.StrategyController do
  use TradingStrategyWeb, :controller

  alias TradingStrategy.Strategies
  alias TradingStrategy.Strategies.Strategy

  action_fallback TradingStrategyWeb.FallbackController

  @doc """
  Lists all strategies with optional filtering.

  Query parameters:
  - status: Filter by status (draft, active, inactive, archived)
  - limit: Maximum number of results (default: 50)
  - offset: Pagination offset (default: 0)
  """
  def index(conn, params) do
    opts =
      [
        status: params["status"],
        limit: parse_int(params["limit"], 50),
        offset: parse_int(params["offset"], 0)
      ]
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    # Use list_all_strategies for API (admin function, not user-scoped)
    strategies = Strategies.list_all_strategies(opts)
    render(conn, :index, strategies: strategies)
  end

  @doc """
  Creates a new strategy from DSL content.

  Expected JSON body:
  {
    "name": "RSI Mean Reversion",
    "description": "Optional description",
    "format": "yaml",
    "content": "name: RSI Mean Reversion\\n...",
    "trading_pair": "BTC/USD",
    "timeframe": "1h",
    "user_id": 123  # Required until authentication is implemented
  }
  """
  def create(conn, %{"strategy" => strategy_params}) do
    # TODO: Add authentication and use create_strategy/2 with current_user
    case Strategies.create_strategy_admin(strategy_params) do
      {:ok, %Strategy{} = strategy} ->
        conn
        |> put_status(:created)
        |> put_resp_header("location", ~p"/api/strategies/#{strategy.id}")
        |> render(:show, strategy: strategy)

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, changeset}
    end
  end

  def create(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing required 'strategy' field in request body"})
  end

  @doc """
  Shows a single strategy by ID.
  """
  def show(conn, %{"id" => id}) do
    case Strategies.get_strategy_admin(id) do
      nil ->
        {:error, :not_found}

      strategy ->
        render(conn, :show, strategy: strategy)
    end
  end

  @doc """
  Updates a strategy.

  Expected JSON body (partial updates allowed):
  {
    "name": "Updated Name",
    "content": "updated: content",
    "status": "active"
  }
  """
  def update(conn, %{"id" => id, "strategy" => strategy_params}) do
    case Strategies.get_strategy_admin(id) do
      nil ->
        {:error, :not_found}

      strategy ->
        # TODO: Add user authentication and use update_strategy/3 with user parameter
        case Strategies.update_strategy(strategy, strategy_params, %TradingStrategy.Accounts.User{
               id: strategy.user_id
             }) do
          {:ok, %Strategy{} = updated_strategy} ->
            render(conn, :show, strategy: updated_strategy)

          {:error, %Ecto.Changeset{} = changeset} ->
            {:error, changeset}
        end
    end
  end

  def update(conn, %{"id" => _id}) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing required 'strategy' field in request body"})
  end

  @doc """
  Deletes a strategy.

  Returns 204 No Content on success.
  """
  def delete(conn, %{"id" => id}) do
    case Strategies.get_strategy_admin(id) do
      nil ->
        {:error, :not_found}

      strategy ->
        # TODO: Add user authentication and use delete_strategy/2 with user parameter
        case Strategies.delete_strategy(strategy, %TradingStrategy.Accounts.User{
               id: strategy.user_id
             }) do
          {:ok, _deleted_strategy} ->
            send_resp(conn, :no_content, "")

          {:error, %Ecto.Changeset{} = changeset} ->
            {:error, changeset}
        end
    end
  end

  # Private helper functions

  defp parse_int(nil, default), do: default

  defp parse_int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> default
    end
  end

  defp parse_int(value, _default) when is_integer(value), do: value
  defp parse_int(_, default), do: default
end
