defmodule TradingStrategy.PaperTrading.PositionTracker do
  @moduledoc """
  Tracks open positions for paper trading sessions.

  Manages position state including entry price, quantity, side, and calculates
  unrealized and realized P&L based on current market prices.

  Similar to backtesting PositionManager but designed for real-time operation
  with live market data updates.
  """

  defstruct [
    :initial_capital,
    :available_capital,
    :open_positions,
    :closed_positions,
    :total_realized_pnl,
    :total_unrealized_pnl,
    :position_sizing_mode,
    :position_size_pct
  ]

  @type position :: %{
          position_id: String.t(),
          symbol: String.t(),
          side: :long | :short,
          entry_price: float(),
          quantity: float(),
          entry_timestamp: DateTime.t(),
          unrealized_pnl: float()
        }

  @type closed_position :: %{
          position_id: String.t(),
          symbol: String.t(),
          side: :long | :short,
          entry_price: float(),
          quantity: float(),
          entry_timestamp: DateTime.t(),
          exit_price: float(),
          exit_timestamp: DateTime.t(),
          realized_pnl: float()
        }

  @type t :: %__MODULE__{
          initial_capital: float(),
          available_capital: float(),
          open_positions: %{String.t() => position()},
          closed_positions: list(closed_position()),
          total_realized_pnl: float(),
          total_unrealized_pnl: float(),
          position_sizing_mode: :percentage | :fixed_amount,
          position_size_pct: float()
        }

  @doc """
  Initializes a new position tracker with starting capital.

  ## Parameters
    - `initial_capital`: Starting capital amount
    - `opts`: Options
      - `:position_sizing`: :percentage or :fixed_amount (default: :percentage)
      - `:position_size_pct`: Percentage of capital per trade (default: 0.1 = 10%)

  ## Examples

      iex> PositionTracker.init(10000, position_sizing: :percentage, position_size_pct: 0.1)
      %PositionTracker{
        initial_capital: 10000.0,
        available_capital: 10000.0,
        open_positions: %{},
        closed_positions: [],
        total_realized_pnl: 0.0,
        total_unrealized_pnl: 0.0,
        position_sizing_mode: :percentage,
        position_size_pct: 0.1
      }
  """
  @spec init(number(), keyword()) :: t()
  def init(initial_capital, opts \\ []) do
    %__MODULE__{
      initial_capital: initial_capital / 1.0,
      available_capital: initial_capital / 1.0,
      open_positions: %{},
      closed_positions: [],
      total_realized_pnl: 0.0,
      total_unrealized_pnl: 0.0,
      position_sizing_mode: Keyword.get(opts, :position_sizing, :percentage),
      position_size_pct: Keyword.get(opts, :position_size_pct, 0.1)
    }
  end

  @doc """
  Opens a new position.

  Calculates position size based on configured sizing mode.

  ## Parameters
    - `tracker`: PositionTracker state
    - `symbol`: Trading pair
    - `side`: :long or :short
    - `entry_price`: Entry price
    - `timestamp`: Entry timestamp
    - `opts`: Options
      - `:quantity`: Manual quantity override (optional)

  ## Returns
    - `{:ok, updated_tracker, position}` - Success with new position details
    - `{:error, reason}` - Cannot open (insufficient capital, etc.)
  """
  @spec open_position(t(), String.t(), atom(), number(), DateTime.t(), keyword()) ::
          {:ok, t(), position()} | {:error, String.t()}
  def open_position(tracker, symbol, side, entry_price, timestamp, opts \\ []) do
    # Calculate quantity based on position sizing mode
    quantity =
      case Keyword.get(opts, :quantity) do
        nil -> calculate_position_size(tracker, entry_price)
        manual_qty -> manual_qty / 1.0
      end

    cost = entry_price * quantity

    if cost > tracker.available_capital do
      {:error, "Insufficient capital: need #{cost}, have #{tracker.available_capital}"}
    else
      position_id = generate_position_id(symbol)

      position = %{
        position_id: position_id,
        symbol: symbol,
        side: side,
        entry_price: entry_price / 1.0,
        quantity: quantity,
        entry_timestamp: timestamp,
        unrealized_pnl: 0.0
      }

      updated_tracker = %{
        tracker
        | open_positions: Map.put(tracker.open_positions, position_id, position),
          available_capital: tracker.available_capital - cost
      }

      {:ok, updated_tracker, position}
    end
  end

  @doc """
  Closes an open position by position ID.

  ## Parameters
    - `tracker`: PositionTracker state
    - `position_id`: Position ID to close
    - `exit_price`: Exit price
    - `timestamp`: Exit timestamp

  ## Returns
    - `{:ok, updated_tracker, closed_position}` - Success with realized PnL
    - `{:error, reason}` - Position not found
  """
  @spec close_position(t(), String.t(), number(), DateTime.t()) ::
          {:ok, t(), closed_position()} | {:error, String.t()}
  def close_position(tracker, position_id, exit_price, timestamp) do
    case Map.get(tracker.open_positions, position_id) do
      nil ->
        {:error, "Position not found: #{position_id}"}

      position ->
        # Calculate realized PnL
        pnl =
          case position.side do
            :long -> (exit_price - position.entry_price) * position.quantity
            :short -> (position.entry_price - exit_price) * position.quantity
          end

        # Return capital plus profit/loss
        proceeds = exit_price * position.quantity

        closed_position =
          position
          |> Map.delete(:unrealized_pnl)
          |> Map.merge(%{
            exit_price: exit_price / 1.0,
            exit_timestamp: timestamp,
            realized_pnl: pnl / 1.0
          })

        updated_tracker = %{
          tracker
          | open_positions: Map.delete(tracker.open_positions, position_id),
            available_capital: tracker.available_capital + proceeds + pnl,
            closed_positions: [closed_position | tracker.closed_positions],
            total_realized_pnl: tracker.total_realized_pnl + pnl
        }

        {:ok, updated_tracker, closed_position}
    end
  end

  @doc """
  Closes all open positions for a given symbol.

  ## Parameters
    - `tracker`: PositionTracker state
    - `symbol`: Trading pair
    - `exit_price`: Exit price
    - `timestamp`: Exit timestamp

  ## Returns
    - `{:ok, updated_tracker, closed_positions}` - Success with list of closed positions
  """
  @spec close_positions_for_symbol(t(), String.t(), number(), DateTime.t()) ::
          {:ok, t(), list(closed_position())}
  def close_positions_for_symbol(tracker, symbol, exit_price, timestamp) do
    # Find all positions for this symbol
    positions_to_close =
      tracker.open_positions
      |> Enum.filter(fn {_id, pos} -> pos.symbol == symbol end)
      |> Enum.map(fn {id, _pos} -> id end)

    # Close each position
    {updated_tracker, closed_positions} =
      Enum.reduce(positions_to_close, {tracker, []}, fn position_id, {acc_tracker, acc_closed} ->
        case close_position(acc_tracker, position_id, exit_price, timestamp) do
          {:ok, new_tracker, closed_pos} ->
            {new_tracker, [closed_pos | acc_closed]}

          {:error, _reason} ->
            {acc_tracker, acc_closed}
        end
      end)

    {:ok, updated_tracker, Enum.reverse(closed_positions)}
  end

  @doc """
  Updates unrealized P&L for all open positions based on current market prices.

  ## Parameters
    - `tracker`: PositionTracker state
    - `current_prices`: Map of symbol => current_price

  ## Returns
    - Updated tracker with recalculated unrealized P&L
  """
  @spec update_unrealized_pnl(t(), %{String.t() => number()}) :: t()
  def update_unrealized_pnl(tracker, current_prices) do
    {updated_positions, total_unrealized} =
      Enum.reduce(tracker.open_positions, {%{}, 0.0}, fn {id, position},
                                                         {acc_positions, acc_pnl} ->
        current_price = Map.get(current_prices, position.symbol)

        if current_price do
          unrealized_pnl =
            case position.side do
              :long -> (current_price - position.entry_price) * position.quantity
              :short -> (position.entry_price - current_price) * position.quantity
            end

          updated_position = %{position | unrealized_pnl: unrealized_pnl / 1.0}
          {Map.put(acc_positions, id, updated_position), acc_pnl + unrealized_pnl}
        else
          # Keep existing position if no price update
          {Map.put(acc_positions, id, position), acc_pnl + position.unrealized_pnl}
        end
      end)

    %{tracker | open_positions: updated_positions, total_unrealized_pnl: total_unrealized}
  end

  @doc """
  Calculates total equity (capital + unrealized P&L from open positions).

  ## Parameters
    - `tracker`: PositionTracker state

  ## Returns
    - Total equity value
  """
  @spec calculate_total_equity(t()) :: float()
  def calculate_total_equity(tracker) do
    tracker.available_capital + tracker.total_unrealized_pnl
  end

  @doc """
  Gets all open positions.
  """
  @spec get_open_positions(t()) :: list(position())
  def get_open_positions(tracker) do
    tracker.open_positions
    |> Map.values()
  end

  @doc """
  Gets a specific open position by ID.
  """
  @spec get_position(t(), String.t()) :: {:ok, position()} | {:error, :not_found}
  def get_position(tracker, position_id) do
    case Map.get(tracker.open_positions, position_id) do
      nil -> {:error, :not_found}
      position -> {:ok, position}
    end
  end

  @doc """
  Checks if there are any open positions.
  """
  @spec has_open_positions?(t()) :: boolean()
  def has_open_positions?(tracker) do
    map_size(tracker.open_positions) > 0
  end

  @doc """
  Gets all closed positions.
  """
  @spec get_closed_positions(t()) :: list(closed_position())
  def get_closed_positions(tracker) do
    Enum.reverse(tracker.closed_positions)
  end

  @doc """
  Gets total realized PnL across all closed positions.
  """
  @spec get_total_realized_pnl(t()) :: float()
  def get_total_realized_pnl(tracker) do
    tracker.total_realized_pnl
  end

  @doc """
  Gets total unrealized PnL from open positions.
  """
  @spec get_total_unrealized_pnl(t()) :: float()
  def get_total_unrealized_pnl(tracker) do
    tracker.total_unrealized_pnl
  end

  @doc """
  Gets available capital for new positions.
  """
  @spec get_available_capital(t()) :: float()
  def get_available_capital(tracker) do
    tracker.available_capital
  end

  @doc """
  Converts tracker state to a map suitable for serialization.
  """
  @spec to_map(t()) :: map()
  def to_map(tracker) do
    %{
      initial_capital: tracker.initial_capital,
      available_capital: tracker.available_capital,
      open_positions: Map.values(tracker.open_positions),
      closed_positions: tracker.closed_positions,
      total_realized_pnl: tracker.total_realized_pnl,
      total_unrealized_pnl: tracker.total_unrealized_pnl,
      position_sizing_mode: tracker.position_sizing_mode,
      position_size_pct: tracker.position_size_pct
    }
  end

  @doc """
  Restores tracker state from a serialized map.
  """
  @spec from_map(map()) :: t()
  def from_map(data) do
    # Convert open positions list back to map
    open_positions =
      (data["open_positions"] || data[:open_positions] || [])
      |> Enum.map(fn pos ->
        position = atomize_keys(pos)
        {position.position_id, position}
      end)
      |> Map.new()

    %__MODULE__{
      initial_capital: get_field(data, "initial_capital") / 1.0,
      available_capital: get_field(data, "available_capital") / 1.0,
      open_positions: open_positions,
      closed_positions: (get_field(data, "closed_positions") || []) |> Enum.map(&atomize_keys/1),
      total_realized_pnl: get_field(data, "total_realized_pnl") / 1.0,
      total_unrealized_pnl: get_field(data, "total_unrealized_pnl") / 1.0,
      position_sizing_mode:
        String.to_existing_atom(get_field(data, "position_sizing_mode") || "percentage"),
      position_size_pct: get_field(data, "position_size_pct") || 0.1
    }
  end

  # Private Functions

  defp calculate_position_size(tracker, entry_price) do
    case tracker.position_sizing_mode do
      :percentage ->
        # Use percentage of available capital
        capital_to_use = tracker.available_capital * tracker.position_size_pct
        capital_to_use / entry_price

      :fixed_amount ->
        # Use fixed percentage as quantity (simpler mode)
        tracker.position_size_pct
    end
  end

  defp generate_position_id(symbol) do
    timestamp = System.system_time(:microsecond)
    "pos_#{symbol}_#{timestamp}"
  end

  defp atomize_keys(map) when is_map(map) do
    Map.new(map, fn
      {key, value} when is_binary(key) -> {String.to_existing_atom(key), value}
      {key, value} -> {key, value}
    end)
  end

  defp get_field(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, String.to_atom(key))
  end
end
