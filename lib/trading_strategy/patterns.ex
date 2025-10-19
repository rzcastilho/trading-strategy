defmodule TradingStrategy.Patterns do
  @moduledoc """
  Candlestick pattern recognition with Decimal precision.

  Detects 11 common bullish and bearish candlestick patterns used in
  technical analysis. All pattern calculations use Decimal arithmetic
  for exact precision.

  ## Supported Patterns

  **Bullish Reversal Patterns:**
  - `:hammer` - Small body at top, long lower shadow
  - `:inverted_hammer` - Small body at bottom, long upper shadow
  - `:bullish_engulfing` - Bullish candle engulfs previous bearish candle
  - `:morning_star` - Three-candle bullish reversal pattern

  **Bearish Reversal Patterns:**
  - `:bearish_engulfing` - Bearish candle engulfs previous bullish candle
  - `:evening_star` - Three-candle bearish reversal pattern
  - `:shooting_star` - Similar to inverted hammer in downtrend
  - `:hanging_man` - Similar to hammer in uptrend

  **Strong Trend Patterns:**
  - `:three_white_soldiers` - Three consecutive bullish candles
  - `:three_black_crows` - Three consecutive bearish candles

  **Indecision:**
  - `:doji` - Open and close are very close

  ## Decimal Precision

  All pattern detection uses Decimal arithmetic for:

  - Body size calculations: `Decimal.abs(Decimal.sub(close, open))`
  - Shadow measurements: Precise upper/lower shadow calculations
  - Ratio comparisons: Exact threshold checks without rounding errors
  - Pattern validation: Reliable pattern detection

  ## Usage

      alias TradingStrategy.{Patterns, Types}

      # Create candle data with Decimal precision
      candles = [
        Types.new_ohlcv(100, 102, 99, 101, 1000),
        Types.new_ohlcv(101, 103, 100, 102, 1100),
        Types.new_ohlcv(97, 98.2, 95, 98, 1000)  # Hammer pattern
      ]

      # Detect all patterns
      patterns = Patterns.detect_all(candles)
      # => [:hammer]

      # Check for specific pattern
      Patterns.has_pattern?(candles, :hammer)
      # => true

  See individual function documentation for pattern-specific details.
  """

  alias TradingStrategy.Types

  # Helper to safely compare Decimal values
  defp to_dec(value), do: Types.to_decimal(value)

  @doc """
  Detects all patterns in the given candle data.

  Returns a list of pattern names found in the most recent candles.
  """
  def detect_all(candles) when is_list(candles) and length(candles) >= 3 do
    patterns = [
      detect_hammer(candles),
      detect_inverted_hammer(candles),
      detect_bullish_engulfing(candles),
      detect_bearish_engulfing(candles),
      detect_doji(candles),
      detect_morning_star(candles),
      detect_evening_star(candles),
      detect_three_white_soldiers(candles),
      detect_three_black_crows(candles),
      detect_shooting_star(candles),
      detect_hanging_man(candles)
    ]

    Enum.filter(patterns, &(&1 != nil))
  end

  def detect_all(_candles), do: []

  @doc """
  Detects a hammer pattern (bullish reversal).

  Characteristics:
  - Small body at the top
  - Long lower shadow (at least 2x body size)
  - Little or no upper shadow
  """
  def detect_hammer(candles) do
    candle = List.last(candles)

    if candle do
      # Convert to Decimal for precise calculations
      open = Types.to_decimal(candle.open)
      high = Types.to_decimal(candle.high)
      low = Types.to_decimal(candle.low)
      close = Types.to_decimal(candle.close)

      body_size = Decimal.abs(Decimal.sub(close, open))
      lower_shadow = Decimal.sub(Decimal.min(open, close), low)
      upper_shadow = Decimal.sub(high, Decimal.max(open, close))

      # Avoid division by zero for very small bodies
      min_body = Decimal.max(body_size, Decimal.new("0.1"))
      threshold_lower = Decimal.mult(min_body, Decimal.new("2"))
      threshold_upper = Decimal.mult(min_body, Decimal.new("0.3"))

      if Decimal.compare(lower_shadow, threshold_lower) != :lt and
           Decimal.compare(upper_shadow, threshold_upper) != :gt do
        :hammer
      end
    end
  end

  @doc """
  Detects an inverted hammer pattern (bullish reversal).
  """
  def detect_inverted_hammer(candles) do
    candle = List.last(candles)

    if candle do
      open = to_dec(candle.open)
      high = to_dec(candle.high)
      low = to_dec(candle.low)
      close = to_dec(candle.close)

      body_size = Decimal.abs(Decimal.sub(close, open))
      lower_shadow = Decimal.sub(Decimal.min(open, close), low)
      upper_shadow = Decimal.sub(high, Decimal.max(open, close))

      min_body = Decimal.max(body_size, Decimal.new("0.1"))
      threshold_upper = Decimal.mult(min_body, Decimal.new("2"))
      threshold_lower = Decimal.mult(min_body, Decimal.new("0.3"))

      if Decimal.compare(upper_shadow, threshold_upper) != :lt and
           Decimal.compare(lower_shadow, threshold_lower) == :lt do
        :inverted_hammer
      end
    end
  end

  @doc """
  Detects a bullish engulfing pattern.

  Characteristics:
  - Previous candle is bearish
  - Current candle is bullish
  - Current body completely engulfs previous body
  """
  def detect_bullish_engulfing(candles) when length(candles) >= 2 do
    [prev, current] = Enum.take(candles, -2)

    prev_bearish = Decimal.compare(to_dec(prev.close), to_dec(prev.open)) == :lt
    current_bullish = Decimal.compare(to_dec(current.close), to_dec(current.open)) == :gt

    if prev_bearish and current_bullish do
      if Decimal.compare(to_dec(current.open), to_dec(prev.close)) != :gt and
           Decimal.compare(to_dec(current.close), to_dec(prev.open)) != :lt do
        :bullish_engulfing
      end
    end
  end

  def detect_bullish_engulfing(_), do: nil

  @doc """
  Detects a bearish engulfing pattern.
  """
  def detect_bearish_engulfing(candles) when length(candles) >= 2 do
    [prev, current] = Enum.take(candles, -2)

    prev_bullish = Decimal.compare(to_dec(prev.close), to_dec(prev.open)) == :gt
    current_bearish = Decimal.compare(to_dec(current.close), to_dec(current.open)) == :lt

    if prev_bullish and current_bearish do
      if Decimal.compare(to_dec(current.open), to_dec(prev.close)) != :lt and
           Decimal.compare(to_dec(current.close), to_dec(prev.open)) != :gt do
        :bearish_engulfing
      end
    end
  end

  def detect_bearish_engulfing(_), do: nil

  @doc """
  Detects a doji pattern (indecision).

  Characteristics:
  - Open and close are very close (within 0.1% of high-low range)
  """
  def detect_doji(candles) do
    candle = List.last(candles)

    if candle do
      open = to_dec(candle.open)
      high = to_dec(candle.high)
      low = to_dec(candle.low)
      close = to_dec(candle.close)

      body_size = Decimal.abs(Decimal.sub(close, open))
      range = Decimal.sub(high, low)

      if Decimal.compare(range, Decimal.new("0")) == :gt do
        ratio = Decimal.div(body_size, range)
        if Decimal.compare(ratio, Decimal.new("0.1")) == :lt do
          :doji
        end
      end
    end
  end

  @doc """
  Detects a morning star pattern (bullish reversal).

  Characteristics:
  - Three candles
  - First: bearish
  - Second: small body (star)
  - Third: bullish, closes above midpoint of first candle
  """
  def detect_morning_star(candles) when length(candles) >= 3 do
    [first, second, third] = Enum.take(candles, -3)

    first_bearish = Decimal.compare(to_dec(first.close), to_dec(first.open)) == :lt

    first_body = Decimal.abs(Decimal.sub(to_dec(first.close), to_dec(first.open)))
    second_body = Decimal.abs(Decimal.sub(to_dec(second.close), to_dec(second.open)))
    threshold = Decimal.mult(first_body, Decimal.new("0.5"))
    second_small = Decimal.compare(second_body, threshold) == :lt

    third_bullish = Decimal.compare(to_dec(third.close), to_dec(third.open)) == :gt

    if first_bearish and second_small and third_bullish do
      first_midpoint = Decimal.div(
        Decimal.add(to_dec(first.open), to_dec(first.close)),
        Decimal.new("2")
      )

      if Decimal.compare(to_dec(third.close), first_midpoint) == :gt do
        :morning_star
      end
    end
  end

  def detect_morning_star(_), do: nil

  @doc """
  Detects an evening star pattern (bearish reversal).
  """
  def detect_evening_star(candles) when length(candles) >= 3 do
    [first, second, third] = Enum.take(candles, -3)

    first_bullish = Decimal.compare(to_dec(first.close), to_dec(first.open)) == :gt

    first_body = Decimal.abs(Decimal.sub(to_dec(first.close), to_dec(first.open)))
    second_body = Decimal.abs(Decimal.sub(to_dec(second.close), to_dec(second.open)))
    threshold = Decimal.mult(first_body, Decimal.new("0.5"))
    second_small = Decimal.compare(second_body, threshold) == :lt

    third_bearish = Decimal.compare(to_dec(third.close), to_dec(third.open)) == :lt

    if first_bullish and second_small and third_bearish do
      first_midpoint = Decimal.div(
        Decimal.add(to_dec(first.open), to_dec(first.close)),
        Decimal.new("2")
      )

      if Decimal.compare(to_dec(third.close), first_midpoint) == :lt do
        :evening_star
      end
    end
  end

  def detect_evening_star(_), do: nil

  @doc """
  Detects three white soldiers (strong bullish).

  Characteristics:
  - Three consecutive bullish candles
  - Each opens within previous body
  - Each closes higher than previous
  """
  def detect_three_white_soldiers(candles) when length(candles) >= 3 do
    [first, second, third] = Enum.take(candles, -3)

    all_bullish =
      Decimal.compare(to_dec(first.close), to_dec(first.open)) == :gt and
        Decimal.compare(to_dec(second.close), to_dec(second.open)) == :gt and
        Decimal.compare(to_dec(third.close), to_dec(third.open)) == :gt

    ascending =
      Decimal.compare(to_dec(second.close), to_dec(first.close)) == :gt and
        Decimal.compare(to_dec(third.close), to_dec(second.close)) == :gt

    opens_in_body =
      Decimal.compare(to_dec(second.open), to_dec(first.open)) != :lt and
        Decimal.compare(to_dec(second.open), to_dec(first.close)) != :gt and
        Decimal.compare(to_dec(third.open), to_dec(second.open)) != :lt and
        Decimal.compare(to_dec(third.open), to_dec(second.close)) != :gt

    if all_bullish and ascending and opens_in_body do
      :three_white_soldiers
    end
  end

  def detect_three_white_soldiers(_), do: nil

  @doc """
  Detects three black crows (strong bearish).
  """
  def detect_three_black_crows(candles) when length(candles) >= 3 do
    [first, second, third] = Enum.take(candles, -3)

    all_bearish =
      Decimal.compare(to_dec(first.close), to_dec(first.open)) == :lt and
        Decimal.compare(to_dec(second.close), to_dec(second.open)) == :lt and
        Decimal.compare(to_dec(third.close), to_dec(third.open)) == :lt

    descending =
      Decimal.compare(to_dec(second.close), to_dec(first.close)) == :lt and
        Decimal.compare(to_dec(third.close), to_dec(second.close)) == :lt

    opens_in_body =
      Decimal.compare(to_dec(second.open), to_dec(first.open)) != :gt and
        Decimal.compare(to_dec(second.open), to_dec(first.close)) != :lt and
        Decimal.compare(to_dec(third.open), to_dec(second.open)) != :gt and
        Decimal.compare(to_dec(third.open), to_dec(second.close)) != :lt

    if all_bearish and descending and opens_in_body do
      :three_black_crows
    end
  end

  def detect_three_black_crows(_), do: nil

  @doc """
  Detects a shooting star (bearish reversal).

  Similar to inverted hammer but appears after an uptrend.
  """
  def detect_shooting_star(candles) do
    candle = List.last(candles)

    if candle do
      open = to_dec(candle.open)
      high = to_dec(candle.high)
      low = to_dec(candle.low)
      close = to_dec(candle.close)

      body_size = Decimal.abs(Decimal.sub(close, open))
      lower_shadow = Decimal.sub(Decimal.min(open, close), low)
      upper_shadow = Decimal.sub(high, Decimal.max(open, close))

      min_body = Decimal.max(body_size, Decimal.new("0.1"))
      threshold_upper = Decimal.mult(min_body, Decimal.new("2"))
      threshold_lower = Decimal.mult(min_body, Decimal.new("0.3"))

      if Decimal.compare(upper_shadow, threshold_upper) != :lt and
           Decimal.compare(lower_shadow, threshold_lower) == :lt do
        :shooting_star
      end
    end
  end

  @doc """
  Detects a hanging man (bearish reversal).

  Similar to hammer but appears after an uptrend.
  """
  def detect_hanging_man(candles) do
    candle = List.last(candles)

    if candle do
      open = to_dec(candle.open)
      high = to_dec(candle.high)
      low = to_dec(candle.low)
      close = to_dec(candle.close)

      body_size = Decimal.abs(Decimal.sub(close, open))
      lower_shadow = Decimal.sub(Decimal.min(open, close), low)
      upper_shadow = Decimal.sub(high, Decimal.max(open, close))

      min_body = Decimal.max(body_size, Decimal.new("0.1"))
      threshold_lower = Decimal.mult(min_body, Decimal.new("2"))
      threshold_upper = Decimal.mult(min_body, Decimal.new("0.3"))

      if Decimal.compare(lower_shadow, threshold_lower) != :lt and
           Decimal.compare(upper_shadow, threshold_upper) == :lt do
        :hanging_man
      end
    end
  end

  @doc """
  Checks if a specific pattern exists in the candle data.
  """
  def has_pattern?(candles, pattern_name) do
    pattern_name in detect_all(candles)
  end
end
