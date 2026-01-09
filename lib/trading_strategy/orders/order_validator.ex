defmodule TradingStrategy.Orders.OrderValidator do
  @moduledoc """
  Order validator checking balance, lot size, price filters.

  This module validates orders before submission to ensure they meet
  exchange requirements and internal risk management rules.
  """

  require Logger

  @type order :: %{
          symbol: String.t(),
          side: :buy | :sell,
          type: :market | :limit | :stop_loss,
          quantity: Decimal.t(),
          price: Decimal.t() | nil
        }

  @type balance :: %{
          asset: String.t(),
          free: Decimal.t(),
          locked: Decimal.t()
        }

  @type symbol_info :: %{
          symbol: String.t(),
          min_quantity: Decimal.t(),
          max_quantity: Decimal.t(),
          step_size: Decimal.t(),
          min_notional: Decimal.t(),
          min_price: Decimal.t(),
          max_price: Decimal.t(),
          tick_size: Decimal.t()
        }

  @type validation_error ::
          :insufficient_balance
          | :quantity_below_minimum
          | :quantity_above_maximum
          | :invalid_quantity_step
          | :notional_below_minimum
          | :price_below_minimum
          | :price_above_maximum
          | :invalid_price_tick
          | :price_required
          | :invalid_symbol

  @doc """
  Validate an order against balance and exchange filters.

  ## Parameters
  - `order`: Order to validate
  - `balances`: List of account balances
  - `symbol_info`: Symbol trading rules (optional, uses defaults if nil)

  ## Returns
  - `:ok` if order is valid
  - `{:error, validation_error}` if order fails validation

  ## Examples
      iex> OrderValidator.validate_order(
      ...>   %{symbol: "BTCUSDT", side: :buy, type: :market, quantity: Decimal.new("0.001"), price: nil},
      ...>   [%{asset: "USDT", free: Decimal.new("1000"), locked: Decimal.new("0")}],
      ...>   %{min_quantity: Decimal.new("0.0001"), min_notional: Decimal.new("10"), ...}
      ...> )
      :ok
  """
  @spec validate_order(order(), [balance()], symbol_info() | nil) ::
          :ok | {:error, validation_error()}
  def validate_order(order, balances, symbol_info \\ nil) do
    with :ok <- validate_symbol(order.symbol),
         :ok <- validate_quantity(order.quantity, symbol_info),
         :ok <- validate_price(order.type, order.price, symbol_info),
         :ok <- validate_notional(order, symbol_info),
         :ok <- validate_balance(order, balances) do
      :ok
    end
  end

  @doc """
  Validate symbol format.

  ## Examples
      iex> OrderValidator.validate_symbol("BTCUSDT")
      :ok

      iex> OrderValidator.validate_symbol("BTC")
      {:error, :invalid_symbol}
  """
  @spec validate_symbol(String.t()) :: :ok | {:error, :invalid_symbol}
  def validate_symbol(symbol) when is_binary(symbol) do
    if String.length(symbol) >= 6 do
      :ok
    else
      {:error, :invalid_symbol}
    end
  end

  def validate_symbol(_), do: {:error, :invalid_symbol}

  @doc """
  Validate order quantity against exchange filters.

  ## Parameters
  - `quantity`: Order quantity
  - `symbol_info`: Symbol trading rules (optional)

  ## Returns
  - `:ok` if quantity is valid
  - `{:error, reason}` if quantity validation fails
  """
  @spec validate_quantity(Decimal.t(), symbol_info() | nil) ::
          :ok | {:error, validation_error()}
  def validate_quantity(quantity, symbol_info \\ nil) do
    with :ok <- check_quantity_positive(quantity),
         :ok <- check_min_quantity(quantity, symbol_info),
         :ok <- check_max_quantity(quantity, symbol_info),
         :ok <- check_quantity_step(quantity, symbol_info) do
      :ok
    end
  end

  @doc """
  Validate order price based on type and exchange filters.

  ## Parameters
  - `order_type`: Type of order (:market, :limit, :stop_loss)
  - `price`: Order price (can be nil for market orders)
  - `symbol_info`: Symbol trading rules (optional)

  ## Returns
  - `:ok` if price is valid
  - `{:error, reason}` if price validation fails
  """
  @spec validate_price(:market | :limit | :stop_loss, Decimal.t() | nil, symbol_info() | nil) ::
          :ok | {:error, validation_error()}
  def validate_price(:market, _price, _symbol_info), do: :ok
  def validate_price(:limit, nil, _symbol_info), do: {:error, :price_required}
  def validate_price(:stop_loss, nil, _symbol_info), do: {:error, :price_required}

  def validate_price(_type, price, symbol_info) when is_struct(price, Decimal) do
    with :ok <- check_price_positive(price),
         :ok <- check_min_price(price, symbol_info),
         :ok <- check_max_price(price, symbol_info),
         :ok <- check_price_tick(price, symbol_info) do
      :ok
    end
  end

  def validate_price(_type, _price, _symbol_info), do: {:error, :price_required}

  @doc """
  Validate minimum notional value (price * quantity).

  The notional value must meet exchange minimum requirements.

  ## Parameters
  - `order`: Order with quantity and price
  - `symbol_info`: Symbol trading rules (optional)

  ## Returns
  - `:ok` if notional value is valid
  - `{:error, :notional_below_minimum}` if notional too small
  """
  @spec validate_notional(order(), symbol_info() | nil) ::
          :ok | {:error, :notional_below_minimum}
  def validate_notional(order, symbol_info) do
    # For market orders, we can't calculate exact notional without current price
    # So we skip this check for market orders
    if order.type == :market or is_nil(symbol_info) do
      :ok
    else
      notional = Decimal.mult(order.quantity, order.price || Decimal.new("0"))
      min_notional = symbol_info[:min_notional] || Decimal.new("10")

      if Decimal.compare(notional, min_notional) != :lt do
        :ok
      else
        Logger.warning("Order notional below minimum",
          notional: Decimal.to_string(notional),
          min_notional: Decimal.to_string(min_notional)
        )

        {:error, :notional_below_minimum}
      end
    end
  end

  @doc """
  Validate sufficient balance for order.

  ## Parameters
  - `order`: Order to validate
  - `balances`: List of account balances

  ## Returns
  - `:ok` if sufficient balance available
  - `{:error, :insufficient_balance}` if not enough funds
  """
  @spec validate_balance(order(), [balance()]) ::
          :ok | {:error, :insufficient_balance}
  def validate_balance(order, balances) do
    required_asset = get_required_asset(order)
    required_amount = calculate_required_amount(order)

    available_balance = get_available_balance(balances, required_asset)

    if Decimal.compare(available_balance, required_amount) != :lt do
      :ok
    else
      Logger.warning("Insufficient balance for order",
        required_asset: required_asset,
        required: Decimal.to_string(required_amount),
        available: Decimal.to_string(available_balance)
      )

      {:error, :insufficient_balance}
    end
  end

  # Private Functions

  defp check_quantity_positive(quantity) do
    if Decimal.positive?(quantity) do
      :ok
    else
      {:error, :quantity_below_minimum}
    end
  end

  defp check_min_quantity(quantity, nil), do: :ok

  defp check_min_quantity(quantity, symbol_info) do
    min_qty = symbol_info[:min_quantity] || Decimal.new("0")

    if Decimal.compare(quantity, min_qty) != :lt do
      :ok
    else
      {:error, :quantity_below_minimum}
    end
  end

  defp check_max_quantity(quantity, nil), do: :ok

  defp check_max_quantity(quantity, symbol_info) do
    case symbol_info[:max_quantity] do
      nil ->
        :ok

      max_qty ->
        if Decimal.compare(quantity, max_qty) != :gt do
          :ok
        else
          {:error, :quantity_above_maximum}
        end
    end
  end

  defp check_quantity_step(quantity, nil), do: :ok

  defp check_quantity_step(quantity, symbol_info) do
    case symbol_info[:step_size] do
      nil ->
        :ok

      step_size ->
        # Check if quantity is a multiple of step_size
        remainder = Decimal.rem(quantity, step_size)

        if Decimal.equal?(remainder, Decimal.new("0")) do
          :ok
        else
          {:error, :invalid_quantity_step}
        end
    end
  end

  defp check_price_positive(price) do
    if Decimal.positive?(price) do
      :ok
    else
      {:error, :price_below_minimum}
    end
  end

  defp check_min_price(price, nil), do: :ok

  defp check_min_price(price, symbol_info) do
    min_price = symbol_info[:min_price] || Decimal.new("0")

    if Decimal.compare(price, min_price) != :lt do
      :ok
    else
      {:error, :price_below_minimum}
    end
  end

  defp check_max_price(price, nil), do: :ok

  defp check_max_price(price, symbol_info) do
    case symbol_info[:max_price] do
      nil ->
        :ok

      max_price ->
        if Decimal.compare(price, max_price) != :gt do
          :ok
        else
          {:error, :price_above_maximum}
        end
    end
  end

  defp check_price_tick(price, nil), do: :ok

  defp check_price_tick(price, symbol_info) do
    case symbol_info[:tick_size] do
      nil ->
        :ok

      tick_size ->
        # Check if price is a multiple of tick_size
        remainder = Decimal.rem(price, tick_size)

        if Decimal.equal?(remainder, Decimal.new("0")) do
          :ok
        else
          {:error, :invalid_price_tick}
        end
    end
  end

  defp get_required_asset(order) do
    # Extract base and quote currency from symbol
    # For BUY orders, we need quote currency (e.g., USDT in BTCUSDT)
    # For SELL orders, we need base currency (e.g., BTC in BTCUSDT)
    case order.side do
      :buy -> extract_quote_asset(order.symbol)
      :sell -> extract_base_asset(order.symbol)
    end
  end

  defp calculate_required_amount(order) do
    case order.side do
      :buy ->
        # For buy orders, we need price * quantity in quote currency
        # If price is nil (market order), we can't calculate exact amount
        # Use a conservative estimate
        if order.price do
          Decimal.mult(order.price, order.quantity)
        else
          # For market orders, assume worst case (we'll validate at execution)
          Decimal.new("999999999")
        end

      :sell ->
        # For sell orders, we need quantity in base currency
        order.quantity
    end
  end

  defp get_available_balance(balances, asset) do
    case Enum.find(balances, fn balance -> balance.asset == asset end) do
      nil -> Decimal.new("0")
      balance -> balance.free
    end
  end

  defp extract_base_asset(symbol) do
    # Common quote currencies
    quote_currencies = ["USDT", "BUSD", "USD", "BTC", "ETH", "BNB"]

    Enum.find_value(quote_currencies, symbol, fn quote ->
      if String.ends_with?(symbol, quote) do
        String.replace_suffix(symbol, quote, "")
      end
    end)
  end

  defp extract_quote_asset(symbol) do
    # Common quote currencies in order of preference
    quote_currencies = ["USDT", "BUSD", "USD", "BTC", "ETH", "BNB"]

    Enum.find_value(quote_currencies, "USDT", fn quote ->
      if String.ends_with?(symbol, quote) do
        quote
      end
    end)
  end
end
