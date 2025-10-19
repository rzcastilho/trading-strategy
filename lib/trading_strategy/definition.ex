defmodule TradingStrategy.Definition do
  @moduledoc """
  Defines the structure and metadata for a trading strategy.

  This module holds the compiled representation of a strategy
  defined using the DSL, including indicators, conditions, and signals.
  """

  @type condition :: %{
          type: :when_all | :when_any | :when_not,
          conditions: list()
        }

  @type indicator_config :: %{
          name: atom(),
          module: module(),
          params: keyword()
        }

  @type signal_config :: %{
          direction: :long | :short,
          condition: condition()
        }

  @type t :: %__MODULE__{
          name: atom(),
          description: String.t(),
          indicators: %{atom() => indicator_config()},
          entry_signals: list(signal_config()),
          exit_signals: list(signal_config()),
          timeframes: list(String.t()),
          parameters: map(),
          metadata: map()
        }

  defstruct [
    :name,
    :description,
    indicators: %{},
    entry_signals: [],
    exit_signals: [],
    timeframes: ["1h"],
    parameters: %{},
    metadata: %{}
  ]

  @doc """
  Creates a new strategy definition.
  """
  def new(name, opts \\ []) do
    %__MODULE__{
      name: name,
      description: Keyword.get(opts, :description, ""),
      timeframes: Keyword.get(opts, :timeframes, ["1h"]),
      parameters: Keyword.get(opts, :parameters, %{}),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Adds an indicator configuration to the strategy.
  """
  def add_indicator(%__MODULE__{} = definition, name, module, params \\ []) do
    indicator = %{
      name: name,
      module: module,
      params: params
    }

    %{definition | indicators: Map.put(definition.indicators, name, indicator)}
  end

  @doc """
  Adds an entry signal to the strategy.
  """
  def add_entry_signal(%__MODULE__{} = definition, direction, condition) do
    signal = %{
      direction: direction,
      condition: condition
    }

    %{definition | entry_signals: definition.entry_signals ++ [signal]}
  end

  @doc """
  Adds an exit signal to the strategy.
  """
  def add_exit_signal(%__MODULE__{} = definition, condition) do
    signal = %{
      condition: condition
    }

    %{definition | exit_signals: definition.exit_signals ++ [signal]}
  end

  @doc """
  Validates a strategy definition.
  """
  def validate(%__MODULE__{} = definition) do
    with :ok <- validate_name(definition),
         :ok <- validate_indicators(definition),
         :ok <- validate_signals(definition) do
      {:ok, definition}
    end
  end

  defp validate_name(%{name: name}) when is_atom(name) and not is_nil(name), do: :ok
  defp validate_name(_), do: {:error, :invalid_name}

  defp validate_indicators(%{indicators: indicators}) when map_size(indicators) > 0, do: :ok

  defp validate_indicators(_),
    do: {:error, :no_indicators_defined}

  defp validate_signals(%{entry_signals: entry}) when length(entry) > 0, do: :ok
  defp validate_signals(_), do: {:error, :no_entry_signals_defined}
end
