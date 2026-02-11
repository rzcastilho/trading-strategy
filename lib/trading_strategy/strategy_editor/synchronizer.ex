defmodule TradingStrategy.StrategyEditor.Synchronizer do
  @moduledoc """
  Bidirectional synchronization between Advanced Strategy Builder and DSL Editor.

  This module handles conversion between:
  - BuilderState (visual form) → DSL text (builder_to_dsl/2)
  - DSL text → BuilderState (dsl_to_builder/1)

  ## Features

  - Comment preservation during transformations (FR-010)
  - Deterministic formatting (FR-016)
  - Validation before conversion
  - Error handling for invalid states

  ## Performance

  - <450ms for 20-indicator strategies (SC-005)
  - Supports 100+ round-trip transformations (SC-009)
  """

  require Logger

  alias TradingStrategy.StrategyEditor.{
    BuilderState,
    CommentPreserver,
    DslParserSimple
  }

  @doc """
  Convert BuilderState to DSL text with comment preservation.

  ## Parameters

  - `builder_state` - The builder form state to convert
  - `comments` - Optional list of preserved comments (default: builder_state._comments)

  ## Returns

  - `{:ok, dsl_text}` - Successfully generated DSL
  - `{:error, reason}` - Validation or generation failed

  ## Examples

      builder_state = %BuilderState{
        name: "My Strategy",
        trading_pair: "BTC/USD",
        timeframe: "1h",
        indicators: [
          %BuilderState.Indicator{
            type: "rsi",
            name: "rsi_14",
            parameters: %{"period" => 14}
          }
        ],
        entry_conditions: "rsi_14 < 30",
        exit_conditions: "rsi_14 > 70",
        position_sizing: %BuilderState.PositionSizing{
          type: "percentage",
          percentage_of_capital: 0.10
        },
        risk_parameters: %BuilderState.RiskParameters{
          max_daily_loss: 0.03,
          max_drawdown: 0.15,
          max_position_size: 0.10
        }
      }

      {:ok, dsl_text} = Synchronizer.builder_to_dsl(builder_state)
  """
  def builder_to_dsl(%BuilderState{} = builder_state, comments \\ []) do
    start_time = System.monotonic_time(:millisecond)
    indicator_count = length(builder_state.indicators || [])
    comment_count = length(comments || builder_state._comments || [])

    Logger.debug("Starting Builder → DSL conversion",
      indicator_count: indicator_count,
      comment_count: comment_count,
      strategy_name: builder_state.name
    )

    result =
      with :ok <- validate_builder_state(builder_state),
           {:ok, dsl_text} <- generate_dsl(builder_state),
           {:ok, formatted_dsl} <-
             apply_comments(dsl_text, comments || builder_state._comments || []) do
        {:ok, formatted_dsl}
      else
        {:error, reason} -> {:error, reason}
      end

    duration_ms = System.monotonic_time(:millisecond) - start_time

    case result do
      {:ok, dsl_text} ->
        Logger.info("Builder → DSL conversion succeeded",
          duration_ms: duration_ms,
          indicator_count: indicator_count,
          comment_count: comment_count,
          dsl_length: String.length(dsl_text),
          strategy_name: builder_state.name
        )

      {:error, reason} ->
        Logger.warning("Builder → DSL conversion failed",
          duration_ms: duration_ms,
          reason: reason,
          indicator_count: indicator_count,
          strategy_name: builder_state.name
        )
    end

    result
  end

  @doc """
  Convert DSL text to BuilderState with comment extraction.

  ## Parameters

  - `dsl_text` - The DSL code to parse
  - `opts` - Options (optional):
    - `:prev_version` - Previous version number to increment from (default: 0)

  ## Returns

  - `{:ok, builder_state}` - Successfully parsed and converted
  - `{:error, reason}` - Parsing or validation failed

  ## Examples

      dsl_text = \"\"\"
      defstrategy MyStrategy do
        @trading_pair "BTC/USD"
        @timeframe "1h"

        indicator :rsi_14, :rsi, period: 14

        entry_conditions do
          rsi_14 < 30
        end

        exit_conditions do
          rsi_14 > 70
        end

        position_sizing do
          percentage_of_capital 0.10
        end

        risk_parameters do
          max_daily_loss 0.03
          max_drawdown 0.15
          max_position_size 0.10
        end
      end
      \"\"\"

      {:ok, builder_state} = Synchronizer.dsl_to_builder(dsl_text)
      # Or with version tracking:
      {:ok, builder_state} = Synchronizer.dsl_to_builder(dsl_text, prev_version: 1)
  """
  def dsl_to_builder(dsl_text, opts \\ []) when is_binary(dsl_text) do
    start_time = System.monotonic_time(:millisecond)
    prev_version = Keyword.get(opts, :prev_version, 0)
    dsl_length = String.length(dsl_text)

    Logger.debug("Starting DSL → Builder conversion",
      dsl_length: dsl_length,
      prev_version: prev_version
    )

    result =
      with :ok <- validate_dsl_syntax(dsl_text),
           {:ok, strategy_map, comments} <- DslParserSimple.parse(dsl_text),
           :ok <- validate_strategy_map(strategy_map),
           :ok <- validate_indicator_references(strategy_map) do
        builder_state = build_state_from_map(strategy_map, comments, prev_version)
        {:ok, builder_state}
      else
        {:error, reason} -> {:error, reason}
      end

    duration_ms = System.monotonic_time(:millisecond) - start_time

    case result do
      {:ok, builder_state} ->
        Logger.info("DSL → Builder conversion succeeded",
          duration_ms: duration_ms,
          dsl_length: dsl_length,
          indicator_count: length(builder_state.indicators || []),
          comment_count: length(builder_state._comments || []),
          strategy_name: builder_state.name,
          version: builder_state._version
        )

      {:error, reason} ->
        Logger.warning("DSL → Builder conversion failed",
          duration_ms: duration_ms,
          dsl_length: dsl_length,
          reason: reason
        )
    end

    result
  end

  def dsl_to_builder(_invalid_input, _opts) do
    Logger.error("DSL → Builder conversion failed: invalid input type")
    {:error, "Invalid input: expected DSL text string"}
  end

  # Private Functions

  defp validate_builder_state(%BuilderState{} = state) do
    errors = []

    errors =
      if is_nil(state.name) or String.trim(state.name) == "" do
        ["name is required" | errors]
      else
        errors
      end

    errors =
      if is_nil(state.trading_pair) do
        ["trading_pair is required" | errors]
      else
        errors
      end

    errors =
      if is_nil(state.timeframe) do
        ["timeframe is required" | errors]
      else
        errors
      end

    if errors == [] do
      :ok
    else
      error_msg = Enum.join(errors, ", ")
      Logger.debug("BuilderState validation failed", errors: errors, strategy_name: state.name)
      {:error, error_msg}
    end
  end

  defp generate_dsl(%BuilderState{} = state) do
    try do
      dsl_parts = [
        generate_header_comment(state),
        generate_strategy_definition(state),
        generate_indicators_section(state),
        generate_conditions_section(state),
        generate_position_sizing_section(state),
        generate_risk_parameters_section(state),
        "end"
      ]

      dsl_text =
        dsl_parts
        |> Enum.reject(&is_nil/1)
        |> Enum.join("\n")

      {:ok, dsl_text}
    rescue
      e ->
        {:error, "DSL generation failed: #{Exception.message(e)}"}
    end
  end

  defp generate_header_comment(%BuilderState{description: description})
       when is_binary(description) do
    "# #{description}\n"
  end

  defp generate_header_comment(_state), do: nil

  defp generate_strategy_definition(%BuilderState{name: name, trading_pair: pair, timeframe: tf}) do
    # Convert name to module case while preserving acronyms
    # e.g., "Simple RSI Strategy" -> "SimpleRSIStrategy"
    module_name =
      name
      |> String.split()
      |> Enum.map(&capitalize_word/1)
      |> Enum.join("")
      |> String.replace(~r/[^A-Za-z0-9]/, "")

    """
    defstrategy #{module_name} do
      @trading_pair "#{pair}"
      @timeframe "#{tf}"
    """
  end

  # Capitalize a word while preserving all-caps acronyms
  defp capitalize_word(word) do
    if String.upcase(word) == word and String.length(word) > 1 do
      # All caps (acronym like RSI, SMA) - keep as is
      word
    else
      # Regular word - capitalize first letter
      String.capitalize(word)
    end
  end

  defp generate_indicators_section(%BuilderState{indicators: indicators})
       when is_list(indicators) and indicators != [] do
    indicator_lines =
      Enum.map(indicators, fn indicator ->
        params = format_indicator_parameters(indicator.parameters)
        "  indicator :#{indicator.name}, :#{indicator.type}#{params}"
      end)

    "\n" <> Enum.join(indicator_lines, "\n")
  end

  defp generate_indicators_section(_state), do: nil

  defp format_indicator_parameters(params) when map_size(params) == 0, do: ""

  defp format_indicator_parameters(params) do
    param_string =
      params
      |> Enum.map(fn {key, value} ->
        "#{key}: #{inspect(value)}"
      end)
      |> Enum.join(", ")

    ", #{param_string}"
  end

  defp generate_conditions_section(%BuilderState{
         entry_conditions: entry,
         exit_conditions: exit,
         stop_conditions: stop
       }) do
    parts = []

    parts =
      if entry do
        [
          """

            entry_conditions do
              #{entry}
            end
          """
          | parts
        ]
      else
        parts
      end

    parts =
      if exit do
        [
          """

            exit_conditions do
              #{exit}
            end
          """
          | parts
        ]
      else
        parts
      end

    parts =
      if stop do
        [
          """

            stop_conditions do
              #{stop}
            end
          """
          | parts
        ]
      else
        parts
      end

    if parts == [] do
      nil
    else
      parts
      |> Enum.reverse()
      |> Enum.join("\n")
    end
  end

  defp generate_position_sizing_section(%BuilderState{position_sizing: nil}), do: nil

  defp generate_position_sizing_section(%BuilderState{position_sizing: ps}) do
    case ps.type do
      "percentage" ->
        """

          position_sizing do
            percentage_of_capital #{ps.percentage_of_capital}
          end
        """

      "fixed" ->
        """

          position_sizing do
            fixed_amount #{ps.fixed_amount}
          end
        """

      _ ->
        nil
    end
  end

  defp generate_risk_parameters_section(%BuilderState{risk_parameters: nil}), do: nil

  defp generate_risk_parameters_section(%BuilderState{risk_parameters: rp}) do
    """

      risk_parameters do
        max_daily_loss #{rp.max_daily_loss}
        max_drawdown #{rp.max_drawdown}
        max_position_size #{rp.max_position_size}
      end
    """
  end

  defp apply_comments(dsl_text, []), do: {:ok, dsl_text}

  defp apply_comments(dsl_text, comments) when is_list(comments) and comments != [] do
    # Insert comments into DSL text at appropriate positions
    lines = String.split(dsl_text, "\n", trim: false)

    # Build a map of line numbers to comments
    comment_map =
      comments
      |> Enum.group_by(& &1.line)
      |> Enum.map(fn {line, comments_at_line} ->
        {line, Enum.map(comments_at_line, & &1.text)}
      end)
      |> Map.new()

    # Insert comments into lines
    enhanced_lines =
      lines
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {line, line_number} ->
        case Map.get(comment_map, line_number) do
          nil ->
            [line]

          line_comments ->
            # Insert comments before this line
            line_comments ++ [line]
        end
      end)

    {:ok, Enum.join(enhanced_lines, "\n")}
  end

  # DSL to Builder conversion helpers

  defp validate_dsl_syntax(dsl_text) do
    # Basic syntax validation
    cond do
      not String.contains?(dsl_text, "defstrategy") ->
        {:error, "Syntax error: missing 'defstrategy' block"}

      not String.contains?(dsl_text, "end") ->
        {:error, "Syntax error: missing 'end' keyword"}

      # Check for balanced blocks (simple check)
      count_do_blocks(dsl_text) != count_end_keywords(dsl_text) ->
        {:error, "Syntax error: unbalanced do/end blocks"}

      true ->
        :ok
    end
  end

  defp count_do_blocks(text) do
    ~r/\bdo\b/
    |> Regex.scan(text)
    |> length()
  end

  defp count_end_keywords(text) do
    ~r/\bend\b/
    |> Regex.scan(text)
    |> length()
  end

  defp validate_strategy_map(strategy_map) do
    errors = []

    errors =
      if is_nil(strategy_map.name) do
        ["Strategy name is required" | errors]
      else
        errors
      end

    if errors == [] do
      :ok
    else
      {:error, Enum.join(errors, ", ")}
    end
  end

  defp validate_indicator_references(strategy_map) do
    defined_indicators =
      strategy_map.indicators
      |> Enum.map(& &1.name)
      |> MapSet.new()

    # Extract indicator references from conditions
    referenced_indicators =
      [
        strategy_map.entry_conditions,
        strategy_map.exit_conditions,
        strategy_map.stop_conditions
      ]
      |> Enum.filter(&(&1 != nil))
      |> Enum.flat_map(&extract_identifiers/1)
      |> MapSet.new()

    # Filter out common non-indicator identifiers
    non_indicators = MapSet.new(["volume", "price", "close", "open", "high", "low"])
    referenced_indicators = MapSet.difference(referenced_indicators, non_indicators)

    undefined = MapSet.difference(referenced_indicators, defined_indicators)

    if MapSet.size(undefined) == 0 do
      :ok
    else
      undefined_list = MapSet.to_list(undefined)

      Logger.warning("Undefined indicator references detected",
        undefined: undefined_list,
        defined: MapSet.to_list(defined_indicators),
        strategy_name: strategy_map.name
      )

      {:error, "Undefined indicators: #{Enum.join(undefined_list, ", ")}"}
    end
  end

  defp extract_identifiers(condition_text) when is_binary(condition_text) do
    ~r/\b[a-z_][a-z0-9_]*\b/
    |> Regex.scan(condition_text)
    |> List.flatten()
    |> Enum.uniq()
  end

  defp extract_identifiers(_), do: []

  defp build_state_from_map(strategy_map, comments, prev_version \\ 0) do
    %BuilderState{
      name: strategy_map.name,
      trading_pair: strategy_map.trading_pair,
      timeframe: strategy_map.timeframe,
      description: strategy_map.description,
      indicators: strategy_map.indicators || [],
      entry_conditions: strategy_map.entry_conditions,
      exit_conditions: strategy_map.exit_conditions,
      stop_conditions: strategy_map.stop_conditions,
      position_sizing: strategy_map.position_sizing,
      risk_parameters: strategy_map.risk_parameters,
      _comments: comments,
      _version: prev_version + 1,
      _last_sync_at: DateTime.utc_now()
    }
  end
end
