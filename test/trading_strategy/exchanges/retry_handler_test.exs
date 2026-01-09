defmodule TradingStrategy.Exchanges.RetryHandlerTest do
  use ExUnit.Case, async: true

  alias TradingStrategy.Exchanges.RetryHandler

  describe "retryable?/2" do
    test "returns true for timeout error" do
      assert RetryHandler.retryable?(:timeout)
    end

    test "returns true for connection_failed error" do
      assert RetryHandler.retryable?(:connection_failed)
    end

    test "returns true for network_error" do
      assert RetryHandler.retryable?(:network_error)
    end

    test "returns true for rate_limited error" do
      assert RetryHandler.retryable?(:rate_limited)
    end

    test "returns true for service_unavailable error" do
      assert RetryHandler.retryable?(:service_unavailable)
    end

    test "returns true for gateway_timeout error" do
      assert RetryHandler.retryable?(:gateway_timeout)
    end

    test "returns false for invalid_credentials error" do
      refute RetryHandler.retryable?(:invalid_credentials)
    end

    test "returns false for insufficient_balance error" do
      refute RetryHandler.retryable?(:insufficient_balance)
    end

    test "returns false for invalid_symbol error" do
      refute RetryHandler.retryable?(:invalid_symbol)
    end

    test "handles error tuples with details" do
      assert RetryHandler.retryable?({:timeout, "connection timeout"})
      refute RetryHandler.retryable?({:invalid_credentials, "bad api key"})
    end

    test "handles string errors with matching substring" do
      assert RetryHandler.retryable?("Connection timeout occurred")
      assert RetryHandler.retryable?("Network error: connection refused")
      assert RetryHandler.retryable?("Rate limited - try again later")
    end

    test "returns false for non-matching string errors" do
      refute RetryHandler.retryable?("Invalid API credentials")
      refute RetryHandler.retryable?("Order rejected")
    end

    test "supports custom retryable errors list" do
      custom_errors = [:custom_error, :another_error]
      assert RetryHandler.retryable?(:custom_error, custom_errors)
      refute RetryHandler.retryable?(:timeout, custom_errors)
    end

    test "returns false for non-error terms" do
      refute RetryHandler.retryable?(12345)
      refute RetryHandler.retryable?(%{error: "test"})
      refute RetryHandler.retryable?(nil)
    end
  end

  describe "calculate_delay/4" do
    test "returns base delay for first attempt" do
      assert RetryHandler.calculate_delay(1, 1000, 8000, 2.0) >= 800
      assert RetryHandler.calculate_delay(1, 1000, 8000, 2.0) <= 1200
    end

    test "doubles delay for second attempt" do
      delay = RetryHandler.calculate_delay(2, 1000, 8000, 2.0)
      # 2000 - 20% jitter
      assert delay >= 1600
      # 2000 + 20% jitter
      assert delay <= 2400
    end

    test "quadruples delay for third attempt" do
      delay = RetryHandler.calculate_delay(3, 1000, 8000, 2.0)
      # 4000 - 20% jitter
      assert delay >= 3200
      # 4000 + 20% jitter
      assert delay <= 4800
    end

    test "caps delay at max_delay" do
      delay = RetryHandler.calculate_delay(10, 1000, 8000, 2.0)
      # 8000 + 20% jitter = max possible
      assert delay <= 9600
    end

    test "respects custom backoff factor" do
      delay = RetryHandler.calculate_delay(2, 1000, 10000, 3.0)
      # 3000 - 20% jitter
      assert delay >= 2400
      # 3000 + 20% jitter
      assert delay <= 3600
    end

    test "never returns delay less than base_delay" do
      # Even with jitter, should never go below base_delay
      delay = RetryHandler.calculate_delay(1, 1000, 8000, 2.0)
      assert delay >= 1000
    end

    test "adds random jitter to prevent thundering herd" do
      # Call multiple times, expect different values due to jitter
      delays =
        for _ <- 1..10 do
          RetryHandler.calculate_delay(2, 1000, 8000, 2.0)
        end

      # Should have some variation (not all identical)
      unique_delays = Enum.uniq(delays)
      assert length(unique_delays) > 1
    end
  end

  describe "with_retry/2" do
    test "returns success immediately on first attempt" do
      result =
        RetryHandler.with_retry(fn ->
          {:ok, "success"}
        end)

      assert {:ok, "success"} = result
    end

    test "retries on retryable error and succeeds" do
      # Use Agent to track call count
      {:ok, agent} = Agent.start_link(fn -> 0 end)

      result =
        RetryHandler.with_retry(
          fn ->
            count = Agent.get_and_update(agent, fn count -> {count, count + 1} end)

            if count < 2 do
              {:error, :timeout}
            else
              {:ok, "success after retries"}
            end
          end,
          base_delay: 10
        )

      assert {:ok, "success after retries"} = result
      # Called 3 times
      assert Agent.get(agent, & &1) == 3
    end

    test "returns error immediately for non-retryable error" do
      {:ok, agent} = Agent.start_link(fn -> 0 end)

      result =
        RetryHandler.with_retry(
          fn ->
            Agent.update(agent, &(&1 + 1))
            {:error, :invalid_credentials}
          end,
          base_delay: 10
        )

      assert {:error, :invalid_credentials} = result
      # Only called once
      assert Agent.get(agent, & &1) == 1
    end

    test "exhausts retries and returns max_retries_exceeded" do
      {:ok, agent} = Agent.start_link(fn -> 0 end)

      result =
        RetryHandler.with_retry(
          fn ->
            Agent.update(agent, &(&1 + 1))
            {:error, :timeout}
          end,
          max_attempts: 3,
          base_delay: 10
        )

      assert {:error, :timeout} = result
      # Tried 3 times
      assert Agent.get(agent, & &1) == 3
    end

    test "respects custom max_attempts" do
      {:ok, agent} = Agent.start_link(fn -> 0 end)

      result =
        RetryHandler.with_retry(
          fn ->
            Agent.update(agent, &(&1 + 1))
            {:error, :rate_limited}
          end,
          max_attempts: 5,
          base_delay: 10
        )

      assert {:error, :rate_limited} = result
      assert Agent.get(agent, & &1) == 5
    end

    test "respects custom retryable_errors" do
      {:ok, agent} = Agent.start_link(fn -> 0 end)

      result =
        RetryHandler.with_retry(
          fn ->
            Agent.update(agent, &(&1 + 1))
            {:error, :custom_error}
          end,
          retryable_errors: [:custom_error],
          max_attempts: 3,
          base_delay: 10
        )

      assert {:error, :custom_error} = result
      # Retried because :custom_error is in retryable list
      assert Agent.get(agent, & &1) == 3
    end

    test "does not retry custom error when not in retryable list" do
      {:ok, agent} = Agent.start_link(fn -> 0 end)

      result =
        RetryHandler.with_retry(
          fn ->
            Agent.update(agent, &(&1 + 1))
            {:error, :custom_error}
          end,
          # Uses default retryable_errors
          base_delay: 10
        )

      assert {:error, :custom_error} = result
      # No retry
      assert Agent.get(agent, & &1) == 1
    end

    test "handles function that raises exception" do
      assert_raise RuntimeError, "Intentional error", fn ->
        RetryHandler.with_retry(fn ->
          raise "Intentional error"
        end)
      end
    end

    test "waits between retry attempts" do
      start_time = System.monotonic_time(:millisecond)

      RetryHandler.with_retry(
        fn ->
          {:error, :timeout}
        end,
        max_attempts: 3,
        base_delay: 50,
        max_delay: 200
      )

      elapsed = System.monotonic_time(:millisecond) - start_time

      # With 3 attempts and base_delay 50ms: delay after attempt 1 ~50ms, delay after attempt 2 ~100ms
      # Total should be at least 100ms (accounting for jitter and execution time)
      assert elapsed >= 100
    end
  end

  describe "call_with_retry/3" do
    test "calls function with retry and returns success" do
      result =
        RetryHandler.call_with_retry(:get_balance, fn ->
          {:ok, [%{asset: "BTC", free: Decimal.new("1.5")}]}
        end)

      assert {:ok, balances} = result
      assert length(balances) == 1
    end

    test "retries operation on transient failure" do
      {:ok, agent} = Agent.start_link(fn -> 0 end)

      result =
        RetryHandler.call_with_retry(
          :place_order,
          fn ->
            count = Agent.get_and_update(agent, fn count -> {count, count + 1} end)

            if count < 1 do
              {:error, :network_error}
            else
              {:ok, %{order_id: "12345"}}
            end
          end,
          base_delay: 10
        )

      assert {:ok, %{order_id: "12345"}} = result
      assert Agent.get(agent, & &1) == 2
    end

    test "returns error after exhausting retries" do
      result =
        RetryHandler.call_with_retry(
          :cancel_order,
          fn ->
            {:error, :connection_failed}
          end,
          max_attempts: 2,
          base_delay: 10
        )

      assert {:error, :connection_failed} = result
    end

    test "accepts custom retry options" do
      {:ok, agent} = Agent.start_link(fn -> 0 end)

      result =
        RetryHandler.call_with_retry(
          :get_order_status,
          fn ->
            Agent.update(agent, &(&1 + 1))
            {:error, :timeout}
          end,
          max_attempts: 4,
          base_delay: 20,
          max_delay: 5000,
          backoff_factor: 1.5
        )

      assert {:error, :timeout} = result
      assert Agent.get(agent, & &1) == 4
    end
  end

  describe "integration scenarios" do
    test "simulates rate limited exchange call with eventual success" do
      {:ok, agent} = Agent.start_link(fn -> 0 end)

      result =
        RetryHandler.with_retry(
          fn ->
            count = Agent.get_and_update(agent, fn count -> {count, count + 1} end)

            case count do
              0 -> {:error, :rate_limited}
              1 -> {:error, :rate_limited}
              2 -> {:ok, %{status: "success"}}
            end
          end,
          max_attempts: 5,
          base_delay: 10
        )

      assert {:ok, %{status: "success"}} = result
      assert Agent.get(agent, & &1) == 3
    end

    test "simulates network instability with mixed errors" do
      {:ok, agent} = Agent.start_link(fn -> 0 end)

      result =
        RetryHandler.with_retry(
          fn ->
            count = Agent.get_and_update(agent, fn count -> {count, count + 1} end)

            case count do
              0 -> {:error, :timeout}
              1 -> {:error, :network_error}
              2 -> {:error, :connection_failed}
              3 -> {:ok, %{recovered: true}}
            end
          end,
          max_attempts: 5,
          base_delay: 10
        )

      assert {:ok, %{recovered: true}} = result
    end

    test "fails fast on permanent error even with retries remaining" do
      {:ok, agent} = Agent.start_link(fn -> 0 end)

      result =
        RetryHandler.with_retry(
          fn ->
            Agent.update(agent, &(&1 + 1))
            {:error, :insufficient_balance}
          end,
          max_attempts: 5,
          base_delay: 10
        )

      assert {:error, :insufficient_balance} = result
      # No retries for non-retryable error
      assert Agent.get(agent, & &1) == 1
    end
  end
end
