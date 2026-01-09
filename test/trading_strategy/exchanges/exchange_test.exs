defmodule TradingStrategy.Exchanges.ExchangeTest do
  use ExUnit.Case, async: true

  import Mox

  alias TradingStrategy.Exchanges.Exchange

  # Define mock for CryptoExchange.API
  Mox.defmock(CryptoExchange.APIMock, for: CryptoExchange.APIBehaviour)

  setup :verify_on_exit!

  describe "connect_user/3" do
    test "successfully connects user with valid credentials" do
      user_id = "user_123"
      api_key = "test_api_key"
      api_secret = "test_api_secret"
      user_pid = spawn(fn -> :ok end)

      expect(CryptoExchange.APIMock, :connect_user, fn ^user_id, ^api_key, ^api_secret ->
        {:ok, user_pid}
      end)

      assert {:ok, ^user_pid} = Exchange.connect_user(user_id, api_key, api_secret)
    end

    test "returns error when connection fails" do
      user_id = "user_123"
      api_key = "invalid_key"
      api_secret = "invalid_secret"

      expect(CryptoExchange.APIMock, :connect_user, fn ^user_id, ^api_key, ^api_secret ->
        {:error, :invalid_credentials}
      end)

      assert {:error, :invalid_credentials} = Exchange.connect_user(user_id, api_key, api_secret)
    end

    test "returns error when exchange is unavailable" do
      user_id = "user_123"
      api_key = "test_api_key"
      api_secret = "test_api_secret"

      expect(CryptoExchange.APIMock, :connect_user, fn ^user_id, ^api_key, ^api_secret ->
        {:error, :exchange_unavailable}
      end)

      assert {:error, :exchange_unavailable} = Exchange.connect_user(user_id, api_key, api_secret)
    end
  end

  describe "place_order/2" do
    test "successfully places a market buy order" do
      user_id = "user_123"

      order_params = %{
        symbol: "BTCUSDT",
        side: :BUY,
        type: :MARKET,
        quantity: Decimal.new("0.001")
      }

      expected_response = %{
        order_id: "order_12345",
        symbol: "BTCUSDT",
        status: "FILLED",
        price: Decimal.new("50000.00"),
        quantity: Decimal.new("0.001")
      }

      expect(CryptoExchange.APIMock, :place_order, fn ^user_id, ^order_params ->
        {:ok, expected_response}
      end)

      assert {:ok, response} = Exchange.place_order(user_id, order_params)
      assert response.order_id == "order_12345"
      assert response.status == "FILLED"
    end

    test "successfully places a limit sell order" do
      user_id = "user_123"

      order_params = %{
        symbol: "ETHUSDT",
        side: :SELL,
        type: :LIMIT,
        quantity: Decimal.new("1.5"),
        price: Decimal.new("3000.00")
      }

      expected_response = %{
        order_id: "order_67890",
        symbol: "ETHUSDT",
        status: "NEW",
        price: Decimal.new("3000.00"),
        quantity: Decimal.new("1.5")
      }

      expect(CryptoExchange.APIMock, :place_order, fn ^user_id, ^order_params ->
        {:ok, expected_response}
      end)

      assert {:ok, response} = Exchange.place_order(user_id, order_params)
      assert response.order_id == "order_67890"
      assert response.status == "NEW"
    end

    test "returns error when order is rejected due to insufficient funds" do
      user_id = "user_123"

      order_params = %{
        symbol: "BTCUSDT",
        side: :BUY,
        type: :MARKET,
        quantity: Decimal.new("100.0")
      }

      expect(CryptoExchange.APIMock, :place_order, fn ^user_id, ^order_params ->
        {:error, :insufficient_balance}
      end)

      assert {:error, :insufficient_balance} = Exchange.place_order(user_id, order_params)
    end

    test "returns error when symbol is invalid" do
      user_id = "user_123"

      order_params = %{
        symbol: "INVALID",
        side: :BUY,
        type: :MARKET,
        quantity: Decimal.new("0.001")
      }

      expect(CryptoExchange.APIMock, :place_order, fn ^user_id, ^order_params ->
        {:error, :invalid_symbol}
      end)

      assert {:error, :invalid_symbol} = Exchange.place_order(user_id, order_params)
    end

    test "returns error when order quantity is too small" do
      user_id = "user_123"

      order_params = %{
        symbol: "BTCUSDT",
        side: :BUY,
        type: :MARKET,
        quantity: Decimal.new("0.00000001")
      }

      expect(CryptoExchange.APIMock, :place_order, fn ^user_id, ^order_params ->
        {:error, :min_notional_not_met}
      end)

      assert {:error, :min_notional_not_met} = Exchange.place_order(user_id, order_params)
    end

    test "returns error when rate limited" do
      user_id = "user_123"

      order_params = %{
        symbol: "BTCUSDT",
        side: :BUY,
        type: :MARKET,
        quantity: Decimal.new("0.001")
      }

      expect(CryptoExchange.APIMock, :place_order, fn ^user_id, ^order_params ->
        {:error, :rate_limited}
      end)

      assert {:error, :rate_limited} = Exchange.place_order(user_id, order_params)
    end
  end

  describe "cancel_order/3" do
    test "successfully cancels an existing order" do
      user_id = "user_123"
      symbol = "BTCUSDT"
      order_id = "order_12345"

      expected_response = %{
        order_id: "order_12345",
        status: "CANCELED"
      }

      expect(CryptoExchange.APIMock, :cancel_order, fn ^user_id, ^symbol, ^order_id ->
        {:ok, expected_response}
      end)

      assert {:ok, response} = Exchange.cancel_order(user_id, symbol, order_id)
      assert response.status == "CANCELED"
    end

    test "returns error when order is already filled" do
      user_id = "user_123"
      symbol = "BTCUSDT"
      order_id = "order_12345"

      expect(CryptoExchange.APIMock, :cancel_order, fn ^user_id, ^symbol, ^order_id ->
        {:error, :order_already_filled}
      end)

      assert {:error, :order_already_filled} = Exchange.cancel_order(user_id, symbol, order_id)
    end

    test "returns error when order does not exist" do
      user_id = "user_123"
      symbol = "BTCUSDT"
      order_id = "nonexistent_order"

      expect(CryptoExchange.APIMock, :cancel_order, fn ^user_id, ^symbol, ^order_id ->
        {:error, :order_not_found}
      end)

      assert {:error, :order_not_found} = Exchange.cancel_order(user_id, symbol, order_id)
    end
  end

  describe "get_balance/1" do
    test "successfully retrieves account balances" do
      user_id = "user_123"

      expected_balances = [
        %{asset: "BTC", free: Decimal.new("1.5"), locked: Decimal.new("0.1")},
        %{asset: "USDT", free: Decimal.new("10000"), locked: Decimal.new("500")},
        %{asset: "ETH", free: Decimal.new("25.0"), locked: Decimal.new("0.0")}
      ]

      expect(CryptoExchange.APIMock, :get_balance, fn ^user_id ->
        {:ok, expected_balances}
      end)

      assert {:ok, balances} = Exchange.get_balance(user_id)
      assert length(balances) == 3
      assert Enum.any?(balances, fn b -> b.asset == "BTC" end)
    end

    test "returns empty list when account has no balances" do
      user_id = "user_123"

      expect(CryptoExchange.APIMock, :get_balance, fn ^user_id ->
        {:ok, []}
      end)

      assert {:ok, []} = Exchange.get_balance(user_id)
    end

    test "returns error when user is not connected" do
      user_id = "disconnected_user"

      expect(CryptoExchange.APIMock, :get_balance, fn ^user_id ->
        {:error, :user_not_connected}
      end)

      assert {:error, :user_not_connected} = Exchange.get_balance(user_id)
    end

    test "returns error when exchange API fails" do
      user_id = "user_123"

      expect(CryptoExchange.APIMock, :get_balance, fn ^user_id ->
        {:error, :api_error}
      end)

      assert {:error, :api_error} = Exchange.get_balance(user_id)
    end
  end

  describe "get_open_orders/2" do
    test "retrieves open orders for all symbols when symbol is nil" do
      user_id = "user_123"

      expected_orders = [
        %{order_id: "order_1", symbol: "BTCUSDT", status: "NEW"},
        %{order_id: "order_2", symbol: "ETHUSDT", status: "PARTIALLY_FILLED"}
      ]

      expect(CryptoExchange.APIMock, :get_open_orders, fn ^user_id, nil ->
        {:ok, expected_orders}
      end)

      assert {:ok, orders} = Exchange.get_open_orders(user_id, nil)
      assert length(orders) == 2
    end

    test "retrieves open orders for specific symbol" do
      user_id = "user_123"
      symbol = "BTCUSDT"

      expected_orders = [
        %{order_id: "order_1", symbol: "BTCUSDT", status: "NEW"}
      ]

      expect(CryptoExchange.APIMock, :get_open_orders, fn ^user_id, ^symbol ->
        {:ok, expected_orders}
      end)

      assert {:ok, orders} = Exchange.get_open_orders(user_id, symbol)
      assert length(orders) == 1
      assert hd(orders).symbol == "BTCUSDT"
    end

    test "returns empty list when no open orders exist" do
      user_id = "user_123"

      expect(CryptoExchange.APIMock, :get_open_orders, fn ^user_id, nil ->
        {:ok, []}
      end)

      assert {:ok, []} = Exchange.get_open_orders(user_id)
    end
  end

  describe "get_order_status/3" do
    test "successfully retrieves order status for filled order" do
      user_id = "user_123"
      symbol = "BTCUSDT"
      order_id = "order_12345"

      expected_status = %{
        order_id: "order_12345",
        symbol: "BTCUSDT",
        status: "FILLED",
        price: Decimal.new("50000.00"),
        quantity: Decimal.new("0.001")
      }

      expect(CryptoExchange.APIMock, :get_order_status, fn ^user_id, ^symbol, ^order_id ->
        {:ok, expected_status}
      end)

      assert {:ok, status} = Exchange.get_order_status(user_id, symbol, order_id)
      assert status.status == "FILLED"
    end

    test "successfully retrieves order status for partially filled order" do
      user_id = "user_123"
      symbol = "BTCUSDT"
      order_id = "order_12345"

      expected_status = %{
        order_id: "order_12345",
        status: "PARTIALLY_FILLED",
        filled_quantity: Decimal.new("0.0005"),
        quantity: Decimal.new("0.001")
      }

      expect(CryptoExchange.APIMock, :get_order_status, fn ^user_id, ^symbol, ^order_id ->
        {:ok, expected_status}
      end)

      assert {:ok, status} = Exchange.get_order_status(user_id, symbol, order_id)
      assert status.status == "PARTIALLY_FILLED"
    end

    test "returns error when order does not exist" do
      user_id = "user_123"
      symbol = "BTCUSDT"
      order_id = "nonexistent_order"

      expect(CryptoExchange.APIMock, :get_order_status, fn ^user_id, ^symbol, ^order_id ->
        {:error, :order_not_found}
      end)

      assert {:error, :order_not_found} = Exchange.get_order_status(user_id, symbol, order_id)
    end
  end
end
