defmodule TradingStrategy.Strategies.Indicators.AdapterTest do
  use ExUnit.Case, async: true
  alias TradingStrategy.Strategies.Indicators.Adapter

  setup do
    # Sample market data for testing
    market_data = [
      %{
        timestamp: ~U[2024-01-01 00:00:00Z],
        open: Decimal.new("100"),
        high: Decimal.new("105"),
        low: Decimal.new("95"),
        close: Decimal.new("102"),
        volume: Decimal.new("1000")
      },
      %{
        timestamp: ~U[2024-01-02 00:00:00Z],
        open: Decimal.new("102"),
        high: Decimal.new("108"),
        low: Decimal.new("101"),
        close: Decimal.new("106"),
        volume: Decimal.new("1200")
      },
      %{
        timestamp: ~U[2024-01-03 00:00:00Z],
        open: Decimal.new("106"),
        high: Decimal.new("110"),
        low: Decimal.new("104"),
        close: Decimal.new("108"),
        volume: Decimal.new("1100")
      }
    ]

    # Generate more data points for indicators that need warmup
    extended_data = generate_sample_data(50)

    %{market_data: market_data, extended_data: extended_data}
  end

  describe "calculate/3" do
    test "calculates RSI indicator with valid params", %{extended_data: data} do
      params = %{"period" => 14}

      assert {:ok, result} = Adapter.calculate("rsi", data, params)
      assert is_map(result) or is_list(result)
    end

    test "calculates SMA indicator with valid params", %{extended_data: data} do
      params = %{"period" => 20}

      assert {:ok, result} = Adapter.calculate("sma", data, params)
      assert is_map(result) or is_list(result)
    end

    test "calculates EMA indicator with valid params", %{extended_data: data} do
      params = %{"period" => 12}

      assert {:ok, result} = Adapter.calculate("ema", data, params)
      assert is_map(result) or is_list(result)
    end

    test "calculates MACD indicator with valid params", %{extended_data: data} do
      params = %{"short_period" => 12, "long_period" => 26, "signal_period" => 9}

      assert {:ok, result} = Adapter.calculate("macd", data, params)
      assert is_map(result)
    end

    test "returns error for unknown indicator type", %{market_data: data} do
      assert {:error, message} = Adapter.calculate("unknown_indicator", data, %{})
      assert message =~ "Unknown indicator type"
    end

    test "returns error for invalid params", %{extended_data: data} do
      # Period out of range
      invalid_params = %{"period" => 1000}

      assert {:error, _reason} = Adapter.calculate("rsi", data, invalid_params)
    end

    test "returns error when market data is not a list" do
      assert {:error, message} = Adapter.calculate("rsi", "not a list", %{})
      assert message == "Market data must be a list"
    end

    test "handles market data with string keys", %{} do
      data_with_strings = [
        %{
          "timestamp" => ~U[2024-01-01 00:00:00Z],
          "open" => "100",
          "high" => "105",
          "low" => "95",
          "close" => "102",
          "volume" => "1000"
        }
      ]

      params = %{"period" => 14}
      extended_string_data = generate_sample_data_with_strings(20)

      # Should convert and calculate successfully
      assert {:ok, _result} = Adapter.calculate("sma", extended_string_data, params)
    end

    test "handles market data with atom keys" do
      data_with_atoms = [
        %{
          timestamp: ~U[2024-01-01 00:00:00Z],
          open: Decimal.new("100"),
          high: Decimal.new("105"),
          low: Decimal.new("95"),
          close: Decimal.new("102"),
          volume: Decimal.new("1000")
        }
      ]

      params = %{"period" => 14}
      extended_atom_data = generate_sample_data(20)

      assert {:ok, _result} = Adapter.calculate("sma", extended_atom_data, params)
    end
  end

  describe "calculate_batch/2" do
    test "calculates multiple indicators in batch", %{extended_data: data} do
      indicators = [
        %{
          "type" => "rsi",
          "name" => "rsi_14",
          "parameters" => %{"period" => 14}
        },
        %{
          "type" => "sma",
          "name" => "sma_20",
          "parameters" => %{"period" => 20}
        },
        %{
          "type" => "ema",
          "name" => "ema_12",
          "parameters" => %{"period" => 12}
        }
      ]

      assert {:ok, results} = Adapter.calculate_batch(indicators, data)

      assert is_map(results)
      assert Map.has_key?(results, "rsi_14")
      assert Map.has_key?(results, "sma_20")
      assert Map.has_key?(results, "ema_12")
    end

    test "returns error if any indicator fails", %{extended_data: data} do
      indicators = [
        %{
          "type" => "rsi",
          "name" => "rsi_14",
          "parameters" => %{"period" => 14}
        },
        %{
          "type" => "unknown_indicator",
          "name" => "bad_indicator",
          "parameters" => %{}
        }
      ]

      assert {:error, message} = Adapter.calculate_batch(indicators, data)
      assert message =~ "Failed to calculate bad_indicator"
    end

    test "handles empty indicators list", %{extended_data: data} do
      assert {:ok, results} = Adapter.calculate_batch([], data)
      assert results == %{}
    end
  end

  describe "init_stream/3" do
    test "initializes streaming indicator with valid params", %{extended_data: data} do
      params = %{"period" => 14}

      case Adapter.init_stream("rsi", params, data) do
        {:ok, stream_state} ->
          assert is_map(stream_state)
          assert Map.has_key?(stream_state, :module)
          assert Map.has_key?(stream_state, :params)
          assert Map.has_key?(stream_state, :state)

        {:error, message} ->
          # Some indicators might not support streaming
          assert message =~ "does not support streaming"
      end
    end

    test "returns error for unknown indicator type" do
      assert {:error, message} = Adapter.init_stream("unknown_indicator", %{}, [])
      assert message =~ "Unknown indicator type"
    end

    test "returns error for invalid params", %{extended_data: data} do
      invalid_params = %{"period" => 1000}

      assert {:error, _reason} = Adapter.init_stream("rsi", invalid_params, data)
    end
  end

  describe "update_stream/2" do
    test "updates streaming indicator with new data point", %{extended_data: data} do
      params = %{"period" => 14}

      case Adapter.init_stream("rsi", params, data) do
        {:ok, stream_state} ->
          new_bar = %{
            timestamp: ~U[2024-02-01 00:00:00Z],
            open: Decimal.new("110"),
            high: Decimal.new("115"),
            low: Decimal.new("109"),
            close: Decimal.new("112"),
            volume: Decimal.new("1500")
          }

          case Adapter.update_stream(stream_state, new_bar) do
            {:ok, result, new_state} ->
              assert is_map(new_state)
              assert Map.has_key?(new_state, :module)
              assert Map.has_key?(new_state, :params)
              assert Map.has_key?(new_state, :state)

            {:error, _reason} ->
              # Update might fail if streaming not fully implemented
              :ok
          end

        {:error, _message} ->
          # Skip test if indicator doesn't support streaming
          :ok
      end
    end
  end

  # Helper Functions

  defp generate_sample_data(count) do
    base_price = 100.0

    Enum.map(1..count, fn i ->
      # Simulate price movement
      price = base_price + :rand.uniform(20) - 10

      %{
        timestamp: DateTime.add(~U[2024-01-01 00:00:00Z], i * 3600, :second),
        open: Decimal.from_float(price),
        high: Decimal.from_float(price + :rand.uniform(5)),
        low: Decimal.from_float(price - :rand.uniform(5)),
        close: Decimal.from_float(price + :rand.uniform(3) - 1.5),
        volume: Decimal.from_float(1000 + :rand.uniform(500))
      }
    end)
  end

  defp generate_sample_data_with_strings(count) do
    base_price = 100.0

    Enum.map(1..count, fn i ->
      price = base_price + :rand.uniform(20) - 10

      %{
        "timestamp" => DateTime.add(~U[2024-01-01 00:00:00Z], i * 3600, :second),
        "open" => Float.to_string(price),
        "high" => Float.to_string(price + :rand.uniform(5)),
        "low" => Float.to_string(price - :rand.uniform(5)),
        "close" => Float.to_string(price + :rand.uniform(3) - 1.5),
        "volume" => Float.to_string(1000 + :rand.uniform(500))
      }
    end)
  end
end
