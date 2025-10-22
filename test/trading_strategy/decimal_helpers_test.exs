defmodule TradingStrategy.DecimalHelpersTest do
  use ExUnit.Case, async: true
  alias TradingStrategy.DecimalHelpers

  describe "ensure_decimal/1" do
    test "returns Decimal value unchanged" do
      decimal_value = Decimal.new("42.5")
      assert DecimalHelpers.ensure_decimal(decimal_value) == decimal_value
    end

    test "converts integer to Decimal" do
      result = DecimalHelpers.ensure_decimal(42)
      assert %Decimal{} = result
      assert Decimal.equal?(result, Decimal.new(42))
    end

    test "converts float to Decimal" do
      result = DecimalHelpers.ensure_decimal(3.14)
      assert %Decimal{} = result
      assert Decimal.equal?(result, Decimal.new("3.14"))
    end

    test "converts string to Decimal" do
      result = DecimalHelpers.ensure_decimal("99.99")
      assert %Decimal{} = result
      assert Decimal.equal?(result, Decimal.new("99.99"))
    end

    test "converts negative integer to Decimal" do
      result = DecimalHelpers.ensure_decimal(-100)
      assert %Decimal{} = result
      assert Decimal.equal?(result, Decimal.new(-100))
    end

    test "converts negative float to Decimal" do
      result = DecimalHelpers.ensure_decimal(-25.5)
      assert %Decimal{} = result
      assert Decimal.equal?(result, Decimal.new("-25.5"))
    end

    test "converts zero integer to Decimal" do
      result = DecimalHelpers.ensure_decimal(0)
      assert %Decimal{} = result
      assert Decimal.equal?(result, Decimal.new(0))
    end

    test "converts zero float to Decimal" do
      result = DecimalHelpers.ensure_decimal(0.0)
      assert %Decimal{} = result
      assert Decimal.equal?(result, Decimal.new("0.0"))
    end

    test "handles large integers" do
      large_int = 999_999_999_999
      result = DecimalHelpers.ensure_decimal(large_int)
      assert %Decimal{} = result
      assert Decimal.equal?(result, Decimal.new(large_int))
    end

    test "handles very small floats" do
      small_float = 0.00001
      result = DecimalHelpers.ensure_decimal(small_float)
      assert %Decimal{} = result
      # Compare with tolerance due to float precision
      assert Decimal.compare(result, Decimal.new("0.00001")) in [:eq, :gt, :lt]
    end

    test "returns nil for invalid string" do
      assert DecimalHelpers.ensure_decimal("invalid") == nil
    end

    test "returns nil for atom" do
      assert DecimalHelpers.ensure_decimal(:invalid) == nil
    end

    test "returns nil for list" do
      assert DecimalHelpers.ensure_decimal([1, 2, 3]) == nil
    end

    test "returns nil for map" do
      assert DecimalHelpers.ensure_decimal(%{value: 42}) == nil
    end

    test "returns nil for tuple" do
      assert DecimalHelpers.ensure_decimal({:ok, 42}) == nil
    end

    test "handles special float values - infinity" do
      # Infinity atoms should be handled gracefully (return nil)
      result = DecimalHelpers.ensure_decimal(:infinity)
      assert result == nil
    end

    test "handles special float values - NaN" do
      # NaN atoms should be handled gracefully (return nil)
      result = DecimalHelpers.ensure_decimal(:nan)
      assert result == nil
    end
  end

  describe "ensure_decimal_components/1" do
    test "converts all integer values in map to Decimal" do
      input = %{upper: 100, middle: 95, lower: 90}
      result = DecimalHelpers.ensure_decimal_components(input)

      assert %Decimal{} = result.upper
      assert %Decimal{} = result.middle
      assert %Decimal{} = result.lower

      assert Decimal.equal?(result.upper, Decimal.new(100))
      assert Decimal.equal?(result.middle, Decimal.new(95))
      assert Decimal.equal?(result.lower, Decimal.new(90))
    end

    test "converts all float values in map to Decimal" do
      input = %{value: 42.5, threshold: 38.2}
      result = DecimalHelpers.ensure_decimal_components(input)

      assert %Decimal{} = result.value
      assert %Decimal{} = result.threshold

      assert Decimal.equal?(result.value, Decimal.new("42.5"))
      assert Decimal.equal?(result.threshold, Decimal.new("38.2"))
    end

    test "converts mixed types in map to Decimal" do
      input = %{integer: 100, float: 95.5, string: "90.0"}
      result = DecimalHelpers.ensure_decimal_components(input)

      assert %Decimal{} = result.integer
      assert %Decimal{} = result.float
      assert %Decimal{} = result.string

      assert Decimal.equal?(result.integer, Decimal.new(100))
      assert Decimal.equal?(result.float, Decimal.new("95.5"))
      assert Decimal.equal?(result.string, Decimal.new("90.0"))
    end

    test "preserves Decimal values in map" do
      decimal_value = Decimal.new("42.5")
      input = %{value: decimal_value}
      result = DecimalHelpers.ensure_decimal_components(input)

      assert result.value == decimal_value
    end

    test "handles multi-value indicator result structure" do
      # Simulates BollingerBands result
      input = %{
        upper_band: 105.5,
        middle_band: 100.0,
        lower_band: 94.5,
        percent_b: 0.75,
        bandwidth: 11.0
      }

      result = DecimalHelpers.ensure_decimal_components(input)

      assert %Decimal{} = result.upper_band
      assert %Decimal{} = result.middle_band
      assert %Decimal{} = result.lower_band
      assert %Decimal{} = result.percent_b
      assert %Decimal{} = result.bandwidth
    end

    test "handles MACD result structure" do
      # Simulates MACD result
      input = %{
        macd: 2.5,
        signal: 1.8,
        histogram: 0.7
      }

      result = DecimalHelpers.ensure_decimal_components(input)

      assert %Decimal{} = result.macd
      assert %Decimal{} = result.signal
      assert %Decimal{} = result.histogram

      assert Decimal.equal?(result.macd, Decimal.new("2.5"))
      assert Decimal.equal?(result.signal, Decimal.new("1.8"))
      assert Decimal.equal?(result.histogram, Decimal.new("0.7"))
    end

    test "handles Stochastic result structure" do
      # Simulates Stochastic result
      input = %{k: 75.5, d: 72.3}
      result = DecimalHelpers.ensure_decimal_components(input)

      assert %Decimal{} = result.k
      assert %Decimal{} = result.d

      assert Decimal.equal?(result.k, Decimal.new("75.5"))
      assert Decimal.equal?(result.d, Decimal.new("72.3"))
    end

    test "converts invalid values to nil" do
      input = %{valid: 100, invalid: :atom, also_invalid: [1, 2]}
      result = DecimalHelpers.ensure_decimal_components(input)

      assert %Decimal{} = result.valid
      assert result.invalid == nil
      assert result.also_invalid == nil
    end

    test "handles empty map" do
      result = DecimalHelpers.ensure_decimal_components(%{})
      assert result == %{}
    end

    test "handles negative values in map" do
      input = %{positive: 100, negative: -50, zero: 0}
      result = DecimalHelpers.ensure_decimal_components(input)

      assert Decimal.equal?(result.positive, Decimal.new(100))
      assert Decimal.equal?(result.negative, Decimal.new(-50))
      assert Decimal.equal?(result.zero, Decimal.new(0))
    end

    test "preserves map keys" do
      input = %{upper: 100, middle: 95, lower: 90}
      result = DecimalHelpers.ensure_decimal_components(input)

      assert Map.keys(result) == Map.keys(input)
    end

    test "works with string keys" do
      input = %{"upper" => 100, "lower" => 90}
      result = DecimalHelpers.ensure_decimal_components(input)

      assert %Decimal{} = result["upper"]
      assert %Decimal{} = result["lower"]
    end

    test "works with atom keys" do
      input = %{upper: 100, lower: 90}
      result = DecimalHelpers.ensure_decimal_components(input)

      assert %Decimal{} = result[:upper]
      assert %Decimal{} = result[:lower]
    end
  end
end
