defmodule TradingStrategy.Risk.RiskManager do
  @moduledoc """
  Risk manager enforcing max position size, daily loss limits.

  This module implements portfolio-level risk management rules to protect
  against excessive losses and position concentration.

  Default Risk Limits (as per requirements):
  - Max position size: 25% of portfolio
  - Max daily loss: 3% of portfolio
  - Max drawdown: 15% from peak equity
  """

  require Logger

  @type session_id :: String.t()
  @type risk_limits :: %{
          max_position_size_pct: Decimal.t(),
          max_daily_loss_pct: Decimal.t(),
          max_drawdown_pct: Decimal.t(),
          max_concurrent_positions: non_neg_integer()
        }

  @type portfolio_state :: %{
          current_equity: Decimal.t(),
          peak_equity: Decimal.t(),
          daily_starting_equity: Decimal.t(),
          open_positions: [map()],
          realized_pnl_today: Decimal.t()
        }

  @type proposed_trade :: %{
          side: :buy | :sell,
          quantity: Decimal.t(),
          price: Decimal.t() | nil,
          symbol: String.t()
        }

  @type risk_check_result ::
          {:ok, :allowed}
          | {:error, :max_position_size_exceeded}
          | {:error, :daily_loss_limit_hit}
          | {:error, :max_drawdown_exceeded}
          | {:error, :max_concurrent_positions}

  # Default risk limits (FR-021)
  # 25%
  @default_max_position_size_pct Decimal.new("0.25")
  # 3%
  @default_max_daily_loss_pct Decimal.new("0.03")
  # 15%
  @default_max_drawdown_pct Decimal.new("0.15")
  @default_max_concurrent_positions 3

  @doc """
  Check if a proposed trade would violate risk limits.

  ## Parameters
  - `proposed_trade`: Trade to evaluate
  - `portfolio_state`: Current portfolio state
  - `risk_limits`: Risk limit configuration (optional, uses defaults)

  ## Returns
  - `{:ok, :allowed}` if trade permitted
  - `{:error, reason}` if trade would violate limits

  ## Examples
      iex> RiskManager.check_trade(
      ...>   %{side: :buy, quantity: Decimal.new("0.1"), price: Decimal.new("50000"), symbol: "BTCUSDT"},
      ...>   %{current_equity: Decimal.new("10000"), peak_equity: Decimal.new("10000"), ...},
      ...>   %{max_position_size_pct: Decimal.new("0.25"), ...}
      ...> )
      {:ok, :allowed}
  """
  @spec check_trade(proposed_trade(), portfolio_state(), risk_limits() | nil) ::
          risk_check_result()
  def check_trade(proposed_trade, portfolio_state, risk_limits \\ nil) do
    limits = risk_limits || default_risk_limits()

    with :ok <- check_position_size(proposed_trade, portfolio_state, limits),
         :ok <- check_daily_loss(portfolio_state, limits),
         :ok <- check_drawdown(portfolio_state, limits),
         :ok <- check_concurrent_positions(portfolio_state, limits) do
      {:ok, :allowed}
    end
  end

  @doc """
  Calculate current risk metrics for a portfolio.

  ## Parameters
  - `portfolio_state`: Current portfolio state
  - `risk_limits`: Risk limit configuration (optional)

  ## Returns
  - Map containing risk utilization percentages

  ## Examples
      iex> RiskManager.calculate_risk_metrics(portfolio_state, risk_limits)
      %{
        position_size_utilization_pct: Decimal.new("20"),
        daily_loss_used_pct: Decimal.new("1.5"),
        drawdown_from_peak_pct: Decimal.new("5"),
        concurrent_positions: 2,
        can_open_new_position: true
      }
  """
  @spec calculate_risk_metrics(portfolio_state(), risk_limits() | nil) :: map()
  def calculate_risk_metrics(portfolio_state, risk_limits \\ nil) do
    limits = risk_limits || default_risk_limits()

    %{
      position_size_utilization_pct: calculate_position_size_utilization(portfolio_state),
      daily_loss_used_pct: calculate_daily_loss_pct(portfolio_state),
      drawdown_from_peak_pct: calculate_drawdown_pct(portfolio_state),
      concurrent_positions: length(portfolio_state.open_positions),
      can_open_new_position: can_open_new_position?(portfolio_state, limits)
    }
  end

  @doc """
  Get default risk limits.

  ## Examples
      iex> RiskManager.default_risk_limits()
      %{
        max_position_size_pct: Decimal.new("0.25"),
        max_daily_loss_pct: Decimal.new("0.03"),
        max_drawdown_pct: Decimal.new("0.15"),
        max_concurrent_positions: 3
      }
  """
  @spec default_risk_limits() :: risk_limits()
  def default_risk_limits do
    %{
      max_position_size_pct: @default_max_position_size_pct,
      max_daily_loss_pct: @default_max_daily_loss_pct,
      max_drawdown_pct: @default_max_drawdown_pct,
      max_concurrent_positions: @default_max_concurrent_positions
    }
  end

  # Private Functions

  defp check_position_size(proposed_trade, portfolio_state, limits) do
    # Calculate position value
    case proposed_trade.price do
      nil ->
        # For market orders, we can't calculate exact value
        # Skip this check and rely on balance validation
        :ok

      price ->
        position_value = Decimal.mult(proposed_trade.quantity, price)
        validate_position_size(position_value, portfolio_state, limits)
    end
  end

  defp validate_position_size(position_value, portfolio_state, limits) do
    # Calculate as percentage of current equity
    position_pct = Decimal.div(position_value, portfolio_state.current_equity)

    if Decimal.compare(position_pct, limits.max_position_size_pct) != :gt do
      :ok
    else
      Logger.warning("Trade exceeds max position size",
        position_pct: Decimal.to_string(Decimal.mult(position_pct, Decimal.new("100"))),
        max_pct: Decimal.to_string(Decimal.mult(limits.max_position_size_pct, Decimal.new("100")))
      )

      {:error, :max_position_size_exceeded}
    end
  end

  defp check_daily_loss(portfolio_state, limits) do
    # Calculate current daily P&L
    current_daily_pnl =
      Decimal.sub(
        portfolio_state.current_equity,
        portfolio_state.daily_starting_equity
      )

    # Add realized P&L from closed positions today
    total_daily_pnl = Decimal.add(current_daily_pnl, portfolio_state.realized_pnl_today)

    # Check if loss exceeds limit
    if Decimal.negative?(total_daily_pnl) do
      loss_pct =
        Decimal.div(
          Decimal.abs(total_daily_pnl),
          portfolio_state.daily_starting_equity
        )

      if Decimal.compare(loss_pct, limits.max_daily_loss_pct) == :gt do
        Logger.error("Daily loss limit exceeded",
          loss_pct: Decimal.to_string(Decimal.mult(loss_pct, Decimal.new("100"))),
          max_pct: Decimal.to_string(Decimal.mult(limits.max_daily_loss_pct, Decimal.new("100")))
        )

        {:error, :daily_loss_limit_hit}
      else
        :ok
      end
    else
      :ok
    end
  end

  defp check_drawdown(portfolio_state, limits) do
    # Calculate drawdown from peak
    drawdown = Decimal.sub(portfolio_state.peak_equity, portfolio_state.current_equity)
    drawdown_pct = Decimal.div(drawdown, portfolio_state.peak_equity)

    if Decimal.compare(drawdown_pct, limits.max_drawdown_pct) == :gt do
      Logger.error("Max drawdown exceeded",
        drawdown_pct: Decimal.to_string(Decimal.mult(drawdown_pct, Decimal.new("100"))),
        max_pct: Decimal.to_string(Decimal.mult(limits.max_drawdown_pct, Decimal.new("100")))
      )

      {:error, :max_drawdown_exceeded}
    else
      :ok
    end
  end

  defp check_concurrent_positions(portfolio_state, limits) do
    current_positions = length(portfolio_state.open_positions)

    if current_positions >= limits.max_concurrent_positions do
      Logger.warning("Max concurrent positions reached",
        current: current_positions,
        max: limits.max_concurrent_positions
      )

      {:error, :max_concurrent_positions}
    else
      :ok
    end
  end

  defp calculate_position_size_utilization(portfolio_state) do
    if Decimal.equal?(portfolio_state.current_equity, Decimal.new("0")) do
      Decimal.new("0")
    else
      # Sum of all open position values as percentage of equity
      total_position_value =
        Enum.reduce(portfolio_state.open_positions, Decimal.new("0"), fn position, acc ->
          position_value =
            Decimal.mult(
              position[:quantity] || Decimal.new("0"),
              position[:current_price] || Decimal.new("0")
            )

          Decimal.add(acc, position_value)
        end)

      Decimal.mult(
        Decimal.div(total_position_value, portfolio_state.current_equity),
        Decimal.new("100")
      )
    end
  end

  defp calculate_daily_loss_pct(portfolio_state) do
    if Decimal.equal?(portfolio_state.daily_starting_equity, Decimal.new("0")) do
      Decimal.new("0")
    else
      daily_pnl =
        Decimal.sub(portfolio_state.current_equity, portfolio_state.daily_starting_equity)

      daily_pnl = Decimal.add(daily_pnl, portfolio_state.realized_pnl_today)

      # Return as positive number for losses
      pct =
        Decimal.mult(
          Decimal.div(Decimal.abs(daily_pnl), portfolio_state.daily_starting_equity),
          Decimal.new("100")
        )

      if Decimal.negative?(daily_pnl), do: pct, else: Decimal.new("0")
    end
  end

  defp calculate_drawdown_pct(portfolio_state) do
    if Decimal.equal?(portfolio_state.peak_equity, Decimal.new("0")) do
      Decimal.new("0")
    else
      drawdown = Decimal.sub(portfolio_state.peak_equity, portfolio_state.current_equity)

      Decimal.mult(
        Decimal.div(drawdown, portfolio_state.peak_equity),
        Decimal.new("100")
      )
    end
  end

  defp can_open_new_position?(portfolio_state, limits) do
    # Check all risk constraints
    case check_trade(
           %{side: :buy, quantity: Decimal.new("0"), price: Decimal.new("0"), symbol: "TEST"},
           portfolio_state,
           limits
         ) do
      {:ok, :allowed} -> true
      # Can still open if size is small
      {:error, :max_position_size_exceeded} -> true
      {:error, _reason} -> false
    end
  end
end
