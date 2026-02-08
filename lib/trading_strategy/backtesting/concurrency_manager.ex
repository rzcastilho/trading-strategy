defmodule TradingStrategy.Backtesting.ConcurrencyManager do
  @moduledoc """
  GenServer-based concurrency manager with token-based semaphore.

  Enforces a configurable limit on concurrent backtests and queues excess requests.
  Uses a FIFO queue to ensure fair scheduling of queued backtests.
  """
  use GenServer
  require Logger

  @default_max_concurrent 5

  ## Client API

  @doc """
  Starts the ConcurrencyManager GenServer.

  Options:
    - max_concurrent: Maximum number of concurrent backtests (default: #{@default_max_concurrent})
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Request a slot to run a backtest.

  Returns:
    - `{:ok, :granted}` if slot is available immediately
    - `{:ok, {:queued, position}}` if queued (position in queue)
    - `{:error, :already_running}` if session already has a slot
  """
  def request_slot(session_id) do
    GenServer.call(__MODULE__, {:request_slot, session_id}, :infinity)
  end

  @doc """
  Release a slot after backtest completion or failure.

  Automatically dequeues the next waiting backtest if queue is not empty.
  """
  def release_slot(session_id) do
    GenServer.cast(__MODULE__, {:release_slot, session_id})
  end

  @doc """
  Get current concurrency status (for monitoring).

  Returns a map with:
    - running: MapSet of currently running session IDs
    - queue: Erlang queue of waiting session IDs
    - max_concurrent: Maximum allowed concurrent backtests
  """
  def get_status do
    GenServer.call(__MODULE__, :get_status)
  end

  @doc """
  Get current concurrency status summary (for monitoring).

  Returns a map with:
    - running_count: Number of currently running backtests
    - queue_depth: Number of backtests waiting in queue
    - max_concurrent: Maximum allowed concurrent backtests
  """
  def status do
    GenServer.call(__MODULE__, :status)
  end

  @doc """
  Reset the concurrency manager state (for testing).

  Clears all running sessions and queued sessions.
  """
  def reset do
    GenServer.call(__MODULE__, :reset)
  end

  ## Server Callbacks

  @impl true
  def init(opts) do
    max_concurrent =
      Keyword.get(opts, :max_concurrent) ||
      Application.get_env(:trading_strategy, :max_concurrent_backtests, @default_max_concurrent)

    state = %{
      running: MapSet.new(),
      queue: :queue.new(),
      max_concurrent: max_concurrent,
      waiting: %{}  # Map of session_id -> from_pid for replying when slot available
    }

    Logger.info("ConcurrencyManager started (max concurrent: #{max_concurrent})")
    {:ok, state}
  end

  @impl true
  def handle_call({:request_slot, session_id}, from, state) do
    cond do
      # Already running or queued
      MapSet.member?(state.running, session_id) or Map.has_key?(state.waiting, session_id) ->
        {:reply, {:error, :already_running}, state}

      # Slot available - grant immediately
      MapSet.size(state.running) < state.max_concurrent ->
        new_running = MapSet.put(state.running, session_id)
        Logger.debug("Granted slot to session #{session_id} (#{MapSet.size(new_running)}/#{state.max_concurrent})")
        {:reply, {:ok, :granted}, %{state | running: new_running}}

      # No slots available - add to queue
      true ->
        new_queue = :queue.in(session_id, state.queue)
        new_waiting = Map.put(state.waiting, session_id, from)
        queue_position = :queue.len(new_queue)

        Logger.info("Session #{session_id} queued (position: #{queue_position}, running: #{MapSet.size(state.running)})")

        # Reply immediately with queued status
        {:reply, {:ok, {:queued, queue_position}}, %{state | queue: new_queue, waiting: new_waiting}}
    end
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call(:status, _from, state) do
    status = %{
      running_count: MapSet.size(state.running),
      queue_depth: :queue.len(state.queue),
      max_concurrent: state.max_concurrent
    }

    {:reply, status, state}
  end

  @impl true
  def handle_call(:reset, _from, state) do
    new_state = %{state | running: MapSet.new(), queue: :queue.new(), waiting: %{}}
    Logger.debug("ConcurrencyManager state reset")
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_cast({:release_slot, session_id}, state) do
    # Only release if actually running
    if MapSet.member?(state.running, session_id) do
      new_running = MapSet.delete(state.running, session_id)
      Logger.debug("Released slot for session #{session_id} (#{MapSet.size(new_running)}/#{state.max_concurrent})")

      # Check if there are queued backtests
      case :queue.out(state.queue) do
        {{:value, next_session_id}, new_queue} ->
          # Dequeue next backtest and grant slot
          new_running = MapSet.put(new_running, next_session_id)
          new_waiting = Map.delete(state.waiting, next_session_id)

          Logger.info(
            "Slot released, starting queued session #{next_session_id} (#{MapSet.size(new_running)}/#{state.max_concurrent}, queue: #{:queue.len(new_queue)})"
          )

          # Notify the Backtesting module to start the queued backtest
          # This will be handled by the BacktestingSupervisor
          send(self(), {:start_queued_backtest, next_session_id})

          {:noreply, %{state | running: new_running, queue: new_queue, waiting: new_waiting}}

        {:empty, _} ->
          # No queued backtests
          {:noreply, %{state | running: new_running}}
      end
    else
      # Session not running - no-op
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:start_queued_backtest, session_id}, state) do
    # Trigger the Backtesting module to start the queued backtest
    Logger.debug("Starting queued backtest #{session_id}")

    # Call directly instead of spawning Task to maintain database sandbox permissions in tests
    # Gracefully handle case where Repo is not available (e.g., in unit tests)
    try do
      TradingStrategy.Backtesting.start_queued_backtest(session_id)
    rescue
      RuntimeError ->
        Logger.debug("Repo not available for session #{session_id} (unit test context)")
        :ok
    end

    {:noreply, state}
  end
end
