defmodule TradingStrategy.Exchanges.RetryHandler do
  @moduledoc """
  Request retry logic wrapping CryptoExchange.API calls with exponential backoff for transient failures.

  This module provides automatic retry functionality for exchange API calls,
  using exponential backoff to handle temporary network issues, rate limiting,
  and other transient failures.
  """

  require Logger

  @type retry_opts :: [
          max_attempts: pos_integer(),
          base_delay: pos_integer(),
          max_delay: pos_integer(),
          backoff_factor: number(),
          retryable_errors: [atom()]
        ]

  # Default retry configuration
  @default_max_attempts 3
  # 1 second
  @default_base_delay 1000
  # 8 seconds
  @default_max_delay 8000
  @default_backoff_factor 2.0

  # Errors that should trigger a retry
  @default_retryable_errors [
    :timeout,
    :connection_failed,
    :network_error,
    :rate_limited,
    :service_unavailable,
    :gateway_timeout,
    :connection_refused,
    :nxdomain
  ]

  @doc """
  Execute a function with automatic retry on transient failures.

  ## Parameters
  - `fun`: Zero-arity function to execute (should return {:ok, result} | {:error, reason})
  - `opts`: Keyword list of retry options (optional)

  ## Options
  - `:max_attempts` - Maximum number of attempts (default: 3)
  - `:base_delay` - Initial delay in milliseconds (default: 1000)
  - `:max_delay` - Maximum delay in milliseconds (default: 8000)
  - `:backoff_factor` - Exponential backoff multiplier (default: 2.0)
  - `:retryable_errors` - List of error atoms that should trigger retry

  ## Returns
  - `{:ok, result}` if function succeeds
  - `{:error, reason}` if all retries exhausted or non-retryable error occurs

  ## Examples
      iex> RetryHandler.with_retry(fn ->
      ...>   Exchange.get_balance("user_123")
      ...> end)
      {:ok, [%{asset: "BTC", free: Decimal.new("1.5"), ...}]}

      iex> RetryHandler.with_retry(fn ->
      ...>   Exchange.place_order("user_123", order_params)
      ...> end, max_attempts: 5, base_delay: 2000)
      {:ok, %{order_id: "12345", ...}}
  """
  @spec with_retry((-> {:ok, term()} | {:error, term()}), retry_opts()) ::
          {:ok, term()} | {:error, term()}
  def with_retry(fun, opts \\ []) when is_function(fun, 0) do
    max_attempts = Keyword.get(opts, :max_attempts, @default_max_attempts)
    base_delay = Keyword.get(opts, :base_delay, @default_base_delay)
    max_delay = Keyword.get(opts, :max_delay, @default_max_delay)
    backoff_factor = Keyword.get(opts, :backoff_factor, @default_backoff_factor)
    retryable_errors = Keyword.get(opts, :retryable_errors, @default_retryable_errors)

    do_retry(fun, 1, max_attempts, base_delay, max_delay, backoff_factor, retryable_errors)
  end

  @doc """
  Check if an error is retryable.

  ## Parameters
  - `error`: Error term
  - `retryable_errors`: List of retryable error atoms (optional)

  ## Returns
  - `true` if error should trigger a retry
  - `false` if error is not retryable

  ## Examples
      iex> RetryHandler.retryable?(:timeout)
      true

      iex> RetryHandler.retryable?(:invalid_credentials)
      false
  """
  @spec retryable?(term(), [atom()]) :: boolean()
  def retryable?(error, retryable_errors \\ @default_retryable_errors)

  def retryable?(error, retryable_errors) when is_atom(error) do
    error in retryable_errors
  end

  def retryable?({error, _details}, retryable_errors) when is_atom(error) do
    error in retryable_errors
  end

  def retryable?(error, retryable_errors) when is_binary(error) do
    # Try to match common error strings
    error_lower = String.downcase(error)

    Enum.any?(retryable_errors, fn retryable_error ->
      error_str = Atom.to_string(retryable_error)
      String.contains?(error_lower, error_str)
    end)
  end

  def retryable?(_error, _retryable_errors), do: false

  @doc """
  Calculate delay for next retry attempt using exponential backoff.

  ## Parameters
  - `attempt`: Current attempt number (1-indexed)
  - `base_delay`: Base delay in milliseconds
  - `max_delay`: Maximum delay in milliseconds
  - `backoff_factor`: Exponential backoff multiplier

  ## Returns
  - Delay in milliseconds for next attempt

  ## Examples
      iex> RetryHandler.calculate_delay(1, 1000, 8000, 2.0)
      1000

      iex> RetryHandler.calculate_delay(2, 1000, 8000, 2.0)
      2000

      iex> RetryHandler.calculate_delay(3, 1000, 8000, 2.0)
      4000

      iex> RetryHandler.calculate_delay(10, 1000, 8000, 2.0)
      8000  # Capped at max_delay
  """
  @spec calculate_delay(pos_integer(), pos_integer(), pos_integer(), number()) :: pos_integer()
  def calculate_delay(attempt, base_delay, max_delay, backoff_factor) do
    # Calculate exponential backoff: base_delay * (backoff_factor ^ (attempt - 1))
    delay =
      (base_delay * :math.pow(backoff_factor, attempt - 1))
      |> round()
      |> min(max_delay)

    # Add jitter (random variation of ±20%) to prevent thundering herd
    jitter = round(delay * 0.2 * (:rand.uniform() - 0.5))
    max(delay + jitter, base_delay)
  end

  # Private Functions

  defp do_retry(
         fun,
         attempt,
         max_attempts,
         _base_delay,
         _max_delay,
         _backoff_factor,
         _retryable_errors
       )
       when attempt > max_attempts do
    Logger.error("All retry attempts exhausted", max_attempts: max_attempts)
    {:error, :max_retries_exceeded}
  end

  defp do_retry(
         fun,
         attempt,
         max_attempts,
         base_delay,
         max_delay,
         backoff_factor,
         retryable_errors
       ) do
    case fun.() do
      {:ok, _result} = success ->
        if attempt > 1 do
          Logger.info("Request succeeded after retry", attempt: attempt)
        end

        success

      {:error, reason} = error ->
        if retryable?(reason, retryable_errors) and attempt < max_attempts do
          delay = calculate_delay(attempt, base_delay, max_delay, backoff_factor)

          Logger.warning("Request failed, retrying",
            attempt: attempt,
            max_attempts: max_attempts,
            reason: inspect(reason),
            retry_in_ms: delay
          )

          # Sleep before retry
          Process.sleep(delay)

          # Retry with incremented attempt
          do_retry(
            fun,
            attempt + 1,
            max_attempts,
            base_delay,
            max_delay,
            backoff_factor,
            retryable_errors
          )
        else
          if attempt >= max_attempts do
            Logger.error("Max retry attempts reached",
              attempt: attempt,
              reason: inspect(reason)
            )
          else
            Logger.error("Non-retryable error encountered",
              reason: inspect(reason)
            )
          end

          error
        end
    end
  end

  @doc """
  Wrap an exchange API call with retry logic.

  Convenience function for common exchange operations.

  ## Parameters
  - `operation`: Atom describing the operation (for logging)
  - `fun`: Function to execute
  - `opts`: Retry options (optional)

  ## Examples
      iex> RetryHandler.call_with_retry(:get_balance, fn ->
      ...>   Exchange.get_balance("user_123")
      ...> end)
      {:ok, balances}
  """
  @spec call_with_retry(atom(), (-> {:ok, term()} | {:error, term()}), retry_opts()) ::
          {:ok, term()} | {:error, term()}
  def call_with_retry(operation, fun, opts \\ []) do
    Logger.debug("Calling exchange API with retry", operation: operation)

    with_retry(fun, opts)
  end
end
