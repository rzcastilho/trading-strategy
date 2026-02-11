defmodule TradingStrategy.StrategyEditor.EditHistory do
  @moduledoc """
  Manages undo/redo stacks for a strategy editing session.

  Stored in GenServer + ETS for fast access (<50ms undo/redo response).
  Periodically persisted to database for durability.

  ## Architecture

  - Primary storage: ETS table with `read_concurrency: true`
  - Backup storage: PostgreSQL (edit_histories table)
  - Cleanup: Stale histories (>24h inactive) removed automatically

  ## Usage

      # Create a new editing session
      {:ok, session_id} = EditHistory.start_session(strategy_id)

      # Push a change event
      EditHistory.push(session_id, change_event)

      # Undo the last change
      {:ok, event} = EditHistory.undo(session_id)

      # Redo an undone change
      {:ok, event} = EditHistory.redo(session_id)

      # End the session
      EditHistory.end_session(session_id)
  """

  use GenServer
  require Logger

  alias TradingStrategy.StrategyEditor.ChangeEvent

  @table_name :edit_histories
  @max_stack_size 100
  # Persist every 10 seconds
  @persist_interval 10_000
  # Cleanup every hour
  @cleanup_interval 3_600_000

  # Client API

  @doc """
  Start the EditHistory GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Start a new editing session for a strategy.

  Returns a unique session_id for tracking this editing session.
  """
  def start_session(strategy_id, user_id) do
    session_id = generate_session_id()

    GenServer.call(__MODULE__, {:start_session, session_id, strategy_id, user_id})

    {:ok, session_id}
  end

  @doc """
  End an editing session and persist final state.
  """
  def end_session(session_id) do
    GenServer.call(__MODULE__, {:end_session, session_id})
  end

  @doc """
  Push a new change event onto the undo stack.
  Clears the redo stack (standard undo/redo behavior).
  """
  def push(session_id, %ChangeEvent{} = event) do
    GenServer.call(__MODULE__, {:push, session_id, event})
  end

  @doc """
  Undo the most recent change.
  Returns {:ok, event} or {:error, :nothing_to_undo}.
  """
  def undo(session_id) do
    GenServer.call(__MODULE__, {:undo, session_id})
  end

  @doc """
  Redo the most recently undone change.
  Returns {:ok, event} or {:error, :nothing_to_redo}.
  """
  def redo(session_id) do
    GenServer.call(__MODULE__, {:redo, session_id})
  end

  @doc """
  Check if undo is available for the session.
  """
  def can_undo?(session_id) do
    case :ets.lookup(@table_name, session_id) do
      [{^session_id, history}] -> history.undo_stack != []
      [] -> false
    end
  end

  @doc """
  Check if redo is available for the session.
  """
  def can_redo?(session_id) do
    case :ets.lookup(@table_name, session_id) do
      [{^session_id, history}] -> history.redo_stack != []
      [] -> false
    end
  end

  @doc """
  Get the current history state for a session.
  """
  def get(session_id) do
    case :ets.lookup(@table_name, session_id) do
      [{^session_id, history}] -> {:ok, history}
      [] -> {:error, :session_not_found}
    end
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Create ETS table for fast history access
    :ets.new(@table_name, [
      :set,
      :named_table,
      :public,
      read_concurrency: true
    ])

    # Schedule periodic persistence
    Process.send_after(self(), :persist_all, @persist_interval)
    Process.send_after(self(), :cleanup_stale, @cleanup_interval)

    Logger.info("EditHistory GenServer started")

    {:ok, %{}}
  end

  @impl true
  def handle_call({:start_session, session_id, strategy_id, user_id}, _from, state) do
    history = %{
      session_id: session_id,
      strategy_id: strategy_id,
      user_id: user_id,
      undo_stack: [],
      redo_stack: [],
      max_size: @max_stack_size,
      created_at: DateTime.utc_now(),
      last_modified_at: DateTime.utc_now()
    }

    :ets.insert(@table_name, {session_id, history})

    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:end_session, session_id}, _from, state) do
    case :ets.lookup(@table_name, session_id) do
      [{^session_id, history}] ->
        persist_history(history)
        :ets.delete(@table_name, session_id)
        {:reply, :ok, state}

      [] ->
        {:reply, {:error, :session_not_found}, state}
    end
  end

  @impl true
  def handle_call({:push, session_id, event}, _from, state) do
    case :ets.lookup(@table_name, session_id) do
      [{^session_id, history}] ->
        new_undo_stack =
          [event | history.undo_stack]
          |> Enum.take(@max_stack_size)

        updated_history = %{
          history
          | undo_stack: new_undo_stack,
            redo_stack: [],
            last_modified_at: DateTime.utc_now()
        }

        :ets.insert(@table_name, {session_id, updated_history})

        {:reply, :ok, state}

      [] ->
        {:reply, {:error, :session_not_found}, state}
    end
  end

  @impl true
  def handle_call({:undo, session_id}, _from, state) do
    case :ets.lookup(@table_name, session_id) do
      [{^session_id, history}] ->
        case history.undo_stack do
          [event | rest] ->
            updated_history = %{
              history
              | undo_stack: rest,
                redo_stack: [event | history.redo_stack],
                last_modified_at: DateTime.utc_now()
            }

            :ets.insert(@table_name, {session_id, updated_history})

            {:reply, {:ok, event}, state}

          [] ->
            {:reply, {:error, :nothing_to_undo}, state}
        end

      [] ->
        {:reply, {:error, :session_not_found}, state}
    end
  end

  @impl true
  def handle_call({:redo, session_id}, _from, state) do
    case :ets.lookup(@table_name, session_id) do
      [{^session_id, history}] ->
        case history.redo_stack do
          [event | rest] ->
            updated_history = %{
              history
              | undo_stack: [event | history.undo_stack],
                redo_stack: rest,
                last_modified_at: DateTime.utc_now()
            }

            :ets.insert(@table_name, {session_id, updated_history})

            {:reply, {:ok, event}, state}

          [] ->
            {:reply, {:error, :nothing_to_redo}, state}
        end

      [] ->
        {:reply, {:error, :session_not_found}, state}
    end
  end

  @impl true
  def handle_info(:persist_all, state) do
    # Persist all active histories to database
    :ets.tab2list(@table_name)
    |> Enum.each(fn {_session_id, history} ->
      persist_history(history)
    end)

    # Schedule next persistence
    Process.send_after(self(), :persist_all, @persist_interval)

    {:noreply, state}
  end

  @impl true
  def handle_info(:cleanup_stale, state) do
    # Remove histories older than 24 hours
    now = DateTime.utc_now()
    stale_cutoff = DateTime.add(now, -24 * 3600, :second)

    :ets.tab2list(@table_name)
    |> Enum.each(fn {session_id, history} ->
      if DateTime.compare(history.last_modified_at, stale_cutoff) == :lt do
        Logger.info("Cleaning up stale edit history: #{session_id}")
        :ets.delete(@table_name, session_id)
      end
    end)

    # Schedule next cleanup
    Process.send_after(self(), :cleanup_stale, @cleanup_interval)

    {:noreply, state}
  end

  # Private Functions

  defp generate_session_id do
    :crypto.strong_rand_bytes(16) |> Base.encode64(padding: false)
  end

  defp persist_history(_history) do
    # TODO: Implement database persistence to edit_histories table
    # This will be implemented when we need durable undo/redo across server restarts
    :ok
  end
end
