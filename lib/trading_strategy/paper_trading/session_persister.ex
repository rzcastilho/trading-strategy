defmodule TradingStrategy.PaperTrading.SessionPersister do
  @moduledoc """
  Persists paper trading session state to database.

  Saves session state periodically (every 60 seconds by default) to support
  session restoration after application restart. Uses the TradingSession schema
  from backtesting.

  Supports crash recovery by maintaining session state in PostgreSQL.
  """

  use GenServer
  require Logger

  alias TradingStrategy.Repo
  alias TradingStrategy.Backtesting.TradingSession
  alias TradingStrategy.PaperTrading.PositionTracker

  import Ecto.Query

  @default_persist_interval 60_000
  @mode "paper"

  # Client API

  @doc """
  Starts the session persister.

  ## Parameters
    - `opts`: Options
      - `:persist_interval` - Milliseconds between persists (default: 60000)
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Creates a new paper trading session record in the database.

  ## Parameters
    - `session_data`: Session configuration
      - `:session_id` - Unique session identifier
      - `:strategy_id` - Strategy UUID
      - `:initial_capital` - Starting capital
      - `:config` - Additional config (trading_pair, data_source, etc.)

  ## Returns
    - `{:ok, session_id}` - Session created
    - `{:error, reason}` - Database error
  """
  def create_session(session_data) do
    GenServer.call(__MODULE__, {:create_session, session_data})
  end

  @doc """
  Updates session state in the database.

  ## Parameters
    - `session_id`: Session UUID
    - `state_data`: Session state to persist
      - `:status` - :active, :paused, :stopped
      - `:current_capital` - Current capital
      - `:position_tracker` - PositionTracker state
      - `:metadata` - Additional metadata (trades_count, last_price, etc.)

  ## Returns
    - `:ok` - State updated
    - `{:error, reason}` - Database error
  """
  def update_session(session_id, state_data) do
    GenServer.call(__MODULE__, {:update_session, session_id, state_data})
  end

  @doc """
  Loads session state from the database.

  ## Parameters
    - `session_id`: Session UUID

  ## Returns
    - `{:ok, session_data}` - Session state loaded
    - `{:error, :not_found}` - Session doesn't exist
    - `{:error, reason}` - Database error
  """
  def load_session(session_id) do
    GenServer.call(__MODULE__, {:load_session, session_id})
  end

  @doc """
  Marks a session as stopped and records final state.

  ## Parameters
    - `session_id`: Session UUID
    - `final_state`: Final session state

  ## Returns
    - `:ok` - Session stopped
    - `{:error, reason}` - Database error
  """
  def stop_session(session_id, final_state) do
    GenServer.call(__MODULE__, {:stop_session, session_id, final_state})
  end

  @doc """
  Lists all active paper trading sessions (for restoration on startup).

  ## Returns
    - `{:ok, [session_data]}` - List of active sessions
  """
  def list_active_sessions do
    GenServer.call(__MODULE__, :list_active_sessions)
  end

  @doc """
  Schedules periodic persistence for a session.

  The persister will automatically save the session state at regular intervals.

  ## Parameters
    - `session_id`: Session UUID
    - `state_provider_fun`: Function that returns current state when called
  """
  def schedule_periodic_persist(session_id, state_provider_fun) do
    GenServer.cast(__MODULE__, {:schedule_persist, session_id, state_provider_fun})
  end

  @doc """
  Cancels periodic persistence for a session.
  """
  def cancel_periodic_persist(session_id) do
    GenServer.cast(__MODULE__, {:cancel_persist, session_id})
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    persist_interval = Keyword.get(opts, :persist_interval, @default_persist_interval)

    state = %{
      persist_interval: persist_interval,
      scheduled_sessions: %{},
      timer_ref: nil
    }

    # Start periodic persist timer
    timer_ref = Process.send_after(self(), :persist_all, persist_interval)

    Logger.info("[SessionPersister] Started with interval=#{persist_interval}ms")

    {:ok, %{state | timer_ref: timer_ref}}
  end

  @impl true
  def handle_call({:create_session, session_data}, _from, state) do
    %{
      session_id: session_id,
      strategy_id: strategy_id,
      initial_capital: initial_capital,
      config: config
    } = session_data

    attrs = %{
      id: session_id,
      strategy_id: strategy_id,
      mode: @mode,
      status: "running",
      initial_capital: Decimal.new(to_string(initial_capital)),
      current_capital: Decimal.new(to_string(initial_capital)),
      started_at: DateTime.utc_now(),
      config: config,
      metadata: %{}
    }

    case %TradingSession{}
         |> TradingSession.changeset(attrs)
         |> Repo.insert() do
      {:ok, _session} ->
        Logger.info("[SessionPersister] Created session #{session_id}")
        {:reply, {:ok, session_id}, state}

      {:error, changeset} ->
        Logger.error("[SessionPersister] Failed to create session: #{inspect(changeset.errors)}")

        {:reply, {:error, :database_error}, state}
    end
  end

  @impl true
  def handle_call({:update_session, session_id, state_data}, _from, state) do
    case Repo.get(TradingSession, session_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      session ->
        status_string = atom_to_status_string(state_data[:status])

        updates = %{
          status: status_string,
          current_capital: Decimal.new(to_string(state_data[:current_capital] || 0)),
          metadata: build_metadata(state_data)
        }

        case session
             |> TradingSession.changeset(updates)
             |> Repo.update() do
          {:ok, _updated} ->
            {:reply, :ok, state}

          {:error, changeset} ->
            Logger.error(
              "[SessionPersister] Failed to update session #{session_id}: #{inspect(changeset.errors)}"
            )

            {:reply, {:error, :database_error}, state}
        end
    end
  end

  @impl true
  def handle_call({:load_session, session_id}, _from, state) do
    case Repo.get(TradingSession, session_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      session ->
        session_data = %{
          session_id: session.id,
          strategy_id: session.strategy_id,
          status: status_string_to_atom(session.status),
          initial_capital: Decimal.to_float(session.initial_capital),
          current_capital: Decimal.to_float(session.current_capital),
          started_at: session.started_at,
          config: session.config,
          metadata: session.metadata
        }

        {:reply, {:ok, session_data}, state}
    end
  end

  @impl true
  def handle_call({:stop_session, session_id, final_state}, _from, state) do
    case Repo.get(TradingSession, session_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      session ->
        updates = %{
          status: "stopped",
          ended_at: DateTime.utc_now(),
          current_capital: Decimal.new(to_string(final_state[:current_capital] || 0)),
          metadata: build_metadata(final_state)
        }

        case session
             |> TradingSession.changeset(updates)
             |> Repo.update() do
          {:ok, _updated} ->
            Logger.info("[SessionPersister] Stopped session #{session_id}")
            # Cancel periodic persistence
            new_state = %{
              state
              | scheduled_sessions: Map.delete(state.scheduled_sessions, session_id)
            }

            {:reply, :ok, new_state}

          {:error, changeset} ->
            Logger.error(
              "[SessionPersister] Failed to stop session #{session_id}: #{inspect(changeset.errors)}"
            )

            {:reply, {:error, :database_error}, state}
        end
    end
  end

  @impl true
  def handle_call(:list_active_sessions, _from, state) do
    query =
      from s in TradingSession,
        where: s.mode == ^@mode and s.status in ["running", "paused"],
        order_by: [desc: s.started_at]

    sessions =
      Repo.all(query)
      |> Enum.map(fn session ->
        %{
          session_id: session.id,
          strategy_id: session.strategy_id,
          status: status_string_to_atom(session.status),
          initial_capital: Decimal.to_float(session.initial_capital),
          current_capital: Decimal.to_float(session.current_capital),
          started_at: session.started_at,
          config: session.config,
          metadata: session.metadata
        }
      end)

    {:reply, {:ok, sessions}, state}
  end

  @impl true
  def handle_cast({:schedule_persist, session_id, state_provider_fun}, state) do
    new_scheduled =
      Map.put(state.scheduled_sessions, session_id, state_provider_fun)

    Logger.debug("[SessionPersister] Scheduled periodic persist for #{session_id}")

    {:noreply, %{state | scheduled_sessions: new_scheduled}}
  end

  @impl true
  def handle_cast({:cancel_persist, session_id}, state) do
    new_scheduled = Map.delete(state.scheduled_sessions, session_id)

    Logger.debug("[SessionPersister] Cancelled periodic persist for #{session_id}")

    {:noreply, %{state | scheduled_sessions: new_scheduled}}
  end

  @impl true
  def handle_info(:persist_all, state) do
    # Persist all scheduled sessions
    Enum.each(state.scheduled_sessions, fn {session_id, state_provider_fun} ->
      try do
        current_state = state_provider_fun.()
        update_session(session_id, current_state)
      rescue
        error ->
          Logger.error(
            "[SessionPersister] Failed to persist session #{session_id}: #{inspect(error)}"
          )
      end
    end)

    # Schedule next persist
    timer_ref = Process.send_after(self(), :persist_all, state.persist_interval)

    {:noreply, %{state | timer_ref: timer_ref}}
  end

  # Private Functions

  defp build_metadata(state_data) do
    base_metadata = %{
      last_updated: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    # Add position tracker data if present
    metadata =
      case state_data[:position_tracker] do
        %PositionTracker{} = tracker ->
          Map.merge(base_metadata, %{
            open_positions_count: map_size(tracker.open_positions),
            total_realized_pnl: tracker.total_realized_pnl,
            total_unrealized_pnl: tracker.total_unrealized_pnl,
            closed_positions_count: length(tracker.closed_positions),
            position_tracker_state: PositionTracker.to_map(tracker)
          })

        _ ->
          base_metadata
      end

    # Add additional metadata fields
    metadata =
      metadata
      |> maybe_put(:trades_count, state_data[:trades_count])
      |> maybe_put(:last_market_price, state_data[:last_market_price])
      |> maybe_put(:last_signal_timestamp, format_timestamp(state_data[:last_signal_timestamp]))

    metadata
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp format_timestamp(nil), do: nil
  defp format_timestamp(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp format_timestamp(other), do: other

  defp atom_to_status_string(:active), do: "running"
  defp atom_to_status_string(:paused), do: "paused"
  defp atom_to_status_string(:stopped), do: "stopped"
  defp atom_to_status_string(:error), do: "error"
  defp atom_to_status_string(other) when is_binary(other), do: other

  defp status_string_to_atom("running"), do: :active
  defp status_string_to_atom("paused"), do: :paused
  defp status_string_to_atom("stopped"), do: :stopped
  defp status_string_to_atom("error"), do: :error
  defp status_string_to_atom(other), do: String.to_existing_atom(other)

  @doc """
  Restores a PositionTracker from persisted metadata.

  ## Parameters
    - `metadata`: Session metadata containing position_tracker_state

  ## Returns
    - `{:ok, position_tracker}` - Restored tracker
    - `{:error, :no_state}` - No persisted state found
  """
  def restore_position_tracker(metadata) when is_map(metadata) do
    case metadata["position_tracker_state"] || metadata[:position_tracker_state] do
      nil ->
        {:error, :no_state}

      tracker_data ->
        tracker = PositionTracker.from_map(tracker_data)
        {:ok, tracker}
    end
  end

  def restore_position_tracker(_), do: {:error, :no_state}
end
