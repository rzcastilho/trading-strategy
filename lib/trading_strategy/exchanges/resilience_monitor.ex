defmodule TradingStrategy.Exchanges.ResilienceMonitor do
  @moduledoc """
  Monitor crypto-exchange circuit breaker status logging API health events.

  This module monitors the circuit breaker state and other resilience patterns
  used by the crypto-exchange library, providing visibility into API health
  and automatically logging important state transitions.
  """

  use GenServer
  require Logger

  @type circuit_state :: :closed | :open | :half_open
  @type user_id :: String.t()

  @type circuit_status :: %{
          state: circuit_state(),
          failure_count: non_neg_integer(),
          success_count: non_neg_integer(),
          last_failure_time: DateTime.t() | nil,
          last_state_change: DateTime.t() | nil,
          open_until: DateTime.t() | nil
        }

  # Circuit breaker thresholds (aligned with crypto-exchange defaults)
  @failure_threshold 5
  @reset_timeout :timer.seconds(60)
  @half_open_success_threshold 2

  # Client API

  @doc """
  Start the resilience monitor.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, opts ++ [name: __MODULE__])
  end

  @doc """
  Register a user for circuit breaker monitoring.

  ## Parameters
  - `user_id`: User identifier to monitor

  ## Examples
      iex> ResilienceMonitor.register_user("user_123")
      :ok
  """
  @spec register_user(user_id()) :: :ok
  def register_user(user_id) do
    GenServer.call(__MODULE__, {:register_user, user_id})
  end

  @doc """
  Unregister a user from circuit breaker monitoring.

  ## Parameters
  - `user_id`: User identifier to stop monitoring

  ## Examples
      iex> ResilienceMonitor.unregister_user("user_123")
      :ok
  """
  @spec unregister_user(user_id()) :: :ok
  def unregister_user(user_id) do
    GenServer.call(__MODULE__, {:unregister_user, user_id})
  end

  @doc """
  Record a circuit breaker state change.

  ## Parameters
  - `user_id`: User identifier
  - `new_state`: New circuit breaker state (:closed | :open | :half_open)

  ## Examples
      iex> ResilienceMonitor.record_state_change("user_123", :open)
      :ok
  """
  @spec record_state_change(user_id(), circuit_state()) :: :ok
  def record_state_change(user_id, new_state) do
    GenServer.cast(__MODULE__, {:state_change, user_id, new_state})
  end

  @doc """
  Record a failure in the circuit breaker.

  ## Parameters
  - `user_id`: User identifier
  - `reason`: Failure reason (optional)

  ## Examples
      iex> ResilienceMonitor.record_failure("user_123", :timeout)
      :ok
  """
  @spec record_failure(user_id(), term()) :: :ok
  def record_failure(user_id, reason \\ nil) do
    GenServer.cast(__MODULE__, {:failure, user_id, reason})
  end

  @doc """
  Record a success in the circuit breaker.

  ## Parameters
  - `user_id`: User identifier

  ## Examples
      iex> ResilienceMonitor.record_success("user_123")
      :ok
  """
  @spec record_success(user_id()) :: :ok
  def record_success(user_id) do
    GenServer.cast(__MODULE__, {:success, user_id})
  end

  @doc """
  Get current circuit breaker status for a user.

  ## Parameters
  - `user_id`: User identifier

  ## Returns
  - `{:ok, circuit_status}` if user is registered
  - `{:error, :not_found}` if user not registered

  ## Examples
      iex> ResilienceMonitor.get_status("user_123")
      {:ok, %{state: :closed, failure_count: 0, ...}}
  """
  @spec get_status(user_id()) :: {:ok, circuit_status()} | {:error, :not_found}
  def get_status(user_id) do
    GenServer.call(__MODULE__, {:get_status, user_id})
  end

  @doc """
  Get status for all monitored users.

  ## Returns
  - Map of user_id => circuit_status

  ## Examples
      iex> ResilienceMonitor.get_all_status()
      %{"user_123" => %{state: :closed, ...}, ...}
  """
  @spec get_all_status() :: %{user_id() => circuit_status()}
  def get_all_status do
    GenServer.call(__MODULE__, :get_all_status)
  end

  # Server Callbacks

  @impl true
  def init(:ok) do
    Logger.info("Starting Resilience Monitor")

    {:ok, %{circuits: %{}}}
  end

  @impl true
  def handle_call({:register_user, user_id}, _from, state) do
    Logger.info("Registering user for circuit breaker monitoring", user_id: user_id)

    new_state = put_in(state, [:circuits, user_id], initial_circuit_status())

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:unregister_user, user_id}, _from, state) do
    Logger.info("Unregistering user from circuit breaker monitoring", user_id: user_id)

    {_value, new_circuits} = Map.pop(state.circuits, user_id)
    new_state = %{state | circuits: new_circuits}

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:get_status, user_id}, _from, state) do
    case Map.get(state.circuits, user_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      status ->
        {:reply, {:ok, status}, state}
    end
  end

  @impl true
  def handle_call(:get_all_status, _from, state) do
    {:reply, state.circuits, state}
  end

  @impl true
  def handle_cast({:state_change, user_id, new_state}, state) do
    old_state = get_in(state, [:circuits, user_id, :state])

    Logger.warning("Circuit breaker state changed",
      user_id: user_id,
      old_state: old_state,
      new_state: new_state
    )

    # Update state
    new_circuit_state =
      update_circuit_status(state, user_id, fn status ->
        %{
          status
          | state: new_state,
            last_state_change: DateTime.utc_now(),
            open_until:
              if(new_state == :open,
                do: DateTime.add(DateTime.utc_now(), @reset_timeout, :millisecond),
                else: nil
              )
        }
      end)

    # Log critical alert if circuit opens
    if new_state == :open do
      Logger.error("CRITICAL: Circuit breaker opened for user",
        user_id: user_id,
        failure_count: get_in(new_circuit_state, [:circuits, user_id, :failure_count]),
        open_until: get_in(new_circuit_state, [:circuits, user_id, :open_until])
      )
    end

    # Log info when circuit closes (recovery)
    if new_state == :closed and old_state != :closed do
      Logger.info("Circuit breaker closed (recovered)",
        user_id: user_id,
        success_count: get_in(new_circuit_state, [:circuits, user_id, :success_count])
      )
    end

    {:noreply, new_circuit_state}
  end

  @impl true
  def handle_cast({:failure, user_id, reason}, state) do
    Logger.debug("Circuit breaker failure recorded",
      user_id: user_id,
      reason: inspect(reason)
    )

    new_state =
      update_circuit_status(state, user_id, fn status ->
        new_failure_count = status.failure_count + 1

        updated_status = %{
          status
          | failure_count: new_failure_count,
            last_failure_time: DateTime.utc_now()
        }

        # Check if threshold reached
        if new_failure_count >= @failure_threshold and status.state == :closed do
          Logger.warning("Circuit breaker failure threshold reached",
            user_id: user_id,
            failure_count: new_failure_count,
            threshold: @failure_threshold
          )

          # Trigger state change to open
          send(self(), {:auto_state_change, user_id, :open})
        end

        updated_status
      end)

    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:success, user_id}, state) do
    Logger.debug("Circuit breaker success recorded", user_id: user_id)

    new_state =
      update_circuit_status(state, user_id, fn status ->
        new_success_count = status.success_count + 1

        updated_status = %{
          status
          | success_count: new_success_count,
            # Reset failure count on success
            failure_count: 0
        }

        # Check if recovery threshold reached in half-open state
        if status.state == :half_open and new_success_count >= @half_open_success_threshold do
          Logger.info("Circuit breaker recovery threshold reached",
            user_id: user_id,
            success_count: new_success_count
          )

          # Trigger state change to closed
          send(self(), {:auto_state_change, user_id, :closed})
        end

        updated_status
      end)

    {:noreply, new_state}
  end

  @impl true
  def handle_info({:auto_state_change, user_id, new_state}, state) do
    # Internal state change triggered by threshold conditions
    handle_cast({:state_change, user_id, new_state}, state)
  end

  # Private Functions

  defp initial_circuit_status do
    %{
      state: :closed,
      failure_count: 0,
      success_count: 0,
      last_failure_time: nil,
      last_state_change: nil,
      open_until: nil
    }
  end

  defp update_circuit_status(state, user_id, update_fn) do
    case Map.get(state.circuits, user_id) do
      nil ->
        # User not registered, create initial state
        new_status = update_fn.(initial_circuit_status())
        put_in(state, [:circuits, user_id], new_status)

      status ->
        new_status = update_fn.(status)
        put_in(state, [:circuits, user_id], new_status)
    end
  end
end
