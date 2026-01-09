defmodule TradingStrategy.PaperTrading.SessionSupervisor do
  @moduledoc """
  DynamicSupervisor for managing paper trading session processes.

  Each paper trading session runs as a supervised GenServer process.
  Sessions are registered in the SessionRegistry for easy lookup.

  ## Responsibilities
  - Start new paper trading session processes
  - Supervise running sessions
  - Stop sessions when requested
  - Restart crashed sessions automatically

  ## Usage

  ```elixir
  # Start a new session
  {:ok, pid} = SessionSupervisor.start_session(%{
    session_id: "session_123",
    strategy_id: "...",
    ...
  })

  # Stop a session
  :ok = SessionSupervisor.stop_session("session_123")
  ```
  """

  use DynamicSupervisor
  require Logger

  alias TradingStrategy.PaperTrading.SessionManager

  @registry TradingStrategy.PaperTrading.SessionRegistry

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Starts a new paper trading session under supervision.

  ## Parameters
  - `session_config`: Map with session configuration

  ## Returns
  - `{:ok, pid}` if session started successfully
  - `{:error, reason}` if start failed
  """
  def start_session(session_config) do
    session_id = session_config.session_id

    # Check if session already exists
    case Registry.lookup(@registry, session_id) do
      [{_pid, _}] ->
        {:error, :session_already_exists}

      [] ->
        # Start new session
        child_spec = %{
          id: SessionManager,
          start: {SessionManager, :start_link, [session_config]},
          # Don't automatically restart stopped sessions
          restart: :temporary
        }

        case DynamicSupervisor.start_child(__MODULE__, child_spec) do
          {:ok, pid} = success ->
            Logger.info(
              "[SessionSupervisor] Started session #{session_id} (PID: #{inspect(pid)})"
            )

            success

          {:error, reason} = error ->
            Logger.error(
              "[SessionSupervisor] Failed to start session #{session_id}: #{inspect(reason)}"
            )

            error
        end
    end
  end

  @doc """
  Stops a paper trading session.

  ## Parameters
  - `session_id`: UUID of the session to stop

  ## Returns
  - `:ok` if session stopped successfully
  - `{:error, :not_found}` if session doesn't exist
  """
  def stop_session(session_id) do
    case Registry.lookup(@registry, session_id) do
      [{pid, _}] ->
        DynamicSupervisor.terminate_child(__MODULE__, pid)
        Logger.info("[SessionSupervisor] Stopped session #{session_id}")
        :ok

      [] ->
        {:error, :not_found}
    end
  end

  @doc """
  Lists all running paper trading sessions.

  ## Returns
  - List of `{session_id, pid}` tuples
  """
  def list_sessions do
    DynamicSupervisor.which_children(__MODULE__)
    |> Enum.filter(fn
      {_, pid, :worker, _} when is_pid(pid) -> true
      _ -> false
    end)
    |> Enum.map(fn {_, pid, _, _} ->
      case Registry.keys(@registry, pid) do
        [session_id] -> {session_id, pid}
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Get the number of running sessions.

  ## Returns
  - Integer count of active sessions
  """
  def count_sessions do
    DynamicSupervisor.count_children(__MODULE__).active
  end
end
