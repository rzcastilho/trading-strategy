defmodule TradingStrategy.SyncTestHelpers do
  @moduledoc """
  Performance measurement helpers for synchronization tests.

  Provides utilities for:
  - Measuring operation latency with :timer.tc
  - Calculating statistical metrics (mean, median, P95, P99)
  - Performance validation against targets
  - Test reporting with summary statistics

  ## Usage

      import TradingStrategy.SyncTestHelpers

      test "sync completes within 500ms" do
        {latency_ms, result} = measure_sync(fn ->
          Synchronizer.builder_to_dsl(builder_state)
        end)

        assert latency_ms < 500
        assert {:ok, _dsl} = result
      end

      test "95% of operations meet target" do
        samples = collect_samples(100, fn ->
          Synchronizer.builder_to_dsl(builder_state)
        end)

        stats = calculate_statistics(samples)
        assert stats.p95 < 500
      end
  """

  @doc """
  Measure synchronization operation latency using :timer.tc.

  Returns {latency_in_ms, result} tuple.

  ## Examples

      {latency_ms, {:ok, dsl}} = measure_sync(fn ->
        Synchronizer.builder_to_dsl(builder_state)
      end)

      assert latency_ms < 500
  """
  def measure_sync(operation) when is_function(operation, 0) do
    {time_us, result} = :timer.tc(operation)
    time_ms = time_us / 1000
    {time_ms, result}
  end

  @doc """
  Collect timing samples from repeated operation execution.

  Returns list of latency measurements in milliseconds.

  ## Examples

      samples = collect_samples(100, fn ->
        Synchronizer.builder_to_dsl(builder_state)
      end)

      # samples = [245.3, 267.1, 423.8, ...]
  """
  def collect_samples(count, operation) when is_integer(count) and count > 0 do
    for _ <- 1..count do
      {latency_ms, _result} = measure_sync(operation)
      latency_ms
    end
  end

  @doc """
  Calculate comprehensive statistics from timing samples.

  Returns map with:
  - mean: Average latency
  - median: Middle value
  - p95: 95th percentile (SC-003 target)
  - p99: 99th percentile
  - min: Fastest operation
  - max: Slowest operation
  - std_dev: Standard deviation
  - count: Number of samples

  ## Examples

      samples = [245.3, 267.1, 423.8, ...]
      stats = calculate_statistics(samples)

      assert stats.p95 < 500  # SC-003 validation
  """
  def calculate_statistics(samples) when is_list(samples) and length(samples) > 0 do
    sorted = Enum.sort(samples)
    count = length(samples)

    mean = Enum.sum(samples) / count
    median = percentile(sorted, 0.50)
    p95 = percentile(sorted, 0.95)
    p99 = percentile(sorted, 0.99)

    %{
      mean: Float.round(mean, 2),
      median: Float.round(median, 2),
      p95: Float.round(p95, 2),
      p99: Float.round(p99, 2),
      min: Float.round(Enum.min(samples), 2),
      max: Float.round(Enum.max(samples), 2),
      std_dev: Float.round(standard_deviation(samples, mean), 2),
      count: count
    }
  end

  @doc """
  Calculate percentile value from sorted samples.

  ## Examples

      sorted = Enum.sort(samples)
      p95 = percentile(sorted, 0.95)
  """
  def percentile(sorted_samples, percentile) when percentile >= 0 and percentile <= 1 do
    count = length(sorted_samples)
    index = round(count * percentile) - 1
    index = max(0, min(index, count - 1))
    Enum.at(sorted_samples, index)
  end

  @doc """
  Calculate standard deviation of samples.

  ## Examples

      mean = Enum.sum(samples) / length(samples)
      std_dev = standard_deviation(samples, mean)
  """
  def standard_deviation(samples, mean) do
    variance =
      samples
      |> Enum.map(fn x -> :math.pow(x - mean, 2) end)
      |> Enum.sum()
      |> Kernel./(length(samples))

    :math.sqrt(variance)
  end

  @doc """
  Validate performance against target with pass/fail result.

  Returns %{pass: boolean, actual: float, target: float, percentage: float}

  ## Examples

      stats = calculate_statistics(samples)
      result = validate_performance(stats.p95, 500, "P95 sync latency")

      assert result.pass
  """
  def validate_performance(actual, target, metric_name) do
    pass = actual < target
    percentage = Float.round((actual / target) * 100, 1)

    %{
      pass: pass,
      actual: actual,
      target: target,
      percentage: percentage,
      metric_name: metric_name
    }
  end

  @doc """
  Format statistics for console output.

  Returns formatted string for test reporting (FR-017).

  ## Examples

      stats = calculate_statistics(samples)
      IO.puts(format_statistics(stats, 500, "Sync Latency"))

      # Output:
      # === Sync Latency ===
      # Samples: 100
      # Mean: 312.5ms
      # Median: 289.0ms
      # P95: 432.1ms
      # Max: 498.3ms
      # Target: <500ms
  """
  def format_statistics(stats, target, title) do
    """

    === #{title} ===
    Samples: #{stats.count}
    Mean: #{stats.mean}ms
    Median: #{stats.median}ms
    P95: #{stats.p95}ms
    P99: #{stats.p99}ms
    Max: #{stats.max}ms
    Min: #{stats.min}ms
    Std Dev: #{stats.std_dev}ms
    Target: <#{target}ms
    """
  end

  @doc """
  Count samples over threshold.

  Returns count and percentage of samples exceeding target.

  ## Examples

      over_threshold = count_over_threshold(samples, 500)
      # %{count: 3, total: 100, percentage: 3.0}
  """
  def count_over_threshold(samples, threshold) do
    count = Enum.count(samples, &(&1 > threshold))
    total = length(samples)
    percentage = Float.round((count / total) * 100, 1)

    %{
      count: count,
      total: total,
      percentage: percentage
    }
  end

  @doc """
  Measure event with context for tracking.

  Returns map with latency, result, timestamp, and metadata.

  ## Examples

      event = measure_event(fn ->
        Synchronizer.builder_to_dsl(builder_state)
      end, %{direction: :builder_to_dsl, indicator_count: 20})

      assert event.latency_ms < 500
      assert event.metadata.direction == :builder_to_dsl
  """
  def measure_event(operation, metadata \\ %{}) do
    {latency_ms, result} = measure_sync(operation)

    %{
      latency_ms: latency_ms,
      result: result,
      timestamp: System.monotonic_time(:millisecond),
      success: match?({:ok, _}, result),
      metadata: metadata
    }
  end

  @doc """
  Assert P95 latency is within target.

  Convenience assertion for common test pattern.

  ## Examples

      samples = collect_samples(100, fn -> operation() end)
      assert_p95_within(samples, 500, "Sync latency")
  """
  defmacro assert_p95_within(samples, target, message) do
    quote do
      stats = TradingStrategy.SyncTestHelpers.calculate_statistics(unquote(samples))

      assert stats.p95 < unquote(target),
             "#{unquote(message)}: P95 #{stats.p95}ms exceeds target #{unquote(target)}ms"
    end
  end

  @doc """
  Assert all samples are within target.

  Used for stricter performance requirements (e.g., undo/redo SC-005).

  ## Examples

      samples = collect_samples(100, fn -> undo_operation() end)
      assert_all_within(samples, 50, "Undo latency")
  """
  defmacro assert_all_within(samples, target, message) do
    quote do
      stats = TradingStrategy.SyncTestHelpers.calculate_statistics(unquote(samples))

      assert stats.max < unquote(target),
             "#{unquote(message)}: Max #{stats.max}ms exceeds target #{unquote(target)}ms"
    end
  end
end
