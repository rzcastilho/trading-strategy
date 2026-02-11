defmodule TradingStrategy.StrategyEditor.Validator do
  @moduledoc """
  Validates DSL text for syntax errors, semantic errors, and unsupported features.

  This module provides comprehensive validation for strategy DSL code, including:
  - Syntax validation (brackets, quotes, basic structure)
  - Semantic validation (valid indicators, conditions, parameters)
  - Parser crash handling (FR-005a)
  - Unsupported feature detection (FR-009)

  ## Performance
  - Target: <500ms for strategies with 20 indicators (SC-005)
  - Typical: 100-250ms for validation
  """

  require Logger

  alias TradingStrategy.StrategyEditor.{DslParser, ValidationResult}
  alias ValidationResult.{ValidationError, ValidationWarning}

  @valid_trading_pair_pattern ~r/^[A-Z]{3,10}\/[A-Z]{3,10}$/
  @valid_timeframes ~w(1m 5m 15m 30m 1h 4h 1d 1w 1M)

  @known_indicators ~w(
    rsi sma ema macd bollinger_bands
    atr stochastic adx cci
    roc williams obv
  )

  # Functions considered "unsupported" in the builder (custom Elixir code)
  @unsupported_patterns [
    # Function definitions
    ~r/def\s+\w+/,
    # If expressions
    ~r/if\s+.+\s+do/,
    # Case expressions
    ~r/case\s+.+\s+do/,
    # Cond expressions
    ~r/cond\s+do/,
    # Guard clauses
    ~r/\w+\([^)]*\)\s*when/,
    # Import statements
    ~r/import\s+/,
    # Alias statements
    ~r/alias\s+/,
    # Require statements
    ~r/require\s+/
  ]

  @doc """
  Validate DSL text and return a ValidationResult.

  ## Examples

      iex> Validator.validate("name: Test\\ntrading_pair: BTC/USD")
      %ValidationResult{valid: true, errors: [], ...}

      iex> Validator.validate("invalid syntax {")
      %ValidationResult{valid: false, errors: [...], ...}
  """
  def validate(dsl_text)

  def validate(nil) do
    ValidationResult.failure([
      ValidationError.new(:syntax, "DSL text cannot be nil", line: nil, severity: :error)
    ])
  end

  def validate("") do
    ValidationResult.failure([
      ValidationError.new(:syntax, "DSL text cannot be empty", line: nil, severity: :error)
    ])
  end

  def validate(dsl_text) when is_binary(dsl_text) do
    # Performance tracking (SC-005: target <500ms)
    {time_us, result} =
      :timer.tc(fn ->
        dsl_text
        |> validate_syntax()
        |> validate_semantic()
        |> detect_unsupported_features()
      end)

    time_ms = time_us / 1000

    if time_ms > 500 do
      Logger.warning("Validation exceeded performance target: #{time_ms}ms (target: <500ms)")
    end

    result
  end

  # Step 1: Syntax Validation (T054)
  # Validates basic DSL structure using the parser
  defp validate_syntax(dsl_text) do
    # First try simple YAML-like format validation (for tests and simple DSL)
    case validate_simple_dsl_syntax(dsl_text) do
      {:ok, _} ->
        # Simple syntax is valid, continue to semantic validation
        {:ok, dsl_text, nil, [], []}

      {:simple_error, errors} ->
        # Simple syntax validation found errors
        ValidationResult.failure(errors)

      :not_simple_dsl ->
        # Not simple YAML-like DSL, try full Elixir parser
        case DslParser.parse(dsl_text) do
          {:ok, ast, comments} ->
            # Syntax is valid
            {:ok, dsl_text, ast, comments, []}

          {:error, "Parser crashed: " <> reason} ->
            # Parser crash (FR-005a)
            error =
              ValidationError.new(
                :parser_crash,
                "Parser encountered an unexpected error: #{reason}. Please check your DSL syntax.",
                line: nil,
                severity: :error
              )

            ValidationResult.failure([error])

          {:error, "Syntax error: " <> message} ->
            # Extract line/column info from error message if available
            {line, column} = extract_location_from_error(message)

            error =
              ValidationError.new(
                :syntax,
                message,
                line: line,
                column: column,
                severity: :error
              )

            ValidationResult.failure([error])

          {:error, reason} ->
            error =
              ValidationError.new(
                :syntax,
                "Syntax error: #{reason}",
                line: nil,
                severity: :error
              )

            ValidationResult.failure([error])
        end
    end
  end

  # Validate simple YAML-like DSL format (used in tests)
  defp validate_simple_dsl_syntax(dsl_text) do
    cond do
      # Check if it looks like simple YAML-like DSL
      dsl_text =~ ~r/^[a-z_]+\s*:/ ->
        # Check for multi-line YAML indicators (| or >) which contain complex code
        has_multiline = dsl_text =~ ~r/:\s*\|/ or dsl_text =~ ~r/:\s*>/

        if has_multiline do
          # Has complex multi-line content, treat as valid but will be flagged as unsupported
          {:ok, :simple_dsl_with_multiline}
        else
          errors = check_simple_syntax_errors(dsl_text)

          if Enum.empty?(errors) do
            {:ok, :simple_dsl}
          else
            {:simple_error, errors}
          end
        end

      # Check if it looks like Elixir defstrategy
      dsl_text =~ ~r/defstrategy|defmodule/ ->
        :not_simple_dsl

      true ->
        # Unknown format, let full parser handle it
        :not_simple_dsl
    end
  end

  defp check_simple_syntax_errors(dsl_text) do
    errors = []

    # Check for missing colons in key-value pairs
    lines = String.split(dsl_text, "\n")

    errors =
      lines
      |> Enum.with_index(1)
      |> Enum.reduce(errors, fn {line, line_num}, acc ->
        trimmed = String.trim(line)

        # Check if line looks like it should have a colon but doesn't
        if trimmed != "" and not String.starts_with?(trimmed, "#") and
             not String.contains?(trimmed, ":") and
             not String.starts_with?(trimmed, "-") and
             not String.starts_with?(trimmed, "|") and
             Regex.match?(~r/^[a-z_]+\s+\w/, trimmed) do
          error =
            ValidationError.new(
              :syntax,
              "missing colon in key-value pair",
              line: line_num,
              severity: :error
            )

          [error | acc]
        else
          acc
        end
      end)

    # Check for unbalanced brackets
    errors =
      if count_chars(dsl_text, "(") != count_chars(dsl_text, ")") do
        line = find_unbalanced_line(dsl_text, "(", ")")

        error =
          ValidationError.new(
            :syntax,
            "missing terminator: )",
            line: line,
            severity: :error
          )

        [error | errors]
      else
        errors
      end

    # Check for unclosed quotes
    errors =
      if rem(count_chars(dsl_text, "\""), 2) != 0 do
        line = find_unclosed_quote_line(dsl_text)

        error =
          ValidationError.new(
            :syntax,
            "missing terminator: \"",
            line: line,
            severity: :error
          )

        [error | errors]
      else
        errors
      end

    errors
  end

  defp count_chars(text, char) do
    text
    |> String.graphemes()
    |> Enum.count(&(&1 == char))
  end

  defp find_unbalanced_line(dsl_text, _open, _close) do
    # Find the line with unbalanced brackets
    lines = String.split(dsl_text, "\n")

    lines
    |> Enum.with_index(1)
    |> Enum.find(fn {line, _idx} ->
      count_chars(line, "(") > count_chars(line, ")")
    end)
    |> case do
      {_line, idx} -> idx
      nil -> nil
    end
  end

  defp find_unclosed_quote_line(dsl_text) do
    # Find the line with unclosed quote
    lines = String.split(dsl_text, "\n")

    lines
    |> Enum.with_index(1)
    |> Enum.find(fn {line, _idx} ->
      rem(count_chars(line, "\""), 2) != 0
    end)
    |> case do
      {_line, idx} -> idx
      nil -> nil
    end
  end

  # Step 2: Semantic Validation (T055)
  # Validates indicator types, parameters, trading pairs, etc.
  defp validate_semantic({:ok, dsl_text, ast, comments, _errors}) do
    # Try to parse as structured map for validation
    strategy_map = parse_dsl_to_map(dsl_text)

    semantic_errors =
      []
      |> validate_trading_pair(strategy_map)
      |> validate_timeframe(strategy_map)
      |> validate_indicators(strategy_map)
      |> validate_conditions(strategy_map)

    if Enum.empty?(semantic_errors) do
      {:ok, dsl_text, ast, comments, semantic_errors, strategy_map}
    else
      ValidationResult.failure(semantic_errors)
    end
  end

  defp validate_semantic(%ValidationResult{} = result), do: result

  # Parse DSL text to map (supports both simple YAML-like and Elixir formats)
  defp parse_dsl_to_map(dsl_text) do
    cond do
      dsl_text =~ ~r/^[a-z_]+\s*:/ ->
        parse_simple_dsl_to_map(dsl_text)

      dsl_text =~ ~r/defstrategy|defmodule/ ->
        case DslParser.parse_to_map(dsl_text) do
          {:ok, strategy_map, _comments} -> strategy_map
          {:error, _reason} -> %{}
        end

      true ->
        %{}
    end
  end

  # Parse simple YAML-like DSL to map
  defp parse_simple_dsl_to_map(dsl_text) do
    lines = String.split(dsl_text, "\n")

    strategy_map = %{
      indicators: []
    }

    Enum.reduce(lines, strategy_map, fn line, acc ->
      cond do
        line =~ ~r/^name:\s*(.+)/ ->
          [_, name] = Regex.run(~r/^name:\s*(.+)/, line)
          Map.put(acc, :name, String.trim(name))

        line =~ ~r/^trading_pair:\s*(.+)/ ->
          [_, pair] = Regex.run(~r/^trading_pair:\s*(.+)/, line)
          Map.put(acc, :trading_pair, String.trim(pair))

        line =~ ~r/^timeframe:\s*(.+)/ ->
          [_, timeframe] = Regex.run(~r/^timeframe:\s*(.+)/, line)
          Map.put(acc, :timeframe, String.trim(timeframe))

        line =~ ~r/^\s*-\s*(\w+)\((.+)\)/ ->
          # Parse indicator like: - rsi(period: 14)
          [_, type, params_str] = Regex.run(~r/^\s*-\s*(\w+)\((.+)\)/, line)
          params = parse_indicator_params(params_str)

          indicator = %{
            type: type,
            name: "#{type}_#{params[:period] || "1"}",
            parameters: params
          }

          Map.update(acc, :indicators, [indicator], &(&1 ++ [indicator]))

        line =~ ~r/^entry_conditions:\s*(.+)/ ->
          [_, cond] = Regex.run(~r/^entry_conditions:\s*(.+)/, line)
          Map.put(acc, :entry_conditions, String.trim(cond))

        line =~ ~r/^exit_conditions:\s*(.+)/ ->
          [_, cond] = Regex.run(~r/^exit_conditions:\s*(.+)/, line)
          Map.put(acc, :exit_conditions, String.trim(cond))

        true ->
          acc
      end
    end)
  end

  defp parse_indicator_params(params_str) do
    # Parse "period: 14" or "period: -5", etc.
    params_str
    |> String.split(",")
    |> Enum.reduce(%{}, fn param, acc ->
      case String.split(param, ":", parts: 2) do
        [key, value] ->
          key = String.trim(key) |> String.to_atom()
          value = String.trim(value)

          # Try to parse as integer
          parsed_value =
            case Integer.parse(value) do
              {int, ""} -> int
              _ -> value
            end

          Map.put(acc, key, parsed_value)

        _ ->
          acc
      end
    end)
  end

  # Step 3: Detect Unsupported Features (T052 - FR-009)
  # Identifies DSL features that work but aren't supported by the builder
  defp detect_unsupported_features({:ok, dsl_text, _ast, _comments, _errors, strategy_map}) do
    {unsupported_features, warnings} = scan_for_unsupported_patterns(dsl_text)

    # Check for performance warnings (large number of indicators)
    warnings =
      case Map.get(strategy_map, :indicators, []) do
        indicators when length(indicators) > 50 ->
          warning =
            ValidationWarning.new(
              :performance,
              "Strategy has #{length(indicators)} indicators, which may impact performance. " <>
                "Consider reducing the number of indicators for optimal performance.",
              "Reduce the number of indicators or split into multiple strategies"
            )

          [warning | warnings]

        _ ->
          warnings
      end

    if Enum.empty?(warnings) do
      ValidationResult.success()
    else
      ValidationResult.with_warnings(warnings, unsupported_features)
    end
  end

  defp detect_unsupported_features(%ValidationResult{} = result), do: result

  # Semantic Validation Helpers

  defp validate_trading_pair(errors, %{trading_pair: trading_pair})
       when is_binary(trading_pair) do
    if Regex.match?(@valid_trading_pair_pattern, trading_pair) do
      errors
    else
      error =
        ValidationError.new(
          :semantic,
          "Invalid trading pair format: '#{trading_pair}'. Expected format: XXX/YYY (e.g., BTC/USD)",
          path: ["trading_pair"],
          severity: :error
        )

      [error | errors]
    end
  end

  defp validate_trading_pair(errors, _), do: errors

  defp validate_timeframe(errors, %{timeframe: timeframe}) when is_binary(timeframe) do
    if timeframe in @valid_timeframes do
      errors
    else
      error =
        ValidationError.new(
          :semantic,
          "Invalid timeframe: '#{timeframe}'. Supported: #{Enum.join(@valid_timeframes, ", ")}",
          path: ["timeframe"],
          severity: :error
        )

      [error | errors]
    end
  end

  defp validate_timeframe(errors, _), do: errors

  defp validate_indicators(errors, %{indicators: indicators}) when is_list(indicators) do
    Enum.reduce(indicators, errors, fn indicator, acc ->
      validate_single_indicator(indicator, acc)
    end)
  end

  defp validate_indicators(errors, _), do: errors

  defp validate_single_indicator(%{type: type, parameters: params}, errors) do
    errors
    |> validate_indicator_type(type)
    |> validate_indicator_parameters(type, params)
  end

  defp validate_single_indicator(_, errors), do: errors

  defp validate_indicator_type(errors, type) when is_binary(type) or is_atom(type) do
    type_str = to_string(type)

    if type_str in @known_indicators do
      errors
    else
      error =
        ValidationError.new(
          :semantic,
          "Unknown indicator type: '#{type_str}'. Known indicators: #{Enum.join(@known_indicators, ", ")}",
          path: ["indicators", type_str],
          severity: :error
        )

      [error | errors]
    end
  end

  defp validate_indicator_parameters(errors, _type, %{period: period}) when is_integer(period) do
    if period > 0 and period <= 1000 do
      errors
    else
      error =
        ValidationError.new(
          :semantic,
          "Invalid indicator period: #{period}. Period must be between 1 and 1000",
          path: ["indicators", "period"],
          severity: :error
        )

      [error | errors]
    end
  end

  defp validate_indicator_parameters(errors, _type, _params), do: errors

  defp validate_conditions(errors, strategy_map) do
    errors
    |> validate_condition_field(strategy_map, :entry_conditions, "entry_conditions")
    |> validate_condition_field(strategy_map, :exit_conditions, "exit_conditions")
    |> validate_condition_field(strategy_map, :stop_conditions, "stop_conditions")
  end

  defp validate_condition_field(errors, strategy_map, field, field_name) do
    case Map.get(strategy_map, field) do
      condition when is_binary(condition) ->
        validate_condition_syntax(errors, condition, field_name)

      nil ->
        errors

      _ ->
        errors
    end
  end

  defp validate_condition_syntax(errors, condition, field_name) do
    # Check for incomplete boolean expressions
    if String.ends_with?(String.trim(condition), ["&&", "||", "and", "or"]) do
      error =
        ValidationError.new(
          :semantic,
          "Incomplete boolean expression in #{field_name}",
          path: [field_name],
          severity: :error
        )

      [error | errors]
    else
      errors
    end
  end

  # Unsupported Feature Detection (FR-009)

  defp scan_for_unsupported_patterns(dsl_text) do
    unsupported_features = []
    warnings = []

    {unsupported, warnings} =
      Enum.reduce(@unsupported_patterns, {unsupported_features, warnings}, fn pattern,
                                                                              {features, warns} ->
        if Regex.match?(pattern, dsl_text) do
          feature_name = extract_feature_name(pattern, dsl_text)

          warning =
            ValidationWarning.new(
              :unsupported_feature,
              "The builder does not support custom Elixir code (#{feature_name}). " <>
                "These features work in DSL but cannot be edited in the visual builder.",
              "Edit in DSL mode or simplify your strategy to use only built-in features"
            )

          {[feature_name | features], [warning | warns]}
        else
          {features, warns}
        end
      end)

    # Check for custom function calls (e.g., my_custom_function())
    custom_functions = extract_custom_function_calls(dsl_text)

    {unsupported, warnings} =
      if Enum.empty?(custom_functions) do
        {unsupported, warnings}
      else
        warning =
          ValidationWarning.new(
            :unsupported_feature,
            "Custom functions detected: #{Enum.join(custom_functions, ", ")}. " <>
              "These are not supported by the builder.",
            "Edit in DSL mode to use custom functions"
          )

        {custom_functions ++ unsupported, [warning | warnings]}
      end

    {Enum.uniq(unsupported), warnings}
  end

  defp extract_feature_name(pattern, dsl_text) do
    case Regex.run(pattern, dsl_text, capture: :first) do
      [match | _] -> String.trim(match)
      nil -> "unknown"
    end
  end

  defp extract_custom_function_calls(dsl_text) do
    # Match function calls that are not known built-in functions
    ~r/(\w+)\s*\(/
    |> Regex.scan(dsl_text)
    |> Enum.map(fn [_, fn_name] -> fn_name end)
    |> Enum.reject(fn fn_name ->
      fn_name in ["if", "case", "cond", "def", "defp", "defmodule"] or
        fn_name in @known_indicators
    end)
    |> Enum.map(fn fn_name -> "#{fn_name}/?" end)
    |> Enum.uniq()
  end

  # Error Location Extraction

  defp extract_location_from_error(message) do
    # Try to extract line/column from error messages like "line 5, column 10:"
    case Regex.run(~r/line (\d+)(?:, column (\d+))?/, message) do
      [_, line] -> {String.to_integer(line), nil}
      [_, line, column] -> {String.to_integer(line), String.to_integer(column)}
      nil -> {nil, nil}
    end
  end
end
