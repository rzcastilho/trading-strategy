defmodule TradingStrategy.MarketData.CacheTest do
  use ExUnit.Case, async: false

  alias TradingStrategy.MarketData.Cache

  setup do
    # Start the cache GenServer
    start_supervised!(Cache)

    # Clear all data before each test
    Cache.clear_all()

    :ok
  end

  describe "put_ticker/2 and get_ticker/1" do
    test "stores and retrieves ticker data" do
      ticker_data = %{
        price: "43250.50",
        volume: "1234.56",
        bid: "43250.00",
        ask: "43251.00"
      }

      assert :ok = Cache.put_ticker("BTCUSDT", ticker_data)

      assert {:ok, {timestamp, data}} = Cache.get_ticker("BTCUSDT")
      assert %DateTime{} = timestamp
      assert data.price == "43250.50"
      assert data.volume == "1234.56"
    end

    test "updates existing ticker data" do
      ticker_1 = %{price: "43250.50"}
      ticker_2 = %{price: "43260.75"}

      Cache.put_ticker("BTCUSDT", ticker_1)
      Cache.put_ticker("BTCUSDT", ticker_2)

      {:ok, {_timestamp, data}} = Cache.get_ticker("BTCUSDT")
      assert data.price == "43260.75"
    end

    test "returns error for non-existent ticker" do
      assert {:error, :not_found} = Cache.get_ticker("NONEXISTENT")
    end

    test "supports multiple symbols" do
      Cache.put_ticker("BTCUSDT", %{price: "43250.50"})
      Cache.put_ticker("ETHUSDT", %{price: "2250.00"})

      assert {:ok, {_, btc_data}} = Cache.get_ticker("BTCUSDT")
      assert {:ok, {_, eth_data}} = Cache.get_ticker("ETHUSDT")

      assert btc_data.price == "43250.50"
      assert eth_data.price == "2250.00"
    end

    test "ticker includes timestamp" do
      Cache.put_ticker("BTCUSDT", %{price: "43250.50"})

      {:ok, {timestamp, _data}} = Cache.get_ticker("BTCUSDT")

      assert %DateTime{} = timestamp
      assert DateTime.diff(DateTime.utc_now(), timestamp, :second) < 2
    end
  end

  describe "get_latest_price/1" do
    test "retrieves only the price from ticker" do
      ticker_data = %{price: "43250.50", volume: "1234.56"}
      Cache.put_ticker("BTCUSDT", ticker_data)

      assert {:ok, "43250.50"} = Cache.get_latest_price("BTCUSDT")
    end

    test "handles ticker with string key" do
      ticker_data = %{"price" => "43250.50"}
      Cache.put_ticker("BTCUSDT", ticker_data)

      assert {:ok, "43250.50"} = Cache.get_latest_price("BTCUSDT")
    end

    test "returns error when ticker not found" do
      assert {:error, :not_found} = Cache.get_latest_price("NONEXISTENT")
    end
  end

  describe "get_latest/1" do
    test "is an alias for get_ticker/1" do
      ticker_data = %{price: "43250.50"}
      Cache.put_ticker("BTCUSDT", ticker_data)

      assert Cache.get_latest("BTCUSDT") == Cache.get_ticker("BTCUSDT")
    end
  end

  describe "put_trade/2 and get_trades/2" do
    test "stores and retrieves trade data" do
      trade_data = %{
        trade_id: "12345",
        price: "43250.50",
        quantity: "0.5",
        timestamp: DateTime.utc_now(),
        side: :buy
      }

      assert :ok = Cache.put_trade("BTCUSDT", trade_data)

      trades = Cache.get_trades("BTCUSDT")
      assert length(trades) == 1
      assert hd(trades).trade_id == "12345"
    end

    test "supports string trade_id key" do
      trade_data = %{
        "trade_id" => "12345",
        "price" => "43250.50"
      }

      assert :ok = Cache.put_trade("BTCUSDT", trade_data)

      trades = Cache.get_trades("BTCUSDT")
      assert length(trades) == 1
    end

    test "supports id key as fallback" do
      trade_data = %{
        id: "12345",
        price: "43250.50",
        timestamp: DateTime.utc_now()
      }

      assert :ok = Cache.put_trade("BTCUSDT", trade_data)

      trades = Cache.get_trades("BTCUSDT")
      assert length(trades) == 1
    end

    test "returns error when trade_id missing" do
      trade_data = %{price: "43250.50"}

      assert {:error, :missing_trade_id} = Cache.put_trade("BTCUSDT", trade_data)
    end

    test "maintains multiple trades for same symbol" do
      trade_1 = %{trade_id: "1", price: "43250.50", timestamp: DateTime.utc_now()}
      trade_2 = %{trade_id: "2", price: "43260.00", timestamp: DateTime.utc_now()}

      Cache.put_trade("BTCUSDT", trade_1)
      Cache.put_trade("BTCUSDT", trade_2)

      trades = Cache.get_trades("BTCUSDT")
      assert length(trades) == 2
    end

    test "returns trades sorted by timestamp descending" do
      timestamp_1 = DateTime.utc_now()
      Process.sleep(10)
      timestamp_2 = DateTime.utc_now()
      Process.sleep(10)
      timestamp_3 = DateTime.utc_now()

      Cache.put_trade("BTCUSDT", %{trade_id: "1", timestamp: timestamp_1})
      Cache.put_trade("BTCUSDT", %{trade_id: "2", timestamp: timestamp_3})
      Cache.put_trade("BTCUSDT", %{trade_id: "3", timestamp: timestamp_2})

      trades = Cache.get_trades("BTCUSDT")

      # Most recent first
      assert hd(trades).trade_id == "2"
    end

    test "respects limit parameter" do
      for i <- 1..20 do
        Cache.put_trade("BTCUSDT", %{
          trade_id: "#{i}",
          timestamp: DateTime.utc_now()
        })
      end

      trades = Cache.get_trades("BTCUSDT", 5)
      assert length(trades) == 5
    end

    test "returns empty list for symbol with no trades" do
      assert [] = Cache.get_trades("NONEXISTENT")
    end

    test "implements ring buffer - removes oldest trades" do
      # Put more than @max_trades_per_symbol (1000)
      for i <- 1..1100 do
        Cache.put_trade("BTCUSDT", %{
          trade_id: "#{i}",
          timestamp: DateTime.utc_now()
        })
      end

      trades = Cache.get_trades("BTCUSDT", 2000)

      # Should only keep 1000 most recent
      assert length(trades) <= 1000
    end
  end

  describe "put_candle/3 and get_candles/3" do
    test "stores and retrieves candle data" do
      candle_data = %{
        timestamp: ~U[2025-12-04 12:00:00Z],
        open: "43000.00",
        high: "43500.00",
        low: "42800.00",
        close: "43250.00",
        volume: "1234.56"
      }

      assert :ok = Cache.put_candle("BTCUSDT", "1h", candle_data)

      candles = Cache.get_candles("BTCUSDT", "1h")
      assert length(candles) == 1
      assert hd(candles).close == "43250.00"
    end

    test "returns error when timestamp missing" do
      candle_data = %{open: "43000.00", close: "43250.00"}

      assert {:error, :missing_timestamp} = Cache.put_candle("BTCUSDT", "1h", candle_data)
    end

    test "supports multiple timeframes for same symbol" do
      candle_1h = %{timestamp: ~U[2025-12-04 12:00:00Z], close: "43250.00"}
      candle_1m = %{timestamp: ~U[2025-12-04 12:00:00Z], close: "43260.00"}

      Cache.put_candle("BTCUSDT", "1h", candle_1h)
      Cache.put_candle("BTCUSDT", "1m", candle_1m)

      candles_1h = Cache.get_candles("BTCUSDT", "1h")
      candles_1m = Cache.get_candles("BTCUSDT", "1m")

      assert length(candles_1h) == 1
      assert length(candles_1m) == 1
      assert hd(candles_1h).close == "43250.00"
      assert hd(candles_1m).close == "43260.00"
    end

    test "returns candles sorted by timestamp ascending" do
      timestamp_1 = ~U[2025-12-04 10:00:00Z]
      timestamp_2 = ~U[2025-12-04 11:00:00Z]
      timestamp_3 = ~U[2025-12-04 12:00:00Z]

      Cache.put_candle("BTCUSDT", "1h", %{timestamp: timestamp_2, close: "43200.00"})
      Cache.put_candle("BTCUSDT", "1h", %{timestamp: timestamp_1, close: "43000.00"})
      Cache.put_candle("BTCUSDT", "1h", %{timestamp: timestamp_3, close: "43400.00"})

      candles = Cache.get_candles("BTCUSDT", "1h")

      # Oldest first
      assert hd(candles).close == "43000.00"
    end

    test "respects limit parameter" do
      for i <- 1..50 do
        timestamp = DateTime.add(~U[2025-12-04 00:00:00Z], i * 3600, :second)
        Cache.put_candle("BTCUSDT", "1h", %{timestamp: timestamp, close: "#{43000 + i}"})
      end

      candles = Cache.get_candles("BTCUSDT", "1h", 10)
      assert length(candles) == 10

      # Should return most recent 10
      last_candle = List.last(candles)
      assert String.to_integer(last_candle.close) > 43040
    end

    test "returns empty list for non-existent symbol/timeframe" do
      assert [] = Cache.get_candles("NONEXISTENT", "1h")
    end

    test "updates existing candle at same timestamp" do
      timestamp = ~U[2025-12-04 12:00:00Z]

      Cache.put_candle("BTCUSDT", "1h", %{timestamp: timestamp, close: "43000.00"})
      Cache.put_candle("BTCUSDT", "1h", %{timestamp: timestamp, close: "43250.00"})

      candles = Cache.get_candles("BTCUSDT", "1h")
      assert length(candles) == 1
      assert hd(candles).close == "43250.00"
    end
  end

  describe "clear_symbol/1" do
    test "clears all data for a symbol" do
      # Add ticker
      Cache.put_ticker("BTCUSDT", %{price: "43250.50"})

      # Add trades
      Cache.put_trade("BTCUSDT", %{trade_id: "1", timestamp: DateTime.utc_now()})

      # Add candles
      Cache.put_candle("BTCUSDT", "1h", %{
        timestamp: ~U[2025-12-04 12:00:00Z],
        close: "43250.00"
      })

      # Verify data exists
      assert {:ok, _} = Cache.get_ticker("BTCUSDT")
      assert length(Cache.get_trades("BTCUSDT")) == 1
      assert length(Cache.get_candles("BTCUSDT", "1h")) == 1

      # Clear
      assert :ok = Cache.clear_symbol("BTCUSDT")

      # Verify all cleared
      assert {:error, :not_found} = Cache.get_ticker("BTCUSDT")
      assert [] = Cache.get_trades("BTCUSDT")
      assert [] = Cache.get_candles("BTCUSDT", "1h")
    end

    test "does not affect other symbols" do
      Cache.put_ticker("BTCUSDT", %{price: "43250.50"})
      Cache.put_ticker("ETHUSDT", %{price: "2250.00"})

      Cache.clear_symbol("BTCUSDT")

      assert {:error, :not_found} = Cache.get_ticker("BTCUSDT")
      assert {:ok, _} = Cache.get_ticker("ETHUSDT")
    end
  end

  describe "clear_all/0" do
    test "clears all cached data" do
      Cache.put_ticker("BTCUSDT", %{price: "43250.50"})
      Cache.put_ticker("ETHUSDT", %{price: "2250.00"})
      Cache.put_trade("BTCUSDT", %{trade_id: "1", timestamp: DateTime.utc_now()})

      Cache.put_candle("BTCUSDT", "1h", %{
        timestamp: ~U[2025-12-04 12:00:00Z],
        close: "43250.00"
      })

      assert :ok = Cache.clear_all()

      assert {:error, :not_found} = Cache.get_ticker("BTCUSDT")
      assert {:error, :not_found} = Cache.get_ticker("ETHUSDT")
      assert [] = Cache.get_trades("BTCUSDT")
      assert [] = Cache.get_candles("BTCUSDT", "1h")
    end
  end

  describe "stats/0" do
    test "returns cache statistics" do
      stats = Cache.stats()

      assert is_map(stats)
      assert Map.has_key?(stats, :ticker_count)
      assert Map.has_key?(stats, :trade_count)
      assert Map.has_key?(stats, :candle_count)
      assert Map.has_key?(stats, :memory_bytes)
    end

    test "reflects current cache contents" do
      initial_stats = Cache.stats()

      Cache.put_ticker("BTCUSDT", %{price: "43250.50"})
      Cache.put_ticker("ETHUSDT", %{price: "2250.00"})

      updated_stats = Cache.stats()

      assert updated_stats.ticker_count == initial_stats.ticker_count + 2
    end

    test "counts trades correctly" do
      initial_stats = Cache.stats()

      Cache.put_trade("BTCUSDT", %{trade_id: "1", timestamp: DateTime.utc_now()})
      Cache.put_trade("BTCUSDT", %{trade_id: "2", timestamp: DateTime.utc_now()})

      updated_stats = Cache.stats()

      assert updated_stats.trade_count == initial_stats.trade_count + 2
    end

    test "counts candles correctly" do
      initial_stats = Cache.stats()

      Cache.put_candle("BTCUSDT", "1h", %{
        timestamp: ~U[2025-12-04 12:00:00Z],
        close: "43250.00"
      })

      Cache.put_candle("BTCUSDT", "1h", %{
        timestamp: ~U[2025-12-04 13:00:00Z],
        close: "43300.00"
      })

      updated_stats = Cache.stats()

      assert updated_stats.candle_count == initial_stats.candle_count + 2
    end

    test "reports memory usage" do
      stats = Cache.stats()

      assert is_integer(stats.memory_bytes)
      assert stats.memory_bytes > 0
    end
  end

  describe "concurrent access" do
    test "handles concurrent reads and writes" do
      # Spawn multiple processes writing to cache
      tasks =
        for i <- 1..50 do
          Task.async(fn ->
            Cache.put_ticker("BTCUSDT", %{price: "#{43000 + i}"})
            Cache.get_ticker("BTCUSDT")
          end)
        end

      results = Task.await_many(tasks)

      # All should succeed
      assert Enum.all?(results, fn
               {:ok, _} -> true
               _ -> false
             end)
    end

    test "handles concurrent trade writes" do
      tasks =
        for i <- 1..100 do
          Task.async(fn ->
            Cache.put_trade("BTCUSDT", %{trade_id: "#{i}", timestamp: DateTime.utc_now()})
          end)
        end

      Task.await_many(tasks)

      trades = Cache.get_trades("BTCUSDT", 200)
      assert length(trades) == 100
    end
  end

  describe "ETS table properties" do
    test "ticker table supports concurrent reads" do
      Cache.put_ticker("BTCUSDT", %{price: "43250.50"})

      # Multiple concurrent reads should all succeed
      tasks =
        for _ <- 1..100 do
          Task.async(fn -> Cache.get_ticker("BTCUSDT") end)
        end

      results = Task.await_many(tasks)
      assert Enum.all?(results, fn {:ok, _} -> true end)
    end

    test "maintains data integrity under load" do
      symbol = "BTCUSDT"
      initial_price = "43000.00"

      Cache.put_ticker(symbol, %{price: initial_price})

      # Concurrent updates
      tasks =
        for i <- 1..20 do
          Task.async(fn ->
            Cache.put_ticker(symbol, %{price: "#{43000 + i}"})
          end)
        end

      Task.await_many(tasks)

      # Should still be able to read valid data
      assert {:ok, {_timestamp, data}} = Cache.get_ticker(symbol)
      assert is_binary(data.price)
    end
  end
end
