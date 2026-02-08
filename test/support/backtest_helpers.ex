defmodule TradingStrategy.BacktestHelpers do
  @moduledoc """
  Helper functions for backtesting tests.
  """

  alias TradingStrategy.Repo
  alias TradingStrategy.Strategies.Strategy
  alias TradingStrategy.Backtesting

  @doc """
  Creates a minimal valid strategy for testing.
  Returns {:ok, strategy}.
  """
  def create_test_strategy(attrs \\ %{}) do
    strategy_id = Ecto.UUID.generate()

    # Minimal valid strategy YAML that meets all required fields
    strategy_content = """
    name: Test Strategy
    trading_pair: BTC/USD
    timeframe: 1h

    indicators: []

    entry_conditions: "close > open"

    exit_conditions: "close < open"

    stop_conditions: "unrealized_pnl_pct < -0.05"

    position_sizing:
      type: percentage
      percentage_of_capital: 0.10

    risk_parameters:
      max_daily_loss: 0.03
      max_position_size: 1.0
      max_drawdown: 0.20
      stop_loss_percentage: 0.05
      take_profit_percentage: 0.10
    """

    strategy_attrs = %{
      id: strategy_id,
      name: Map.get(attrs, :name, "Test Strategy"),
      description: Map.get(attrs, :description, "For testing"),
      version: 1,
      status: "active",
      format: "yaml",
      content: strategy_content,
      trading_pair: Map.get(attrs, :trading_pair, "BTC/USD"),
      timeframe: Map.get(attrs, :timeframe, "1h")
    }

    {:ok, strategy} = %Strategy{}
      |> Strategy.changeset(strategy_attrs)
      |> Repo.insert()

    {:ok, strategy}
  end

  @doc """
  Creates a test backtest session without starting it.
  """
  def create_test_backtest(strategy_id, attrs \\ %{}) do
    config = %{
      strategy_id: strategy_id,
      trading_pair: Map.get(attrs, :trading_pair, "BTC/USD"),
      start_time: Map.get(attrs, :start_time, ~U[2024-01-01 00:00:00Z]),
      end_time: Map.get(attrs, :end_time, ~U[2024-01-02 00:00:00Z]),
      initial_capital: Map.get(attrs, :initial_capital, Decimal.new("10000.00")),
      timeframe: Map.get(attrs, :timeframe, "1h")
    }

    Backtesting.create_backtest(config)
  end

  @doc """
  Mocks the Engine.run_backtest to prevent actual execution.
  Useful for testing concurrency without running real backtests.
  """
  def mock_engine_execution(mode \\ :success) do
    # Import Mox if available, otherwise use a simple approach
    case Code.ensure_loaded(Mox) do
      {:module, Mox} ->
        mock_with_mox(mode)
      {:error, _} ->
        mock_with_process_dict(mode)
    end
  end

  defp mock_with_mox(:success) do
    # This would require setting up Mox in the test environment
    # For now, we'll use a simpler approach
    :ok
  end

  defp mock_with_process_dict(:sleep) do
    # Store in process dictionary that we should sleep instead of running
    Process.put(:mock_backtest_mode, :sleep)
  end

  defp mock_with_process_dict(:fast) do
    # Store in process dictionary that we should return immediately
    Process.put(:mock_backtest_mode, :fast)
  end

  defp mock_with_process_dict(_) do
    Process.delete(:mock_backtest_mode)
  end

  @doc """
  Waits for a backtest to reach a specific status.
  """
  def wait_for_status(session_id, expected_status, timeout \\ 5000) do
    deadline = System.monotonic_time(:millisecond) + timeout

    wait_loop(session_id, expected_status, deadline)
  end

  defp wait_loop(session_id, expected_status, deadline) do
    session = Repo.get(TradingStrategy.Backtesting.TradingSession, session_id)

    cond do
      session.status == expected_status ->
        {:ok, session}

      System.monotonic_time(:millisecond) > deadline ->
        {:error, :timeout, session.status}

      true ->
        Process.sleep(50)
        wait_loop(session_id, expected_status, deadline)
    end
  end

  @doc """
  Creates sample market data for testing.
  """
  def create_sample_market_data(pair, start_time, end_time, timeframe \\ "1h") do
    # Generate simple OHLCV data
    start_unix = DateTime.to_unix(start_time)
    end_unix = DateTime.to_unix(end_time)
    interval_seconds = parse_timeframe_to_seconds(timeframe)

    timestamps = start_unix..end_unix//interval_seconds

    Enum.map(timestamps, fn ts ->
      datetime = DateTime.from_unix!(ts)
      # Generate simple price data
      base_price = 50000.0
      variation = :rand.uniform() * 1000

      %{
        timestamp: datetime,
        open: base_price + variation,
        high: base_price + variation + 100,
        low: base_price + variation - 100,
        close: base_price + variation + 50,
        volume: 100.0 + :rand.uniform() * 50
      }
    end)
  end

  defp parse_timeframe_to_seconds("1m"), do: 60
  defp parse_timeframe_to_seconds("5m"), do: 300
  defp parse_timeframe_to_seconds("15m"), do: 900
  defp parse_timeframe_to_seconds("1h"), do: 3600
  defp parse_timeframe_to_seconds("4h"), do: 14400
  defp parse_timeframe_to_seconds("1d"), do: 86400
  defp parse_timeframe_to_seconds(_), do: 3600
end
