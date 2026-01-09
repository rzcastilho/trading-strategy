defmodule TradingStrategy.Backtesting.PositionManager do
  @moduledoc """
  Manages position tracking during backtest execution.

  Tracks open positions, available capital, and calculates profit/loss
  for both realized and unrealized positions.
  """

  defstruct [
    :initial_capital,
    :available_capital,
    :current_position,
    :closed_positions,
    :total_realized_pnl
  ]

  @type t :: %__MODULE__{
          initial_capital: float(),
          available_capital: float(),
          current_position: map() | nil,
          closed_positions: list(map()),
          total_realized_pnl: float()
        }

  @doc """
  Initializes a new position manager with starting capital.

  ## Examples

      iex> PositionManager.init(10000)
      %PositionManager{
        initial_capital: 10000,
        available_capital: 10000,
        current_position: nil,
        closed_positions: [],
        total_realized_pnl: 0
      }
  """
  @spec init(number()) :: t()
  def init(initial_capital) do
    %__MODULE__{
      initial_capital: initial_capital / 1.0,
      available_capital: initial_capital / 1.0,
      current_position: nil,
      closed_positions: [],
      total_realized_pnl: 0.0
    }
  end

  @doc """
  Opens a new position.

  ## Parameters
    - `manager`: PositionManager state
    - `symbol`: Trading pair
    - `side`: :long or :short
    - `entry_price`: Entry price
    - `quantity`: Position size
    - `timestamp`: Entry timestamp

  ## Returns
    - `{:ok, updated_manager}` - Success
    - `{:error, reason}` - Cannot open (position already open, insufficient capital)
  """
  @spec open_position(t(), String.t(), atom(), number(), number(), DateTime.t()) ::
          {:ok, t()} | {:error, String.t()}
  def open_position(manager, symbol, side, entry_price, quantity, timestamp) do
    if manager.current_position != nil do
      {:error, "Position already open"}
    else
      cost = entry_price * quantity

      if cost > manager.available_capital do
        {:error, "Insufficient capital"}
      else
        position = %{
          symbol: symbol,
          side: side,
          entry_price: entry_price / 1.0,
          quantity: quantity / 1.0,
          entry_timestamp: timestamp,
          unrealized_pnl: 0.0
        }

        updated_manager = %{
          manager
          | current_position: position,
            available_capital: manager.available_capital - cost
        }

        {:ok, updated_manager}
      end
    end
  end

  @doc """
  Closes the current position.

  ## Parameters
    - `manager`: PositionManager state
    - `exit_price`: Exit price
    - `timestamp`: Exit timestamp

  ## Returns
    - `{:ok, updated_manager, pnl}` - Success with realized PnL
    - `{:error, reason}` - No open position
  """
  @spec close_position(t(), number(), DateTime.t()) ::
          {:ok, t(), float()} | {:error, String.t()}
  def close_position(manager, exit_price, timestamp) do
    case manager.current_position do
      nil ->
        {:error, "No open position to close"}

      position ->
        # Calculate realized PnL
        pnl =
          case position.side do
            :long -> (exit_price - position.entry_price) * position.quantity
            :short -> (position.entry_price - exit_price) * position.quantity
          end

        # Return capital plus profit/loss
        proceeds = exit_price * position.quantity + pnl

        closed_position =
          Map.merge(position, %{
            exit_price: exit_price / 1.0,
            exit_timestamp: timestamp,
            realized_pnl: pnl / 1.0
          })

        updated_manager = %{
          manager
          | current_position: nil,
            available_capital: manager.available_capital + proceeds,
            closed_positions: [closed_position | manager.closed_positions],
            total_realized_pnl: manager.total_realized_pnl + pnl
        }

        {:ok, updated_manager, pnl}
    end
  end

  @doc """
  Checks if there's an open position.
  """
  @spec has_open_position?(t()) :: boolean()
  def has_open_position?(manager) do
    manager.current_position != nil
  end

  @doc """
  Gets the current open position.

  ## Returns
    - `{:ok, position}` - Position details
    - `{:error, :no_position}` - No open position
  """
  @spec get_current_position(t()) :: {:ok, map()} | {:error, :no_position}
  def get_current_position(manager) do
    case manager.current_position do
      nil -> {:error, :no_position}
      position -> {:ok, position}
    end
  end

  @doc """
  Gets available capital for new positions.
  """
  @spec get_available_capital(t()) :: float()
  def get_available_capital(manager) do
    manager.available_capital
  end

  @doc """
  Calculates unrealized PnL for current position at a given price.

  ## Parameters
    - `manager`: PositionManager state
    - `current_price`: Current market price

  ## Returns
    - `{:ok, unrealized_pnl}` - PnL value
    - `{:error, :no_position}` - No open position
  """
  @spec calculate_unrealized_pnl(t(), number()) :: {:ok, float()} | {:error, :no_position}
  def calculate_unrealized_pnl(manager, current_price) do
    case manager.current_position do
      nil ->
        {:error, :no_position}

      position ->
        pnl =
          case position.side do
            :long -> (current_price - position.entry_price) * position.quantity
            :short -> (position.entry_price - current_price) * position.quantity
          end

        {:ok, pnl / 1.0}
    end
  end

  @doc """
  Calculates total equity (capital + unrealized PnL).

  ## Parameters
    - `manager`: PositionManager state
    - `current_price`: Current market price (optional, for unrealized PnL)

  ## Returns
    - Total equity value
  """
  @spec calculate_total_equity(t(), number() | nil) :: float()
  def calculate_total_equity(manager, current_price \\ nil) do
    base_equity = manager.available_capital

    if current_price && manager.current_position do
      {:ok, unrealized} = calculate_unrealized_pnl(manager, current_price)
      base_equity + unrealized
    else
      base_equity
    end
  end

  @doc """
  Gets all closed positions.
  """
  @spec get_closed_positions(t()) :: list(map())
  def get_closed_positions(manager) do
    Enum.reverse(manager.closed_positions)
  end

  @doc """
  Gets total realized PnL across all closed positions.
  """
  @spec get_total_realized_pnl(t()) :: float()
  def get_total_realized_pnl(manager) do
    manager.total_realized_pnl
  end
end
