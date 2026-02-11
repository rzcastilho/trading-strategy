defmodule TradingStrategy.StrategyEditor.Telemetry do
  @moduledoc """
  Telemetry instrumentation for strategy editor operations.

  Tracks key metrics for observability and performance monitoring:
  - Synchronization latency (builder ↔ DSL)
  - Parse errors and validation failures
  - Undo/redo usage patterns
  - Editor performance characteristics

  ## Events Emitted

  ### Synchronization Events

  - `[:trading_strategy, :strategy_editor, :sync, :start]`
    - Measurements: `%{system_time: integer()}`
    - Metadata: `%{direction: :builder_to_dsl | :dsl_to_builder, indicator_count: integer(), ...}`

  - `[:trading_strategy, :strategy_editor, :sync, :stop]`
    - Measurements: `%{duration: native_time(), indicator_count: integer()}`
    - Metadata: `%{direction: :builder_to_dsl | :dsl_to_builder, success: boolean(), ...}`

  - `[:trading_strategy, :strategy_editor, :sync, :exception]`
    - Measurements: `%{duration: native_time()}`
    - Metadata: `%{direction: atom(), kind: atom(), reason: term(), stacktrace: list()}`

  ### Parse Events

  - `[:trading_strategy, :strategy_editor, :parse, :error]`
    - Measurements: `%{count: 1}`
    - Metadata: `%{error_type: :syntax | :semantic | :validation, reason: string(), ...}`

  ### Undo/Redo Events

  - `[:trading_strategy, :strategy_editor, :undo_redo, :execute]`
    - Measurements: `%{stack_size: integer()}`
    - Metadata: `%{operation: :undo | :redo, source: :builder | :dsl, session_id: string()}`

  ### Performance Metrics

  - `[:trading_strategy, :strategy_editor, :performance, :benchmark]`
    - Measurements: `%{duration: integer(), memory_bytes: integer()}`
    - Metadata: `%{operation: atom(), indicator_count: integer(), ...}`

  ## Usage

  Attach your custom handler to consume metrics:

      :telemetry.attach(
        "my-handler",
        [:trading_strategy, :strategy_editor, :sync, :stop],
        &MyModule.handle_event/4,
        nil
      )

  Or use the provided convenience function to attach a logger handler:

      TradingStrategy.StrategyEditor.Telemetry.attach_default_handlers()
  """

  require Logger

  @sync_start [:trading_strategy, :strategy_editor, :sync, :start]
  @sync_stop [:trading_strategy, :strategy_editor, :sync, :stop]
  @sync_exception [:trading_strategy, :strategy_editor, :sync, :exception]
  @parse_error [:trading_strategy, :strategy_editor, :parse, :error]
  @undo_redo_execute [:trading_strategy, :strategy_editor, :undo_redo, :execute]
  @performance_benchmark [:trading_strategy, :strategy_editor, :performance, :benchmark]

  @doc """
  Attach default telemetry handlers that log events to Logger.

  Call this function once during application startup to enable automatic
  metric logging.

  ## Example

      # In application.ex start/2
      TradingStrategy.StrategyEditor.Telemetry.attach_default_handlers()
  """
  def attach_default_handlers do
    events = [
      @sync_stop,
      @sync_exception,
      @parse_error,
      @undo_redo_execute,
      @performance_benchmark
    ]

    :telemetry.attach_many(
      "trading-strategy-editor-default-handler",
      events,
      &__MODULE__.handle_event/4,
      nil
    )
  end

  @doc """
  Default event handler that logs metrics using Logger.

  This is attached automatically when `attach_default_handlers/0` is called.
  """
  def handle_event(@sync_stop, measurements, metadata, _config) do
    %{duration: duration} = measurements
    %{direction: direction, success: success} = metadata

    duration_ms = System.convert_time_unit(duration, :native, :millisecond)
    indicator_count = Map.get(metadata, :indicator_count, 0)

    if success do
      Logger.info("Synchronization completed",
        direction: direction,
        duration_ms: duration_ms,
        indicator_count: indicator_count,
        success: true
      )
    else
      Logger.warning("Synchronization failed",
        direction: direction,
        duration_ms: duration_ms,
        indicator_count: indicator_count,
        success: false,
        reason: Map.get(metadata, :error_reason)
      )
    end
  end

  def handle_event(@sync_exception, measurements, metadata, _config) do
    %{duration: duration} = measurements
    %{direction: direction, kind: kind, reason: reason} = metadata

    duration_ms = System.convert_time_unit(duration, :native, :millisecond)

    Logger.error("Synchronization exception",
      direction: direction,
      duration_ms: duration_ms,
      kind: kind,
      reason: inspect(reason)
    )
  end

  def handle_event(@parse_error, _measurements, metadata, _config) do
    %{error_type: error_type, reason: reason} = metadata

    Logger.warning("Parse error",
      error_type: error_type,
      reason: reason,
      strategy_name: Map.get(metadata, :strategy_name)
    )
  end

  def handle_event(@undo_redo_execute, measurements, metadata, _config) do
    %{stack_size: stack_size} = measurements
    %{operation: operation, source: source} = metadata

    Logger.debug("Undo/Redo operation",
      operation: operation,
      source: source,
      stack_size: stack_size,
      session_id: Map.get(metadata, :session_id)
    )
  end

  def handle_event(@performance_benchmark, measurements, metadata, _config) do
    %{duration: duration_ms} = measurements
    %{operation: operation, indicator_count: indicator_count} = metadata

    memory_mb = Map.get(measurements, :memory_bytes, 0) / (1024 * 1024)

    Logger.info("Performance benchmark",
      operation: operation,
      duration_ms: duration_ms,
      indicator_count: indicator_count,
      memory_mb: Float.round(memory_mb, 3)
    )
  end

  def handle_event(_event, _measurements, _metadata, _config) do
    :ok
  end

  # Public API for emitting telemetry events

  @doc """
  Emit a synchronization start event.

  ## Parameters

  - `direction` - `:builder_to_dsl` or `:dsl_to_builder`
  - `metadata` - Additional context (indicator_count, strategy_name, etc.)

  Returns opaque metadata that should be passed to `emit_sync_stop/2`.
  """
  def emit_sync_start(direction, metadata \\ %{}) do
    start_time = System.monotonic_time()
    metadata = Map.merge(metadata, %{direction: direction, start_time: start_time})

    :telemetry.execute(@sync_start, %{system_time: System.system_time()}, metadata)

    metadata
  end

  @doc """
  Emit a synchronization stop event.

  ## Parameters

  - `start_metadata` - Metadata returned from `emit_sync_start/2`
  - `result` - `{:ok, value}` or `{:error, reason}`
  """
  def emit_sync_stop(start_metadata, result) do
    end_time = System.monotonic_time()
    duration = end_time - start_metadata.start_time

    {success, metadata} =
      case result do
        {:ok, _value} ->
          {true, start_metadata}

        {:error, reason} ->
          {false, Map.put(start_metadata, :error_reason, reason)}
      end

    metadata = Map.merge(metadata, %{success: success, end_time: end_time})

    :telemetry.execute(@sync_stop, %{duration: duration}, metadata)
  end

  @doc """
  Emit a synchronization exception event.

  Use this when a synchronization crashes unexpectedly.
  """
  def emit_sync_exception(start_metadata, kind, reason, stacktrace) do
    end_time = System.monotonic_time()
    duration = end_time - start_metadata.start_time

    metadata =
      start_metadata
      |> Map.put(:kind, kind)
      |> Map.put(:reason, reason)
      |> Map.put(:stacktrace, stacktrace)

    :telemetry.execute(@sync_exception, %{duration: duration}, metadata)
  end

  @doc """
  Emit a parse error event.

  ## Parameters

  - `error_type` - `:syntax`, `:semantic`, or `:validation`
  - `reason` - Error message string
  - `metadata` - Additional context (strategy_name, line, column, etc.)
  """
  def emit_parse_error(error_type, reason, metadata \\ %{}) do
    metadata = Map.merge(metadata, %{error_type: error_type, reason: reason})
    :telemetry.execute(@parse_error, %{count: 1}, metadata)
  end

  @doc """
  Emit an undo/redo execution event.

  ## Parameters

  - `operation` - `:undo` or `:redo`
  - `source` - `:builder` or `:dsl`
  - `metadata` - Additional context (session_id, stack_size, etc.)
  """
  def emit_undo_redo(operation, source, metadata \\ %{}) do
    stack_size = Map.get(metadata, :stack_size, 0)

    metadata =
      metadata
      |> Map.put(:operation, operation)
      |> Map.put(:source, source)

    :telemetry.execute(@undo_redo_execute, %{stack_size: stack_size}, metadata)
  end

  @doc """
  Emit a performance benchmark event.

  ## Parameters

  - `operation` - Operation name atom (e.g., `:builder_to_dsl_20_indicators`)
  - `duration_ms` - Duration in milliseconds
  - `metadata` - Additional context (indicator_count, memory_bytes, etc.)
  """
  def emit_performance_benchmark(operation, duration_ms, metadata \\ %{}) do
    measurements = %{
      duration: duration_ms,
      memory_bytes: Map.get(metadata, :memory_bytes, 0)
    }

    metadata = Map.put(metadata, :operation, operation)

    :telemetry.execute(@performance_benchmark, measurements, metadata)
  end
end
