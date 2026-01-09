defmodule TradingStrategy.Strategies.Indicators.RegistryTest do
  use ExUnit.Case, async: true
  alias TradingStrategy.Strategies.Indicators.Registry

  describe "build_registry/0" do
    test "builds registry with all indicators from TradingIndicators library" do
      registry = Registry.build_registry()

      assert is_map(registry)
      assert map_size(registry) > 0

      # Verify registry contains common indicators
      assert Map.has_key?(registry, "rsi")
      assert Map.has_key?(registry, "sma")
      assert Map.has_key?(registry, "ema")
      assert Map.has_key?(registry, "macd")
    end

    test "registry values are modules" do
      registry = Registry.build_registry()

      Enum.each(registry, fn {_name, module} ->
        assert is_atom(module)
        # Module should be from TradingIndicators namespace
        assert Module.split(module) |> List.first() == "TradingIndicators"
      end)
    end
  end

  describe "get_indicator_module/1" do
    test "returns module for valid indicator type (lowercase)" do
      assert {:ok, module} = Registry.get_indicator_module("rsi")
      assert is_atom(module)
      assert Module.split(module) |> List.last() == "RSI"
    end

    test "returns module for valid indicator type (uppercase)" do
      assert {:ok, module} = Registry.get_indicator_module("RSI")
      assert is_atom(module)
    end

    test "returns module for valid indicator type (mixed case)" do
      assert {:ok, module} = Registry.get_indicator_module("RsI")
      assert is_atom(module)
    end

    test "returns error for unknown indicator type" do
      assert {:error, message} = Registry.get_indicator_module("unknown_indicator")
      assert message =~ "Unknown indicator type"
      assert message =~ "Available indicators"
    end

    test "supports common indicator aliases" do
      # Bollinger Bands aliases
      {:ok, bb_module1} = Registry.get_indicator_module("bb")
      {:ok, bb_module2} = Registry.get_indicator_module("bollinger_bands")
      {:ok, bb_module3} = Registry.get_indicator_module("bollingerbands")
      assert bb_module1 == bb_module2
      assert bb_module2 == bb_module3

      # Moving average aliases
      {:ok, sma_module1} = Registry.get_indicator_module("sma")
      {:ok, sma_module2} = Registry.get_indicator_module("simple_moving_average")
      assert sma_module1 == sma_module2
    end
  end

  describe "list_available_indicators/0" do
    test "returns sorted list of indicator names" do
      indicators = Registry.list_available_indicators()

      assert is_list(indicators)
      assert length(indicators) > 0

      # Should be sorted
      assert indicators == Enum.sort(indicators)

      # Should contain common indicators
      assert "rsi" in indicators
      assert "sma" in indicators
      assert "ema" in indicators
      assert "macd" in indicators
    end

    test "returns unique indicator names" do
      indicators = Registry.list_available_indicators()

      unique_count = indicators |> Enum.uniq() |> length()
      assert unique_count == length(indicators)
    end
  end

  describe "get_indicator_metadata/1" do
    test "returns metadata for valid indicator" do
      assert {:ok, metadata} = Registry.get_indicator_metadata("rsi")

      assert is_map(metadata)
      assert Map.has_key?(metadata, :module)
      assert Map.has_key?(metadata, :category)
      assert Map.has_key?(metadata, :parameters)

      assert is_atom(metadata.module)
      assert is_atom(metadata.category)
      assert is_map(metadata.parameters)
    end

    test "metadata includes parameter information" do
      {:ok, metadata} = Registry.get_indicator_metadata("rsi")

      # RSI should have period parameter
      assert is_map(metadata.parameters)
      assert Map.has_key?(metadata.parameters, :period)

      period_meta = metadata.parameters.period
      assert Map.has_key?(period_meta, :type)
      assert Map.has_key?(period_meta, :default)
    end

    test "returns error for unknown indicator" do
      assert {:error, message} = Registry.get_indicator_metadata("unknown")
      assert message =~ "Unknown indicator type"
    end

    test "categorizes indicators correctly" do
      {:ok, rsi_meta} = Registry.get_indicator_metadata("rsi")
      assert rsi_meta.category == :momentum

      {:ok, sma_meta} = Registry.get_indicator_metadata("sma")
      assert sma_meta.category == :trend
    end
  end

  describe "caching behavior" do
    test "registry is cached using persistent_term" do
      # First call builds registry
      registry1 = Registry.build_registry()

      # Second call should return cached version
      registry2 = Registry.build_registry()

      # Should be the same reference (cached)
      assert registry1 == registry2
    end

    test "cached registry is accessible via persistent_term" do
      # Ensure registry is built
      _registry = Registry.build_registry()

      # Should be in persistent_term
      cached = :persistent_term.get(Registry, nil)
      assert cached != nil
      assert is_map(cached)
    end
  end
end
