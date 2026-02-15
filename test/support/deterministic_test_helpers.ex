defmodule TradingStrategy.DeterministicTestHelpers do
  @moduledoc """
  Deterministic testing helpers to achieve 0% flakiness (SC-011).

  Provides utilities for:
  - Unique ID generation for test isolation
  - Session cleanup and lifecycle management
  - Async operation waiting (LiveView render_async)
  - Debounce period waiting
  - Database sandbox allowance for GenServers

  ## Design Principles

  1. **Session Isolation**: Each test gets unique IDs to prevent state collisions
  2. **Cleanup Guarantees**: Use on_exit callbacks for reliable cleanup
  3. **No Manual Sleeps**: Use declarative waits (render_async, assert_has)
  4. **Database Isolation**: Ecto Sandbox with GenServer allowance

  ## Usage

      import TradingStrategy.DeterministicTestHelpers

      setup do
        session = setup_test_session()
        on_exit(fn -> cleanup_test_session(session) end)
        {:ok, session: session}
      end

      test "operation", %{session: session} do
        # Test uses unique session.id for isolation
      end
  """

  @doc """
  Generate unique session ID for test isolation.

  Returns a UUID v4 string.

  ## Examples

      session_id = unique_session_id()
      # "550e8400-e29b-41d4-a716-446655440000"
  """
  def unique_session_id do
    Ecto.UUID.generate()
  end

  @doc """
  Generate unique user ID for test isolation.

  Returns a UUID v4 string.

  ## Examples

      user_id = unique_user_id()
      # "7b3d8f9a-2c1e-4d6b-9a8c-5e7f6d8c9b0a"
  """
  def unique_user_id do
    Ecto.UUID.generate()
  end

  @doc """
  Generate unique strategy ID for test isolation.

  Returns a UUID v4 string.

  ## Examples

      strategy_id = unique_strategy_id()
      # "a1b2c3d4-e5f6-4a5b-8c7d-9e0f1a2b3c4d"
  """
  def unique_strategy_id do
    Ecto.UUID.generate()
  end

  @doc """
  Setup test session with unique IDs.

  Returns map with session_id, user_id, strategy_id for test isolation.

  ## Examples

      session = setup_test_session()
      # %{
      #   session_id: "...",
      #   user_id: "...",
      #   strategy_id: "..."
      # }
  """
  def setup_test_session do
    %{
      session_id: unique_session_id(),
      user_id: unique_user_id(),
      strategy_id: unique_strategy_id()
    }
  end

  @doc """
  Cleanup test session.

  Ensures all resources associated with session are released.
  Should be called in on_exit callback.

  ## Examples

      setup do
        session = setup_test_session()
        on_exit(fn -> cleanup_test_session(session) end)
        {:ok, session: session}
      end
  """
  def cleanup_test_session(session) do
    # Cleanup EditHistory session if it exists
    try do
      if Code.ensure_loaded?(TradingStrategy.StrategyEditor.EditHistory) do
        TradingStrategy.StrategyEditor.EditHistory.end_session(session.session_id)
      end
    rescue
      _ -> :ok
    end

    :ok
  end

  @doc """
  Allow GenServer to access test database connection.

  Required when GenServers (like EditHistory) need to query the database
  in tests with Ecto Sandbox mode.

  ## Examples

      setup do
        :ok = Ecto.Adapters.SQL.Sandbox.checkout(TradingStrategy.Repo)

        # Allow EditHistory GenServer to access this test's DB connection
        allow_genserver_db_access(TradingStrategy.StrategyEditor.EditHistory)

        :ok
      end
  """
  def allow_genserver_db_access(genserver_name) do
    if process = Process.whereis(genserver_name) do
      Ecto.Adapters.SQL.Sandbox.allow(
        TradingStrategy.Repo,
        self(),
        process
      )
    end

    :ok
  end

  @doc """
  Wait for debounce period to complete.

  Adds explicit sleep for client-side debounce timers (300ms + buffer).

  ## Examples

      # User types in DSL editor
      view |> element("#dsl-editor") |> render_change(%{"value" => "new DSL"})

      # Wait for debounce period
      wait_for_debounce()

      # Now check synchronized state
      render(view)
  """
  def wait_for_debounce(debounce_ms \\ 300, buffer_ms \\ 50) do
    :timer.sleep(debounce_ms + buffer_ms)
  end

  @doc """
  Wait for LiveView async operations to complete.

  Uses render_async/2 which waits for all assign_async and start_async
  tasks in the LiveView's FIFO message queue.

  ## Examples

      {:ok, view, _html} = live(conn, ~p"/strategies")
      view |> element("#load-data") |> render_click()

      # Wait for async operations
      wait_for_async(view)

      assert render(view) =~ "Data loaded"
  """
  def wait_for_async(view, timeout_ms \\ 5000) do
    Phoenix.LiveViewTest.render_async(view, timeout_ms)
  end

  @doc """
  Create temporary file for test with automatic cleanup.

  Returns path to temporary file that will be deleted on test exit.

  ## Examples

      setup do
        tmp_file = create_temp_file("test_data.exs", "# test data")
        {:ok, tmp_file: tmp_file}
      end
  """
  def create_temp_file(filename, content) do
    tmp_dir = System.tmp_dir!()
    file_path = Path.join(tmp_dir, filename)

    File.write!(file_path, content)

    # Register cleanup
    on_exit_cleanup(fn -> File.rm(file_path) end)

    file_path
  end

  @doc """
  Register cleanup function to run on test exit.

  Wrapper around ExUnit's on_exit for consistency.

  ## Examples

      file_path = "/tmp/test_file.txt"
      File.write!(file_path, "data")
      on_exit_cleanup(fn -> File.rm(file_path) end)
  """
  def on_exit_cleanup(cleanup_fn) when is_function(cleanup_fn, 0) do
    ExUnit.Callbacks.on_exit(cleanup_fn)
  end

  @doc """
  Generate deterministic timestamp for test ordering.

  Returns monotonic time in milliseconds.

  ## Examples

      timestamp = test_timestamp()
      # 123456789
  """
  def test_timestamp do
    System.monotonic_time(:millisecond)
  end

  @doc """
  Create isolated ETS table for test.

  Returns ETS table reference that will be cleaned up on test exit.

  ## Examples

      setup do
        table = create_test_ets_table(:test_data, [:set, :public])
        {:ok, table: table}
      end
  """
  def create_test_ets_table(name, options \\ [:set, :public, :named_table]) do
    # Generate unique name if :named_table is used
    table_name =
      if :named_table in options do
        unique_table_name(name)
      else
        name
      end

    table = :ets.new(table_name, options)

    on_exit_cleanup(fn ->
      if :ets.info(table) != :undefined do
        :ets.delete(table)
      end
    end)

    table
  end

  @doc """
  Generate unique ETS table name for test isolation.

  ## Examples

      name = unique_table_name(:my_table)
      # :my_table_550e8400_e29b_41d4_a716_446655440000
  """
  def unique_table_name(base_name) do
    uuid = unique_session_id() |> String.replace("-", "_")
    String.to_atom("#{base_name}_#{uuid}")
  end

  @doc """
  Wait for condition to be true with polling.

  Polls every poll_interval_ms until condition returns true
  or timeout_ms is exceeded.

  ## Examples

      wait_for(fn -> GenServer.call(MyServer, :ready?) end, 5000, 100)
  """
  def wait_for(condition_fn, timeout_ms \\ 5000, poll_interval_ms \\ 100)
      when is_function(condition_fn, 0) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_wait_for(condition_fn, deadline, poll_interval_ms)
  end

  defp do_wait_for(condition_fn, deadline, poll_interval_ms) do
    cond do
      condition_fn.() ->
        :ok

      System.monotonic_time(:millisecond) > deadline ->
        {:error, :timeout}

      true ->
        :timer.sleep(poll_interval_ms)
        do_wait_for(condition_fn, deadline, poll_interval_ms)
    end
  end

  @doc """
  Assert condition becomes true within timeout.

  Wrapper around wait_for with assertion.

  ## Examples

      assert_eventually(fn ->
        GenServer.call(MyServer, :ready?)
      end, "Server should be ready")
  """
  defmacro assert_eventually(condition, message, timeout_ms \\ 5000) do
    quote do
      case TradingStrategy.DeterministicTestHelpers.wait_for(
             unquote(condition),
             unquote(timeout_ms)
           ) do
        :ok ->
          :ok

        {:error, :timeout} ->
          flunk("#{unquote(message)} (timed out after #{unquote(timeout_ms)}ms)")
      end
    end
  end

  @doc """
  Retry flaky operation with exponential backoff.

  CAUTION: Only use for external dependencies (database, network).
  Do NOT use for test logic - fix root cause instead.

  ## Examples

      # Acceptable: Retry database connection
      {:ok, conn} = retry_with_backoff(fn ->
        Ecto.Adapters.SQL.Sandbox.checkout(Repo)
      end)

      # NOT acceptable: Retry test assertion
      # Fix the test to be deterministic instead!
  """
  def retry_with_backoff(operation, max_attempts \\ 3, base_delay_ms \\ 100)
      when is_function(operation, 0) do
    do_retry(operation, 1, max_attempts, base_delay_ms)
  end

  defp do_retry(operation, attempt, max_attempts, base_delay_ms) do
    case operation.() do
      {:ok, result} ->
        {:ok, result}

      {:error, reason} when attempt < max_attempts ->
        delay = base_delay_ms * :math.pow(2, attempt - 1) |> round()
        :timer.sleep(delay)
        do_retry(operation, attempt + 1, max_attempts, base_delay_ms)

      {:error, reason} ->
        {:error, reason}

      result ->
        result
    end
  end
end
