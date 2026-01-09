defmodule TradingStrategy.PaperTrading.PaperExecutorTest do
  use ExUnit.Case, async: true

  alias TradingStrategy.PaperTrading.PaperExecutor

  @moduletag :capture_log

  describe "execute_trade/3" do
    test "executes a buy trade successfully" do
      trade_params = %{
        symbol: "BTC/USD",
        side: :buy,
        quantity: 0.1,
        signal_type: :entry
      }

      current_price = 43250.0

      assert {:ok, trade} = PaperExecutor.execute_trade(trade_params, current_price)

      assert trade.symbol == "BTC/USD"
      assert trade.side == :buy
      assert trade.quantity == 0.1
      assert trade.signal_type == :entry
      assert trade.price > current_price
      assert trade.slippage > 0
      assert trade.fees > 0
      assert trade.net_price > trade.price
      assert is_binary(trade.trade_id)
      assert %DateTime{} = trade.timestamp
    end

    test "executes a sell trade successfully" do
      trade_params = %{
        symbol: "ETH/USD",
        side: :sell,
        quantity: 1.5,
        signal_type: :exit
      }

      current_price = 2250.0

      assert {:ok, trade} = PaperExecutor.execute_trade(trade_params, current_price)

      assert trade.symbol == "ETH/USD"
      assert trade.side == :sell
      assert trade.quantity == 1.5
      assert trade.signal_type == :exit
      assert trade.price < current_price
      assert trade.slippage > 0
      assert trade.fees > 0
    end

    test "applies slippage correctly for buy orders" do
      trade_params = %{
        symbol: "BTC/USD",
        side: :buy,
        quantity: 0.1,
        signal_type: :entry
      }

      current_price = 40000.0
      slippage_pct = 0.001

      assert {:ok, trade} =
               PaperExecutor.execute_trade(trade_params, current_price,
                 slippage_pct: slippage_pct
               )

      expected_price = current_price * (1 + slippage_pct)
      assert_in_delta trade.price, expected_price, 0.01
      assert_in_delta trade.slippage, 40.0, 0.01
    end

    test "applies slippage correctly for sell orders" do
      trade_params = %{
        symbol: "BTC/USD",
        side: :sell,
        quantity: 0.1,
        signal_type: :exit
      }

      current_price = 40000.0
      slippage_pct = 0.001

      assert {:ok, trade} =
               PaperExecutor.execute_trade(trade_params, current_price,
                 slippage_pct: slippage_pct
               )

      expected_price = current_price * (1 - slippage_pct)
      assert_in_delta trade.price, expected_price, 0.01
      assert_in_delta trade.slippage, 40.0, 0.01
    end

    test "calculates fees correctly" do
      trade_params = %{
        symbol: "BTC/USD",
        side: :buy,
        quantity: 0.1,
        signal_type: :entry
      }

      current_price = 40000.0
      fee_pct = 0.001

      assert {:ok, trade} =
               PaperExecutor.execute_trade(trade_params, current_price,
                 fee_pct: fee_pct,
                 slippage_pct: 0
               )

      gross_value = 40000.0 * 0.1
      expected_fees = gross_value * fee_pct
      assert_in_delta trade.fees, expected_fees, 0.01
    end

    test "calculates net price including fees" do
      trade_params = %{
        symbol: "BTC/USD",
        side: :buy,
        quantity: 0.1,
        signal_type: :entry
      }

      current_price = 40000.0

      assert {:ok, trade} =
               PaperExecutor.execute_trade(trade_params, current_price,
                 slippage_pct: 0,
                 fee_pct: 0.001
               )

      fee_per_unit = trade.fees / trade.quantity
      expected_net_price = trade.price + fee_per_unit
      assert_in_delta trade.net_price, expected_net_price, 0.01
    end

    test "generates unique trade IDs" do
      trade_params = %{
        symbol: "BTC/USD",
        side: :buy,
        quantity: 0.1,
        signal_type: :entry
      }

      {:ok, trade1} = PaperExecutor.execute_trade(trade_params, 40000.0)
      {:ok, trade2} = PaperExecutor.execute_trade(trade_params, 40000.0)

      assert trade1.trade_id != trade2.trade_id
    end

    test "accepts custom slippage percentage" do
      trade_params = %{
        symbol: "BTC/USD",
        side: :buy,
        quantity: 0.1,
        signal_type: :entry
      }

      {:ok, trade} =
        PaperExecutor.execute_trade(trade_params, 40000.0, slippage_pct: 0.002)

      expected_price = 40000.0 * 1.002
      assert_in_delta trade.price, expected_price, 0.01
    end

    test "accepts custom fee percentage" do
      trade_params = %{
        symbol: "BTC/USD",
        side: :buy,
        quantity: 0.1,
        signal_type: :entry
      }

      {:ok, trade} =
        PaperExecutor.execute_trade(trade_params, 40000.0, fee_pct: 0.002, slippage_pct: 0)

      gross_value = 40000.0 * 0.1
      expected_fees = gross_value * 0.002
      assert_in_delta trade.fees, expected_fees, 0.01
    end

    test "accepts session_id option for logging" do
      trade_params = %{
        symbol: "BTC/USD",
        side: :buy,
        quantity: 0.1,
        signal_type: :entry
      }

      {:ok, trade} =
        PaperExecutor.execute_trade(trade_params, 40000.0, session_id: "session-123")

      assert trade
    end

    test "returns error for invalid quantity (zero)" do
      trade_params = %{
        symbol: "BTC/USD",
        side: :buy,
        quantity: 0,
        signal_type: :entry
      }

      assert {:error, "Quantity must be positive"} =
               PaperExecutor.execute_trade(trade_params, 40000.0)
    end

    test "returns error for invalid quantity (negative)" do
      trade_params = %{
        symbol: "BTC/USD",
        side: :buy,
        quantity: -0.1,
        signal_type: :entry
      }

      assert {:error, "Quantity must be positive"} =
               PaperExecutor.execute_trade(trade_params, 40000.0)
    end

    test "returns error for empty symbol" do
      trade_params = %{
        symbol: "",
        side: :buy,
        quantity: 0.1,
        signal_type: :entry
      }

      assert {:error, "Symbol cannot be empty"} =
               PaperExecutor.execute_trade(trade_params, 40000.0)
    end

    test "returns error for invalid price (zero)" do
      trade_params = %{
        symbol: "BTC/USD",
        side: :buy,
        quantity: 0.1,
        signal_type: :entry
      }

      assert {:error, "Invalid price: must be positive number"} =
               PaperExecutor.execute_trade(trade_params, 0)
    end

    test "returns error for invalid price (negative)" do
      trade_params = %{
        symbol: "BTC/USD",
        side: :buy,
        quantity: 0.1,
        signal_type: :entry
      }

      assert {:error, "Invalid price: must be positive number"} =
               PaperExecutor.execute_trade(trade_params, -100)
    end

    test "returns error for invalid trade parameters (missing fields)" do
      trade_params = %{
        symbol: "BTC/USD",
        side: :buy
      }

      assert {:error, message} = PaperExecutor.execute_trade(trade_params, 40000.0)
      assert message =~ "Invalid trade parameters"
    end

    test "returns error for invalid side" do
      trade_params = %{
        symbol: "BTC/USD",
        side: :invalid_side,
        quantity: 0.1,
        signal_type: :entry
      }

      assert {:error, message} = PaperExecutor.execute_trade(trade_params, 40000.0)
      assert message =~ "Invalid trade parameters"
    end

    test "supports all signal types" do
      for signal_type <- [:entry, :exit, :stop] do
        trade_params = %{
          symbol: "BTC/USD",
          side: :buy,
          quantity: 0.1,
          signal_type: signal_type
        }

        assert {:ok, trade} = PaperExecutor.execute_trade(trade_params, 40000.0)
        assert trade.signal_type == signal_type
      end
    end
  end

  describe "execute_exit_trade/6" do
    test "executes exit for long position (sells)" do
      assert {:ok, trade} =
               PaperExecutor.execute_exit_trade(
                 "BTC/USD",
                 0.1,
                 :exit,
                 43000.0,
                 :long
               )

      assert trade.side == :sell
      assert trade.signal_type == :exit
      assert trade.quantity == 0.1
    end

    test "executes exit for short position (buys)" do
      assert {:ok, trade} =
               PaperExecutor.execute_exit_trade(
                 "BTC/USD",
                 0.1,
                 :exit,
                 43000.0,
                 :short
               )

      assert trade.side == :buy
      assert trade.signal_type == :exit
    end

    test "executes stop for long position" do
      assert {:ok, trade} =
               PaperExecutor.execute_exit_trade(
                 "BTC/USD",
                 0.1,
                 :stop,
                 42000.0,
                 :long
               )

      assert trade.side == :sell
      assert trade.signal_type == :stop
    end

    test "executes stop for short position" do
      assert {:ok, trade} =
               PaperExecutor.execute_exit_trade(
                 "BTC/USD",
                 0.1,
                 :stop,
                 42000.0,
                 :short
               )

      assert trade.side == :buy
      assert trade.signal_type == :stop
    end

    test "accepts custom options" do
      assert {:ok, trade} =
               PaperExecutor.execute_exit_trade(
                 "BTC/USD",
                 0.1,
                 :exit,
                 43000.0,
                 :long,
                 slippage_pct: 0.002,
                 fee_pct: 0.002
               )

      assert trade.side == :sell
    end
  end

  describe "execute_batch/3" do
    test "executes multiple trades successfully" do
      trades = [
        %{symbol: "BTC/USD", side: :buy, quantity: 0.1, signal_type: :entry},
        %{symbol: "ETH/USD", side: :buy, quantity: 1.0, signal_type: :entry}
      ]

      prices = %{
        "BTC/USD" => 43000.0,
        "ETH/USD" => 2250.0
      }

      assert {:ok, executed_trades} = PaperExecutor.execute_batch(trades, prices)

      assert length(executed_trades) == 2
      assert Enum.all?(executed_trades, fn trade -> is_binary(trade.trade_id) end)
    end

    test "returns success with partial failures" do
      trades = [
        %{symbol: "BTC/USD", side: :buy, quantity: 0.1, signal_type: :entry},
        %{symbol: "ETH/USD", side: :buy, quantity: 1.0, signal_type: :entry},
        %{symbol: "MISSING/USD", side: :buy, quantity: 0.5, signal_type: :entry}
      ]

      prices = %{
        "BTC/USD" => 43000.0,
        "ETH/USD" => 2250.0
      }

      assert {:error, "Some trades failed", {successful, failed}} =
               PaperExecutor.execute_batch(trades, prices)

      assert length(successful) == 2
      assert length(failed) == 1
    end

    test "returns all successful trades when all execute" do
      trades = [
        %{symbol: "BTC/USD", side: :buy, quantity: 0.1, signal_type: :entry}
      ]

      prices = %{"BTC/USD" => 43000.0}

      assert {:ok, executed_trades} = PaperExecutor.execute_batch(trades, prices)
      assert length(executed_trades) == 1
    end

    test "handles empty trade list" do
      assert {:ok, []} = PaperExecutor.execute_batch([], %{})
    end

    test "handles missing price for symbol" do
      trades = [
        %{symbol: "BTC/USD", side: :buy, quantity: 0.1, signal_type: :entry}
      ]

      prices = %{}

      assert {:error, "Some trades failed", {[], failed}} =
               PaperExecutor.execute_batch(trades, prices)

      assert length(failed) == 1
    end

    test "passes options to individual trades" do
      trades = [
        %{symbol: "BTC/USD", side: :buy, quantity: 0.1, signal_type: :entry}
      ]

      prices = %{"BTC/USD" => 43000.0}

      assert {:ok, [trade]} =
               PaperExecutor.execute_batch(trades, prices,
                 slippage_pct: 0.002,
                 session_id: "batch-session"
               )

      assert trade.slippage > 0
    end
  end

  describe "calculate_trade_pnl/2" do
    test "returns negative fees for entry trades" do
      entry_trade = %{
        signal_type: :entry,
        fees: 4.33
      }

      pnl = PaperExecutor.calculate_trade_pnl(entry_trade)
      assert pnl == -4.33
    end

    test "calculates profit for long position exit (sell)" do
      exit_trade = %{
        signal_type: :exit,
        side: :sell,
        price: 45000.0,
        quantity: 0.1,
        fees: 4.50
      }

      entry_price = 43000.0

      pnl = PaperExecutor.calculate_trade_pnl(exit_trade, entry_price)

      gross_pnl = (45000.0 - 43000.0) * 0.1
      expected_pnl = gross_pnl - 4.50

      assert_in_delta pnl, expected_pnl, 0.01
    end

    test "calculates loss for long position exit (sell)" do
      exit_trade = %{
        signal_type: :exit,
        side: :sell,
        price: 41000.0,
        quantity: 0.1,
        fees: 4.10
      }

      entry_price = 43000.0

      pnl = PaperExecutor.calculate_trade_pnl(exit_trade, entry_price)

      gross_pnl = (41000.0 - 43000.0) * 0.1
      expected_pnl = gross_pnl - 4.10

      assert_in_delta pnl, expected_pnl, 0.01
      assert pnl < 0
    end

    test "calculates profit for short position exit (buy)" do
      exit_trade = %{
        signal_type: :exit,
        side: :buy,
        price: 41000.0,
        quantity: 0.1,
        fees: 4.10
      }

      entry_price = 43000.0

      pnl = PaperExecutor.calculate_trade_pnl(exit_trade, entry_price)

      gross_pnl = (43000.0 - 41000.0) * 0.1
      expected_pnl = gross_pnl - 4.10

      assert_in_delta pnl, expected_pnl, 0.01
      assert pnl > 0
    end

    test "calculates loss for short position exit (buy)" do
      exit_trade = %{
        signal_type: :exit,
        side: :buy,
        price: 45000.0,
        quantity: 0.1,
        fees: 4.50
      }

      entry_price = 43000.0

      pnl = PaperExecutor.calculate_trade_pnl(exit_trade, entry_price)

      gross_pnl = (43000.0 - 45000.0) * 0.1
      expected_pnl = gross_pnl - 4.50

      assert_in_delta pnl, expected_pnl, 0.01
      assert pnl < 0
    end

    test "handles stop signal type same as exit" do
      stop_trade = %{
        signal_type: :stop,
        side: :sell,
        price: 40000.0,
        quantity: 0.1,
        fees: 4.00
      }

      entry_price = 43000.0

      pnl = PaperExecutor.calculate_trade_pnl(stop_trade, entry_price)

      gross_pnl = (40000.0 - 43000.0) * 0.1
      expected_pnl = gross_pnl - 4.00

      assert_in_delta pnl, expected_pnl, 0.01
      assert pnl < 0
    end

    test "returns zero when no entry price provided for exit" do
      exit_trade = %{
        signal_type: :exit,
        side: :sell,
        price: 45000.0,
        quantity: 0.1,
        fees: 4.50
      }

      pnl = PaperExecutor.calculate_trade_pnl(exit_trade, nil)
      assert pnl == 0.0
    end
  end
end
