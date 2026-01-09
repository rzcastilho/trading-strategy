defmodule TradingStrategy.PaperTrading.PaperExecutor do
  @moduledoc """
  Simulates order execution for paper trading sessions.

  Executes simulated trades at current market prices with realistic slippage modeling.
  No actual exchange API calls are made - all executions are simulated.

  Records all simulated trades with timestamps, prices, and P&L calculations.
  """

  require Logger

  @type trade_params :: %{
          symbol: String.t(),
          side: :buy | :sell,
          quantity: float(),
          signal_type: :entry | :exit | :stop
        }

  @type executed_trade :: %{
          trade_id: String.t(),
          symbol: String.t(),
          side: :buy | :sell,
          quantity: float(),
          price: float(),
          timestamp: DateTime.t(),
          signal_type: :entry | :exit | :stop,
          slippage: float(),
          fees: float(),
          net_price: float()
        }

  @doc """
  Executes a simulated trade at current market price.

  Applies slippage modeling to simulate realistic fills and calculates fees.

  ## Parameters
    - `trade_params`: Trade parameters (symbol, side, quantity, signal_type)
    - `current_price`: Current market price
    - `opts`: Options
      - `:slippage_pct`: Slippage percentage (default: 0.001 = 0.1%)
      - `:fee_pct`: Trading fee percentage (default: 0.001 = 0.1%)
      - `:session_id`: Paper trading session ID (optional, for logging)

  ## Returns
    - `{:ok, executed_trade}` - Trade execution details
    - `{:error, reason}` - Execution error

  ## Examples

      iex> PaperExecutor.execute_trade(
      ...>   %{symbol: "BTC/USD", side: :buy, quantity: 0.1, signal_type: :entry},
      ...>   43250.00,
      ...>   slippage_pct: 0.001
      ...> )
      {:ok, %{
        trade_id: "trade_abc123",
        symbol: "BTC/USD",
        side: :buy,
        quantity: 0.1,
        price: 43293.25,
        timestamp: ~U[2025-12-04 12:34:56Z],
        signal_type: :entry,
        slippage: 43.25,
        fees: 4.33,
        net_price: 43297.58
      }}
  """
  @spec execute_trade(trade_params(), number(), keyword()) ::
          {:ok, executed_trade()} | {:error, String.t()}
  def execute_trade(trade_params, current_price, opts \\ []) do
    slippage_pct = Keyword.get(opts, :slippage_pct, 0.001)
    fee_pct = Keyword.get(opts, :fee_pct, 0.001)
    session_id = Keyword.get(opts, :session_id)

    # Validate inputs
    with :ok <- validate_trade_params(trade_params),
         :ok <- validate_price(current_price) do
      # Calculate execution price with slippage
      {execution_price, slippage} = apply_slippage(current_price, trade_params.side, slippage_pct)

      # Calculate fees
      gross_value = execution_price * trade_params.quantity
      fees = gross_value * fee_pct

      # Calculate net price (execution price + fees per unit)
      net_price = calculate_net_price(execution_price, fees, trade_params.quantity)

      trade_id = generate_trade_id(trade_params.symbol)
      timestamp = DateTime.utc_now()

      executed_trade = %{
        trade_id: trade_id,
        symbol: trade_params.symbol,
        side: trade_params.side,
        quantity: trade_params.quantity / 1.0,
        price: execution_price,
        timestamp: timestamp,
        signal_type: trade_params.signal_type,
        slippage: slippage,
        fees: fees,
        net_price: net_price
      }

      log_trade(executed_trade, session_id)

      {:ok, executed_trade}
    end
  end

  @doc """
  Executes a market exit trade to close a position.

  Convenience function for executing exit trades with position context.

  ## Parameters
    - `symbol`: Trading pair
    - `quantity`: Position quantity to close
    - `signal_type`: :exit or :stop
    - `current_price`: Current market price
    - `position_side`: :long or :short (to determine buy/sell)
    - `opts`: Options (same as execute_trade/3)

  ## Returns
    - `{:ok, executed_trade}` - Trade execution details
    - `{:error, reason}` - Execution error
  """
  @spec execute_exit_trade(String.t(), number(), atom(), number(), atom(), keyword()) ::
          {:ok, executed_trade()} | {:error, String.t()}
  def execute_exit_trade(symbol, quantity, signal_type, current_price, position_side, opts \\ []) do
    # For long positions, we sell to exit. For short positions, we buy to exit
    exit_side =
      case position_side do
        :long -> :sell
        :short -> :buy
      end

    trade_params = %{
      symbol: symbol,
      side: exit_side,
      quantity: quantity,
      signal_type: signal_type
    }

    execute_trade(trade_params, current_price, opts)
  end

  @doc """
  Simulates a batch of trades (useful for closing multiple positions).

  ## Parameters
    - `trades`: List of trade_params
    - `current_prices`: Map of symbol => current_price
    - `opts`: Options passed to execute_trade/3

  ## Returns
    - `{:ok, executed_trades}` - List of executed trades
    - `{:error, reason, partial_results}` - Error with any successful executions
  """
  @spec execute_batch(list(trade_params()), %{String.t() => number()}, keyword()) ::
          {:ok, list(executed_trade())} | {:error, String.t(), list(executed_trade())}
  def execute_batch(trades, current_prices, opts \\ []) do
    {successful, failed} =
      Enum.reduce(trades, {[], []}, fn trade_params, {success_acc, fail_acc} ->
        current_price = Map.get(current_prices, trade_params.symbol)

        if current_price do
          case execute_trade(trade_params, current_price, opts) do
            {:ok, executed} -> {[executed | success_acc], fail_acc}
            {:error, reason} -> {success_acc, [{trade_params, reason} | fail_acc]}
          end
        else
          {success_acc,
           [{trade_params, "No price available for #{trade_params.symbol}"} | fail_acc]}
        end
      end)

    case failed do
      [] -> {:ok, Enum.reverse(successful)}
      errors -> {:error, "Some trades failed", {Enum.reverse(successful), errors}}
    end
  end

  @doc """
  Calculates the net P&L for a trade (considering fees and slippage).

  ## Parameters
    - `executed_trade`: Executed trade from execute_trade/3
    - `position_entry_price`: Original entry price of the position (for exit trades)

  ## Returns
    - P&L value (positive = profit, negative = loss)
  """
  @spec calculate_trade_pnl(executed_trade(), number() | nil) :: float()
  def calculate_trade_pnl(executed_trade, position_entry_price \\ nil) do
    case executed_trade.signal_type do
      :entry ->
        # Entry trades don't have P&L, just costs (fees)
        -executed_trade.fees

      signal_type when signal_type in [:exit, :stop] ->
        if position_entry_price do
          # Calculate P&L from entry to exit
          price_diff =
            case executed_trade.side do
              :sell -> executed_trade.price - position_entry_price
              :buy -> position_entry_price - executed_trade.price
            end

          gross_pnl = price_diff * executed_trade.quantity
          # Subtract fees and slippage impact
          net_pnl = gross_pnl - executed_trade.fees

          net_pnl
        else
          # Can't calculate P&L without entry price
          0.0
        end
    end
  end

  # Private Functions

  defp validate_trade_params(%{
         symbol: symbol,
         side: side,
         quantity: quantity,
         signal_type: signal_type
       })
       when is_binary(symbol) and side in [:buy, :sell] and is_number(quantity) and
              signal_type in [:entry, :exit, :stop] do
    cond do
      quantity <= 0 ->
        {:error, "Quantity must be positive"}

      String.trim(symbol) == "" ->
        {:error, "Symbol cannot be empty"}

      true ->
        :ok
    end
  end

  defp validate_trade_params(_) do
    {:error, "Invalid trade parameters: must include symbol, side, quantity, signal_type"}
  end

  defp validate_price(price) when is_number(price) and price > 0, do: :ok
  defp validate_price(_), do: {:error, "Invalid price: must be positive number"}

  defp apply_slippage(price, side, slippage_pct) do
    # Slippage is unfavorable - buying costs more, selling gets less
    slippage_multiplier =
      case side do
        :buy -> 1 + slippage_pct
        :sell -> 1 - slippage_pct
      end

    execution_price = price * slippage_multiplier
    slippage_amount = abs(execution_price - price)

    {execution_price, slippage_amount}
  end

  defp calculate_net_price(execution_price, fees, quantity) do
    # Net price includes fees distributed per unit
    fee_per_unit = fees / quantity
    execution_price + fee_per_unit
  end

  defp generate_trade_id(symbol) do
    timestamp = System.system_time(:microsecond)
    random = :rand.uniform(9999)
    "trade_#{symbol}_#{timestamp}_#{random}"
  end

  defp log_trade(trade, session_id) do
    Logger.info(
      "[PaperExecutor] Executed trade: " <>
        "session=#{session_id || "N/A"} " <>
        "#{trade.symbol} #{trade.side} #{trade.quantity} @ #{Float.round(trade.price, 2)} " <>
        "type=#{trade.signal_type} " <>
        "slippage=#{Float.round(trade.slippage, 4)} " <>
        "fees=#{Float.round(trade.fees, 4)}"
    )
  end
end
