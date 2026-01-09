defmodule TradingStrategy.Exchanges.OrderAdapterTest do
  use ExUnit.Case, async: true

  alias TradingStrategy.Exchanges.OrderAdapter

  describe "normalize_symbol/1" do
    test "converts BTC/USDT to BTCUSDT" do
      assert {:ok, "BTCUSDT"} = OrderAdapter.normalize_symbol("BTC/USDT")
    end

    test "converts ETH/BTC to ETHBTC" do
      assert {:ok, "ETHBTC"} = OrderAdapter.normalize_symbol("ETH/BTC")
    end

    test "converts SOL/USD to SOLUSD" do
      assert {:ok, "SOLUSD"} = OrderAdapter.normalize_symbol("SOL/USD")
    end

    test "returns error for invalid symbol (too short)" do
      assert {:error, :invalid_symbol} = OrderAdapter.normalize_symbol("BTC/U")
    end

    test "returns error for non-string input" do
      assert {:error, :invalid_symbol} = OrderAdapter.normalize_symbol(12345)
    end

    test "returns error for nil input" do
      assert {:error, :invalid_symbol} = OrderAdapter.normalize_symbol(nil)
    end
  end

  describe "normalize_side/1" do
    test "converts :buy to :BUY" do
      assert {:ok, :BUY} = OrderAdapter.normalize_side(:buy)
    end

    test "converts :sell to :SELL" do
      assert {:ok, :SELL} = OrderAdapter.normalize_side(:sell)
    end

    test "returns error for invalid side" do
      assert {:error, :invalid_side} = OrderAdapter.normalize_side(:invalid)
    end

    test "returns error for string input" do
      assert {:error, :invalid_side} = OrderAdapter.normalize_side("buy")
    end
  end

  describe "normalize_type/1" do
    test "converts :market to :MARKET" do
      assert {:ok, :MARKET} = OrderAdapter.normalize_type(:market)
    end

    test "converts :limit to :LIMIT" do
      assert {:ok, :LIMIT} = OrderAdapter.normalize_type(:limit)
    end

    test "converts :stop_loss to :STOP_LOSS" do
      assert {:ok, :STOP_LOSS} = OrderAdapter.normalize_type(:stop_loss)
    end

    test "returns error for invalid type" do
      assert {:error, :invalid_type} = OrderAdapter.normalize_type(:invalid)
    end
  end

  describe "validate_quantity/1" do
    test "accepts positive decimal quantity" do
      assert :ok = OrderAdapter.validate_quantity(Decimal.new("0.001"))
    end

    test "accepts large quantity" do
      assert :ok = OrderAdapter.validate_quantity(Decimal.new("1000.5"))
    end

    test "rejects zero quantity" do
      assert {:error, :invalid_quantity} = OrderAdapter.validate_quantity(Decimal.new("0"))
    end

    test "rejects negative quantity" do
      assert {:error, :invalid_quantity} = OrderAdapter.validate_quantity(Decimal.new("-1.5"))
    end
  end

  describe "validate_price/2" do
    test "market orders don't require price" do
      assert :ok = OrderAdapter.validate_price(:market, nil)
    end

    test "limit orders require price" do
      assert {:error, :price_required} = OrderAdapter.validate_price(:limit, nil)
    end

    test "stop_loss orders require price" do
      assert {:error, :price_required} = OrderAdapter.validate_price(:stop_loss, nil)
    end

    test "accepts positive price for limit orders" do
      assert :ok = OrderAdapter.validate_price(:limit, Decimal.new("50000.00"))
    end

    test "accepts positive price for stop_loss orders" do
      assert :ok = OrderAdapter.validate_price(:stop_loss, Decimal.new("48000.00"))
    end

    test "rejects zero price for limit orders" do
      assert {:error, :invalid_price} = OrderAdapter.validate_price(:limit, Decimal.new("0"))
    end

    test "rejects negative price for limit orders" do
      assert {:error, :invalid_price} = OrderAdapter.validate_price(:limit, Decimal.new("-100"))
    end

    test "rejects non-Decimal price" do
      assert {:error, :invalid_price} = OrderAdapter.validate_price(:limit, "50000")
    end
  end

  describe "translate_order/1" do
    test "successfully translates market buy order" do
      internal_order = %{
        trading_pair: "BTC/USDT",
        side: :buy,
        type: :market,
        quantity: Decimal.new("0.001"),
        price: nil,
        signal_type: :entry
      }

      assert {:ok, exchange_params} = OrderAdapter.translate_order(internal_order)
      assert exchange_params.symbol == "BTCUSDT"
      assert exchange_params.side == :BUY
      assert exchange_params.type == :MARKET
      assert Decimal.equal?(exchange_params.quantity, Decimal.new("0.001"))
      assert exchange_params.price == nil
    end

    test "successfully translates limit sell order" do
      internal_order = %{
        trading_pair: "ETH/BTC",
        side: :sell,
        type: :limit,
        quantity: Decimal.new("2.5"),
        price: Decimal.new("0.065"),
        signal_type: :exit
      }

      assert {:ok, exchange_params} = OrderAdapter.translate_order(internal_order)
      assert exchange_params.symbol == "ETHBTC"
      assert exchange_params.side == :SELL
      assert exchange_params.type == :LIMIT
      assert Decimal.equal?(exchange_params.quantity, Decimal.new("2.5"))
      assert Decimal.equal?(exchange_params.price, Decimal.new("0.065"))
    end

    test "successfully translates stop_loss order" do
      internal_order = %{
        trading_pair: "BTC/USDT",
        side: :sell,
        type: :stop_loss,
        quantity: Decimal.new("0.5"),
        price: Decimal.new("45000.00"),
        signal_type: :stop
      }

      assert {:ok, exchange_params} = OrderAdapter.translate_order(internal_order)
      assert exchange_params.symbol == "BTCUSDT"
      assert exchange_params.side == :SELL
      assert exchange_params.type == :STOP_LOSS
      assert Decimal.equal?(exchange_params.price, Decimal.new("45000.00"))
    end

    test "returns error for invalid trading pair" do
      internal_order = %{
        trading_pair: "INVALID",
        side: :buy,
        type: :market,
        quantity: Decimal.new("0.001"),
        price: nil,
        signal_type: :entry
      }

      assert {:error, :invalid_symbol} = OrderAdapter.translate_order(internal_order)
    end

    test "returns error for invalid side" do
      internal_order = %{
        trading_pair: "BTC/USDT",
        side: :invalid_side,
        type: :market,
        quantity: Decimal.new("0.001"),
        price: nil,
        signal_type: :entry
      }

      assert {:error, :invalid_side} = OrderAdapter.translate_order(internal_order)
    end

    test "returns error for invalid type" do
      internal_order = %{
        trading_pair: "BTC/USDT",
        side: :buy,
        type: :invalid_type,
        quantity: Decimal.new("0.001"),
        price: nil,
        signal_type: :entry
      }

      assert {:error, :invalid_type} = OrderAdapter.translate_order(internal_order)
    end

    test "returns error for zero quantity" do
      internal_order = %{
        trading_pair: "BTC/USDT",
        side: :buy,
        type: :market,
        quantity: Decimal.new("0"),
        price: nil,
        signal_type: :entry
      }

      assert {:error, :invalid_quantity} = OrderAdapter.translate_order(internal_order)
    end

    test "returns error for limit order without price" do
      internal_order = %{
        trading_pair: "BTC/USDT",
        side: :buy,
        type: :limit,
        quantity: Decimal.new("0.001"),
        price: nil,
        signal_type: :entry
      }

      assert {:error, :price_required} = OrderAdapter.translate_order(internal_order)
    end
  end

  describe "translate_response/1" do
    test "translates Binance response with string keys to internal format" do
      exchange_response = %{
        "orderId" => "12345",
        "symbol" => "BTCUSDT",
        "status" => "FILLED",
        "price" => "50000.00",
        "origQty" => "0.001",
        "executedQty" => "0.001"
      }

      internal_response = OrderAdapter.translate_response(exchange_response)

      assert internal_response.exchange_order_id == "12345"
      assert internal_response.symbol == "BTCUSDT"
      assert internal_response.status == :filled
      assert internal_response.price == "50000.00"
      assert internal_response.quantity == "0.001"
      assert Decimal.equal?(internal_response.filled_quantity, Decimal.new("0.001"))
    end

    test "translates response with atom keys to internal format" do
      exchange_response = %{
        order_id: "67890",
        symbol: "ETHUSDT",
        status: "NEW",
        price: "3000.00",
        quantity: "1.5",
        filled_quantity: Decimal.new("0")
      }

      internal_response = OrderAdapter.translate_response(exchange_response)

      assert internal_response.exchange_order_id == "67890"
      assert internal_response.symbol == "ETHUSDT"
      assert internal_response.status == :open
      assert internal_response.price == "3000.00"
    end

    test "translates PARTIALLY_FILLED status correctly" do
      exchange_response = %{
        "orderId" => "12345",
        "symbol" => "BTCUSDT",
        "status" => "PARTIALLY_FILLED",
        "price" => "50000.00",
        "origQty" => "0.002",
        "executedQty" => "0.001"
      }

      internal_response = OrderAdapter.translate_response(exchange_response)
      assert internal_response.status == :partially_filled
    end

    test "translates CANCELED status correctly" do
      exchange_response = %{
        "orderId" => "12345",
        "symbol" => "BTCUSDT",
        "status" => "CANCELED",
        "price" => "50000.00",
        "origQty" => "0.001",
        "executedQty" => "0"
      }

      internal_response = OrderAdapter.translate_response(exchange_response)
      assert internal_response.status == :cancelled
    end

    test "translates EXPIRED status to cancelled" do
      exchange_response = %{
        "orderId" => "12345",
        "symbol" => "BTCUSDT",
        "status" => "EXPIRED",
        "price" => "50000.00",
        "origQty" => "0.001",
        "executedQty" => "0"
      }

      internal_response = OrderAdapter.translate_response(exchange_response)
      assert internal_response.status == :cancelled
    end

    test "translates REJECTED status correctly" do
      exchange_response = %{
        "orderId" => "12345",
        "symbol" => "BTCUSDT",
        "status" => "REJECTED",
        "price" => "50000.00",
        "origQty" => "0.001",
        "executedQty" => "0"
      }

      internal_response = OrderAdapter.translate_response(exchange_response)
      assert internal_response.status == :rejected
    end

    test "handles missing executedQty field with default zero" do
      exchange_response = %{
        "orderId" => "12345",
        "symbol" => "BTCUSDT",
        "status" => "NEW",
        "price" => "50000.00",
        "origQty" => "0.001"
      }

      internal_response = OrderAdapter.translate_response(exchange_response)
      assert Decimal.equal?(internal_response.filled_quantity, Decimal.new("0"))
    end

    test "sets timestamp to current UTC time" do
      exchange_response = %{
        "orderId" => "12345",
        "symbol" => "BTCUSDT",
        "status" => "FILLED",
        "price" => "50000.00",
        "origQty" => "0.001",
        "executedQty" => "0.001"
      }

      before_call = DateTime.utc_now()
      internal_response = OrderAdapter.translate_response(exchange_response)
      after_call = DateTime.utc_now()

      assert DateTime.compare(internal_response.timestamp, before_call) in [:gt, :eq]
      assert DateTime.compare(internal_response.timestamp, after_call) in [:lt, :eq]
    end
  end
end
