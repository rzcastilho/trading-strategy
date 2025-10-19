defmodule TradingStrategy.Position do
  @moduledoc """
  Represents an open or closed trading position.

  Tracks entry/exit points, profit/loss, and position metadata.
  """

  alias TradingStrategy.Signal

  @type status :: :open | :closed
  @type t :: %__MODULE__{
          id: String.t(),
          symbol: String.t(),
          direction: Signal.direction(),
          entry_price: float(),
          entry_time: DateTime.t(),
          exit_price: float() | nil,
          exit_time: DateTime.t() | nil,
          quantity: float(),
          status: status(),
          pnl: float() | nil,
          pnl_percent: float() | nil,
          strategy: atom(),
          metadata: map()
        }

  defstruct [
    :id,
    :symbol,
    :direction,
    :entry_price,
    :entry_time,
    :exit_price,
    :exit_time,
    :quantity,
    :status,
    :pnl,
    :pnl_percent,
    :strategy,
    metadata: %{}
  ]

  @doc """
  Opens a new position from an entry signal.
  """
  def open(%Signal{type: :entry} = signal, quantity, opts \\ []) do
    %__MODULE__{
      id: Keyword.get(opts, :id, generate_id()),
      symbol: signal.symbol,
      direction: signal.direction,
      entry_price: signal.price,
      entry_time: signal.timestamp,
      quantity: quantity,
      status: :open,
      strategy: signal.strategy,
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Closes a position with an exit signal.
  """
  def close(%__MODULE__{status: :open} = position, %Signal{type: :exit} = signal) do
    pnl = calculate_pnl(position, signal.price)
    pnl_percent = calculate_pnl_percent(position, signal.price)

    %{
      position
      | exit_price: signal.price,
        exit_time: signal.timestamp,
        status: :closed,
        pnl: pnl,
        pnl_percent: pnl_percent
    }
  end

  @doc """
  Checks if a position is open.
  """
  def open?(%__MODULE__{status: :open}), do: true
  def open?(_), do: false

  @doc """
  Checks if a position is closed.
  """
  def closed?(%__MODULE__{status: :closed}), do: true
  def closed?(_), do: false

  @doc """
  Calculates the current or final profit/loss for a position.
  """
  def calculate_pnl(%__MODULE__{direction: :long} = position, exit_price) do
    (exit_price - position.entry_price) * position.quantity
  end

  def calculate_pnl(%__MODULE__{direction: :short} = position, exit_price) do
    (position.entry_price - exit_price) * position.quantity
  end

  @doc """
  Calculates the profit/loss percentage for a position.
  """
  def calculate_pnl_percent(%__MODULE__{direction: :long} = position, exit_price) do
    ((exit_price - position.entry_price) / position.entry_price) * 100
  end

  def calculate_pnl_percent(%__MODULE__{direction: :short} = position, exit_price) do
    ((position.entry_price - exit_price) / position.entry_price) * 100
  end

  @doc """
  Gets the current unrealized PnL for an open position.
  """
  def unrealized_pnl(%__MODULE__{status: :open} = position, current_price) do
    calculate_pnl(position, current_price)
  end

  def unrealized_pnl(%__MODULE__{status: :closed} = position, _current_price) do
    position.pnl
  end

  defp generate_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
end
