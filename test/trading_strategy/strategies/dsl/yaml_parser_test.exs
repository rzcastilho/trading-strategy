defmodule TradingStrategy.Strategies.DSL.YamlParserTest do
  use ExUnit.Case, async: true

  alias TradingStrategy.Strategies.DSL.YamlParser

  describe "parse/1" do
    test "successfully parses valid YAML strategy" do
      yaml = """
      name: RSI Mean Reversion
      trading_pair: BTC/USD
      timeframe: 1h
      indicators:
        - type: rsi
          name: rsi_14
          parameters:
            period: 14
      entry_conditions: "rsi_14 < 30"
      exit_conditions: "rsi_14 > 70"
      stop_conditions: "rsi_14 < 25"
      position_sizing:
        type: percentage
        percentage_of_capital: 0.10
      risk_parameters:
        max_daily_loss: 0.03
        max_drawdown: 0.15
      """

      assert {:ok, strategy} = YamlParser.parse(yaml)
      assert strategy["name"] == "RSI Mean Reversion"
      assert strategy["trading_pair"] == "BTC/USD"
      assert strategy["timeframe"] == "1h"
      assert is_list(strategy["indicators"])
      assert length(strategy["indicators"]) == 1
    end

    test "parses nested structures correctly" do
      yaml = """
      indicators:
        - type: rsi
          name: rsi_14
          parameters:
            period: 14
        - type: macd
          name: macd_default
          parameters:
            short_period: 12
            long_period: 26
            signal_period: 9
      """

      assert {:ok, strategy} = YamlParser.parse(yaml)
      assert length(strategy["indicators"]) == 2

      [rsi, macd] = strategy["indicators"]
      assert rsi["type"] == "rsi"
      assert rsi["name"] == "rsi_14"
      assert rsi["parameters"]["period"] == 14

      assert macd["type"] == "macd"
      assert macd["parameters"]["short_period"] == 12
    end

    test "converts all keys to strings" do
      yaml = """
      name: Test Strategy
      trading_pair: BTC/USD
      """

      assert {:ok, strategy} = YamlParser.parse(yaml)
      assert is_binary(Map.fetch!(strategy, "name"))
      assert is_binary(Map.fetch!(strategy, "trading_pair"))

      # Should not have atom keys
      refute Map.has_key?(strategy, :name)
      refute Map.has_key?(strategy, :trading_pair)
    end

    test "handles numeric values correctly" do
      yaml = """
      position_sizing:
        type: percentage
        percentage_of_capital: 0.10
        max_position_size: 0.25
      risk_parameters:
        max_daily_loss: 0.03
        max_drawdown: 0.15
        stop_loss_percentage: 0.05
      """

      assert {:ok, strategy} = YamlParser.parse(yaml)
      assert strategy["position_sizing"]["percentage_of_capital"] == 0.10
      assert strategy["risk_parameters"]["max_daily_loss"] == 0.03
    end

    test "returns error for invalid YAML syntax" do
      yaml = """
      name: Test
      invalid: [unclosed bracket
      """

      assert {:error, message} = YamlParser.parse(yaml)
      assert message =~ "Failed to parse YAML"
    end

    test "returns error for non-map YAML" do
      yaml = """
      - item1
      - item2
      """

      assert {:error, message} = YamlParser.parse(yaml)
      assert message =~ "Expected YAML to parse as a map"
    end

    test "returns error for non-string input" do
      assert {:error, "YAML content must be a string"} = YamlParser.parse(123)
      assert {:error, "YAML content must be a string"} = YamlParser.parse(nil)
      assert {:error, "YAML content must be a string"} = YamlParser.parse(%{})
    end

    test "handles empty YAML" do
      yaml = ""

      # Empty YAML should return an error
      assert {:error, _message} = YamlParser.parse(yaml)
    end

    test "handles multiline strings" do
      yaml = """
      description: |
        This is a multi-line
        description of the strategy
        with multiple lines
      name: Test
      """

      assert {:ok, strategy} = YamlParser.parse(yaml)
      assert strategy["description"] =~ "This is a multi-line"
      assert strategy["description"] =~ "with multiple lines"
    end
  end

  describe "parse_file/1" do
    setup do
      # Create temporary directory for test files
      temp_dir = System.tmp_dir!() |> Path.join("yaml_parser_test_#{:rand.uniform(100_000)}")
      File.mkdir_p!(temp_dir)

      on_exit(fn ->
        File.rm_rf!(temp_dir)
      end)

      {:ok, temp_dir: temp_dir}
    end

    test "successfully parses valid YAML file", %{temp_dir: temp_dir} do
      file_path = Path.join(temp_dir, "test_strategy.yaml")

      yaml = """
      name: Test Strategy
      trading_pair: BTC/USD
      timeframe: 1h
      """

      File.write!(file_path, yaml)

      assert {:ok, strategy} = YamlParser.parse_file(file_path)
      assert strategy["name"] == "Test Strategy"
      assert strategy["trading_pair"] == "BTC/USD"
    end

    test "returns error for non-existent file" do
      assert {:error, message} = YamlParser.parse_file("/non/existent/file.yaml")
      assert message =~ "Failed to read YAML file"
      assert message =~ "non/existent/file.yaml"
    end

    test "returns error for file with invalid YAML", %{temp_dir: temp_dir} do
      file_path = Path.join(temp_dir, "invalid.yaml")
      File.write!(file_path, "invalid: [unclosed")

      assert {:error, message} = YamlParser.parse_file(file_path)
      assert message =~ "Failed to parse YAML"
    end
  end
end
