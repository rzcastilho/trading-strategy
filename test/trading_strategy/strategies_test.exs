defmodule TradingStrategy.StrategiesTest do
  use TradingStrategy.DataCase, async: true

  import TradingStrategy.StrategiesFixtures
  import TradingStrategy.AccountsFixtures

  alias TradingStrategy.Strategies

  describe "test_strategy_syntax/2" do
    test "T068: successfully parses and validates valid YAML strategy" do
      valid_yaml = """
      name: Test Strategy
      trading_pair: BTC/USD
      timeframe: 1h
      indicators:
        - type: sma
          name: sma_20
          parameters:
            period: 20
        - type: rsi
          name: rsi_14
          parameters:
            period: 14
      entry_conditions: rsi_14 < 30
      exit_conditions: rsi_14 > 70
      stop_conditions: rsi_14 < 25
      position_sizing:
        type: percentage
        percentage_of_capital: 0.10
      risk_parameters:
        max_daily_loss: 0.03
        max_drawdown: 0.15
      """

      assert {:ok, result} = Strategies.test_strategy_syntax(valid_yaml, :yaml)

      # Should return parsed strategy details
      assert is_map(result)
      assert Map.has_key?(result, :parsed)
      assert Map.has_key?(result, :summary)

      # Verify summary structure
      assert result.summary.name == "Test Strategy"
      assert result.summary.trading_pair == "BTC/USD"
      assert result.summary.indicator_count == 2
    end

    test "T068: returns error for invalid YAML syntax" do
      invalid_yaml = "invalid: [yaml: {structure: [[["

      assert {:error, errors} = Strategies.test_strategy_syntax(invalid_yaml, :yaml)
      assert is_list(errors) or is_binary(errors)
    end

    test "T068: returns error for missing required DSL fields" do
      incomplete_yaml = """
      name: Incomplete Strategy
      trading_pair: BTC/USD
      timeframe: 1h
      indicators:
        - type: sma
          name: sma_20
          parameters:
            period: 20
      """

      result = Strategies.test_strategy_syntax(incomplete_yaml, :yaml)

      # Should fail validation due to missing required fields
      assert {:error, errors} = result
      assert is_list(errors)
      assert length(errors) > 0
    end

    test "T068: successfully parses valid TOML strategy" do
      valid_toml = """
      name = "TOML Test Strategy"
      trading_pair = "BTC/USD"
      timeframe = "1h"
      entry_conditions = "rsi_14 < 30"
      exit_conditions = "rsi_14 > 70"
      stop_conditions = "rsi_14 < 25"

      [[indicators]]
      type = "sma"
      name = "sma_20"

      [indicators.parameters]
      period = 20

      [[indicators]]
      type = "rsi"
      name = "rsi_14"

      [indicators.parameters]
      period = 14

      [position_sizing]
      type = "percentage"
      percentage_of_capital = 0.10

      [risk_parameters]
      max_daily_loss = 0.03
      max_drawdown = 0.15
      """

      assert {:ok, result} = Strategies.test_strategy_syntax(valid_toml, :toml)
      assert is_map(result)
      assert Map.has_key?(result, :parsed)
      assert Map.has_key?(result, :summary)
    end

    test "T068: returns error for invalid format" do
      valid_yaml = """
      name: Test Strategy
      trading_pair: BTC/USD
      timeframe: 1h
      indicators:
        - type: sma
          name: sma_20
          parameters: {period: 20}
      entry_conditions: close > sma_20
      exit_conditions: close < sma_20
      stop_conditions: close < sma_20
      position_sizing:
        type: fixed
        quantity: 1
      risk_parameters:
        max_daily_loss: 0.03
      """

      # Should handle invalid format gracefully
      result = Strategies.test_strategy_syntax(valid_yaml, :invalid_format)
      assert {:error, error} = result
      assert is_binary(error)
      assert error =~ "Unsupported format"
    end

    test "T068: syntax test completes quickly for complex strategies" do
      # Create a strategy with many indicators
      complex_yaml = """
      name: Complex Strategy
      trading_pair: BTC/USD
      timeframe: 1h
      indicators:
        - type: sma
          name: sma_20
          parameters: {period: 20}
        - type: sma
          name: sma_50
          parameters: {period: 50}
        - type: sma
          name: sma_200
          parameters: {period: 200}
        - type: ema
          name: ema_12
          parameters: {period: 12}
        - type: ema
          name: ema_26
          parameters: {period: 26}
        - type: rsi
          name: rsi_14
          parameters: {period: 14}
        - type: macd
          name: macd
          parameters: {fast: 12, slow: 26, signal: 9}
        - type: bollinger
          name: bollinger
          parameters: {period: 20, std_dev: 2}
        - type: atr
          name: atr
          parameters: {period: 14}
        - type: stochastic
          name: stochastic
          parameters: {k_period: 14, d_period: 3}
      entry_conditions: rsi_14 < 30 and close > sma_20 and sma_20 > sma_50
      exit_conditions: rsi_14 > 70 or close < sma_20
      stop_conditions: rsi_14 < 25
      position_sizing:
        type: percentage
        percentage_of_capital: 0.10
      risk_parameters:
        max_daily_loss: 0.03
        max_drawdown: 0.15
      """

      start_time = System.monotonic_time(:millisecond)
      _result = Strategies.test_strategy_syntax(complex_yaml, :yaml)
      end_time = System.monotonic_time(:millisecond)

      elapsed = end_time - start_time

      # Should complete in reasonable time (< 1 second for unit test)
      assert elapsed < 1000, "Syntax test took #{elapsed}ms"
    end
  end

  describe "duplicate_strategy/2" do
    setup do
      user = user_fixture()
      {:ok, user: user}
    end

    test "T078: successfully duplicates a strategy with ' - Copy' suffix", %{user: user} do
      original = strategy_fixture(
        user: user,
        name: "Original Strategy",
        description: "Original description",
        trading_pair: "BTC/USD",
        timeframe: "1h",
        status: "draft"
      )

      assert {:ok, duplicate} = Strategies.duplicate_strategy(original, user)

      # Verify duplicate has correct name
      assert duplicate.name == "Original Strategy - Copy"

      # Verify all fields copied except name
      assert duplicate.description == original.description
      assert duplicate.trading_pair == original.trading_pair
      assert duplicate.timeframe == original.timeframe
      assert duplicate.format == original.format
      assert duplicate.content == original.content

      # Verify new strategy has its own identity
      assert duplicate.id != original.id
      assert duplicate.version == 1
      # lock_version is managed by Ecto, just verify it's set
      assert is_integer(duplicate.lock_version)

      # Duplicate should always be in draft status
      assert duplicate.status == "draft"

      # Verify it belongs to the same user
      assert duplicate.user_id == user.id
    end

    test "T078: duplicates active strategy as draft", %{user: user} do
      active_strategy = strategy_fixture(
        user: user,
        name: "Active Strategy",
        status: "active"
      )

      assert {:ok, duplicate} = Strategies.duplicate_strategy(active_strategy, user)

      # Even if original is active, duplicate should be draft
      assert active_strategy.status == "active"
      assert duplicate.status == "draft"
    end

    test "T078: creates unique name when ' - Copy' already exists", %{user: user} do
      original = strategy_fixture(user: user, name: "Original Strategy")

      # Create first copy
      {:ok, first_copy} = Strategies.duplicate_strategy(original, user)
      assert first_copy.name == "Original Strategy - Copy"

      # Create second copy
      {:ok, second_copy} = Strategies.duplicate_strategy(original, user)
      assert second_copy.name == "Original Strategy - Copy 2"

      # Create third copy
      {:ok, third_copy} = Strategies.duplicate_strategy(original, user)
      assert third_copy.name == "Original Strategy - Copy 3"
    end

    test "T078: handles strategy with long name that approaches limit", %{user: user} do
      # Create strategy with name close to max length (200 chars)
      long_name = String.duplicate("A", 180)
      original = strategy_fixture(user: user, name: long_name)

      assert {:ok, duplicate} = Strategies.duplicate_strategy(original, user)

      # Should truncate if necessary to fit " - Copy"
      assert String.length(duplicate.name) <= 200
      assert duplicate.name =~ "- Copy"
    end

    test "T078: preserves metadata from original", %{user: user} do
      metadata = %{
        "custom_field" => "custom_value",
        "last_validation_at" => "2026-02-08T10:30:00Z"
      }

      original = strategy_fixture(
        user: user,
        name: "Strategy with Metadata",
        metadata: metadata
      )

      assert {:ok, duplicate} = Strategies.duplicate_strategy(original, user)

      # Metadata should be copied
      assert duplicate.metadata == metadata
    end

    test "T078: duplicate is independent from original", %{user: user} do
      original = strategy_fixture(
        user: user,
        name: "Original Strategy",
        description: "Original description"
      )

      {:ok, duplicate} = Strategies.duplicate_strategy(original, user)

      # Modify the duplicate
      {:ok, updated_duplicate} = Strategies.update_strategy(duplicate, %{
        description: "Modified description"
      }, user)

      # Original should remain unchanged
      refreshed_original = Strategies.get_strategy(original.id, user)
      assert refreshed_original.description == "Original description"
      assert updated_duplicate.description == "Modified description"
    end

    test "T078: returns error when user does not own the strategy", %{user: user} do
      other_user = user_fixture(email: "other@example.com")
      other_strategy = strategy_fixture(user: other_user, name: "Other's Strategy")

      # Should not be able to duplicate another user's strategy
      assert {:error, :not_found} = Strategies.duplicate_strategy(other_strategy, user)
    end
  end
end
