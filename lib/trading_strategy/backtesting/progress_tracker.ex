defmodule TradingStrategy.Backtesting.ProgressTracker do
  @moduledoc """
  GenServer-based progress tracker with ETS for fast concurrent reads.

  Tracks backtest execution progress in memory using ETS table for:
  - Real-time progress monitoring (bars processed / total bars)
  - Accurate percentage calculation
  - Stale record cleanup after 24 hours
  """
  use GenServer
  require Logger

  @table_name :backtest_progress
  @cleanup_interval 60_000  # 1 minute
  @stale_threshold 86_400_000  # 24 hours in milliseconds

  ## Client API

  @doc """
  Starts the ProgressTracker GenServer.
  """
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @doc """
  Initialize tracking for a new backtest session.

  ## Parameters
    - session_id: UUID of the trading session
    - total_bars: Total number of bars to process
  """
  def track(session_id, total_bars) do
    GenServer.cast(__MODULE__, {:track, session_id, total_bars})
  end

  @doc """
  Update progress for an ongoing backtest (fast ETS write).

  ## Parameters
    - session_id: UUID of the trading session
    - bars_processed: Number of bars processed so far
  """
  def update(session_id, bars_processed) do
    now = System.monotonic_time(:millisecond)
    result = :ets.update_element(@table_name, session_id, [
      {2, bars_processed},
      {4, now}
    ])

    if result do
      :ok
    else
      # Handle case where session doesn't exist in ETS
      Logger.warning("Failed to update progress for session #{session_id} - not tracked")
      :ok
    end
  end

  @doc """
  Get current progress for a backtest session.

  Returns `{:ok, progress_map}` or `{:error, :not_found}`
  """
  def get(session_id) do
    case :ets.lookup(@table_name, session_id) do
      [{^session_id, bars_processed, total_bars, updated_at}] ->
        percentage =
          if total_bars > 0 do
            Float.round(bars_processed / total_bars * 100, 2)
          else
            0.0
          end

        {:ok,
         %{
           bars_processed: bars_processed,
           total_bars: total_bars,
           percentage: percentage,
           updated_at: updated_at
         }}

      [] ->
        {:error, :not_found}
    end
  end

  @doc """
  Remove progress tracking for a completed backtest.
  """
  def complete(session_id) do
    :ets.delete(@table_name, session_id)
    :ok
  end

  ## Server Callbacks

  @impl true
  def init(:ok) do
    :ets.new(@table_name, [:set, :public, :named_table, read_concurrency: true])
    schedule_cleanup()
    Logger.info("ProgressTracker started with ETS table #{@table_name}")
    {:ok, %{}}
  end

  @impl true
  def handle_cast({:track, session_id, total_bars}, state) do
    now = System.monotonic_time(:millisecond)
    :ets.insert(@table_name, {session_id, 0, total_bars, now})
    Logger.debug("Tracking progress for session #{session_id} (#{total_bars} bars)")
    {:noreply, state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    now = System.monotonic_time(:millisecond)
    stale_threshold = now - @stale_threshold

    deleted =
      :ets.select_delete(@table_name, [
        {
          {:"$1", :"$2", :"$3", :"$4"},
          [{:<, :"$4", stale_threshold}],
          [true]
        }
      ])

    if deleted > 0 do
      Logger.info("Cleaned up #{deleted} stale progress records")
    end

    schedule_cleanup()
    {:noreply, state}
  end

  ## Private Functions

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval)
  end
end
