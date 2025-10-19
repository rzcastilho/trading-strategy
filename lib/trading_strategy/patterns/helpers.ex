defmodule TradingStrategy.Patterns.Helpers do
  @moduledoc false
  # Internal helpers for pattern recognition with Decimal support

  alias TradingStrategy.Types

  @doc """
  Extracts OHLC values from a candle as Decimals.
  """
  def extract_ohlc(candle) do
    %{
      open: Types.to_decimal(candle.open),
      high: Types.to_decimal(candle.high),
      low: Types.to_decimal(candle.low),
      close: Types.to_decimal(candle.close)
    }
  end

  @doc """
  Calculates body size (absolute difference between close and open).
  """
  def body_size(candle) do
    ohlc = extract_ohlc(candle)
    Decimal.abs(Decimal.sub(ohlc.close, ohlc.open))
  end

  @doc """
  Checks if a candle is bullish (close > open).
  """
  def bullish?(candle) do
    ohlc = extract_ohlc(candle)
    Decimal.compare(ohlc.close, ohlc.open) == :gt
  end

  @doc """
  Checks if a candle is bearish (close < open).
  """
  def bearish?(candle) do
    ohlc = extract_ohlc(candle)
    Decimal.compare(ohlc.close, ohlc.open) == :lt
  end

  @doc """
  Gets the candle range (high - low).
  """
  def range(candle) do
    ohlc = extract_ohlc(candle)
    Decimal.sub(ohlc.high, ohlc.low)
  end

  @doc """
  Gets the midpoint of a candle ((open + close) / 2).
  """
  def midpoint(candle) do
    ohlc = extract_ohlc(candle)
    Decimal.div(Decimal.add(ohlc.open, ohlc.close), Decimal.new("2"))
  end
end
