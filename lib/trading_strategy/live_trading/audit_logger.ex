defmodule TradingStrategy.LiveTrading.AuditLogger do
  @moduledoc """
  Audit logger recording all orders with timestamps and correlation IDs.

  Implements FR-028 requirement to log every order placement with full audit trail.
  """

  require Logger

  @type audit_entry :: %{
          correlation_id: String.t(),
          timestamp: DateTime.t(),
          user_id: String.t(),
          session_id: String.t() | nil,
          event_type: atom(),
          order_details: map(),
          result: :success | :failure,
          error_reason: term() | nil
        }

  @doc """
  Log an order placement attempt.

  ## Parameters
  - `user_id`: User identifier
  - `session_id`: Live trading session ID (optional)
  - `order`: Order details
  - `result`: Execution result (:success or :failure)
  - `error_reason`: Error reason if failed (optional)

  ## Returns
  - `correlation_id` for tracking this order through the system

  ## Examples
      iex> AuditLogger.log_order_placement("user_123", "session_456", order, :success)
      "corr_abc123def456"
  """
  @spec log_order_placement(
          String.t(),
          String.t() | nil,
          map(),
          :success | :failure,
          term() | nil
        ) :: String.t()
  def log_order_placement(user_id, session_id, order, result, error_reason \\ nil) do
    correlation_id = generate_correlation_id()

    entry = %{
      correlation_id: correlation_id,
      timestamp: DateTime.utc_now(),
      user_id: user_id,
      session_id: session_id,
      event_type: :order_placement,
      order_details: sanitize_order_details(order),
      result: result,
      error_reason: error_reason
    }

    log_audit_entry(entry)

    correlation_id
  end

  @doc """
  Log an order cancellation.
  """
  @spec log_order_cancellation(
          String.t(),
          String.t() | nil,
          String.t(),
          String.t(),
          :success | :failure,
          term() | nil
        ) :: String.t()
  def log_order_cancellation(user_id, session_id, symbol, order_id, result, error_reason \\ nil) do
    correlation_id = generate_correlation_id()

    entry = %{
      correlation_id: correlation_id,
      timestamp: DateTime.utc_now(),
      user_id: user_id,
      session_id: session_id,
      event_type: :order_cancellation,
      order_details: %{symbol: symbol, order_id: order_id},
      result: result,
      error_reason: error_reason
    }

    log_audit_entry(entry)

    correlation_id
  end

  @doc """
  Log a session event.
  """
  @spec log_session_event(String.t(), String.t(), atom(), map()) :: String.t()
  def log_session_event(user_id, session_id, event_type, details) do
    correlation_id = generate_correlation_id()

    entry = %{
      correlation_id: correlation_id,
      timestamp: DateTime.utc_now(),
      user_id: user_id,
      session_id: session_id,
      event_type: event_type,
      order_details: details,
      result: :success,
      error_reason: nil
    }

    log_audit_entry(entry)

    correlation_id
  end

  @doc """
  Log an emergency stop event.
  """
  @spec log_emergency_stop(String.t(), String.t() | nil, map()) :: String.t()
  def log_emergency_stop(user_id, session_id, details) do
    correlation_id = generate_correlation_id()

    entry = %{
      correlation_id: correlation_id,
      timestamp: DateTime.utc_now(),
      user_id: user_id,
      session_id: session_id,
      event_type: :emergency_stop,
      order_details: details,
      result: :success,
      error_reason: nil
    }

    # Log with ERROR level for emergency stops
    Logger.error(
      "AUDIT: Emergency Stop Executed",
      entry
      |> Map.put(:level, :critical)
    )

    correlation_id
  end

  # Private Functions

  defp generate_correlation_id do
    "corr_" <> (:crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower))
  end

  defp log_audit_entry(entry) do
    # Log to Elixir Logger (which can be configured to write to files, external systems, etc.)
    Logger.info("AUDIT: #{entry.event_type}",
      correlation_id: entry.correlation_id,
      timestamp: DateTime.to_iso8601(entry.timestamp),
      user_id: entry.user_id,
      session_id: entry.session_id,
      event_type: entry.event_type,
      result: entry.result,
      order_details: inspect(entry.order_details),
      error_reason: if(entry.error_reason, do: inspect(entry.error_reason), else: nil)
    )

    # In production, you might also:
    # - Write to dedicated audit log file
    # - Send to external audit system
    # - Store in audit database table
    # - Send to SIEM system
  end

  defp sanitize_order_details(order) do
    # Remove any sensitive information from order details before logging
    # (Though order details shouldn't contain credentials)
    Map.drop(order, [:api_key, :api_secret, :passphrase])
  end
end
