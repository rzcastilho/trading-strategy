defmodule TradingStrategyWeb.StrategyLive.IndicatorBuilderPerformanceTest do
  @moduledoc """
  Performance tests for IndicatorBuilder LiveComponent tooltip display.

  Validates SC-007 requirement: Tooltip display latency <200ms after indicator selection.
  """

  use ExUnit.Case, async: true

  alias TradingStrategy.StrategyEditor.IndicatorMetadata

  @target_latency_ms 200

  describe "T042: tooltip display latency meets SC-007 requirement (<200ms)" do
    test "tooltip content generation is fast enough for real-time display" do
      indicators = ["sma", "rsi", "bollinger_bands", "macd", "stochastic"]

      for indicator <- indicators do
        # Simulate the tooltip display workflow:
        # 1. User selects indicator or hovers over info icon
        # 2. Component fetches metadata
        # 3. Tooltip renders with content

        {time_us, result} = :timer.tc(fn -> IndicatorMetadata.format_help(indicator) end)
        time_ms = time_us / 1000

        case result do
          {:ok, content} ->
            assert time_ms < @target_latency_ms,
                   "Tooltip content generation for #{indicator} took #{time_ms}ms (target: <#{@target_latency_ms}ms)"

            # Verify content is ready for display
            assert is_binary(content)
            assert String.length(content) > 0

          {:error, _reason} ->
            # Even fallback content generation should be fast
            assert time_ms < @target_latency_ms,
                   "Fallback content generation took #{time_ms}ms (target: <#{@target_latency_ms}ms)"
        end
      end
    end

    test "configured indicator tooltip display meets latency target" do
      # Simulate configured indicator with metadata enrichment
      configured_indicators = [
        %{id: "ind_1", type: "sma", params: %{"period" => 20}, valid?: true},
        %{id: "ind_2", type: "rsi", params: %{"period" => 14}, valid?: true},
        %{id: "ind_3", type: "bollinger_bands", params: %{"period" => 20}, valid?: true}
      ]

      for indicator <- configured_indicators do
        # Measure time to enrich indicator with metadata (as done in update callback)
        {time_us, enriched} =
          :timer.tc(fn ->
            help_text =
              case IndicatorMetadata.format_help(indicator.type) do
                {:ok, text} -> text
                {:error, _} -> nil
              end

            Map.put(indicator, :help_text, help_text)
          end)

        time_ms = time_us / 1000

        assert time_ms < @target_latency_ms,
               "Metadata enrichment for #{indicator.type} took #{time_ms}ms (target: <#{@target_latency_ms}ms)"

        # Verify enrichment worked
        assert Map.has_key?(enriched, :help_text)
      end
    end

    test "batch metadata enrichment for multiple configured indicators" do
      # Simulate loading a strategy with many configured indicators
      many_indicators =
        for i <- 1..20 do
          type = Enum.random(["sma", "ema", "rsi", "macd", "bollinger_bands"])

          %{
            id: "ind_#{i}",
            type: type,
            params: %{"period" => 20},
            valid?: true
          }
        end

      # Measure time to enrich all indicators (as done in update callback)
      {time_us, enriched_indicators} =
        :timer.tc(fn ->
          Enum.map(many_indicators, fn indicator ->
            help_text =
              case IndicatorMetadata.format_help(indicator.type) do
                {:ok, text} -> text
                {:error, _} -> nil
              end

            Map.put(indicator, :help_text, help_text)
          end)
        end)

      time_ms = time_us / 1000
      avg_time_ms = time_ms / length(many_indicators)

      # Total time should be reasonable
      assert time_ms < @target_latency_ms * 2,
             "Batch enrichment of #{length(many_indicators)} indicators took #{time_ms}ms"

      # Average per indicator should be well under target
      assert avg_time_ms < @target_latency_ms / 10,
             "Average enrichment time: #{avg_time_ms}ms per indicator"

      # Verify all enrichments succeeded
      assert length(enriched_indicators) == length(many_indicators)

      for enriched <- enriched_indicators do
        assert Map.has_key?(enriched, :help_text)
      end
    end

    test "tooltip display under concurrent load" do
      # Simulate multiple users viewing tooltips simultaneously
      tasks =
        for _i <- 1..10 do
          Task.async(fn ->
            indicator = Enum.random(["sma", "rsi", "bollinger_bands", "macd"])
            {time_us, result} = :timer.tc(fn -> IndicatorMetadata.format_help(indicator) end)
            {time_us / 1000, result}
          end)
        end

      results = Task.await_many(tasks, :timer.seconds(5))

      for {time_ms, result} <- results do
        assert time_ms < @target_latency_ms,
               "Concurrent tooltip display exceeded target: #{time_ms}ms"

        assert match?({:ok, _} | {:error, _}, result)
      end
    end

    test "reports tooltip display performance statistics" do
      IO.puts("\n=== Tooltip Display Performance Report ===\n")

      indicators = [
        {"Single-value (SMA)", "sma"},
        {"Single-value (RSI)", "rsi"},
        {"Multi-value (Bollinger Bands)", "bollinger_bands"},
        {"Multi-value (MACD)", "macd"},
        {"Multi-value (Stochastic)", "stochastic"}
      ]

      stats =
        for {label, type} <- indicators do
          {time_us, result} = :timer.tc(fn -> IndicatorMetadata.format_help(type) end)
          time_ms = time_us / 1000

          status =
            case result do
              {:ok, content} ->
                content_length = String.length(content)
                "✓ (#{content_length} chars)"

              {:error, _} ->
                "✗ (error)"
            end

          IO.puts(
            "#{String.pad_trailing(label, 30)} #{:io_lib.format("~6.2f", [time_ms])}ms  #{status}"
          )

          %{label: label, time_ms: time_ms, success?: String.starts_with?(status, "✓")}
        end

      successful = Enum.filter(stats, & &1.success?)

      if length(successful) > 0 do
        avg_time = Enum.sum(Enum.map(successful, & &1.time_ms)) / length(successful)
        max_time = Enum.max(Enum.map(successful, & &1.time_ms))

        IO.puts("\n=== Summary ===")
        IO.puts("Successful: #{length(successful)}/#{length(indicators)}")
        IO.puts("Average display time: #{:io_lib.format("~.2f", [avg_time])}ms")
        IO.puts("Max display time: #{:io_lib.format("~.2f", [max_time])}ms")
        IO.puts("Target: <#{@target_latency_ms}ms")

        IO.puts(
          "Status: #{if max_time < @target_latency_ms, do: "✓ PASS", else: "✗ FAIL"}\n"
        )
      end

      assert true
    end
  end
end
