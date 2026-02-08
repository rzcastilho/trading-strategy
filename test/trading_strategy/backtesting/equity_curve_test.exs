defmodule TradingStrategy.Backtesting.EquityCurveTest do
  use ExUnit.Case, async: true

  alias TradingStrategy.Backtesting.EquityCurve

  describe "generate/2" do
    test "generates equity curve from empty equity history" do
      equity_history = []
      initial_capital = Decimal.new("10000.00")

      result = EquityCurve.generate(equity_history, initial_capital)

      assert is_list(result)
      assert length(result) == 0
    end

    test "generates equity curve with single equity point" do
      timestamp = ~U[2024-01-01 00:00:00Z]
      equity_history = [{timestamp, Decimal.new("10500.00")}]
      initial_capital = Decimal.new("10000.00")

      result = EquityCurve.generate(equity_history, initial_capital)

      assert length(result) == 1
      assert [{^timestamp, value}] = result
      assert Decimal.eq?(value, Decimal.new("10500.00"))
    end

    test "generates equity curve with multiple equity points" do
      equity_history = [
        {~U[2024-01-01 00:00:00Z], Decimal.new("10000.00")},
        {~U[2024-01-01 01:00:00Z], Decimal.new("10150.50")},
        {~U[2024-01-01 02:00:00Z], Decimal.new("10120.25")},
        {~U[2024-01-01 03:00:00Z], Decimal.new("10300.00")}
      ]
      initial_capital = Decimal.new("10000.00")

      result = EquityCurve.generate(equity_history, initial_capital)

      assert length(result) == 4
      assert Enum.all?(result, fn {timestamp, value} ->
        is_struct(timestamp, DateTime) and is_struct(value, Decimal)
      end)
    end

    test "preserves chronological order of equity points" do
      equity_history = [
        {~U[2024-01-01 00:00:00Z], Decimal.new("10000.00")},
        {~U[2024-01-01 01:00:00Z], Decimal.new("10150.50")},
        {~U[2024-01-01 02:00:00Z], Decimal.new("10120.25")}
      ]
      initial_capital = Decimal.new("10000.00")

      result = EquityCurve.generate(equity_history, initial_capital)

      timestamps = Enum.map(result, fn {ts, _} -> ts end)
      assert timestamps == Enum.sort(timestamps, DateTime)
    end
  end

  describe "sample/2" do
    test "returns all points when total points <= max_points" do
      curve = [
        {~U[2024-01-01 00:00:00Z], Decimal.new("10000.00")},
        {~U[2024-01-01 01:00:00Z], Decimal.new("10150.50")},
        {~U[2024-01-01 02:00:00Z], Decimal.new("10120.25")}
      ]
      max_points = 1000

      result = EquityCurve.sample(curve, max_points)

      assert length(result) == 3
      assert result == curve
    end

    test "samples down to max_points when curve exceeds limit" do
      # Create 5000 points
      curve = Enum.map(1..5000, fn i ->
        timestamp = DateTime.add(~U[2024-01-01 00:00:00Z], i * 60, :second)
        value = Decimal.add(Decimal.new("10000.00"), Decimal.new(i))
        {timestamp, value}
      end)

      max_points = 1000

      result = EquityCurve.sample(curve, max_points)

      assert length(result) <= max_points
      # First and last points should always be included
      assert List.first(result) == List.first(curve)
      assert List.last(result) == List.last(curve)
    end

    test "sampling preserves chronological order" do
      curve = Enum.map(1..5000, fn i ->
        timestamp = DateTime.add(~U[2024-01-01 00:00:00Z], i * 60, :second)
        value = Decimal.add(Decimal.new("10000.00"), Decimal.new(i))
        {timestamp, value}
      end)

      max_points = 1000

      result = EquityCurve.sample(curve, max_points)

      timestamps = Enum.map(result, fn {ts, _} -> ts end)
      assert timestamps == Enum.sort(timestamps, DateTime)
    end

    test "empty curve returns empty list" do
      curve = []
      max_points = 1000

      result = EquityCurve.sample(curve, max_points)

      assert result == []
    end

    test "single point curve returns that point" do
      curve = [{~U[2024-01-01 00:00:00Z], Decimal.new("10000.00")}]
      max_points = 1000

      result = EquityCurve.sample(curve, max_points)

      assert result == curve
    end

    test "handles exact max_points boundary correctly" do
      # Create exactly 1000 points
      curve = Enum.map(1..1000, fn i ->
        timestamp = DateTime.add(~U[2024-01-01 00:00:00Z], i * 60, :second)
        value = Decimal.add(Decimal.new("10000.00"), Decimal.new(i))
        {timestamp, value}
      end)

      max_points = 1000

      result = EquityCurve.sample(curve, max_points)

      # Should return all points when exactly at limit
      assert length(result) == 1000
      assert result == curve
    end

    test "handles very large datasets (10K+ points)" do
      # Create 10,000 points
      curve = Enum.map(1..10_000, fn i ->
        timestamp = DateTime.add(~U[2024-01-01 00:00:00Z], i * 60, :second)
        value = Decimal.add(Decimal.new("10000.00"), Decimal.new(i * 10))
        {timestamp, value}
      end)

      max_points = 1000

      result = EquityCurve.sample(curve, max_points)

      # Should sample down to max_points
      assert length(result) <= max_points
      assert length(result) > 0

      # Verify sampling maintains data distribution
      # First and last should be preserved
      assert List.first(result) == List.first(curve)
      assert List.last(result) == List.last(curve)
    end

    test "handles negative equity values correctly" do
      # Equity curve that goes negative (account blown up)
      curve = [
        {~U[2024-01-01 00:00:00Z], Decimal.new("10000.00")},
        {~U[2024-01-01 01:00:00Z], Decimal.new("5000.00")},
        {~U[2024-01-01 02:00:00Z], Decimal.new("1000.00")},
        {~U[2024-01-01 03:00:00Z], Decimal.new("0.00")},
        {~U[2024-01-01 04:00:00Z], Decimal.new("-500.00")}
      ]

      max_points = 1000

      result = EquityCurve.sample(curve, max_points)

      assert length(result) == 5
      # All points should be preserved since under max_points
      assert result == curve

      # Verify negative value is preserved
      {_ts, last_value} = List.last(result)
      assert Decimal.eq?(last_value, Decimal.new("-500.00"))
    end

    test "sampling with odd number of points" do
      # Create 999 points (odd number just under 1000)
      curve = Enum.map(1..999, fn i ->
        timestamp = DateTime.add(~U[2024-01-01 00:00:00Z], i * 60, :second)
        value = Decimal.add(Decimal.new("10000.00"), Decimal.new(i))
        {timestamp, value}
      end)

      max_points = 1000

      result = EquityCurve.sample(curve, max_points)

      # Should return all points since under limit
      assert length(result) == 999
    end

    test "sampling with 2 points (boundary case)" do
      curve = [
        {~U[2024-01-01 00:00:00Z], Decimal.new("10000.00")},
        {~U[2024-01-01 01:00:00Z], Decimal.new("10500.00")}
      ]

      max_points = 1000

      result = EquityCurve.sample(curve, max_points)

      assert length(result) == 2
      assert result == curve
    end

    test "sampling respects sample_rate calculation" do
      # Create 5000 points, should sample every 5th point to get 1000
      curve = Enum.map(1..5000, fn i ->
        timestamp = DateTime.add(~U[2024-01-01 00:00:00Z], i * 60, :second)
        value = Decimal.new(10000 + i)
        {timestamp, value}
      end)

      max_points = 1000

      result = EquityCurve.sample(curve, max_points)

      # Should sample down intelligently
      assert length(result) <= max_points
      assert length(result) > 0

      # Verify no duplicate timestamps
      timestamps = Enum.map(result, fn {ts, _} -> ts end)
      assert length(timestamps) == length(Enum.uniq(timestamps))
    end
  end

  describe "to_json_format/1" do
    test "converts equity curve to JSON-compatible format" do
      curve = [
        {~U[2024-01-01 00:00:00Z], Decimal.new("10000.00")},
        {~U[2024-01-01 01:00:00Z], Decimal.new("10150.50")}
      ]

      result = EquityCurve.to_json_format(curve)

      assert is_list(result)
      assert length(result) == 2

      [first, second] = result
      assert %{"timestamp" => "2024-01-01T00:00:00Z", "value" => 10000.0} = first
      assert %{"timestamp" => "2024-01-01T01:00:00Z", "value" => 10150.5} = second
    end

    test "handles empty curve" do
      curve = []

      result = EquityCurve.to_json_format(curve)

      assert result == []
    end

    test "converts Decimal values to floats accurately" do
      curve = [{~U[2024-01-01 00:00:00Z], Decimal.new("10123.456789")}]

      result = EquityCurve.to_json_format(curve)

      assert [%{"value" => value}] = result
      assert is_float(value)
      assert_in_delta value, 10123.456789, 0.000001
    end
  end
end
