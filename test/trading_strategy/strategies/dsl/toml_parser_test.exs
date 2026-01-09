defmodule TradingStrategy.Strategies.DSL.TomlParserTest do
  use ExUnit.Case, async: true

  alias TradingStrategy.Strategies.DSL.TomlParser

  describe "parse/1" do
    test "successfully parses valid TOML strategy" do
      toml = """
      name = "RSI Mean Reversion"
      trading_pair = "BTC/USD"
      timeframe = "1h"
      entry_conditions = "rsi_14 < 30"
      exit_conditions = "rsi_14 > 70"
      stop_conditions = "rsi_14 < 25"

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

      assert {:ok, strategy} = TomlParser.parse(toml)
      assert strategy["name"] == "RSI Mean Reversion"
      assert strategy["trading_pair"] == "BTC/USD"
      assert strategy["timeframe"] == "1h"
      assert is_list(strategy["indicators"])
      assert length(strategy["indicators"]) == 1
    end

    test "parses multiple indicators correctly" do
      toml = """
      [[indicators]]
      type = "rsi"
      name = "rsi_14"

      [indicators.parameters]
      period = 14

      [[indicators]]
      type = "macd"
      name = "macd_default"

      [indicators.parameters]
      short_period = 12
      long_period = 26
      signal_period = 9
      """

      assert {:ok, strategy} = TomlParser.parse(toml)
      assert length(strategy["indicators"]) == 2

      [rsi, macd] = strategy["indicators"]
      assert rsi["type"] == "rsi"
      assert rsi["name"] == "rsi_14"
      assert rsi["parameters"]["period"] == 14

      assert macd["type"] == "macd"
      assert macd["parameters"]["short_period"] == 12
    end

    test "converts all keys to strings" do
      toml = """
      name = "Test Strategy"
      trading_pair = "BTC/USD"
      """

      assert {:ok, strategy} = TomlParser.parse(toml)
      assert is_binary(Map.fetch!(strategy, "name"))
      assert is_binary(Map.fetch!(strategy, "trading_pair"))

      # Should not have atom keys
      refute Map.has_key?(strategy, :name)
      refute Map.has_key?(strategy, :trading_pair)
    end

    test "handles numeric values with explicit typing" do
      toml = """
      [position_sizing]
      type = "percentage"
      percentage_of_capital = 0.10
      max_position_size = 0.25

      [risk_parameters]
      max_daily_loss = 0.03
      max_drawdown = 0.15
      stop_loss_percentage = 0.05
      """

      assert {:ok, strategy} = TomlParser.parse(toml)
      assert strategy["position_sizing"]["percentage_of_capital"] == 0.10
      assert strategy["risk_parameters"]["max_daily_loss"] == 0.03
    end

    test "handles integer and float types" do
      toml = """
      integer_value = 42
      float_value = 3.14
      """

      assert {:ok, parsed} = TomlParser.parse(toml)
      assert parsed["integer_value"] == 42
      assert parsed["float_value"] == 3.14
    end

    test "returns error for invalid TOML syntax" do
      toml = """
      name = "Test
      invalid = unclosed string
      """

      assert {:error, message} = TomlParser.parse(toml)
      assert message =~ "Failed to parse TOML"
    end

    test "returns error for non-string input" do
      assert {:error, "TOML content must be a string"} = TomlParser.parse(123)
      assert {:error, "TOML content must be a string"} = TomlParser.parse(nil)
      assert {:error, "TOML content must be a string"} = TomlParser.parse(%{})
    end

    test "handles empty TOML" do
      toml = ""

      # Empty TOML is valid and returns empty map
      assert {:ok, strategy} = TomlParser.parse(toml)
      assert strategy == %{}
    end

    test "handles nested tables" do
      toml = """
      [position_sizing]
      type = "percentage"

      [position_sizing.advanced]
      use_kelly = true
      max_leverage = 2.0
      """

      assert {:ok, strategy} = TomlParser.parse(toml)
      assert strategy["position_sizing"]["type"] == "percentage"
      assert strategy["position_sizing"]["advanced"]["use_kelly"] == true
      assert strategy["position_sizing"]["advanced"]["max_leverage"] == 2.0
    end

    test "handles boolean values" do
      toml = """
      enabled = true
      disabled = false
      """

      assert {:ok, parsed} = TomlParser.parse(toml)
      assert parsed["enabled"] == true
      assert parsed["disabled"] == false
    end
  end

  describe "parse_file/1" do
    setup do
      # Create temporary directory for test files
      temp_dir = System.tmp_dir!() |> Path.join("toml_parser_test_#{:rand.uniform(100_000)}")
      File.mkdir_p!(temp_dir)

      on_exit(fn ->
        File.rm_rf!(temp_dir)
      end)

      {:ok, temp_dir: temp_dir}
    end

    test "successfully parses valid TOML file", %{temp_dir: temp_dir} do
      file_path = Path.join(temp_dir, "test_strategy.toml")

      toml = """
      name = "Test Strategy"
      trading_pair = "BTC/USD"
      timeframe = "1h"
      """

      File.write!(file_path, toml)

      assert {:ok, strategy} = TomlParser.parse_file(file_path)
      assert strategy["name"] == "Test Strategy"
      assert strategy["trading_pair"] == "BTC/USD"
    end

    test "returns error for non-existent file" do
      assert {:error, message} = TomlParser.parse_file("/non/existent/file.toml")
      assert message =~ "Failed to read TOML file"
      assert message =~ "non/existent/file.toml"
    end

    test "returns error for file with invalid TOML", %{temp_dir: temp_dir} do
      file_path = Path.join(temp_dir, "invalid.toml")
      File.write!(file_path, "invalid = unclosed string")

      assert {:error, message} = TomlParser.parse_file(file_path)
      assert message =~ "Failed to parse TOML"
    end
  end
end
