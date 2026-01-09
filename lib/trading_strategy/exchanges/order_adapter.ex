defmodule TradingStrategy.Exchanges.OrderAdapter do
  @moduledoc """
  Order placement adapter translating internal order format to CryptoExchange.API.place_order/2 params.

  This module handles the conversion between our internal order representation
  and the format expected by the crypto-exchange library.
  """

  alias TradingStrategy.Exchanges.Exchange

  @type internal_order :: %{
          trading_pair: String.t(),
          side: :buy | :sell,
          type: :market | :limit | :stop_loss,
          quantity: Decimal.t(),
          price: Decimal.t() | nil,
          signal_type: :entry | :exit | :stop
        }

  @type exchange_order_params :: %{
          symbol: String.t(),
          side: :BUY | :SELL,
          type: :MARKET | :LIMIT | :STOP_LOSS,
          quantity: Decimal.t(),
          price: Decimal.t() | nil
        }

  @doc """
  Translate internal order format to exchange API format and place the order.

  ## Parameters
  - `user_id`: User identifier for the exchange connection
  - `order`: Internal order structure

  ## Returns
  - `{:ok, exchange_order_response}` if order placed successfully
  - `{:error, reason}` if order placement failed

  ## Examples
      iex> OrderAdapter.place_order("user_123", %{
      ...>   trading_pair: "BTC/USDT",
      ...>   side: :buy,
      ...>   type: :market,
      ...>   quantity: Decimal.new("0.001"),
      ...>   price: nil,
      ...>   signal_type: :entry
      ...> })
      {:ok, %{order_id: "12345", status: "FILLED", ...}}
  """
  @spec place_order(String.t(), internal_order()) :: {:ok, map()} | {:error, term()}
  def place_order(user_id, order) do
    with {:ok, exchange_params} <- translate_order(order) do
      Exchange.place_order(user_id, exchange_params)
    end
  end

  @doc """
  Translate internal order format to exchange API format.

  Converts:
  - trading_pair: "BTC/USDT" -> symbol: "BTCUSDT"
  - side: :buy -> side: :BUY
  - type: :market -> type: :MARKET

  ## Parameters
  - `order`: Internal order structure

  ## Returns
  - `{:ok, exchange_params}` if translation successful
  - `{:error, reason}` if validation fails
  """
  @spec translate_order(internal_order()) :: {:ok, exchange_order_params()} | {:error, term()}
  def translate_order(order) do
    with {:ok, symbol} <- normalize_symbol(order.trading_pair),
         {:ok, side} <- normalize_side(order.side),
         {:ok, type} <- normalize_type(order.type),
         :ok <- validate_quantity(order.quantity),
         :ok <- validate_price(order.type, order.price) do
      {:ok,
       %{
         symbol: symbol,
         side: side,
         type: type,
         quantity: order.quantity,
         price: order.price
       }}
    end
  end

  @doc """
  Normalize trading pair format from "BTC/USDT" to "BTCUSDT".

  ## Examples
      iex> OrderAdapter.normalize_symbol("BTC/USDT")
      {:ok, "BTCUSDT"}

      iex> OrderAdapter.normalize_symbol("ETH/BTC")
      {:ok, "ETHBTC"}
  """
  @spec normalize_symbol(String.t()) :: {:ok, String.t()} | {:error, :invalid_symbol}
  def normalize_symbol(trading_pair) when is_binary(trading_pair) do
    symbol = String.replace(trading_pair, "/", "")

    if String.length(symbol) >= 6 do
      {:ok, symbol}
    else
      {:error, :invalid_symbol}
    end
  end

  def normalize_symbol(_), do: {:error, :invalid_symbol}

  @doc """
  Normalize order side from internal format to exchange format.

  ## Examples
      iex> OrderAdapter.normalize_side(:buy)
      {:ok, :BUY}

      iex> OrderAdapter.normalize_side(:sell)
      {:ok, :SELL}
  """
  @spec normalize_side(:buy | :sell) :: {:ok, :BUY | :SELL} | {:error, :invalid_side}
  def normalize_side(:buy), do: {:ok, :BUY}
  def normalize_side(:sell), do: {:ok, :SELL}
  def normalize_side(_), do: {:error, :invalid_side}

  @doc """
  Normalize order type from internal format to exchange format.

  ## Examples
      iex> OrderAdapter.normalize_type(:market)
      {:ok, :MARKET}

      iex> OrderAdapter.normalize_type(:limit)
      {:ok, :LIMIT}

      iex> OrderAdapter.normalize_type(:stop_loss)
      {:ok, :STOP_LOSS}
  """
  @spec normalize_type(:market | :limit | :stop_loss) ::
          {:ok, :MARKET | :LIMIT | :STOP_LOSS} | {:error, :invalid_type}
  def normalize_type(:market), do: {:ok, :MARKET}
  def normalize_type(:limit), do: {:ok, :LIMIT}
  def normalize_type(:stop_loss), do: {:ok, :STOP_LOSS}
  def normalize_type(_), do: {:error, :invalid_type}

  @doc """
  Validate order quantity.

  ## Examples
      iex> OrderAdapter.validate_quantity(Decimal.new("0.001"))
      :ok

      iex> OrderAdapter.validate_quantity(Decimal.new("0"))
      {:error, :invalid_quantity}
  """
  @spec validate_quantity(Decimal.t()) :: :ok | {:error, :invalid_quantity}
  def validate_quantity(quantity) do
    if Decimal.positive?(quantity) do
      :ok
    else
      {:error, :invalid_quantity}
    end
  end

  @doc """
  Validate price based on order type.

  Market orders don't require a price, but limit and stop_loss orders do.

  ## Examples
      iex> OrderAdapter.validate_price(:market, nil)
      :ok

      iex> OrderAdapter.validate_price(:limit, Decimal.new("50000"))
      :ok

      iex> OrderAdapter.validate_price(:limit, nil)
      {:error, :price_required}
  """
  @spec validate_price(:market | :limit | :stop_loss, Decimal.t() | nil) ::
          :ok | {:error, :price_required | :invalid_price}
  def validate_price(:market, _price), do: :ok
  def validate_price(:limit, nil), do: {:error, :price_required}
  def validate_price(:stop_loss, nil), do: {:error, :price_required}

  def validate_price(_type, price) when is_struct(price, Decimal) do
    if Decimal.positive?(price) do
      :ok
    else
      {:error, :invalid_price}
    end
  end

  def validate_price(_type, _price), do: {:error, :invalid_price}

  @doc """
  Translate exchange order response to internal format.

  Converts exchange response back to our internal representation
  for consistency across the application.

  ## Parameters
  - `exchange_response`: Response from exchange API

  ## Returns
  - Internal order representation
  """
  @spec translate_response(map()) :: map()
  def translate_response(exchange_response) do
    %{
      exchange_order_id: exchange_response[:order_id] || exchange_response["orderId"],
      symbol: exchange_response[:symbol] || exchange_response["symbol"],
      status: parse_status(exchange_response[:status] || exchange_response["status"]),
      price: exchange_response[:price] || exchange_response["price"],
      quantity: exchange_response[:quantity] || exchange_response["origQty"],
      filled_quantity:
        exchange_response[:filled_quantity] || exchange_response["executedQty"] ||
          Decimal.new("0"),
      timestamp: DateTime.utc_now()
    }
  end

  # Parse exchange status to internal status
  defp parse_status("NEW"), do: :open
  defp parse_status("PARTIALLY_FILLED"), do: :partially_filled
  defp parse_status("FILLED"), do: :filled
  defp parse_status("CANCELED"), do: :cancelled
  defp parse_status("REJECTED"), do: :rejected
  defp parse_status("EXPIRED"), do: :cancelled
  defp parse_status(status) when is_atom(status), do: status
  defp parse_status(_), do: :unknown
end
