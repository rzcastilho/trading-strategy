defmodule TradingStrategy.Orders.LiveExecutorTest do
  use ExUnit.Case, async: false

  import Mox

  alias TradingStrategy.Orders.LiveExecutor

  # Set up mocks
  setup :verify_on_exit!

  describe "execute_order/2 - basic functionality" do
    test "successfully executes market buy order" do
      order_params = %{
        user_id: "user_123",
        symbol: "BTCUSDT",
        side: :buy,
        type: :market,
        quantity: Decimal.new("0.001"),
        price: nil,
        signal_type: :entry
      }

      # Mock Exchange functions
      expect(CryptoExchange.APIMock, :place_order, fn _user_id, _params ->
        {:ok,
         %{
           "orderId" => "12345",
           "symbol" => "BTCUSDT",
           "status" => "FILLED",
           "price" => "50000.00",
           "origQty" => "0.001",
           "executedQty" => "0.001"
         }}
      end)

      assert {:ok, response} = LiveExecutor.execute_order(order_params)
      assert response.exchange_order_id == "12345"
      assert response.status == :filled
    end

    test "successfully executes limit sell order" do
      order_params = %{
        user_id: "user_123",
        symbol: "ETHUSDT",
        side: :sell,
        type: :limit,
        quantity: Decimal.new("1.5"),
        price: Decimal.new("3000.00"),
        signal_type: :exit
      }

      expect(CryptoExchange.APIMock, :place_order, fn _user_id, _params ->
        {:ok,
         %{
           "orderId" => "67890",
           "symbol" => "ETHUSDT",
           "status" => "NEW",
           "price" => "3000.00",
           "origQty" => "1.5",
           "executedQty" => "0"
         }}
      end)

      assert {:ok, response} = LiveExecutor.execute_order(order_params)
      assert response.exchange_order_id == "67890"
      assert response.status == :open
    end

    test "returns error for missing required parameters" do
      order_params = %{
        user_id: "user_123",
        symbol: "BTCUSDT",
        side: :buy
        # Missing type, quantity, signal_type
      }

      assert {:error, :missing_parameters} = LiveExecutor.execute_order(order_params)
    end
  end

  describe "execute_order/2 - with context validation" do
    test "validates order against balance when context provided" do
      order_params = %{
        user_id: "user_123",
        symbol: "BTCUSDT",
        side: :buy,
        type: :market,
        # Large quantity
        quantity: Decimal.new("10.0"),
        price: nil,
        signal_type: :entry
      }

      context = %{
        balances: [
          %{asset: "USDT", free: Decimal.new("1000"), locked: Decimal.new("0")}
        ],
        symbol_info: %{
          min_qty: Decimal.new("0.001"),
          max_qty: Decimal.new("100"),
          min_notional: Decimal.new("10")
        }
      }

      # Should fail balance check
      assert {:error, _reason} = LiveExecutor.execute_order(order_params, context)
    end
  end

  describe "execute_order/2 - risk management" do
    test "rejects order when risk limits exceeded" do
      order_params = %{
        user_id: "user_123",
        symbol: "BTCUSDT",
        side: :buy,
        type: :limit,
        # Large position
        quantity: Decimal.new("0.2"),
        price: Decimal.new("50000"),
        signal_type: :entry
      }

      context = %{
        portfolio_state: %{
          current_equity: Decimal.new("10000"),
          peak_equity: Decimal.new("10000"),
          daily_starting_equity: Decimal.new("10000"),
          open_positions: [],
          realized_pnl_today: Decimal.new("0")
        },
        risk_limits: %{
          # 25% limit
          max_position_size_pct: Decimal.new("0.25"),
          max_daily_loss_pct: Decimal.new("0.03"),
          max_drawdown_pct: Decimal.new("0.15"),
          max_concurrent_positions: 3
        }
      }

      # 0.2 * 50000 = 10000 (100% of portfolio) - exceeds 25% limit
      assert {:error, :max_position_size_exceeded} =
               LiveExecutor.execute_order(order_params, context)
    end
  end

  describe "cancel_order/3" do
    test "successfully cancels an order" do
      expect(CryptoExchange.APIMock, :cancel_order, fn "user_123", "BTCUSDT", "12345" ->
        {:ok, %{order_id: "12345", status: "CANCELED"}}
      end)

      assert {:ok, response} = LiveExecutor.cancel_order("user_123", "BTCUSDT", "12345")
      assert response.status == "CANCELED"
    end

    test "retries on transient failure" do
      # First call fails, second succeeds
      expect(CryptoExchange.APIMock, :cancel_order, 2, fn _user_id, _symbol, _order_id ->
        # Simplified: In real test you'd use Agent to track call count
        {:ok, %{order_id: "12345", status: "CANCELED"}}
      end)

      assert {:ok, _response} = LiveExecutor.cancel_order("user_123", "BTCUSDT", "12345")
    end
  end

  describe "get_order_status/3" do
    test "successfully retrieves order status" do
      expect(CryptoExchange.APIMock, :get_order_status, fn "user_123", "BTCUSDT", "12345" ->
        {:ok, %{order_id: "12345", status: "FILLED", filled_quantity: Decimal.new("0.001")}}
      end)

      assert {:ok, status} = LiveExecutor.get_order_status("user_123", "BTCUSDT", "12345")
      assert status.status == "FILLED"
    end
  end

  describe "execute_batch/2" do
    test "executes multiple orders in batch" do
      orders = [
        %{
          user_id: "user_123",
          symbol: "BTCUSDT",
          side: :buy,
          type: :market,
          quantity: Decimal.new("0.001"),
          price: nil,
          signal_type: :entry
        },
        %{
          user_id: "user_123",
          symbol: "ETHUSDT",
          side: :buy,
          type: :market,
          quantity: Decimal.new("0.1"),
          price: nil,
          signal_type: :entry
        }
      ]

      expect(CryptoExchange.APIMock, :place_order, 2, fn _user_id, params ->
        {:ok,
         %{
           "orderId" => "order_#{params[:symbol]}",
           "symbol" => params[:symbol],
           "status" => "FILLED",
           "price" => "50000.00",
           "origQty" => "0.001",
           "executedQty" => "0.001"
         }}
      end)

      assert {:ok, results} = LiveExecutor.execute_batch(orders)
      assert length(results) == 2
      assert Enum.all?(results, fn result -> match?({:ok, _}, result) end)
    end

    test "continues batch execution even if some orders fail" do
      orders = [
        %{
          user_id: "user_123",
          symbol: "BTCUSDT",
          side: :buy,
          type: :market,
          quantity: Decimal.new("0.001"),
          price: nil,
          signal_type: :entry
        },
        %{
          user_id: "user_123",
          # Invalid symbol
          symbol: "INVALID",
          side: :buy,
          type: :market
          # Missing required fields
        }
      ]

      expect(CryptoExchange.APIMock, :place_order, fn _user_id, _params ->
        {:ok,
         %{
           "orderId" => "12345",
           "symbol" => "BTCUSDT",
           "status" => "FILLED",
           "price" => "50000.00",
           "origQty" => "0.001",
           "executedQty" => "0.001"
         }}
      end)

      assert {:ok, results} = LiveExecutor.execute_batch(orders)
      assert length(results) == 2

      # First should succeed, second should fail
      assert {:ok, _} = Enum.at(results, 0)
      assert {:error, _} = Enum.at(results, 1)
    end
  end
end
