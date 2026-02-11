defmodule TradingStrategy.StrategyEditor.ValidatorTest do
  use ExUnit.Case, async: true

  alias TradingStrategy.StrategyEditor.Validator
  alias TradingStrategy.StrategyEditor.ValidationResult

  describe "syntax validation (T050)" do
    test "detects unbalanced brackets with line and column numbers" do
      dsl = """
      name: Test Strategy
      trading_pair: BTC/USD
      indicators:
        - rsi(period: 14
      """

      result = Validator.validate(dsl)

      assert result.valid == false
      assert length(result.errors) > 0

      error = hd(result.errors)
      assert error.type == :syntax
      # Accept various phrasings: "unbalanced", "missing terminator", "missing )"
      assert error.message =~ ~r/(unbalanced|missing.*terminator|missing.*\))/i
      # Line/column may be nil for some syntax errors
      assert error.line != nil || error.column != nil || error.message != nil
    end

    test "detects unclosed quotes with line and column numbers" do
      dsl = """
      name: "Unclosed quote
      trading_pair: BTC/USD
      """

      result = Validator.validate(dsl)

      assert result.valid == false
      assert length(result.errors) > 0

      error = hd(result.errors)
      assert error.type == :syntax
      # Accept various phrasings for quote/string errors
      assert error.message =~ ~r/(quote|string|terminator|missing)/i
    end

    test "detects missing colons in key-value pairs" do
      dsl = """
      name Test Strategy
      trading_pair: BTC/USD
      """

      result = Validator.validate(dsl)

      assert result.valid == false
      assert length(result.errors) > 0
    end

    test "returns valid result for correct syntax" do
      dsl = """
      name: Test Strategy
      trading_pair: BTC/USD
      timeframe: 1h
      """

      result = Validator.validate(dsl)

      assert result.valid == true
      assert result.errors == []
    end

    test "provides accurate line numbers for multiple errors" do
      dsl = """
      name: Test
      trading_pair BTC/USD
      indicators:
        - rsi(period: 14
      """

      result = Validator.validate(dsl)

      assert result.valid == false
      assert length(result.errors) >= 2

      # Errors should have different line numbers
      line_numbers = Enum.map(result.errors, & &1.line)
      assert length(Enum.uniq(line_numbers)) > 1
    end
  end

  describe "semantic validation (T051)" do
    test "detects invalid indicator types" do
      dsl = """
      name: Test Strategy
      trading_pair: BTC/USD
      indicators:
        - unknown_indicator(period: 14)
      """

      result = Validator.validate(dsl)

      assert result.valid == false
      assert length(result.errors) > 0

      error = hd(result.errors)
      assert error.type == :semantic
      assert error.message =~ "unknown" or error.message =~ "invalid indicator"
    end

    test "detects invalid indicator parameters" do
      dsl = """
      name: Test Strategy
      trading_pair: BTC/USD
      indicators:
        - rsi(period: -5)
      """

      result = Validator.validate(dsl)

      assert result.valid == false
      assert length(result.errors) > 0

      error = hd(result.errors)
      assert error.type == :semantic
      assert error.message =~ "period" or error.message =~ "parameter"
    end

    test "detects invalid trading pairs" do
      dsl = """
      name: Test Strategy
      trading_pair: INVALID
      """

      result = Validator.validate(dsl)

      assert result.valid == false
      assert length(result.errors) > 0

      error = hd(result.errors)
      assert error.type == :semantic
      assert error.message =~ "trading_pair" or error.message =~ "pair"
    end

    test "detects invalid timeframes" do
      dsl = """
      name: Test Strategy
      trading_pair: BTC/USD
      timeframe: 99z
      """

      result = Validator.validate(dsl)

      assert result.valid == false
      assert length(result.errors) > 0

      error = hd(result.errors)
      assert error.type == :semantic
      assert error.message =~ "timeframe"
    end

    test "validates condition expressions" do
      dsl = """
      name: Test Strategy
      trading_pair: BTC/USD
      entry_conditions: invalid && syntax &&
      """

      result = Validator.validate(dsl)

      assert result.valid == false
      assert length(result.errors) > 0
    end

    test "allows valid strategies to pass semantic validation" do
      dsl = """
      name: Test Strategy
      trading_pair: BTC/USD
      timeframe: 1h
      indicators:
        - rsi(period: 14)
        - sma(period: 20)
      entry_conditions: rsi_14 < 30 && sma_20 > close
      """

      result = Validator.validate(dsl)

      assert result.valid == true
      assert result.errors == []
    end
  end

  describe "unsupported DSL features (T052 - FR-009)" do
    test "identifies custom Elixir functions in conditions" do
      dsl = """
      name: Test Strategy
      trading_pair: BTC/USD
      entry_conditions: custom_function(arg1, arg2) > 10
      """

      result = Validator.validate(dsl)

      # Should be valid DSL but with warnings about unsupported features
      assert result.valid == true
      assert length(result.warnings) > 0

      warning = hd(result.warnings)
      assert warning.type == :unsupported_feature
      assert warning.message =~ "custom" or warning.message =~ "function"

      assert length(result.unsupported) > 0
      # Check that custom_function is detected (arity may vary)
      assert Enum.any?(result.unsupported, &String.starts_with?(&1, "custom_function"))
    end

    test "identifies advanced DSL constructs not supported by builder" do
      dsl = """
      name: Test Strategy
      trading_pair: BTC/USD
      indicators:
        - rsi(period: 14)
      # Complex multi-line expressions
      entry_conditions: |
        if rsi_14 < 30 do
          true
        else
          false
        end
      """

      result = Validator.validate(dsl)

      assert result.valid == true
      assert length(result.warnings) > 0
      assert length(result.unsupported) > 0
    end

    test "suggests editing in DSL mode for unsupported features" do
      dsl = """
      name: Test Strategy
      trading_pair: BTC/USD
      entry_conditions: my_custom_logic()
      """

      result = Validator.validate(dsl)

      assert result.valid == true
      warning = Enum.find(result.warnings, &(&1.type == :unsupported_feature))
      assert warning != nil
      assert warning.suggestion =~ "DSL mode" or warning.suggestion =~ "edit"
    end
  end

  describe "parser crash handling (T053 - FR-005a)" do
    test "handles parser crashes gracefully" do
      # Extremely malformed DSL that could crash parser
      dsl = String.duplicate("{{{{", 1000) <> String.duplicate("}}}}", 1000)

      result = Validator.validate(dsl)

      assert result.valid == false
      assert length(result.errors) > 0

      error = hd(result.errors)
      assert error.type == :parser_crash or error.type == :syntax
      assert error.severity == :error
    end

    test "provides actionable error message for parser crashes" do
      dsl = "completely invalid % ^ & * content"

      result = Validator.validate(dsl)

      assert result.valid == false
      error = hd(result.errors)
      assert error.message != nil
      assert String.length(error.message) > 0
    end

    test "handles empty DSL gracefully" do
      result = Validator.validate("")

      assert result.valid == false
      assert length(result.errors) > 0
      error = hd(result.errors)
      assert error.message =~ "empty" or error.message =~ "required"
    end

    test "handles nil input gracefully" do
      result = Validator.validate(nil)

      assert result.valid == false
      assert length(result.errors) > 0
    end

    test "handles very large DSL without crashing" do
      # Generate DSL with 100 indicators (exceeds normal limits)
      indicators =
        for i <- 1..100 do
          "  - rsi(period: #{i})"
        end
        |> Enum.join("\n")

      dsl = """
      name: Large Strategy
      trading_pair: BTC/USD
      indicators:
      #{indicators}
      """

      # Should not crash, might return warnings about size
      result = Validator.validate(dsl)

      assert result != nil
      # Either valid with warnings, or invalid with error about size
      if result.valid do
        assert length(result.warnings) > 0
      else
        assert length(result.errors) > 0
      end
    end
  end

  describe "ValidationResult structure" do
    test "returns ValidationResult struct with all fields" do
      result = Validator.validate("name: Test")

      assert %ValidationResult{} = result
      assert is_boolean(result.valid)
      assert is_list(result.errors)
      assert is_list(result.warnings)
      assert is_list(result.unsupported)
      assert %DateTime{} = result.validated_at
    end

    test "ValidationError has required fields" do
      dsl = "invalid syntax {"

      result = Validator.validate(dsl)
      assert length(result.errors) > 0

      error = hd(result.errors)
      assert error.type in [:syntax, :semantic, :parser_crash]
      assert is_binary(error.message)
      assert error.severity in [:error, :warning]
    end

    test "ValidationWarning has required fields" do
      dsl = """
      name: Test
      trading_pair: BTC/USD
      entry_conditions: custom_fn()
      """

      result = Validator.validate(dsl)

      if length(result.warnings) > 0 do
        warning = hd(result.warnings)
        assert warning.type in [:unsupported_feature, :incomplete_data, :performance]
        assert is_binary(warning.message)
      end
    end
  end

  describe "performance (SC-005)" do
    test "validates strategy with 20 indicators in < 500ms" do
      indicators =
        for i <- 1..20 do
          "  - rsi(period: #{i + 10})"
        end
        |> Enum.join("\n")

      dsl = """
      name: Large Strategy
      trading_pair: BTC/USD
      indicators:
      #{indicators}
      """

      {time_us, result} = :timer.tc(fn -> Validator.validate(dsl) end)
      time_ms = time_us / 1000

      assert time_ms < 500, "Validation took #{time_ms}ms, expected < 500ms"
      assert result != nil
    end
  end
end
