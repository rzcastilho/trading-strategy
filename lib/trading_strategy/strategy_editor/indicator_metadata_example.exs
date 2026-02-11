#!/usr/bin/env elixir
#
# Example usage of the new indicator output fields metadata feature
#
# Run this with: elixir -r lib/trading_strategy/strategy_editor/indicator_metadata_example.exs

alias TradingStrategy.StrategyEditor.IndicatorMetadata

IO.puts("\n=== Indicator Output Fields Metadata Examples ===\n")

# Example 1: Get complete metadata for Bollinger Bands
IO.puts("1. Bollinger Bands (multi-value indicator):")
{:ok, bb_metadata} = IndicatorMetadata.get("bollinger_bands")
IO.puts("   Type: #{bb_metadata.output_fields.type}")
IO.puts("   Fields:")
Enum.each(bb_metadata.output_fields.fields, fn field ->
  IO.puts("     - #{field.name}: #{field.description}")
end)

# Example 2: Check if indicator is multi-value
IO.puts("\n2. Checking indicator types:")
IO.puts("   Bollinger Bands is multi-value? #{IndicatorMetadata.multi_value?("bollinger_bands")}")
IO.puts("   SMA is multi-value? #{IndicatorMetadata.multi_value?("sma")}")
IO.puts("   MACD is multi-value? #{IndicatorMetadata.multi_value?("macd")}")

# Example 3: Validate field references
IO.puts("\n3. Validating field references:")
case IndicatorMetadata.validate_field("bollinger_bands", "upper_band") do
  :ok -> IO.puts("   ✓ bb_20.upper_band is valid")
  {:error, reason} -> IO.puts("   ✗ Error: #{reason}")
end

case IndicatorMetadata.validate_field("bollinger_bands", "invalid_field") do
  :ok -> IO.puts("   ✓ bb_20.invalid_field is valid")
  {:error, reason} -> IO.puts("   ✗ bb_20.invalid_field: #{reason}")
end

case IndicatorMetadata.validate_field("sma", nil) do
  :ok -> IO.puts("   ✓ sma_20 (no field access) is valid")
  {:error, reason} -> IO.puts("   ✗ Error: #{reason}")
end

# Example 4: Get formatted help text
IO.puts("\n4. Formatted help text for UI tooltips:")
{:ok, help} = IndicatorMetadata.format_help("macd")
IO.puts(help)

# Example 5: List all indicators
IO.puts("\n5. All available indicators:")
IndicatorMetadata.list_all()
|> Enum.take(10)
|> Enum.each(fn %{indicator: name, type: type} ->
  IO.puts("   #{name} (#{type})")
end)

IO.puts("\n=== End of Examples ===\n")
