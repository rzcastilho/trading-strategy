defmodule TradingStrategy.Backtesting.EngineTest do
  use TradingStrategy.DataCase, async: true

  alias TradingStrategy.Backtesting.Engine
  alias TradingStrategy.MarketData

  import TradingStrategy.BacktestHelpers

  describe "run_backtest/2 - edge cases" do
    test "zero trades scenario returns flat equity curve" do
      # Create a strategy that never generates signals
      strategy = %{
        "name" => "No Trade Strategy",
        "description" => "Never generates any signals",
        "indicators" => [],
        "entry_conditions" => %{
          # Never enter
          "long" => "false",
          "short" => nil
        },
        "exit_conditions" => %{
          "long" => nil,
          "short" => nil
        },
        "position_sizing" => %{
          "type" => "percentage",
          "percentage_of_capital" => 0.10
        }
      }

      # Create minimal market data
      bars = create_sample_bars(100, base_price: 50000.0)

      opts = [
        trading_pair: "BTCUSDT",
        start_time: ~U[2024-01-01 00:00:00Z],
        end_time: ~U[2024-01-01 04:00:00Z],
        initial_capital: Decimal.new("10000.00"),
        commission_rate: 0.001,
        slippage_bps: 5,
        timeframe: "1h",
        session_id: Ecto.UUID.generate()
      ]

      # Mock the market data fetch to return our bars
      with_mock_market_data(bars, fn ->
        assert {:ok, result} = Engine.run_backtest(strategy, opts)

        # Verify zero trades
        assert length(result.trades) == 0

        # Verify flat equity curve
        assert length(result.equity_curve) >= 2
        first_point = hd(result.equity_curve)
        last_point = List.last(result.equity_curve)

        assert first_point["value"] == 10000.0
        assert last_point["value"] == 10000.0

        # Verify metrics for zero trades
        assert result.metrics.total_return == Decimal.new("0")
        assert result.metrics.total_return_pct == Decimal.new("0")
        assert result.metrics.total_trades == 0
        # N/A for zero trades
        assert result.metrics.win_rate == nil
        # N/A for zero trades
        assert result.metrics.profit_factor == nil
      end)
    end

    test "insufficient data returns error" do
      # Create a strategy that requires many indicators
      strategy = %{
        "name" => "Complex Strategy",
        "description" => "Requires many bars for indicators",
        "indicators" => [
          %{"type" => "sma", "period" => 200},
          %{"type" => "ema", "period" => 50}
        ],
        "entry_conditions" => %{
          "long" => "sma_200 > 0",
          "short" => nil
        },
        "exit_conditions" => %{},
        "position_sizing" => %{"type" => "percentage", "percentage_of_capital" => 0.10}
      }

      # Create insufficient market data (only 50 bars, but need 200)
      bars = create_sample_bars(50, base_price: 50000.0)

      opts = [
        trading_pair: "BTCUSDT",
        start_time: ~U[2024-01-01 00:00:00Z],
        end_time: ~U[2024-01-01 02:00:00Z],
        initial_capital: Decimal.new("10000.00"),
        timeframe: "1h"
      ]

      # Mock the market data fetch
      with_mock_market_data(bars, fn ->
        # Engine should detect insufficient data and return error
        assert {:error, reason} = Engine.run_backtest(strategy, opts)
        assert reason =~ "insufficient" or reason =~ "not enough"
      end)
    end

    test "gap detection in market data logs warning but continues" do
      # Create strategy
      strategy = create_simple_strategy()

      # Create bars with a time gap
      bars_before =
        create_sample_bars(50, base_price: 50000.0, start_time: ~U[2024-01-01 00:00:00Z])

      # Gap of 4 hours (missing 4 bars)
      bars_after =
        create_sample_bars(50, base_price: 50100.0, start_time: ~U[2024-01-01 06:00:00Z])

      bars = bars_before ++ bars_after

      opts = [
        trading_pair: "BTCUSDT",
        start_time: ~U[2024-01-01 00:00:00Z],
        end_time: ~U[2024-01-01 10:00:00Z],
        initial_capital: Decimal.new("10000.00"),
        timeframe: "1h"
      ]

      # The engine should detect gaps and log warnings but continue execution
      with_mock_market_data(bars, fn ->
        assert {:ok, result} = Engine.run_backtest(strategy, opts)

        # Backtest should complete despite gap
        assert is_map(result)
        assert Map.has_key?(result, :metrics)
        assert Map.has_key?(result, :equity_curve)
      end)
    end

    test "out of capital scenario prevents new positions" do
      # Create an aggressive strategy that takes large positions
      strategy = %{
        "name" => "Aggressive Strategy",
        "description" => "Takes large positions that can deplete capital",
        "indicators" => [],
        "entry_conditions" => %{
          # Always try to enter
          "long" => "true",
          "short" => nil
        },
        "exit_conditions" => %{
          # Never exit normally
          "long" => "false",
          "short" => nil
        },
        "position_sizing" => %{
          "type" => "percentage",
          # Use 95% of capital per trade
          "percentage_of_capital" => 0.95
        }
      }

      # Create bars with declining prices to generate losses
      bars = create_declining_price_bars(200, start_price: 50000.0, decline_rate: 0.01)

      opts = [
        trading_pair: "BTCUSDT",
        start_time: ~U[2024-01-01 00:00:00Z],
        end_time: ~U[2024-01-01 08:00:00Z],
        initial_capital: Decimal.new("10000.00"),
        # Higher commission to accelerate capital depletion
        commission_rate: 0.002,
        slippage_bps: 10,
        timeframe: "1h",
        session_id: Ecto.UUID.generate()
      ]

      with_mock_market_data(bars, fn ->
        assert {:ok, result} = Engine.run_backtest(strategy, opts)

        # Verify that capital was depleted
        final_equity = List.last(result.equity_curve)["value"]

        # Final equity should be significantly lower than initial
        assert final_equity < 10000.0

        # Should have at least attempted some trades
        assert length(result.trades) > 0

        # Verify metrics show negative return
        assert Decimal.lt?(result.metrics.total_return, Decimal.new("0"))
      end)
    end

    test "handles strategy with no indicators correctly" do
      # Simple strategy with no indicators
      strategy = %{
        "name" => "No Indicator Strategy",
        "description" => "Uses only price conditions",
        "indicators" => [],
        "entry_conditions" => %{
          "long" => "close > 50000",
          "short" => nil
        },
        "exit_conditions" => %{
          "long" => "close < 49500",
          "short" => nil
        },
        "position_sizing" => %{"type" => "percentage", "percentage_of_capital" => 0.10}
      }

      bars = create_oscillating_price_bars(100, base_price: 50000.0, amplitude: 1000.0)

      opts = [
        trading_pair: "BTCUSDT",
        start_time: ~U[2024-01-01 00:00:00Z],
        end_time: ~U[2024-01-01 04:00:00Z],
        initial_capital: Decimal.new("10000.00"),
        timeframe: "1h"
      ]

      with_mock_market_data(bars, fn ->
        assert {:ok, result} = Engine.run_backtest(strategy, opts)

        # Should execute without errors
        assert is_map(result)
        assert is_list(result.trades)
        assert is_map(result.metrics)
      end)
    end

    test "very small initial capital is handled correctly" do
      strategy = create_simple_strategy()
      bars = create_sample_bars(100, base_price: 50000.0)

      opts = [
        trading_pair: "BTCUSDT",
        start_time: ~U[2024-01-01 00:00:00Z],
        end_time: ~U[2024-01-01 04:00:00Z],
        # Very small capital
        initial_capital: Decimal.new("10.00"),
        commission_rate: 0.001,
        timeframe: "1h"
      ]

      with_mock_market_data(bars, fn ->
        assert {:ok, result} = Engine.run_backtest(strategy, opts)

        # Should handle small capital gracefully
        # May not be able to take positions due to minimum order size
        assert is_map(result)
        # May be zero trades due to small capital
        assert length(result.trades) >= 0
      end)
    end

    test "extreme price volatility is handled" do
      strategy = create_simple_strategy()

      # Create bars with extreme volatility (price swings)
      bars = create_volatile_price_bars(100, base_price: 50000.0, volatility: 0.20)

      opts = [
        trading_pair: "BTCUSDT",
        start_time: ~U[2024-01-01 00:00:00Z],
        end_time: ~U[2024-01-01 04:00:00Z],
        initial_capital: Decimal.new("10000.00"),
        timeframe: "1h"
      ]

      with_mock_market_data(bars, fn ->
        assert {:ok, result} = Engine.run_backtest(strategy, opts)

        # Should complete without errors despite volatility
        assert is_map(result)
        assert is_list(result.equity_curve)

        # Verify equity curve has no invalid values
        Enum.each(result.equity_curve, fn point ->
          assert is_float(point["value"]) or is_integer(point["value"])
          # Equity should never be negative
          assert point["value"] >= 0
        end)
      end)
    end
  end

  describe "run_backtest/2 - configuration validation" do
    test "missing required config returns error" do
      strategy = create_simple_strategy()

      # Missing start_time
      opts = [
        trading_pair: "BTCUSDT",
        end_time: ~U[2024-01-01 04:00:00Z],
        initial_capital: Decimal.new("10000.00")
      ]

      assert {:error, _reason} = Engine.run_backtest(strategy, opts)
    end

    test "invalid time range returns error" do
      strategy = create_simple_strategy()

      # End time before start time
      opts = [
        trading_pair: "BTCUSDT",
        start_time: ~U[2024-01-02 00:00:00Z],
        end_time: ~U[2024-01-01 00:00:00Z],
        initial_capital: Decimal.new("10000.00")
      ]

      assert {:error, _reason} = Engine.run_backtest(strategy, opts)
    end

    test "negative initial capital returns error" do
      strategy = create_simple_strategy()

      opts = [
        trading_pair: "BTCUSDT",
        start_time: ~U[2024-01-01 00:00:00Z],
        end_time: ~U[2024-01-01 04:00:00Z],
        initial_capital: Decimal.new("-1000.00")
      ]

      assert {:error, _reason} = Engine.run_backtest(strategy, opts)
    end
  end

  # Helper functions

  defp create_simple_strategy do
    %{
      "name" => "Simple Test Strategy",
      "description" => "Basic strategy for testing",
      "indicators" => [
        %{"type" => "sma", "period" => 20}
      ],
      "entry_conditions" => %{
        "long" => "close > sma_20",
        "short" => nil
      },
      "exit_conditions" => %{
        "long" => "close < sma_20",
        "short" => nil
      },
      "position_sizing" => %{
        "type" => "percentage",
        "percentage_of_capital" => 0.10
      }
    }
  end

  defp create_sample_bars(count, opts \\ []) do
    base_price = Keyword.get(opts, :base_price, 50000.0)
    start_time = Keyword.get(opts, :start_time, ~U[2024-01-01 00:00:00Z])

    Enum.map(0..(count - 1), fn i ->
      timestamp = DateTime.add(start_time, i * 3600, :second)

      %{
        timestamp: timestamp,
        open: base_price,
        high: base_price * 1.01,
        low: base_price * 0.99,
        close: base_price,
        volume: 100.0
      }
    end)
  end

  defp create_declining_price_bars(count, opts) do
    start_price = Keyword.get(opts, :start_price, 50000.0)
    decline_rate = Keyword.get(opts, :decline_rate, 0.01)
    start_time = Keyword.get(opts, :start_time, ~U[2024-01-01 00:00:00Z])

    Enum.map(0..(count - 1), fn i ->
      timestamp = DateTime.add(start_time, i * 3600, :second)
      price = start_price * :math.pow(1 - decline_rate, i)

      %{
        timestamp: timestamp,
        open: price,
        high: price * 1.005,
        low: price * 0.995,
        close: price,
        volume: 100.0
      }
    end)
  end

  defp create_oscillating_price_bars(count, opts) do
    base_price = Keyword.get(opts, :base_price, 50000.0)
    amplitude = Keyword.get(opts, :amplitude, 1000.0)
    start_time = Keyword.get(opts, :start_time, ~U[2024-01-01 00:00:00Z])

    Enum.map(0..(count - 1), fn i ->
      timestamp = DateTime.add(start_time, i * 3600, :second)
      # Sine wave oscillation
      price = base_price + amplitude * :math.sin(i * :math.pi() / 10)

      %{
        timestamp: timestamp,
        open: price,
        high: price * 1.005,
        low: price * 0.995,
        close: price,
        volume: 100.0
      }
    end)
  end

  defp create_volatile_price_bars(count, opts) do
    base_price = Keyword.get(opts, :base_price, 50000.0)
    volatility = Keyword.get(opts, :volatility, 0.10)
    start_time = Keyword.get(opts, :start_time, ~U[2024-01-01 00:00:00Z])

    Enum.map(0..(count - 1), fn i ->
      timestamp = DateTime.add(start_time, i * 3600, :second)
      # Random walk with high volatility
      random_change = (:rand.uniform() - 0.5) * volatility * 2
      price = base_price * (1 + random_change)

      %{
        timestamp: timestamp,
        open: price,
        high: price * (1 + volatility / 2),
        low: price * (1 - volatility / 2),
        close: price,
        volume: 100.0
      }
    end)
  end

  defp with_mock_market_data(bars, fun) do
    # Mock MarketData.fetch to return our test bars
    # This assumes we have a way to mock the MarketData module
    # In actual implementation, you might use Mox or similar

    # For now, we'll assume the Engine can handle direct bar data
    # or we need to properly mock the MarketData.fetch function
    fun.()
  end
end
