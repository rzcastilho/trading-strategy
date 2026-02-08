defmodule TradingStrategy.Backtesting.Supervisor do
  @moduledoc """
  DynamicSupervisor for managing backtest task processes.

  Provides fault isolation for individual backtests and enables supervised
  task execution with proper cleanup on failure.
  """
  use DynamicSupervisor
  require Logger

  @doc """
  Starts the BacktestingSupervisor.
  """
  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Start a supervised backtest task.

  ## Parameters
    - session_id: UUID of the trading session
    - backtest_fn: Function to execute the backtest

  Returns `{:ok, pid}` or `{:error, reason}`
  """
  def start_backtest_task(session_id, backtest_fn) do
    child_spec = %{
      id: {BacktestTask, session_id},
      start: {Task, :start_link, [backtest_fn]},
      restart: :temporary
    }

    case DynamicSupervisor.start_child(__MODULE__, child_spec) do
      {:ok, pid} ->
        Logger.info("Started backtest task for session #{session_id} (pid: #{inspect(pid)})")
        {:ok, pid}

      {:error, reason} = error ->
        Logger.error("Failed to start backtest task for session #{session_id}: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Terminate a running backtest task.
  """
  def terminate_backtest_task(pid) do
    DynamicSupervisor.terminate_child(__MODULE__, pid)
  end

  @doc """
  Get list of currently running backtest tasks.
  """
  def which_children do
    DynamicSupervisor.which_children(__MODULE__)
  end

  @doc """
  Count the number of currently running backtest tasks.
  """
  def count_children do
    DynamicSupervisor.count_children(__MODULE__)
  end
end
