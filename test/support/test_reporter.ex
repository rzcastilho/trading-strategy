defmodule TradingStrategy.TestReporter do
  @moduledoc """
  Custom ExUnit formatter for strategy editor synchronization tests.

  Provides console-formatted test results with:
  - Summary statistics (total/passed/failed/skipped)
  - Grouping by user story (US1-US6)
  - Performance metrics (mean/median/P95 latency)
  - Failed test details with file/line/error

  Implements FR-017: Console-only reporting with structured output.

  ## Configuration

  Add to test_helper.exs:

      ExUnit.configure(formatters: [TradingStrategy.TestReporter])

  Or run with:

      mix test --formatter TradingStrategy.TestReporter
  """

  use GenServer

  # ExUnit formatter callbacks
  @behaviour ExUnit.Formatter

  ## Formatter Callbacks

  @impl true
  def init(opts) do
    config = %{
      seed: opts[:seed],
      trace: opts[:trace],
      colors: Keyword.get(opts, :colors, []),
      width: Keyword.get(opts, :width, 80),
      tests_counter: 0,
      failures_counter: 0,
      skipped_counter: 0,
      test_results: [],
      start_time: System.monotonic_time()
    }

    {:ok, config}
  end

  @impl true
  def handle_cast({:suite_started, _opts}, config) do
    IO.puts("\n" <> separator(config.width))
    IO.puts(center_text("Strategy Editor Synchronization Test Suite", config.width))
    IO.puts(separator(config.width))
    IO.puts("")

    {:noreply, config}
  end

  @impl true
  def handle_cast({:suite_finished, _times_us}, config) do
    print_final_report(config)
    {:noreply, config}
  end

  @impl true
  def handle_cast({:test_started, %ExUnit.Test{} = test}, config) do
    if config.trace do
      IO.write("  #{test.name} ")
    end

    {:noreply, config}
  end

  @impl true
  def handle_cast({:test_finished, %ExUnit.Test{state: nil} = test}, config) do
    if config.trace do
      IO.puts(colorize("✓", :green, config.colors))
    else
      IO.write(colorize(".", :green, config.colors))
    end

    new_config =
      config
      |> Map.update!(:tests_counter, &(&1 + 1))
      |> Map.update!(:test_results, &[test | &1])

    {:noreply, new_config}
  end

  @impl true
  def handle_cast({:test_finished, %ExUnit.Test{state: {:failed, _failures}} = test}, config) do
    if config.trace do
      IO.puts(colorize("✗", :red, config.colors))
    else
      IO.write(colorize("F", :red, config.colors))
    end

    new_config =
      config
      |> Map.update!(:tests_counter, &(&1 + 1))
      |> Map.update!(:failures_counter, &(&1 + 1))
      |> Map.update!(:test_results, &[test | &1])

    {:noreply, new_config}
  end

  @impl true
  def handle_cast({:test_finished, %ExUnit.Test{state: {:skipped, _reason}} = test}, config) do
    if config.trace do
      IO.puts(colorize("⊘", :yellow, config.colors))
    else
      IO.write(colorize("*", :yellow, config.colors))
    end

    new_config =
      config
      |> Map.update!(:tests_counter, &(&1 + 1))
      |> Map.update!(:skipped_counter, &(&1 + 1))
      |> Map.update!(:test_results, &[test | &1])

    {:noreply, new_config}
  end

  @impl true
  def handle_cast({:test_finished, %ExUnit.Test{state: {:excluded, _reason}} = test}, config) do
    # Excluded tests are not counted in results
    {:noreply, config}
  end

  @impl true
  def handle_cast(_msg, config) do
    {:noreply, config}
  end

  ## Report Generation

  defp print_final_report(config) do
    IO.puts("\n\n")
    IO.puts(separator(config.width))
    IO.puts(center_text("Test Results Summary", config.width))
    IO.puts(separator(config.width))

    print_summary_stats(config)
    print_results_by_story(config)
    print_performance_metrics(config)
    print_failed_tests(config)

    IO.puts(separator(config.width))
    IO.puts("")
  end

  defp print_summary_stats(config) do
    total = config.tests_counter
    passed = total - config.failures_counter - config.skipped_counter
    failed = config.failures_counter
    skipped = config.skipped_counter

    elapsed_time =
      (System.monotonic_time() - config.start_time)
      |> System.convert_time_unit(:native, :millisecond)
      |> Kernel./(1000)
      |> Float.round(1)

    IO.puts("\nSummary:")
    IO.puts("  Total Tests: #{total}")
    IO.puts("  Passed:      #{passed} (#{percentage(passed, total)}%)")

    if failed > 0 do
      IO.puts(colorize("  Failed:      #{failed} (#{percentage(failed, total)}%)", :red, config.colors))
    else
      IO.puts("  Failed:      #{failed} (#{percentage(failed, total)}%)")
    end

    if skipped > 0 do
      IO.puts(
        colorize("  Skipped:     #{skipped} (#{percentage(skipped, total)}%)", :yellow, config.colors)
      )
    else
      IO.puts("  Skipped:     #{skipped} (#{percentage(skipped, total)}%)")
    end

    IO.puts("  Duration:    #{elapsed_time} seconds")
  end

  defp print_results_by_story(config) do
    IO.puts("\nResults by User Story:")

    results_by_module = group_by_module(config.test_results)

    story_mapping = %{
      "SynchronizationTest" => "[P1] US1: Builder-to-DSL Sync",
      "DslToBuilderSyncTest" => "[P1] US2: DSL-to-Builder Sync",
      "CommentPreservationTest" => "[P2] US3: Comment Preservation",
      "UndoRedoTest" => "[P2] US4: Undo/Redo",
      "PerformanceTest" => "[P3] US5: Performance Validation",
      "ErrorHandlingTest" => "[P3] US6: Error Handling",
      "EdgeCasesTest" => "Edge Cases"
    }

    Enum.each(story_mapping, fn {module_suffix, story_label} ->
      tests = Map.get(results_by_module, module_suffix, [])

      if length(tests) > 0 do
        total = length(tests)
        passed = Enum.count(tests, &(&1.state == nil))
        failed = total - passed

        status_icon = if failed == 0, do: "✓", else: "✗"
        color = if failed == 0, do: :green, else: :red

        IO.puts(
          colorize("  #{story_label} #{String.pad_leading("#{passed}/#{total}", 10)} #{status_icon}", color, config.colors)
        )
      end
    end)
  end

  defp print_performance_metrics(config) do
    # Extract performance metrics from test metadata if available
    # This is a placeholder - actual implementation would parse test tags/metadata

    IO.puts("\nPerformance Metrics:")
    IO.puts("  (Performance metrics available with @tag :benchmark tests)")
    IO.puts("  Run: mix test --only benchmark")
  end

  defp print_failed_tests(config) do
    failed_tests =
      config.test_results
      |> Enum.filter(&match?(%{state: {:failed, _}}, &1))
      |> Enum.reverse()

    if length(failed_tests) > 0 do
      IO.puts("\n" <> colorize("Failed Tests:", :red, config.colors))

      failed_tests
      |> Enum.with_index(1)
      |> Enum.each(fn {test, index} ->
        print_failed_test(test, index, config)
      end)
    end
  end

  defp print_failed_test(test, index, config) do
    IO.puts("\n  #{index}. #{test.name}")
    IO.puts("     File: #{test.tags.file}:#{test.tags.line}")

    case test.state do
      {:failed, failures} ->
        Enum.each(failures, fn failure ->
          IO.puts(colorize("     #{format_failure(failure)}", :red, config.colors))
        end)

      _ ->
        :ok
    end
  end

  defp format_failure({:error, exception, stacktrace}) do
    Exception.format(:error, exception, stacktrace)
  end

  defp format_failure(failure) do
    inspect(failure)
  end

  ## Helpers

  defp group_by_module(test_results) do
    test_results
    |> Enum.group_by(fn test ->
      test.module
      |> Module.split()
      |> List.last()
    end)
  end

  defp percentage(_count, 0), do: 0

  defp percentage(count, total) do
    Float.round(count / total * 100, 1)
  end

  defp separator(width) do
    String.duplicate("=", width)
  end

  defp center_text(text, width) do
    padding = div(width - String.length(text), 2)
    String.duplicate(" ", padding) <> text
  end

  defp colorize(text, color, colors) do
    if colors_enabled?(colors) do
      IO.ANSI.format([color, text, :reset])
    else
      text
    end
  end

  defp colors_enabled?([]), do: false
  defp colors_enabled?(colors), do: Keyword.get(colors, :enabled, true)
end
