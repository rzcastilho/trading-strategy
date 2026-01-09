defmodule TradingStrategy.Exchanges.Credentials do
  @moduledoc """
  User credential management for runtime API key handling.

  SECURITY POLICY (FR-018):
  - API credentials are NEVER persisted to database
  - Credentials exist only in GenServer state (memory)
  - Credentials are cleared on session termination
  - No logging of sensitive credential data

  This module provides a secure way to manage exchange API credentials
  during live trading sessions without storing them permanently.
  """

  use GenServer
  require Logger

  @type user_id :: String.t()
  @type credentials :: %{
          api_key: String.t(),
          api_secret: String.t(),
          passphrase: String.t() | nil
        }

  # Client API

  @doc """
  Start the credentials manager.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, opts ++ [name: __MODULE__])
  end

  @doc """
  Store credentials for a user (runtime only, never persisted).

  ## Parameters
  - `user_id`: Unique user identifier
  - `credentials`: Map containing api_key, api_secret, and optional passphrase

  ## Returns
  - `:ok` - Credentials stored successfully

  ## Examples
      iex> Credentials.store("user_123", %{
      ...>   api_key: "key",
      ...>   api_secret: "secret",
      ...>   passphrase: nil
      ...> })
      :ok
  """
  @spec store(user_id(), credentials()) :: :ok
  def store(user_id, credentials) do
    # Validate required fields
    unless Map.has_key?(credentials, :api_key) and Map.has_key?(credentials, :api_secret) do
      raise ArgumentError, "credentials must contain :api_key and :api_secret"
    end

    GenServer.call(__MODULE__, {:store, user_id, credentials})
  end

  @doc """
  Retrieve credentials for a user.

  ## Parameters
  - `user_id`: User identifier

  ## Returns
  - `{:ok, credentials}` - Credentials found
  - `{:error, :not_found}` - No credentials stored for this user

  ## Examples
      iex> Credentials.get("user_123")
      {:ok, %{api_key: "key", api_secret: "secret", passphrase: nil}}
  """
  @spec get(user_id()) :: {:ok, credentials()} | {:error, :not_found}
  def get(user_id) do
    GenServer.call(__MODULE__, {:get, user_id})
  end

  @doc """
  Delete credentials for a user.

  Called when a live trading session ends to clear credentials from memory.

  ## Parameters
  - `user_id`: User identifier

  ## Returns
  - `:ok` - Credentials deleted (or didn't exist)
  """
  @spec delete(user_id()) :: :ok
  def delete(user_id) do
    GenServer.call(__MODULE__, {:delete, user_id})
  end

  @doc """
  List all user IDs with stored credentials (for debugging/monitoring).

  Does not return actual credentials, only user IDs.

  ## Returns
  - List of user IDs
  """
  @spec list_users() :: [user_id()]
  def list_users do
    GenServer.call(__MODULE__, :list_users)
  end

  # Server Callbacks

  @impl true
  def init(:ok) do
    Logger.info("Starting Credentials manager")
    # ETS table for fast in-memory storage
    # :protected - only this process can write, any process can read
    # {:read_concurrency, true} - optimize for concurrent reads
    table = :ets.new(:credentials_store, [:set, :protected, {:read_concurrency, true}])
    {:ok, %{table: table}}
  end

  @impl true
  def handle_call({:store, user_id, credentials}, _from, state) do
    # Redact sensitive data in logs
    Logger.info("Storing credentials for user", user_id: user_id)

    # Store in ETS
    :ets.insert(state.table, {user_id, credentials})

    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:get, user_id}, _from, state) do
    case :ets.lookup(state.table, user_id) do
      [{^user_id, credentials}] ->
        {:reply, {:ok, credentials}, state}

      [] ->
        Logger.debug("Credentials not found for user", user_id: user_id)
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call({:delete, user_id}, _from, state) do
    Logger.info("Deleting credentials for user", user_id: user_id)
    :ets.delete(state.table, user_id)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:list_users, _from, state) do
    user_ids =
      state.table
      |> :ets.tab2list()
      |> Enum.map(fn {user_id, _credentials} -> user_id end)

    {:reply, user_ids, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("Credentials manager terminating", reason: inspect(reason))

    # Clear all credentials from memory on shutdown
    :ets.delete_all_objects(state.table)

    :ok
  end
end
