defmodule TradingStrategy.Risk.PositionSizer do
  @moduledoc """
  Position size calculator computing order quantity based on risk percentage.

  This module calculates appropriate position sizes based on:
  - Account equity
  - Risk percentage per trade
  - Stop loss distance
  - Position sizing method (fixed, percentage, risk-based, Kelly criterion)
  """

  require Logger

  @type sizing_method :: :fixed | :percentage | :risk_based | :kelly
  @type sizing_params :: %{
          method: sizing_method(),
          account_equity: Decimal.t(),
          risk_per_trade_pct: Decimal.t(),
          entry_price: Decimal.t(),
          stop_loss_price: Decimal.t() | nil,
          fixed_quantity: Decimal.t() | nil,
          position_pct: Decimal.t() | nil,
          win_rate: Decimal.t() | nil,
          win_loss_ratio: Decimal.t() | nil
        }

  @doc """
  Calculate position size based on sizing method and parameters.

  ## Parameters
  - `params`: Position sizing parameters

  ## Returns
  - `{:ok, quantity}` - Calculated position size
  - `{:error, reason}` - Calculation failed

  ## Examples
      # Risk-based sizing
      iex> PositionSizer.calculate_size(%{
      ...>   method: :risk_based,
      ...>   account_equity: Decimal.new("10000"),
      ...>   risk_per_trade_pct: Decimal.new("0.02"),  # 2% risk
      ...>   entry_price: Decimal.new("50000"),
      ...>   stop_loss_price: Decimal.new("48000")
      ...> })
      {:ok, Decimal.new("0.1")}  # $200 risk / $2000 risk per coin

      # Percentage-based sizing
      iex> PositionSizer.calculate_size(%{
      ...>   method: :percentage,
      ...>   account_equity: Decimal.new("10000"),
      ...>   position_pct: Decimal.new("0.25"),  # 25% of account
      ...>   entry_price: Decimal.new("50000")
      ...> })
      {:ok, Decimal.new("0.05")}  # $2500 / $50000
  """
  @spec calculate_size(sizing_params()) :: {:ok, Decimal.t()} | {:error, atom()}
  def calculate_size(params) do
    case params.method do
      :fixed ->
        calculate_fixed_size(params)

      :percentage ->
        calculate_percentage_size(params)

      :risk_based ->
        calculate_risk_based_size(params)

      :kelly ->
        calculate_kelly_size(params)

      _ ->
        {:error, :invalid_method}
    end
  end

  @doc """
  Calculate fixed position size.

  ## Parameters
  - `params`: Must include `:fixed_quantity`

  ## Returns
  - `{:ok, quantity}` - Fixed quantity
  - `{:error, :missing_fixed_quantity}` if not specified
  """
  @spec calculate_fixed_size(sizing_params()) :: {:ok, Decimal.t()} | {:error, atom()}
  def calculate_fixed_size(params) do
    case params[:fixed_quantity] do
      nil ->
        {:error, :missing_fixed_quantity}

      qty when is_struct(qty, Decimal) ->
        if Decimal.positive?(qty) do
          {:ok, qty}
        else
          {:error, :invalid_quantity}
        end

      _ ->
        {:error, :invalid_quantity}
    end
  end

  @doc """
  Calculate position size as percentage of account equity.

  ## Parameters
  - `params`: Must include `:account_equity`, `:position_pct`, `:entry_price`

  ## Returns
  - `{:ok, quantity}` - Calculated quantity
  - `{:error, reason}` if parameters missing or invalid
  """
  @spec calculate_percentage_size(sizing_params()) :: {:ok, Decimal.t()} | {:error, atom()}
  def calculate_percentage_size(params) do
    with {:ok, equity} <- get_required_param(params, :account_equity),
         {:ok, pct} <- get_required_param(params, :position_pct),
         {:ok, price} <- get_required_param(params, :entry_price) do
      # Calculate position value as percentage of equity
      position_value = Decimal.mult(equity, pct)

      # Calculate quantity
      quantity = Decimal.div(position_value, price)

      Logger.debug("Percentage-based position sizing",
        equity: Decimal.to_string(equity),
        position_pct: Decimal.to_string(Decimal.mult(pct, Decimal.new("100"))),
        position_value: Decimal.to_string(position_value),
        quantity: Decimal.to_string(quantity)
      )

      {:ok, quantity}
    end
  end

  @doc """
  Calculate position size based on risk per trade.

  Formula: Position Size = (Account Equity * Risk %) / (Entry Price - Stop Loss Price)

  ## Parameters
  - `params`: Must include `:account_equity`, `:risk_per_trade_pct`, `:entry_price`, `:stop_loss_price`

  ## Returns
  - `{:ok, quantity}` - Calculated quantity
  - `{:error, reason}` if parameters missing or invalid
  """
  @spec calculate_risk_based_size(sizing_params()) :: {:ok, Decimal.t()} | {:error, atom()}
  def calculate_risk_based_size(params) do
    with {:ok, equity} <- get_required_param(params, :account_equity),
         {:ok, risk_pct} <- get_required_param(params, :risk_per_trade_pct),
         {:ok, entry} <- get_required_param(params, :entry_price),
         {:ok, stop} <- get_required_param(params, :stop_loss_price) do
      # Calculate risk amount in currency
      risk_amount = Decimal.mult(equity, risk_pct)

      # Calculate risk per unit (difference between entry and stop)
      risk_per_unit = Decimal.abs(Decimal.sub(entry, stop))

      if Decimal.equal?(risk_per_unit, Decimal.new("0")) do
        {:error, :invalid_stop_loss}
      else
        # Calculate position size
        quantity = Decimal.div(risk_amount, risk_per_unit)

        Logger.info("Risk-based position sizing",
          equity: Decimal.to_string(equity),
          risk_pct: Decimal.to_string(Decimal.mult(risk_pct, Decimal.new("100"))),
          risk_amount: Decimal.to_string(risk_amount),
          risk_per_unit: Decimal.to_string(risk_per_unit),
          quantity: Decimal.to_string(quantity)
        )

        {:ok, quantity}
      end
    end
  end

  @doc """
  Calculate position size using Kelly Criterion.

  Kelly % = W - [(1 - W) / R]
  Where:
  - W = Win rate (probability of winning)
  - R = Win/Loss ratio (average win / average loss)

  ## Parameters
  - `params`: Must include `:account_equity`, `:entry_price`, `:win_rate`, `:win_loss_ratio`

  ## Returns
  - `{:ok, quantity}` - Calculated quantity
  - `{:error, reason}` if parameters missing or invalid

  ## Examples
      iex> PositionSizer.calculate_kelly_size(%{
      ...>   account_equity: Decimal.new("10000"),
      ...>   entry_price: Decimal.new("50000"),
      ...>   win_rate: Decimal.new("0.55"),  # 55% win rate
      ...>   win_loss_ratio: Decimal.new("1.5")  # Wins are 1.5x losses
      ...> })
      {:ok, quantity}
  """
  @spec calculate_kelly_size(sizing_params()) :: {:ok, Decimal.t()} | {:error, atom()}
  def calculate_kelly_size(params) do
    with {:ok, equity} <- get_required_param(params, :account_equity),
         {:ok, price} <- get_required_param(params, :entry_price),
         {:ok, win_rate} <- get_required_param(params, :win_rate),
         {:ok, win_loss_ratio} <- get_required_param(params, :win_loss_ratio) do
      # Kelly formula: W - [(1 - W) / R]
      loss_rate = Decimal.sub(Decimal.new("1"), win_rate)
      kelly_pct = Decimal.sub(win_rate, Decimal.div(loss_rate, win_loss_ratio))

      # Cap Kelly percentage at 25% for safety (half-Kelly or quarter-Kelly often recommended)
      kelly_pct = Decimal.min(kelly_pct, Decimal.new("0.25"))

      # Ensure non-negative
      kelly_pct = Decimal.max(kelly_pct, Decimal.new("0"))

      # Calculate position value
      position_value = Decimal.mult(equity, kelly_pct)

      # Calculate quantity
      quantity = Decimal.div(position_value, price)

      Logger.info("Kelly Criterion position sizing",
        equity: Decimal.to_string(equity),
        win_rate: Decimal.to_string(win_rate),
        win_loss_ratio: Decimal.to_string(win_loss_ratio),
        kelly_pct: Decimal.to_string(Decimal.mult(kelly_pct, Decimal.new("100"))),
        quantity: Decimal.to_string(quantity)
      )

      {:ok, quantity}
    end
  end

  @doc """
  Adjust position size to respect exchange lot size rules.

  ## Parameters
  - `quantity`: Raw calculated quantity
  - `min_quantity`: Minimum allowed quantity
  - `step_size`: Lot size increment

  ## Returns
  - Adjusted quantity that meets exchange requirements

  ## Examples
      iex> PositionSizer.adjust_for_lot_size(
      ...>   Decimal.new("0.12345"),
      ...>   Decimal.new("0.001"),
      ...>   Decimal.new("0.001")
      ...> )
      Decimal.new("0.123")
  """
  @spec adjust_for_lot_size(Decimal.t(), Decimal.t(), Decimal.t()) :: Decimal.t()
  def adjust_for_lot_size(quantity, min_quantity, step_size) do
    # Ensure quantity meets minimum
    quantity = Decimal.max(quantity, min_quantity)

    # Round down to nearest step_size
    steps = Decimal.div_int(quantity, step_size)
    adjusted = Decimal.mult(Decimal.new(steps), step_size)

    # Ensure still meets minimum after rounding
    if Decimal.compare(adjusted, min_quantity) == :lt do
      min_quantity
    else
      adjusted
    end
  end

  # Private Functions

  defp get_required_param(params, key) do
    case Map.get(params, key) do
      nil ->
        {:error, :"missing_#{key}"}

      value when is_struct(value, Decimal) ->
        if Decimal.positive?(value) or Decimal.equal?(value, Decimal.new("0")) do
          {:ok, value}
        else
          {:error, :"invalid_#{key}"}
        end

      _ ->
        {:error, :"invalid_#{key}"}
    end
  end
end
