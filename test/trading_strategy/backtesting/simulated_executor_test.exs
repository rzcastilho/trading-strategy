defmodule TradingStrategy.Backtesting.SimulatedExecutorTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias TradingStrategy.Backtesting.SimulatedExecutor

  describe "slippage calculation" do
    test "applies positive slippage to buy orders (price increases)" do
      bar = %{
        timestamp: ~U[2024-01-01 10:00:00Z],
        open: 50_000.0,
        high: 51_000.0,
        low: 49_000.0,
        close: 50_500.0,
        volume: 100.0
      }

      order = %{
        side: :buy,
        quantity: 0.1,
        price: 50_000.0
      }

      config = %{
        slippage_pct: 0.1,  # 0.1% slippage
        commission_pct: 0.0
      }

      {:ok, executed_trade} = SimulatedExecutor.execute(order, bar, config)

      # Expected price with slippage: 50_000 * (1 + 0.001) = 50_050
      expected_price = 50_000.0 * 1.001

      assert_in_delta executed_trade.price, expected_price, 0.01
      assert executed_trade.quantity == 0.1
      assert executed_trade.side == :buy
      assert executed_trade.timestamp == bar.timestamp
    end

    test "applies negative slippage to sell orders (price decreases)" do
      bar = %{
        timestamp: ~U[2024-01-01 10:00:00Z],
        open: 50_000.0,
        high: 51_000.0,
        low: 49_000.0,
        close: 50_500.0,
        volume: 100.0
      }

      order = %{
        side: :sell,
        quantity: 0.1,
        price: 50_000.0
      }

      config = %{
        slippage_pct: 0.1,  # 0.1% slippage
        commission_pct: 0.0
      }

      {:ok, executed_trade} = SimulatedExecutor.execute(order, bar, config)

      # Expected price with slippage: 50_000 * (1 - 0.001) = 49_950
      expected_price = 50_000.0 * 0.999

      assert_in_delta executed_trade.price, expected_price, 0.01
      assert executed_trade.quantity == 0.1
      assert executed_trade.side == :sell
    end

    test "zero slippage results in exact order price" do
      bar = %{
        timestamp: ~U[2024-01-01 10:00:00Z],
        open: 50_000.0,
        high: 51_000.0,
        low: 49_000.0,
        close: 50_500.0,
        volume: 100.0
      }

      order = %{
        side: :buy,
        quantity: 0.1,
        price: 50_000.0
      }

      config = %{
        slippage_pct: 0.0,
        commission_pct: 0.0
      }

      {:ok, executed_trade} = SimulatedExecutor.execute(order, bar, config)

      assert executed_trade.price == 50_000.0
    end

    property "slippage increases cost for buys and decreases revenue for sells" do
      check all price <- float(min: 100.0, max: 100_000.0),
                slippage_pct <- float(min: 0.0, max: 2.0),
                quantity <- float(min: 0.001, max: 10.0),
                side <- member_of([:buy, :sell]),
                max_runs: 100 do

        bar = %{
          timestamp: ~U[2024-01-01 10:00:00Z],
          open: price,
          high: price * 1.01,
          low: price * 0.99,
          close: price,
          volume: 100.0
        }

        order = %{side: side, quantity: quantity, price: price}
        config = %{slippage_pct: slippage_pct, commission_pct: 0.0}

        {:ok, trade} = SimulatedExecutor.execute(order, bar, config)

        case side do
          :buy ->
            # With slippage, buy price should be higher (worse for buyer)
            if slippage_pct > 0 do
              assert trade.price >= price, "Buy with slippage should have higher price"
            else
              assert trade.price == price
            end

          :sell ->
            # With slippage, sell price should be lower (worse for seller)
            if slippage_pct > 0 do
              assert trade.price <= price, "Sell with slippage should have lower price"
            else
              assert trade.price == price
            end
        end
      end
    end
  end

  describe "commission calculation" do
    test "applies commission to buy orders" do
      bar = %{
        timestamp: ~U[2024-01-01 10:00:00Z],
        open: 50_000.0,
        high: 51_000.0,
        low: 49_000.0,
        close: 50_500.0,
        volume: 100.0
      }

      order = %{
        side: :buy,
        quantity: 1.0,
        price: 50_000.0
      }

      config = %{
        slippage_pct: 0.0,
        commission_pct: 0.1  # 0.1% commission
      }

      {:ok, executed_trade} = SimulatedExecutor.execute(order, bar, config)

      # Commission = 50_000 * 1.0 * 0.001 = 50
      expected_commission = 50_000.0 * 1.0 * 0.001

      assert_in_delta executed_trade.fee, expected_commission, 0.01
      assert executed_trade.fee_currency == "USD"
    end

    test "applies commission to sell orders" do
      bar = %{
        timestamp: ~U[2024-01-01 10:00:00Z],
        open: 50_000.0,
        high: 51_000.0,
        low: 49_000.0,
        close: 50_500.0,
        volume: 100.0
      }

      order = %{
        side: :sell,
        quantity: 1.0,
        price: 50_000.0
      }

      config = %{
        slippage_pct: 0.0,
        commission_pct: 0.1  # 0.1% commission
      }

      {:ok, executed_trade} = SimulatedExecutor.execute(order, bar, config)

      # Commission = 50_000 * 1.0 * 0.001 = 50
      expected_commission = 50_000.0 * 1.0 * 0.001

      assert_in_delta executed_trade.fee, expected_commission, 0.01
    end

    test "zero commission results in no fees" do
      bar = %{
        timestamp: ~U[2024-01-01 10:00:00Z],
        open: 50_000.0,
        high: 51_000.0,
        low: 49_000.0,
        close: 50_500.0,
        volume: 100.0
      }

      order = %{
        side: :buy,
        quantity: 1.0,
        price: 50_000.0
      }

      config = %{
        slippage_pct: 0.0,
        commission_pct: 0.0
      }

      {:ok, executed_trade} = SimulatedExecutor.execute(order, bar, config)

      assert executed_trade.fee == 0.0
    end

    property "commission is always positive and proportional to trade value" do
      check all price <- float(min: 100.0, max: 100_000.0),
                commission_pct <- float(min: 0.0, max: 1.0),
                quantity <- float(min: 0.001, max: 10.0),
                side <- member_of([:buy, :sell]),
                max_runs: 100 do

        bar = %{
          timestamp: ~U[2024-01-01 10:00:00Z],
          open: price,
          high: price * 1.01,
          low: price * 0.99,
          close: price,
          volume: 100.0
        }

        order = %{side: side, quantity: quantity, price: price}
        config = %{slippage_pct: 0.0, commission_pct: commission_pct}

        {:ok, trade} = SimulatedExecutor.execute(order, bar, config)

        # Commission should be non-negative
        assert trade.fee >= 0

        # Commission should be approximately (price * quantity * commission_pct / 100)
        expected_fee = price * quantity * commission_pct / 100
        assert_in_delta trade.fee, expected_fee, max(expected_fee * 0.01, 0.01)
      end
    end
  end

  describe "combined slippage and commission" do
    test "applies both slippage and commission to buy orders" do
      bar = %{
        timestamp: ~U[2024-01-01 10:00:00Z],
        open: 50_000.0,
        high: 51_000.0,
        low: 49_000.0,
        close: 50_500.0,
        volume: 100.0
      }

      order = %{
        side: :buy,
        quantity: 1.0,
        price: 50_000.0
      }

      config = %{
        slippage_pct: 0.1,    # 0.1% slippage
        commission_pct: 0.1   # 0.1% commission
      }

      {:ok, executed_trade} = SimulatedExecutor.execute(order, bar, config)

      # Price with slippage: 50_000 * 1.001 = 50_050
      expected_price = 50_000.0 * 1.001
      assert_in_delta executed_trade.price, expected_price, 0.01

      # Commission on slipped price: 50_050 * 1.0 * 0.001 = 50.05
      expected_commission = expected_price * 1.0 * 0.001
      assert_in_delta executed_trade.fee, expected_commission, 0.01
    end

    test "total cost increases with both slippage and commission" do
      bar = %{
        timestamp: ~U[2024-01-01 10:00:00Z],
        open: 50_000.0,
        high: 51_000.0,
        low: 49_000.0,
        close: 50_500.0,
        volume: 100.0
      }

      quantity = 1.0

      # No slippage or commission
      order_base = %{side: :buy, quantity: quantity, price: 50_000.0}
      config_base = %{slippage_pct: 0.0, commission_pct: 0.0}
      {:ok, trade_base} = SimulatedExecutor.execute(order_base, bar, config_base)
      cost_base = trade_base.price * quantity + trade_base.fee

      # With slippage and commission
      order_full = %{side: :buy, quantity: quantity, price: 50_000.0}
      config_full = %{slippage_pct: 0.1, commission_pct: 0.1}
      {:ok, trade_full} = SimulatedExecutor.execute(order_full, bar, config_full)
      cost_full = trade_full.price * quantity + trade_full.fee

      assert cost_full > cost_base, "Total cost should increase with slippage and commission"
    end
  end

  describe "edge cases" do
    test "handles very small quantities" do
      bar = %{
        timestamp: ~U[2024-01-01 10:00:00Z],
        open: 50_000.0,
        high: 51_000.0,
        low: 49_000.0,
        close: 50_500.0,
        volume: 100.0
      }

      order = %{
        side: :buy,
        quantity: 0.00000001,  # 1 satoshi
        price: 50_000.0
      }

      config = %{
        slippage_pct: 0.1,
        commission_pct: 0.1
      }

      {:ok, executed_trade} = SimulatedExecutor.execute(order, bar, config)

      assert executed_trade.quantity == 0.00000001
      assert executed_trade.price > 0
      assert executed_trade.fee >= 0
    end

    test "handles very large prices" do
      bar = %{
        timestamp: ~U[2024-01-01 10:00:00Z],
        open: 10_000_000.0,
        high: 10_100_000.0,
        low: 9_900_000.0,
        close: 10_000_000.0,
        volume: 100.0
      }

      order = %{
        side: :buy,
        quantity: 1.0,
        price: 10_000_000.0
      }

      config = %{
        slippage_pct: 0.1,
        commission_pct: 0.1
      }

      {:ok, executed_trade} = SimulatedExecutor.execute(order, bar, config)

      assert executed_trade.price > 10_000_000.0
      assert executed_trade.fee > 0
    end

    test "handles maximum slippage (2%)" do
      bar = %{
        timestamp: ~U[2024-01-01 10:00:00Z],
        open: 50_000.0,
        high: 51_000.0,
        low: 49_000.0,
        close: 50_500.0,
        volume: 100.0
      }

      order = %{
        side: :buy,
        quantity: 1.0,
        price: 50_000.0
      }

      config = %{
        slippage_pct: 2.0,  # 2% maximum slippage
        commission_pct: 0.0
      }

      {:ok, executed_trade} = SimulatedExecutor.execute(order, bar, config)

      # Expected price: 50_000 * 1.02 = 51_000
      expected_price = 50_000.0 * 1.02

      assert_in_delta executed_trade.price, expected_price, 0.01
    end
  end

  describe "trade metadata" do
    test "includes execution details in metadata" do
      bar = %{
        timestamp: ~U[2024-01-01 10:00:00Z],
        open: 50_000.0,
        high: 51_000.0,
        low: 49_000.0,
        close: 50_500.0,
        volume: 100.0
      }

      order = %{
        side: :buy,
        quantity: 1.0,
        price: 50_000.0
      }

      config = %{
        slippage_pct: 0.1,
        commission_pct: 0.1
      }

      {:ok, executed_trade} = SimulatedExecutor.execute(order, bar, config)

      assert is_map(executed_trade.metadata)
      assert Map.has_key?(executed_trade.metadata, :original_price)
      assert Map.has_key?(executed_trade.metadata, :slippage_applied)
      assert Map.has_key?(executed_trade.metadata, :commission_rate)
      assert executed_trade.metadata.original_price == 50_000.0
    end
  end
end
