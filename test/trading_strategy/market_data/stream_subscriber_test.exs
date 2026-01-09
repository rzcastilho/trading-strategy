defmodule TradingStrategy.MarketData.StreamSubscriberTest do
  use ExUnit.Case, async: false

  alias TradingStrategy.MarketData.StreamSubscriber
  alias Phoenix.PubSub

  @moduletag :capture_log

  setup do
    # Start the GenServer for testing
    {:ok, pid} = start_supervised(StreamSubscriber)

    %{subscriber_pid: pid}
  end

  describe "subscribe_ticker/2" do
    test "successfully subscribes to ticker updates", %{subscriber_pid: _pid} do
      # Mock successful API response
      expect_api_subscribe_ticker("BTCUSDT", {:ok, make_ref()})

      assert :ok = StreamSubscriber.subscribe_ticker("BTCUSDT")

      # Verify subscription is tracked
      assert ["BTCUSDT"] = StreamSubscriber.list_ticker_subscriptions()
    end

    test "handles subscription failure gracefully", %{subscriber_pid: _pid} do
      # Mock API failure
      expect_api_subscribe_ticker("INVALID", {:error, :connection_failed})

      assert {:error, :connection_failed} = StreamSubscriber.subscribe_ticker("INVALID")

      # Verify no subscription was added
      assert [] = StreamSubscriber.list_ticker_subscriptions()
    end

    test "returns ok when already subscribed to ticker", %{subscriber_pid: _pid} do
      expect_api_subscribe_ticker("BTCUSDT", {:ok, make_ref()})

      assert :ok = StreamSubscriber.subscribe_ticker("BTCUSDT")
      assert :ok = StreamSubscriber.subscribe_ticker("BTCUSDT")

      # Should still only have one subscription
      assert ["BTCUSDT"] = StreamSubscriber.list_ticker_subscriptions()
    end

    test "supports multiple ticker subscriptions", %{subscriber_pid: _pid} do
      expect_api_subscribe_ticker("BTCUSDT", {:ok, make_ref()})
      expect_api_subscribe_ticker("ETHUSDT", {:ok, make_ref()})

      assert :ok = StreamSubscriber.subscribe_ticker("BTCUSDT")
      assert :ok = StreamSubscriber.subscribe_ticker("ETHUSDT")

      subscriptions = StreamSubscriber.list_ticker_subscriptions()
      assert length(subscriptions) == 2
      assert "BTCUSDT" in subscriptions
      assert "ETHUSDT" in subscriptions
    end

    test "accepts custom exchange parameter", %{subscriber_pid: _pid} do
      expect_api_subscribe_ticker("BTCUSDT", {:ok, make_ref()})

      assert :ok = StreamSubscriber.subscribe_ticker("BTCUSDT", "kraken")
      assert ["BTCUSDT"] = StreamSubscriber.list_ticker_subscriptions()
    end
  end

  describe "subscribe_trades/2" do
    test "successfully subscribes to trade stream", %{subscriber_pid: _pid} do
      expect_api_subscribe_trades("BTCUSDT", {:ok, make_ref()})

      assert :ok = StreamSubscriber.subscribe_trades("BTCUSDT")

      assert ["BTCUSDT"] = StreamSubscriber.list_trade_subscriptions()
    end

    test "handles trade subscription failure", %{subscriber_pid: _pid} do
      expect_api_subscribe_trades("INVALID", {:error, :timeout})

      assert {:error, :timeout} = StreamSubscriber.subscribe_trades("INVALID")

      assert [] = StreamSubscriber.list_trade_subscriptions()
    end

    test "returns ok when already subscribed to trades", %{subscriber_pid: _pid} do
      expect_api_subscribe_trades("BTCUSDT", {:ok, make_ref()})

      assert :ok = StreamSubscriber.subscribe_trades("BTCUSDT")
      assert :ok = StreamSubscriber.subscribe_trades("BTCUSDT")

      assert ["BTCUSDT"] = StreamSubscriber.list_trade_subscriptions()
    end

    test "supports multiple trade subscriptions", %{subscriber_pid: _pid} do
      expect_api_subscribe_trades("BTCUSDT", {:ok, make_ref()})
      expect_api_subscribe_trades("ETHUSDT", {:ok, make_ref()})

      assert :ok = StreamSubscriber.subscribe_trades("BTCUSDT")
      assert :ok = StreamSubscriber.subscribe_trades("ETHUSDT")

      subscriptions = StreamSubscriber.list_trade_subscriptions()
      assert length(subscriptions) == 2
      assert "BTCUSDT" in subscriptions
      assert "ETHUSDT" in subscriptions
    end
  end

  describe "unsubscribe_ticker/1" do
    test "successfully unsubscribes from ticker", %{subscriber_pid: _pid} do
      expect_api_subscribe_ticker("BTCUSDT", {:ok, make_ref()})

      assert :ok = StreamSubscriber.subscribe_ticker("BTCUSDT")
      assert ["BTCUSDT"] = StreamSubscriber.list_ticker_subscriptions()

      assert :ok = StreamSubscriber.unsubscribe_ticker("BTCUSDT")
      assert [] = StreamSubscriber.list_ticker_subscriptions()
    end

    test "returns ok when unsubscribing from non-existent subscription", %{subscriber_pid: _pid} do
      assert :ok = StreamSubscriber.unsubscribe_ticker("NONEXISTENT")
    end
  end

  describe "unsubscribe_trades/1" do
    test "successfully unsubscribes from trades", %{subscriber_pid: _pid} do
      expect_api_subscribe_trades("BTCUSDT", {:ok, make_ref()})

      assert :ok = StreamSubscriber.subscribe_trades("BTCUSDT")
      assert ["BTCUSDT"] = StreamSubscriber.list_trade_subscriptions()

      assert :ok = StreamSubscriber.unsubscribe_trades("BTCUSDT")
      assert [] = StreamSubscriber.list_trade_subscriptions()
    end

    test "returns ok when unsubscribing from non-existent subscription", %{subscriber_pid: _pid} do
      assert :ok = StreamSubscriber.unsubscribe_trades("NONEXISTENT")
    end
  end

  describe "handle_info - ticker updates" do
    test "broadcasts ticker updates to PubSub", %{subscriber_pid: pid} do
      # Subscribe to PubSub topic
      PubSub.subscribe(TradingStrategy.PubSub, "ticker:BTCUSDT")

      ticker_data = %{
        symbol: "BTCUSDT",
        price: "43250.50",
        volume: "1234.56",
        timestamp: DateTime.utc_now()
      }

      # Send ticker update message to GenServer
      send(pid, {:ticker_update, "BTCUSDT", ticker_data})

      # Assert we receive the broadcast
      assert_receive {:ticker_update, "BTCUSDT", ^ticker_data}, 1000
    end

    test "handles multiple ticker updates", %{subscriber_pid: pid} do
      PubSub.subscribe(TradingStrategy.PubSub, "ticker:BTCUSDT")

      ticker_data_1 = %{price: "43250.50"}
      ticker_data_2 = %{price: "43260.75"}

      send(pid, {:ticker_update, "BTCUSDT", ticker_data_1})
      send(pid, {:ticker_update, "BTCUSDT", ticker_data_2})

      assert_receive {:ticker_update, "BTCUSDT", ^ticker_data_1}
      assert_receive {:ticker_update, "BTCUSDT", ^ticker_data_2}
    end
  end

  describe "handle_info - trade updates" do
    test "broadcasts trade updates to PubSub", %{subscriber_pid: pid} do
      PubSub.subscribe(TradingStrategy.PubSub, "trades:BTCUSDT")

      trade_data = %{
        trade_id: "12345",
        symbol: "BTCUSDT",
        price: "43250.50",
        quantity: "0.5",
        timestamp: DateTime.utc_now(),
        side: :buy
      }

      send(pid, {:trade_update, "BTCUSDT", trade_data})

      assert_receive {:trade_update, "BTCUSDT", ^trade_data}, 1000
    end

    test "handles multiple trade updates", %{subscriber_pid: pid} do
      PubSub.subscribe(TradingStrategy.PubSub, "trades:ETHUSDT")

      trade_1 = %{trade_id: "1", price: "2250.00"}
      trade_2 = %{trade_id: "2", price: "2255.00"}

      send(pid, {:trade_update, "ETHUSDT", trade_1})
      send(pid, {:trade_update, "ETHUSDT", trade_2})

      assert_receive {:trade_update, "ETHUSDT", ^trade_1}
      assert_receive {:trade_update, "ETHUSDT", ^trade_2}
    end
  end

  describe "handle_info - reconnection logic" do
    test "schedules reconnection on websocket disconnect", %{subscriber_pid: pid} do
      # Send disconnect message
      send(pid, {:websocket_disconnected, "BTCUSDT"})

      # Wait for reconnect attempt (mocked)
      Process.sleep(100)

      # The GenServer should still be alive
      assert Process.alive?(pid)
    end

    test "retries reconnection on failure", %{subscriber_pid: pid} do
      # Mock failed reconnection
      expect_api_subscribe_ticker("BTCUSDT", {:error, :still_down})

      # Trigger reconnection
      send(pid, {:reconnect_ticker, "BTCUSDT"})

      # Wait briefly
      Process.sleep(100)

      # GenServer should still be running
      assert Process.alive?(pid)
    end

    test "successfully reconnects ticker subscription", %{subscriber_pid: pid} do
      expect_api_subscribe_ticker("BTCUSDT", {:ok, make_ref()})

      send(pid, {:reconnect_ticker, "BTCUSDT"})

      # Wait for reconnection
      Process.sleep(100)

      # Should have subscription now
      assert "BTCUSDT" in StreamSubscriber.list_ticker_subscriptions()
    end
  end

  describe "list_ticker_subscriptions/0" do
    test "returns empty list when no subscriptions", %{subscriber_pid: _pid} do
      assert [] = StreamSubscriber.list_ticker_subscriptions()
    end

    test "returns all active ticker subscriptions", %{subscriber_pid: _pid} do
      expect_api_subscribe_ticker("BTCUSDT", {:ok, make_ref()})
      expect_api_subscribe_ticker("ETHUSDT", {:ok, make_ref()})

      StreamSubscriber.subscribe_ticker("BTCUSDT")
      StreamSubscriber.subscribe_ticker("ETHUSDT")

      subscriptions = StreamSubscriber.list_ticker_subscriptions()
      assert length(subscriptions) == 2
      assert "BTCUSDT" in subscriptions
      assert "ETHUSDT" in subscriptions
    end
  end

  describe "list_trade_subscriptions/0" do
    test "returns empty list when no subscriptions", %{subscriber_pid: _pid} do
      assert [] = StreamSubscriber.list_trade_subscriptions()
    end

    test "returns all active trade subscriptions", %{subscriber_pid: _pid} do
      expect_api_subscribe_trades("BTCUSDT", {:ok, make_ref()})
      expect_api_subscribe_trades("ETHUSDT", {:ok, make_ref()})

      StreamSubscriber.subscribe_trades("BTCUSDT")
      StreamSubscriber.subscribe_trades("ETHUSDT")

      subscriptions = StreamSubscriber.list_trade_subscriptions()
      assert length(subscriptions) == 2
      assert "BTCUSDT" in subscriptions
      assert "ETHUSDT" in subscriptions
    end
  end

  # Test helpers

  defp expect_api_subscribe_ticker(symbol, return_value) do
    # Mock CryptoExchange.API.subscribe_to_ticker/1
    # In a real implementation, you would use Mox or a similar library
    # For now, we'll stub the function behavior
    stub_crypto_exchange_api(:subscribe_to_ticker, fn ^symbol -> return_value end)
  end

  defp expect_api_subscribe_trades(symbol, return_value) do
    # Mock CryptoExchange.API.subscribe_to_trades/1
    stub_crypto_exchange_api(:subscribe_to_trades, fn ^symbol -> return_value end)
  end

  defp stub_crypto_exchange_api(function_name, stub_fn) do
    # This is a placeholder for actual mocking
    # In production, you would define a behaviour and use Mox
    # For this implementation, we'll need to ensure CryptoExchange.API
    # is mockable or create a test-only implementation

    # Store the stub in the process dictionary for retrieval in the module
    Process.put({CryptoExchange.API, function_name}, stub_fn)
  end
end
