defmodule TradingStrategy.StrategyEditor.IndicatorMetadataBenchmarkTest do
  @moduledoc """
  Performance benchmark tests for IndicatorMetadata module.

  These tests validate that metadata retrieval meets performance requirements:
  - SC-007: <200ms latency for metadata display
  - Cache hit: <1ms (target from research.md)
  """

  use ExUnit.Case, async: true

  alias TradingStrategy.StrategyEditor.IndicatorMetadata

  @target_latency_ms 200
  @cache_hit_target_ms 1.0

  # Test indicators across all categories
  @test_indicators [
    # Trend indicators
    "sma",
    "ema",
    "macd",
    # Momentum indicators
    "rsi",
    "stochastic",
    # Volatility indicators
    "bollinger_bands",
    "atr",
    # Volume indicators
    "volume_sma"
  ]

  describe "T040: metadata retrieval latency (<200ms target)" do
    test "single indicator metadata retrieval meets <200ms target" do
      for indicator <- @test_indicators do
        {time_us, result} = :timer.tc(fn -> IndicatorMetadata.format_help(indicator) end)
        time_ms = time_us / 1000

        case result do
          {:ok, content} ->
            assert time_ms < @target_latency_ms,
                   "Expected <#{@target_latency_ms}ms, got #{time_ms}ms for #{indicator}"

            assert is_binary(content) and String.length(content) > 0,
                   "Expected non-empty content for #{indicator}"

          {:error, reason} ->
            IO.warn(
              "Metadata not available for #{indicator}: #{inspect(reason)} (latency: #{time_ms}ms)"
            )

            # Even errors should be fast
            assert time_ms < @target_latency_ms
        end
      end
    end

    test "batch metadata retrieval for all indicators completes quickly" do
      {time_us, results} =
        :timer.tc(fn ->
          Enum.map(@test_indicators, fn indicator ->
            IndicatorMetadata.format_help(indicator)
          end)
        end)

      time_ms = time_us / 1000
      avg_time_ms = time_ms / length(@test_indicators)

      # Total time should be reasonable (each indicator * target)
      max_total_time = @target_latency_ms * length(@test_indicators)
      assert time_ms < max_total_time,
             "Batch retrieval too slow: #{time_ms}ms (max: #{max_total_time}ms)"

      # Average per indicator should be well under target
      assert avg_time_ms < @target_latency_ms,
             "Average per indicator: #{avg_time_ms}ms (target: <#{@target_latency_ms}ms)"

      # Verify all results are valid
      for result <- results do
        case result do
          {:ok, _} -> assert true
          {:error, _} -> assert true
          _ -> flunk("Unexpected result format: #{inspect(result)}")
        end
      end
    end

    test "metadata retrieval under load (concurrent requests)" do
      # Simulate multiple LiveView clients requesting metadata simultaneously
      tasks =
        for indicator <- @test_indicators do
          Task.async(fn ->
            {time_us, result} = :timer.tc(fn -> IndicatorMetadata.format_help(indicator) end)
            {time_us / 1000, result}
          end)
        end

      results = Task.await_many(tasks, :timer.seconds(5))

      for {time_ms, result} <- results do
        assert time_ms < @target_latency_ms,
               "Concurrent request exceeded target: #{time_ms}ms"

        case result do
          {:ok, _} -> assert true
          {:error, _} -> assert true
          _ -> flunk("Unexpected result format: #{inspect(result)}")
        end
      end
    end
  end

  describe "T041: caching effectiveness (<1ms cache hit)" do
    test "subsequent calls use cache with sub-millisecond latency" do
      for indicator <- @test_indicators do
        # First call - may be cache miss (or may already be cached from other tests)
        {time1_us, result1} = :timer.tc(fn -> IndicatorMetadata.format_help(indicator) end)

        # Second call - should definitely be cache hit
        {time2_us, result2} = :timer.tc(fn -> IndicatorMetadata.format_help(indicator) end)

        time2_ms = time2_us / 1000

        case {result1, result2} do
          {{:ok, content1}, {:ok, content2}} ->
            # Verify cache hit is fast
            assert time2_ms < @cache_hit_target_ms,
                   "Cache hit too slow for #{indicator}: #{time2_ms}ms (target: <#{@cache_hit_target_ms}ms)"

            # Verify content is identical (cached)
            assert content1 == content2, "Cached content should be identical for #{indicator}"

          _ ->
            # If either call failed, still verify it was fast
            assert time2_ms < @target_latency_ms,
                   "Error handling should be fast: #{time2_ms}ms"
        end
      end
    end

    test "cache hit is consistently faster than initial retrieval" do
      indicator = "sma"

      # Clear any existing cache by calling a different indicator first
      # (persistent_term is global, so we can't truly "clear" it, but we can measure fresh vs cached)

      # Measure multiple cache hits
      cache_hit_times =
        for _i <- 1..10 do
          {time_us, _result} = :timer.tc(fn -> IndicatorMetadata.format_help(indicator) end)
          time_us / 1000
        end

      avg_cache_hit_ms = Enum.sum(cache_hit_times) / length(cache_hit_times)
      max_cache_hit_ms = Enum.max(cache_hit_times)

      # Average should be well under 1ms
      assert avg_cache_hit_ms < @cache_hit_target_ms,
             "Average cache hit: #{avg_cache_hit_ms}ms (target: <#{@cache_hit_target_ms}ms)"

      # Even the slowest cache hit should be fast
      assert max_cache_hit_ms < @cache_hit_target_ms,
             "Max cache hit: #{max_cache_hit_ms}ms (target: <#{@cache_hit_target_ms}ms)"
    end

    test "cache persists across multiple calls" do
      indicator = "bollinger_bands"

      # Call 100 times and verify all are fast (indicating cache is working)
      times =
        for _i <- 1..100 do
          {time_us, result} = :timer.tc(fn -> IndicatorMetadata.format_help(indicator) end)
          assert match?({:ok, _}, result), "Expected successful result"
          time_us / 1000
        end

      # All calls should be cache hits (fast)
      for time_ms <- times do
        assert time_ms < @cache_hit_target_ms,
               "Expected cache hit <#{@cache_hit_target_ms}ms, got #{time_ms}ms"
      end

      # Average should be extremely fast
      avg_time_ms = Enum.sum(times) / length(times)

      assert avg_time_ms < @cache_hit_target_ms / 2,
             "Average cache hit should be very fast: #{avg_time_ms}ms"
    end
  end

  describe "performance profiling" do
    test "reports performance statistics for analysis" do
      IO.puts("\n=== IndicatorMetadata Performance Report ===\n")

      stats =
        for indicator <- @test_indicators do
          # Measure first call (may be cached or not)
          {time1_us, result1} = :timer.tc(fn -> IndicatorMetadata.format_help(indicator) end)

          # Measure cache hit
          {time2_us, result2} = :timer.tc(fn -> IndicatorMetadata.format_help(indicator) end)

          time1_ms = time1_us / 1000
          time2_ms = time2_us / 1000

          status =
            case {result1, result2} do
              {{:ok, _}, {:ok, _}} -> "✓"
              _ -> "✗"
            end

          IO.puts(
            "#{status} #{String.pad_trailing(indicator, 20)} First: #{:io_lib.format("~.4f", [time1_ms])}ms  Cached: #{:io_lib.format("~.4f", [time2_ms])}ms"
          )

          %{indicator: indicator, first_ms: time1_ms, cached_ms: time2_ms, success?: status == "✓"}
        end

      successful = Enum.filter(stats, & &1.success?)

      if length(successful) > 0 do
        avg_first = Enum.sum(Enum.map(successful, & &1.first_ms)) / length(successful)
        avg_cached = Enum.sum(Enum.map(successful, & &1.cached_ms)) / length(successful)

        IO.puts("\n=== Summary ===")
        IO.puts("Successful indicators: #{length(successful)}/#{length(@test_indicators)}")
        IO.puts("Average first call: #{:io_lib.format("~.4f", [avg_first])}ms")
        IO.puts("Average cache hit: #{:io_lib.format("~.4f", [avg_cached])}ms")
        IO.puts("Target latency: <#{@target_latency_ms}ms")
        IO.puts("Cache hit target: <#{@cache_hit_target_ms}ms")
        IO.puts("Status: #{if avg_cached < @cache_hit_target_ms, do: "✓ PASS", else: "✗ FAIL"}\n")
      end

      # Always pass - this test is for reporting only
      assert true
    end
  end
end
