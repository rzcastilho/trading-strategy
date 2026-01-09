defmodule TradingStrategy.LiveTrading.ConnectivityMonitor do
  @moduledoc """
  Connectivity monitor detecting network failures.

  Monitors exchange connectivity and detects when connection is lost,
  triggering appropriate recovery actions.
  """

  use GenServer
  require Logger

  alias TradingStrategy.Exchanges.{Exchange, HealthMonitor}

  @type user_id :: String.t()
  @type connectivity_status :: :connected | :disconnected | :degraded

  @check_interval :timer.seconds(10)
  @failure_threshold 3

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Monitor connectivity for a user.
  """
  @spec monitor_user(user_id()) :: :ok
  def monitor_user(user_id) do
    GenServer.call(__MODULE__, {:monitor_user, user_id})
  end

  @doc """
  Stop monitoring connectivity for a user.
  """
  @spec stop_monitoring(user_id()) :: :ok
  def stop_monitoring(user_id) do
    GenServer.call(__MODULE__, {:stop_monitoring, user_id})
  end

  @doc """
  Get connectivity status for a user.
  """
  @spec get_status(user_id()) :: {:ok, connectivity_status()} | {:error, :not_found}
  def get_status(user_id) do
    GenServer.call(__MODULE__, {:get_status, user_id})
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    Logger.info("Starting Connectivity Monitor")
    schedule_check()
    {:ok, %{monitored_users: %{}}}
  end

  @impl true
  def handle_call({:monitor_user, user_id}, _from, state) do
    Logger.info("Monitoring connectivity", user_id: user_id)

    user_state = %{
      user_id: user_id,
      status: :connected,
      consecutive_failures: 0,
      last_check: DateTime.utc_now()
    }

    new_state = put_in(state, [:monitored_users, user_id], user_state)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:stop_monitoring, user_id}, _from, state) do
    {_value, new_users} = Map.pop(state.monitored_users, user_id)
    {:reply, :ok, %{state | monitored_users: new_users}}
  end

  @impl true
  def handle_call({:get_status, user_id}, _from, state) do
    case Map.get(state.monitored_users, user_id) do
      nil -> {:reply, {:error, :not_found}, state}
      user_state -> {:reply, {:ok, user_state.status}, state}
    end
  end

  @impl true
  def handle_info(:check_connectivity, state) do
    new_users =
      Map.new(state.monitored_users, fn {user_id, user_state} ->
        updated_state = check_user_connectivity(user_state)
        {user_id, updated_state}
      end)

    schedule_check()
    {:noreply, %{state | monitored_users: new_users}}
  end

  # Private Functions

  defp check_user_connectivity(user_state) do
    case HealthMonitor.get_health(user_state.user_id) do
      {:ok, health} ->
        update_connectivity_status(user_state, health.connected, health.status)

      {:error, _} ->
        # Assume disconnected if health check fails
        update_connectivity_status(user_state, false, :unhealthy)
    end
  end

  defp update_connectivity_status(user_state, connected, health_status) do
    old_status = user_state.status

    {new_status, new_failures} =
      cond do
        connected and health_status == :healthy ->
          {:connected, 0}

        connected and health_status == :degraded ->
          {:degraded, user_state.consecutive_failures}

        not connected ->
          failures = user_state.consecutive_failures + 1

          if failures >= @failure_threshold do
            {:disconnected, failures}
          else
            {user_state.status, failures}
          end

        true ->
          {:degraded, user_state.consecutive_failures}
      end

    # Log status changes
    if old_status != new_status do
      Logger.warning("Connectivity status changed",
        user_id: user_state.user_id,
        old_status: old_status,
        new_status: new_status
      )
    end

    %{
      user_state
      | status: new_status,
        consecutive_failures: new_failures,
        last_check: DateTime.utc_now()
    }
  end

  defp schedule_check do
    Process.send_after(self(), :check_connectivity, @check_interval)
  end
end
