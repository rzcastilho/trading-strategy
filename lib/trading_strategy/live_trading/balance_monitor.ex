defmodule TradingStrategy.LiveTrading.BalanceMonitor do
  @moduledoc """
  Account balance monitor tracking available funds.

  This GenServer monitors account balances and calculates available equity
  for trading, alerting when balance falls below thresholds.
  """

  use GenServer
  require Logger

  alias TradingStrategy.Exchanges.Exchange

  @type user_id :: String.t()
  @type balance_state :: %{
          user_id: user_id(),
          balances: [map()],
          total_equity_usd: Decimal.t(),
          last_updated: DateTime.t(),
          alert_threshold_pct: Decimal.t()
        }

  @refresh_interval :timer.seconds(30)
  # Alert at 10% remaining
  @default_alert_threshold Decimal.new("0.10")

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Start monitoring balance for a user.
  """
  @spec monitor_user(user_id(), Decimal.t()) :: :ok
  def monitor_user(user_id, alert_threshold \\ @default_alert_threshold) do
    GenServer.call(__MODULE__, {:monitor_user, user_id, alert_threshold})
  end

  @doc """
  Stop monitoring balance for a user.
  """
  @spec stop_monitoring(user_id()) :: :ok
  def stop_monitoring(user_id) do
    GenServer.call(__MODULE__, {:stop_monitoring, user_id})
  end

  @doc """
  Get current balance state for a user.
  """
  @spec get_balance(user_id()) :: {:ok, balance_state()} | {:error, :not_found}
  def get_balance(user_id) do
    GenServer.call(__MODULE__, {:get_balance, user_id})
  end

  @doc """
  Force an immediate balance refresh.
  """
  @spec refresh_now(user_id()) :: {:ok, balance_state()} | {:error, term()}
  def refresh_now(user_id) do
    GenServer.call(__MODULE__, {:refresh_now, user_id})
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    Logger.info("Starting Balance Monitor")
    schedule_refresh()
    {:ok, %{monitored_users: %{}}}
  end

  @impl true
  def handle_call({:monitor_user, user_id, alert_threshold}, _from, state) do
    Logger.info("Starting balance monitoring", user_id: user_id)

    initial_state = %{
      user_id: user_id,
      balances: [],
      total_equity_usd: Decimal.new("0"),
      last_updated: DateTime.utc_now(),
      alert_threshold_pct: alert_threshold
    }

    # Fetch initial balance
    updated_state =
      case fetch_balance(user_id) do
        {:ok, balances} ->
          %{initial_state | balances: balances, last_updated: DateTime.utc_now()}

        {:error, _} ->
          initial_state
      end

    new_state = put_in(state, [:monitored_users, user_id], updated_state)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:stop_monitoring, user_id}, _from, state) do
    Logger.info("Stopping balance monitoring", user_id: user_id)
    {_value, new_users} = Map.pop(state.monitored_users, user_id)
    {:reply, :ok, %{state | monitored_users: new_users}}
  end

  @impl true
  def handle_call({:get_balance, user_id}, _from, state) do
    case Map.get(state.monitored_users, user_id) do
      nil -> {:reply, {:error, :not_found}, state}
      balance_state -> {:reply, {:ok, balance_state}, state}
    end
  end

  @impl true
  def handle_call({:refresh_now, user_id}, _from, state) do
    case Map.get(state.monitored_users, user_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      balance_state ->
        case fetch_balance(user_id) do
          {:ok, balances} ->
            updated_state = %{
              balance_state
              | balances: balances,
                last_updated: DateTime.utc_now()
            }

            new_state = put_in(state, [:monitored_users, user_id], updated_state)
            {:reply, {:ok, updated_state}, new_state}

          {:error, reason} = error ->
            {:reply, error, state}
        end
    end
  end

  @impl true
  def handle_info(:refresh_balances, state) do
    new_users =
      Map.new(state.monitored_users, fn {user_id, balance_state} ->
        case fetch_balance(user_id) do
          {:ok, balances} ->
            updated = %{balance_state | balances: balances, last_updated: DateTime.utc_now()}
            {user_id, updated}

          {:error, _} ->
            {user_id, balance_state}
        end
      end)

    schedule_refresh()
    {:noreply, %{state | monitored_users: new_users}}
  end

  # Private Functions

  defp fetch_balance(user_id) do
    Exchange.get_balance(user_id)
  end

  defp schedule_refresh do
    Process.send_after(self(), :refresh_balances, @refresh_interval)
  end
end
