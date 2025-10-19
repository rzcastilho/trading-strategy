defmodule TradingStrategy.PatternsTest do
  use ExUnit.Case, async: true
  alias TradingStrategy.Patterns
  import TradingStrategy.TestHelpers

  describe "detect_hammer/1" do
    test "detects a hammer pattern" do
      candles = hammer_pattern()
      assert Patterns.detect_hammer(candles) == :hammer
    end

    test "returns nil when not a hammer" do
      candles = [%{open: 100, high: 105, low: 98, close: 104, volume: 1000}]
      assert Patterns.detect_hammer(candles) == nil
    end
  end

  describe "detect_bullish_engulfing/1" do
    test "detects a bullish engulfing pattern" do
      candles = bullish_engulfing_pattern()
      assert Patterns.detect_bullish_engulfing(candles) == :bullish_engulfing
    end

    test "returns nil with insufficient candles" do
      assert Patterns.detect_bullish_engulfing([]) == nil
    end
  end

  describe "detect_bearish_engulfing/1" do
    test "detects a bearish engulfing pattern" do
      candles = bearish_engulfing_pattern()
      assert Patterns.detect_bearish_engulfing(candles) == :bearish_engulfing
    end
  end

  describe "detect_doji/1" do
    test "detects a doji pattern" do
      candles = doji_pattern()
      assert Patterns.detect_doji(candles) == :doji
    end
  end

  describe "detect_morning_star/1" do
    test "detects a morning star pattern" do
      candles = morning_star_pattern()
      assert Patterns.detect_morning_star(candles) == :morning_star
    end
  end

  describe "detect_evening_star/1" do
    test "detects an evening star pattern" do
      candles = evening_star_pattern()
      assert Patterns.detect_evening_star(candles) == :evening_star
    end
  end

  describe "detect_all/1" do
    test "detects all patterns in candle data" do
      candles = hammer_pattern()
      patterns = Patterns.detect_all(candles)
      assert :hammer in patterns
    end

    test "returns empty list with insufficient data" do
      assert Patterns.detect_all([]) == []
      assert Patterns.detect_all([%{}]) == []
    end
  end

  describe "has_pattern?/2" do
    test "returns true when pattern is detected" do
      candles = hammer_pattern()
      assert Patterns.has_pattern?(candles, :hammer)
    end

    test "returns false when pattern is not detected" do
      candles = [%{open: 100, high: 101, low: 99, close: 100.5, volume: 1000}]
      refute Patterns.has_pattern?(candles, :hammer)
    end
  end
end
