defmodule TradingStrategy.IndicatorsTest do
  use ExUnit.Case, async: true
  alias TradingStrategy.{Indicators, Definition}

  setup do
    strategy =
      Definition.new(:test)
      |> Definition.add_indicator(:sma, TestIndicator, period: 3)
      |> Definition.add_indicator(:rsi, TestIndicator, period: 2)

    market_data = [
      %{open: 98, high: 102, low: 97, close: 100, volume: 1000},
      %{open: 100, high: 104, low: 99, close: 102, volume: 1100},
      %{open: 102, high: 106, low: 101, close: 104, volume: 1200}
    ]

    {:ok, strategy: strategy, market_data: market_data}
  end

  describe "calculate_all/3" do
    test "calculates all indicators for a strategy", %{strategy: strategy, market_data: data} do
      result = Indicators.calculate_all(strategy, data)

      assert is_map(result)
      assert Map.has_key?(result, :sma)
      assert Map.has_key?(result, :rsi)
    end

    test "returns empty map for strategy with no indicators" do
      strategy = Definition.new(:empty)
      result = Indicators.calculate_all(strategy, [])
      assert result == %{}
    end
  end

  describe "calculate_historical/3" do
    test "calculates historical values for indicators", %{strategy: strategy, market_data: data} do
      result = Indicators.calculate_historical(strategy, data, 2)

      assert is_map(result)
      assert Map.has_key?(result, :sma)
      assert is_list(result[:sma])
    end
  end

  describe "extract_data_series/2" do
    test "extracts close prices by default" do
      data = [
        %{close: 100, open: 98, high: 102, low: 97},
        %{close: 102, open: 100, high: 104, low: 99}
      ]

      result = Indicators.extract_data_series(data, [])
      assert result == [Decimal.new("100"), Decimal.new("102")]
    end

    test "extracts specified source field" do
      data = [
        %{close: 100, open: 98, high: 102, low: 97},
        %{close: 102, open: 100, high: 104, low: 99}
      ]

      assert Indicators.extract_data_series(data, source: :high) == [Decimal.new("102"), Decimal.new("104")]
      assert Indicators.extract_data_series(data, source: :low) == [Decimal.new("97"), Decimal.new("99")]
      assert Indicators.extract_data_series(data, source: :open) == [Decimal.new("98"), Decimal.new("100")]
    end

    test "calculates hl2 (high-low average)" do
      data = [%{high: 100, low: 90, close: 95, open: 92}]
      result = Indicators.extract_data_series(data, source: :hl2)
      assert result == [Decimal.new("95")]
    end
  end

  describe "validate_market_data/1" do
    test "validates correct market data" do
      data = [%{open: 100, high: 105, low: 95, close: 102, volume: 1000}]
      assert Indicators.validate_market_data(data)
    end

    test "rejects data missing required fields" do
      data = [%{open: 100, close: 102}]
      refute Indicators.validate_market_data(data)
    end

    test "rejects non-list data" do
      refute Indicators.validate_market_data(%{})
      refute Indicators.validate_market_data(nil)
    end
  end

  describe "caching" do
    test "caches and retrieves indicator calculations" do
      value1 = Indicators.with_cache(:test_key, fn -> 42 end)
      value2 = Indicators.with_cache(:test_key, fn -> 99 end)

      assert value1 == 42
      assert value2 == 42  # Should return cached value
    end

    test "clear_cache/0 removes cached values" do
      Indicators.with_cache(:cache_test, fn -> 100 end)
      Indicators.clear_cache()
      value = Indicators.with_cache(:cache_test, fn -> 200 end)

      assert value == 200  # Should recalculate
    end
  end
end

defmodule TestIndicator do
  def calculate(data, _opts) when is_list(data) do
    if length(data) > 0 do
      sum = Enum.reduce(data, Decimal.new("0"), &Decimal.add/2)
      Decimal.div(sum, Decimal.new(length(data)))
    else
      Decimal.new("0")
    end
  end
end
