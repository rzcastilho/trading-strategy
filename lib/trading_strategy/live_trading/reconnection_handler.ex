defmodule TradingStrategy.LiveTrading.ReconnectionHandler do
  @moduledoc """
  Reconnection handler resuming after disconnection.

  Implements exponential backoff reconnection strategy when
  exchange connectivity is lost.
  """

  require Logger

  alias TradingStrategy.Exchanges.{Exchange, Credentials}

  @type user_id :: String.t()
  @type reconnection_opts :: [
          max_attempts: pos_integer(),
          base_delay: pos_integer(),
          max_delay: pos_integer(),
          backoff_factor: number()
        ]

  @default_max_attempts 10
  @default_base_delay :timer.seconds(2)
  @default_max_delay :timer.seconds(60)
  @default_backoff_factor 2.0

  @doc """
  Attempt to reconnect a user to the exchange.

  Uses exponential backoff with configurable parameters.

  ## Parameters
  - `user_id`: User identifier
  - `opts`: Reconnection options (optional)

  ## Returns
  - `{:ok, user_pid}` if reconnection successful
  - `{:error, reason}` if all attempts failed

  ## Examples
      iex> ReconnectionHandler.reconnect("user_123")
      {:ok, #PID<0.123.0>}
  """
  @spec reconnect(user_id(), reconnection_opts()) :: {:ok, pid()} | {:error, term()}
  def reconnect(user_id, opts \\ []) do
    max_attempts = Keyword.get(opts, :max_attempts, @default_max_attempts)
    base_delay = Keyword.get(opts, :base_delay, @default_base_delay)
    max_delay = Keyword.get(opts, :max_delay, @default_max_delay)
    backoff_factor = Keyword.get(opts, :backoff_factor, @default_backoff_factor)

    Logger.warning("Starting reconnection attempts",
      user_id: user_id,
      max_attempts: max_attempts
    )

    do_reconnect(user_id, 1, max_attempts, base_delay, max_delay, backoff_factor)
  end

  @doc """
  Calculate delay for next reconnection attempt.
  """
  @spec calculate_delay(pos_integer(), pos_integer(), pos_integer(), number()) :: pos_integer()
  def calculate_delay(attempt, base_delay, max_delay, backoff_factor) do
    delay =
      (base_delay * :math.pow(backoff_factor, attempt - 1))
      |> round()
      |> min(max_delay)

    # Add jitter
    jitter = round(delay * 0.2 * (:rand.uniform() - 0.5))
    max(delay + jitter, base_delay)
  end

  # Private Functions

  defp do_reconnect(_user_id, attempt, max_attempts, _base_delay, _max_delay, _backoff_factor)
       when attempt > max_attempts do
    Logger.error("All reconnection attempts exhausted", max_attempts: max_attempts)
    {:error, :max_reconnection_attempts_exceeded}
  end

  defp do_reconnect(user_id, attempt, max_attempts, base_delay, max_delay, backoff_factor) do
    Logger.info("Reconnection attempt",
      user_id: user_id,
      attempt: attempt,
      max_attempts: max_attempts
    )

    case attempt_connection(user_id) do
      {:ok, user_pid} ->
        Logger.info("Reconnection successful",
          user_id: user_id,
          attempt: attempt
        )

        {:ok, user_pid}

      {:error, reason} ->
        if attempt < max_attempts do
          delay = calculate_delay(attempt, base_delay, max_delay, backoff_factor)

          Logger.warning("Reconnection failed, retrying",
            user_id: user_id,
            attempt: attempt,
            reason: inspect(reason),
            retry_in_ms: delay
          )

          Process.sleep(delay)

          do_reconnect(user_id, attempt + 1, max_attempts, base_delay, max_delay, backoff_factor)
        else
          Logger.error("Reconnection failed - max attempts reached",
            user_id: user_id,
            reason: inspect(reason)
          )

          {:error, reason}
        end
    end
  end

  defp attempt_connection(user_id) do
    # Retrieve stored credentials
    case Credentials.get(user_id) do
      {:ok, credentials} ->
        Exchange.connect_user(user_id, credentials.api_key, credentials.api_secret)

      {:error, :not_found} ->
        Logger.error("Cannot reconnect - credentials not found", user_id: user_id)
        {:error, :credentials_not_found}
    end
  end
end
