defmodule TradingStrategy.Exchanges.HealthMonitor do
  @moduledoc """
  Exchange health monitor tracking CryptoExchange connection status.

  This GenServer monitors the health and connectivity status of exchange
  connections, tracking successful/failed requests and connection state.
  """

  use GenServer
  require Logger

  @type user_id :: String.t()
  @type health_status :: :healthy | :degraded | :unhealthy | :disconnected

  @type health_state :: %{
          status: health_status(),
          last_successful_request: DateTime.t() | nil,
          last_failed_request: DateTime.t() | nil,
          consecutive_failures: non_neg_integer(),
          total_requests: non_neg_integer(),
          successful_requests: non_neg_integer(),
          failed_requests: non_neg_integer(),
          connected: boolean()
        }

  # Health thresholds
  @degraded_threshold 3
  @unhealthy_threshold 5
  @health_check_interval :timer.seconds(30)

  # Client API

  @doc """
  Start the health monitor.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, opts ++ [name: __MODULE__])
  end

  @doc """
  Register a user for health monitoring.

  ## Parameters
  - `user_id`: User identifier to monitor

  ## Examples
      iex> HealthMonitor.register_user("user_123")
      :ok
  """
  @spec register_user(user_id()) :: :ok
  def register_user(user_id) do
    GenServer.call(__MODULE__, {:register_user, user_id})
  end

  @doc """
  Unregister a user from health monitoring.

  ## Parameters
  - `user_id`: User identifier to stop monitoring

  ## Examples
      iex> HealthMonitor.unregister_user("user_123")
      :ok
  """
  @spec unregister_user(user_id()) :: :ok
  def unregister_user(user_id) do
    GenServer.call(__MODULE__, {:unregister_user, user_id})
  end

  @doc """
  Record a successful request for a user.

  ## Parameters
  - `user_id`: User identifier

  ## Examples
      iex> HealthMonitor.record_success("user_123")
      :ok
  """
  @spec record_success(user_id()) :: :ok
  def record_success(user_id) do
    GenServer.cast(__MODULE__, {:record_success, user_id})
  end

  @doc """
  Record a failed request for a user.

  ## Parameters
  - `user_id`: User identifier
  - `reason`: Failure reason (optional)

  ## Examples
      iex> HealthMonitor.record_failure("user_123", :timeout)
      :ok
  """
  @spec record_failure(user_id(), atom() | nil) :: :ok
  def record_failure(user_id, reason \\ nil) do
    GenServer.cast(__MODULE__, {:record_failure, user_id, reason})
  end

  @doc """
  Update connection status for a user.

  ## Parameters
  - `user_id`: User identifier
  - `connected`: Boolean indicating connection status

  ## Examples
      iex> HealthMonitor.update_connection_status("user_123", true)
      :ok
  """
  @spec update_connection_status(user_id(), boolean()) :: :ok
  def update_connection_status(user_id, connected) do
    GenServer.cast(__MODULE__, {:update_connection, user_id, connected})
  end

  @doc """
  Get current health status for a user.

  ## Parameters
  - `user_id`: User identifier

  ## Returns
  - `{:ok, health_state}` if user is registered
  - `{:error, :not_found}` if user not registered

  ## Examples
      iex> HealthMonitor.get_health("user_123")
      {:ok, %{status: :healthy, connected: true, ...}}
  """
  @spec get_health(user_id()) :: {:ok, health_state()} | {:error, :not_found}
  def get_health(user_id) do
    GenServer.call(__MODULE__, {:get_health, user_id})
  end

  @doc """
  Get health status for all monitored users.

  ## Returns
  - Map of user_id => health_state

  ## Examples
      iex> HealthMonitor.get_all_health()
      %{"user_123" => %{status: :healthy, ...}, ...}
  """
  @spec get_all_health() :: %{user_id() => health_state()}
  def get_all_health do
    GenServer.call(__MODULE__, :get_all_health)
  end

  # Server Callbacks

  @impl true
  def init(:ok) do
    Logger.info("Starting Exchange Health Monitor")

    # Schedule periodic health check
    schedule_health_check()

    {:ok, %{users: %{}}}
  end

  @impl true
  def handle_call({:register_user, user_id}, _from, state) do
    Logger.info("Registering user for health monitoring", user_id: user_id)

    new_state = put_in(state, [:users, user_id], initial_health_state())

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:unregister_user, user_id}, _from, state) do
    Logger.info("Unregistering user from health monitoring", user_id: user_id)

    {_value, new_users} = Map.pop(state.users, user_id)
    new_state = %{state | users: new_users}

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:get_health, user_id}, _from, state) do
    case Map.get(state.users, user_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      health_state ->
        {:reply, {:ok, health_state}, state}
    end
  end

  @impl true
  def handle_call(:get_all_health, _from, state) do
    {:reply, state.users, state}
  end

  @impl true
  def handle_cast({:record_success, user_id}, state) do
    new_state =
      update_health_state(state, user_id, fn health_state ->
        new_health_state = %{
          health_state
          | last_successful_request: DateTime.utc_now(),
            consecutive_failures: 0,
            total_requests: health_state.total_requests + 1,
            successful_requests: health_state.successful_requests + 1
        }

        # Recalculate status
        %{new_health_state | status: calculate_status(new_health_state)}
      end)

    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:record_failure, user_id, reason}, state) do
    Logger.warning("Exchange request failure",
      user_id: user_id,
      reason: inspect(reason)
    )

    new_state =
      update_health_state(state, user_id, fn health_state ->
        new_health_state = %{
          health_state
          | last_failed_request: DateTime.utc_now(),
            consecutive_failures: health_state.consecutive_failures + 1,
            total_requests: health_state.total_requests + 1,
            failed_requests: health_state.failed_requests + 1
        }

        # Recalculate status
        new_status = calculate_status(new_health_state)

        # Log if status changed to unhealthy
        if new_status == :unhealthy and health_state.status != :unhealthy do
          Logger.error("Exchange connection unhealthy",
            user_id: user_id,
            consecutive_failures: new_health_state.consecutive_failures
          )
        end

        %{new_health_state | status: new_status}
      end)

    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:update_connection, user_id, connected}, state) do
    Logger.info("Exchange connection status updated",
      user_id: user_id,
      connected: connected
    )

    new_state =
      update_health_state(state, user_id, fn health_state ->
        new_health_state = %{health_state | connected: connected}

        # Recalculate status
        %{new_health_state | status: calculate_status(new_health_state)}
      end)

    {:noreply, new_state}
  end

  @impl true
  def handle_info(:health_check, state) do
    # Check for stale connections (no activity in last 60 seconds)
    now = DateTime.utc_now()

    new_state = %{
      state
      | users:
          Map.new(state.users, fn {user_id, health_state} ->
            # Check if last request was more than 60 seconds ago
            stale =
              case health_state.last_successful_request do
                nil ->
                  false

                last_request ->
                  DateTime.diff(now, last_request, :second) > 60
              end

            new_health_state =
              if stale and health_state.status == :healthy do
                Logger.debug("Exchange connection may be stale", user_id: user_id)
                %{health_state | status: :degraded}
              else
                health_state
              end

            {user_id, new_health_state}
          end)
    }

    # Schedule next health check
    schedule_health_check()

    {:noreply, new_state}
  end

  # Private Functions

  defp initial_health_state do
    %{
      status: :healthy,
      last_successful_request: nil,
      last_failed_request: nil,
      consecutive_failures: 0,
      total_requests: 0,
      successful_requests: 0,
      failed_requests: 0,
      connected: false
    }
  end

  defp update_health_state(state, user_id, update_fn) do
    case Map.get(state.users, user_id) do
      nil ->
        # User not registered, create initial state
        new_health_state = update_fn.(initial_health_state())
        put_in(state, [:users, user_id], new_health_state)

      health_state ->
        new_health_state = update_fn.(health_state)
        put_in(state, [:users, user_id], new_health_state)
    end
  end

  defp calculate_status(health_state) do
    cond do
      not health_state.connected ->
        :disconnected

      health_state.consecutive_failures >= @unhealthy_threshold ->
        :unhealthy

      health_state.consecutive_failures >= @degraded_threshold ->
        :degraded

      true ->
        :healthy
    end
  end

  defp schedule_health_check do
    Process.send_after(self(), :health_check, @health_check_interval)
  end
end
