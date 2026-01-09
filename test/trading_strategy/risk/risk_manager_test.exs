defmodule TradingStrategy.Risk.RiskManagerTest do
  use ExUnit.Case, async: true

  alias TradingStrategy.Risk.RiskManager

  describe "check_trade/3" do
    setup do
      portfolio_state = %{
        current_equity: Decimal.new("10000"),
        peak_equity: Decimal.new("10000"),
        daily_starting_equity: Decimal.new("10000"),
        open_positions: [],
        realized_pnl_today: Decimal.new("0")
      }

      risk_limits = %{
        max_position_size_pct: Decimal.new("0.25"),
        max_daily_loss_pct: Decimal.new("0.03"),
        max_drawdown_pct: Decimal.new("0.15"),
        max_concurrent_positions: 3
      }

      {:ok, portfolio_state: portfolio_state, risk_limits: risk_limits}
    end

    test "allows trade within position size limit", %{
      portfolio_state: portfolio,
      risk_limits: limits
    } do
      # Trade value = 0.1 * 20000 = 2000 (20% of portfolio)
      proposed_trade = %{
        side: :buy,
        quantity: Decimal.new("0.1"),
        price: Decimal.new("20000"),
        symbol: "BTCUSDT"
      }

      assert {:ok, :allowed} = RiskManager.check_trade(proposed_trade, portfolio, limits)
    end

    test "rejects trade exceeding position size limit", %{
      portfolio_state: portfolio,
      risk_limits: limits
    } do
      # Trade value = 0.3 * 20000 = 6000 (60% of portfolio, exceeds 25% limit)
      proposed_trade = %{
        side: :buy,
        quantity: Decimal.new("0.3"),
        price: Decimal.new("20000"),
        symbol: "BTCUSDT"
      }

      assert {:error, :max_position_size_exceeded} =
               RiskManager.check_trade(proposed_trade, portfolio, limits)
    end

    test "rejects trade when daily loss limit hit", %{
      portfolio_state: portfolio,
      risk_limits: limits
    } do
      # Portfolio down 4% today (exceeds 3% limit)
      portfolio_with_loss = %{
        portfolio
        | current_equity: Decimal.new("9600"),
          realized_pnl_today: Decimal.new("0")
      }

      proposed_trade = %{
        side: :buy,
        quantity: Decimal.new("0.01"),
        price: Decimal.new("20000"),
        symbol: "BTCUSDT"
      }

      assert {:error, :daily_loss_limit_hit} =
               RiskManager.check_trade(proposed_trade, portfolio_with_loss, limits)
    end

    test "rejects trade when max drawdown exceeded", %{
      portfolio_state: portfolio,
      risk_limits: limits
    } do
      # Portfolio down 20% from peak (exceeds 15% limit)
      portfolio_with_drawdown = %{
        portfolio
        | current_equity: Decimal.new("8000"),
          peak_equity: Decimal.new("10000")
      }

      proposed_trade = %{
        side: :buy,
        quantity: Decimal.new("0.01"),
        price: Decimal.new("20000"),
        symbol: "BTCUSDT"
      }

      assert {:error, :max_drawdown_exceeded} =
               RiskManager.check_trade(proposed_trade, portfolio_with_drawdown, limits)
    end

    test "rejects trade when max concurrent positions reached", %{
      portfolio_state: portfolio,
      risk_limits: limits
    } do
      # Already have 3 positions (at limit)
      portfolio_with_positions = %{
        portfolio
        | open_positions: [
            %{
              symbol: "BTCUSDT",
              quantity: Decimal.new("0.1"),
              current_price: Decimal.new("20000")
            },
            %{
              symbol: "ETHUSDT",
              quantity: Decimal.new("1.0"),
              current_price: Decimal.new("1500")
            },
            %{symbol: "BNBUSDT", quantity: Decimal.new("10"), current_price: Decimal.new("300")}
          ]
      }

      proposed_trade = %{
        side: :buy,
        quantity: Decimal.new("0.01"),
        price: Decimal.new("20000"),
        symbol: "ADAUSDT"
      }

      assert {:error, :max_concurrent_positions} =
               RiskManager.check_trade(proposed_trade, portfolio_with_positions, limits)
    end
  end

  describe "calculate_risk_metrics/2" do
    test "calculates correct risk utilization percentages" do
      portfolio_state = %{
        current_equity: Decimal.new("10000"),
        peak_equity: Decimal.new("12000"),
        daily_starting_equity: Decimal.new("10500"),
        open_positions: [
          %{symbol: "BTCUSDT", quantity: Decimal.new("0.1"), current_price: Decimal.new("20000")}
        ],
        realized_pnl_today: Decimal.new("0")
      }

      risk_limits = RiskManager.default_risk_limits()

      metrics = RiskManager.calculate_risk_metrics(portfolio_state, risk_limits)

      # Position size: 2000 / 10000 = 20%
      assert Decimal.equal?(metrics.position_size_utilization_pct, Decimal.new("20"))

      # Daily loss: (10000 - 10500) / 10500 = 4.76%
      assert Decimal.compare(metrics.daily_loss_used_pct, Decimal.new("4")) == :gt

      # Drawdown: (12000 - 10000) / 12000 = 16.67%
      assert Decimal.compare(metrics.drawdown_from_peak_pct, Decimal.new("16")) == :gt

      assert metrics.concurrent_positions == 1
    end

    test "returns zero metrics for empty portfolio" do
      portfolio_state = %{
        current_equity: Decimal.new("10000"),
        peak_equity: Decimal.new("10000"),
        daily_starting_equity: Decimal.new("10000"),
        open_positions: [],
        realized_pnl_today: Decimal.new("0")
      }

      metrics = RiskManager.calculate_risk_metrics(portfolio_state, nil)

      assert Decimal.equal?(metrics.position_size_utilization_pct, Decimal.new("0"))
      assert Decimal.equal?(metrics.daily_loss_used_pct, Decimal.new("0"))
      assert Decimal.equal?(metrics.drawdown_from_peak_pct, Decimal.new("0"))
      assert metrics.concurrent_positions == 0
      assert metrics.can_open_new_position == true
    end
  end

  describe "default_risk_limits/0" do
    test "returns default risk limits matching requirements" do
      limits = RiskManager.default_risk_limits()

      # FR-021 requirements
      # 25%
      assert Decimal.equal?(limits.max_position_size_pct, Decimal.new("0.25"))
      # 3%
      assert Decimal.equal?(limits.max_daily_loss_pct, Decimal.new("0.03"))
      # 15%
      assert Decimal.equal?(limits.max_drawdown_pct, Decimal.new("0.15"))
      assert limits.max_concurrent_positions == 3
    end
  end
end
