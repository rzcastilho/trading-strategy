defmodule TradingStrategy.Config do
  @moduledoc """
  Configuration module for trading strategy settings.

  Loads and manages configuration for:
  - Exchange API keys and credentials
  - Rate limits for API calls
  - Risk management parameters
  - Trading mode settings
  """

  @doc """
  Gets the exchange configuration for a specific exchange.

  ## Parameters
    - exchange: String.t() - Exchange name (e.g., "binance", "coinbase")

  ## Returns
    - map() with exchange configuration
  """
  def get_exchange_config(exchange) do
    Application.get_env(:trading_strategy, :exchanges, %{})
    |> Map.get(String.to_atom(exchange), %{})
  end

  @doc """
  Gets the API key for a specific exchange.

  ## Parameters
    - exchange: String.t() - Exchange name

  ## Returns
    - String.t() - API key or nil
  """
  def get_api_key(exchange) do
    get_exchange_config(exchange)
    |> Map.get(:api_key)
  end

  @doc """
  Gets the API secret for a specific exchange.

  ## Parameters
    - exchange: String.t() - Exchange name

  ## Returns
    - String.t() - API secret or nil
  """
  def get_api_secret(exchange) do
    get_exchange_config(exchange)
    |> Map.get(:api_secret)
  end

  @doc """
  Gets the rate limits for a specific exchange.

  ## Returns
    - map() with rate limit configuration
  """
  def get_rate_limits(exchange) do
    get_exchange_config(exchange)
    |> Map.get(:rate_limits, %{requests_per_second: 10, requests_per_minute: 100})
  end

  @doc """
  Gets the risk management parameters.

  ## Returns
    - map() with risk parameters
  """
  def get_risk_parameters do
    Application.get_env(:trading_strategy, :risk_parameters, %{
      max_position_size: 0.1,
      max_daily_loss: 0.03,
      max_drawdown: 0.15,
      max_leverage: 1.0
    })
  end

  @doc """
  Gets the default trading mode.

  ## Returns
    - String.t() - "backtest", "paper", or "live"
  """
  def get_trading_mode do
    Application.get_env(:trading_strategy, :trading_mode, "paper")
  end

  @doc """
  Validates the configuration for a specific exchange.

  ## Parameters
    - exchange: String.t() - Exchange name

  ## Returns
    - :ok | {:error, reasons}
  """
  def validate_exchange_config(exchange) do
    config = get_exchange_config(exchange)

    cond do
      config == %{} ->
        {:error, ["Exchange configuration not found for #{exchange}"]}

      is_nil(config[:api_key]) ->
        {:error, ["API key not configured for #{exchange}"]}

      is_nil(config[:api_secret]) ->
        {:error, ["API secret not configured for #{exchange}"]}

      true ->
        :ok
    end
  end
end
