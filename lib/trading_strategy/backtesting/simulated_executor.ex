defmodule TradingStrategy.Backtesting.SimulatedExecutor do
  @moduledoc """
  Simulates order execution for backtesting with realistic slippage and commission modeling.

  Provides instant fill simulation while accounting for transaction costs
  to produce realistic backtest results.
  """

  @doc """
  Executes a simulated order with slippage and commission.

  ## Parameters
    - `side`: :buy or :sell
    - `amount`: Order amount (in quote currency for buy, in base currency for sell)
    - `price`: Target price
    - `commission_rate`: Commission as decimal (e.g., 0.001 for 0.1%)
    - `slippage_bps`: Slippage in basis points (e.g., 5 for 0.05%)

  ## Returns
    - `{:ok, trade}` - Executed trade details
    - `{:error, reason}` - Execution failure

  ## Examples

      iex> SimulatedExecutor.execute_order(:buy, 1000, 42000, 0.001, 5)
      {:ok, %{
        side: :buy,
        requested_price: 42000,
        executed_price: 42021.0,  # with slippage
        requested_amount: 1000,
        executed_quantity: 0.02379,  # amount / executed_price
        commission: 0.02379,
        total_cost: 1000.02379
      }}
  """
  @spec execute_order(atom(), number(), number(), number(), number()) ::
          {:ok, map()} | {:error, String.t()}
  def execute_order(side, amount, price, commission_rate, slippage_bps)
      when side in [:buy, :sell] and amount > 0 and price > 0 do
    # Calculate slippage
    # Convert basis points to decimal
    slippage_factor = slippage_bps / 10000.0

    executed_price =
      case side do
        :buy ->
          # Buying: price goes against you (higher)
          price * (1 + slippage_factor)

        :sell ->
          # Selling: price goes against you (lower)
          price * (1 - slippage_factor)
      end

    # Calculate quantity
    quantity =
      case side do
        :buy ->
          # For buy: amount is in quote currency, calculate base quantity
          amount / executed_price

        :sell ->
          # For sell: amount is in base currency (quantity to sell)
          amount
      end

    # Calculate commission
    commission_amount = quantity * commission_rate

    # Calculate total cost/proceeds
    {total_cost, net_quantity} =
      case side do
        :buy ->
          # Total cost = price * quantity + commission
          cost = executed_price * quantity + executed_price * commission_amount
          # Net quantity after commission
          {cost, quantity - commission_amount}

        :sell ->
          # Total proceeds = price * quantity - commission
          proceeds = executed_price * quantity - executed_price * commission_amount
          # Quantity sold (gross)
          {proceeds, quantity}
      end

    trade = %{
      side: side,
      requested_price: price / 1.0,
      executed_price: executed_price / 1.0,
      requested_amount: amount / 1.0,
      executed_quantity: quantity / 1.0,
      net_quantity: net_quantity / 1.0,
      commission: commission_amount / 1.0,
      commission_rate: commission_rate,
      slippage_bps: slippage_bps,
      slippage_amount: abs(executed_price - price),
      total_cost: total_cost / 1.0
    }

    {:ok, trade}
  rescue
    error ->
      {:error, "Order execution failed: #{Exception.message(error)}"}
  end

  @doc """
  Simulates market impact for large orders.

  For very large orders relative to liquidity, additional price impact is applied.

  ## Parameters
    - `side`: :buy or :sell
    - `quantity`: Order size
    - `price`: Current price
    - `available_liquidity`: Available liquidity (optional, for impact calculation)

  ## Returns
    - Adjusted price with market impact
  """
  @spec calculate_market_impact(atom(), number(), number(), number() | nil) :: float()
  def calculate_market_impact(side, quantity, price, available_liquidity \\ nil)

  def calculate_market_impact(_side, _quantity, price, nil) do
    # No liquidity data, no additional impact
    price / 1.0
  end

  def calculate_market_impact(side, quantity, price, available_liquidity) do
    # Calculate order size as percentage of available liquidity
    order_percentage = quantity / available_liquidity

    # Apply square root impact model: impact = sqrt(order_size %)
    # Scale factor
    impact_factor = :math.sqrt(order_percentage) * 0.01

    case side do
      :buy ->
        # Buying pushes price up
        price * (1 + impact_factor)

      :sell ->
        # Selling pushes price down
        price * (1 - impact_factor)
    end
  end

  @doc """
  Validates order parameters before execution.

  ## Parameters
    - `side`: :buy or :sell
    - `amount`: Order amount
    - `price`: Order price

  ## Returns
    - `:ok` - Valid order
    - `{:error, reason}` - Invalid order
  """
  @spec validate_order(atom(), number(), number()) :: :ok | {:error, String.t()}
  def validate_order(side, amount, price) do
    cond do
      side not in [:buy, :sell] ->
        {:error, "Invalid side: must be :buy or :sell"}

      amount <= 0 ->
        {:error, "Invalid amount: must be positive"}

      price <= 0 ->
        {:error, "Invalid price: must be positive"}

      true ->
        :ok
    end
  end

  @doc """
  Calculates effective fill price given slippage and market impact.

  ## Parameters
    - `side`: :buy or :sell
    - `target_price`: Desired price
    - `slippage_bps`: Slippage in basis points
    - `impact_factor`: Additional market impact (optional)

  ## Returns
    - Effective fill price
  """
  @spec calculate_fill_price(atom(), number(), number(), number()) :: float()
  def calculate_fill_price(side, target_price, slippage_bps, impact_factor \\ 0) do
    slippage_factor = slippage_bps / 10000.0
    total_impact = slippage_factor + impact_factor

    case side do
      :buy -> target_price * (1 + total_impact)
      :sell -> target_price * (1 - total_impact)
    end
  end
end
