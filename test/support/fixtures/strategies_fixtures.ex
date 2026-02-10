defmodule TradingStrategy.StrategiesFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `TradingStrategy.Strategies` context.
  """

  import TradingStrategy.AccountsFixtures

  alias TradingStrategy.Strategies

  @doc """
  Generate a valid YAML strategy content for testing.
  """
  def valid_yaml_strategy do
    """
    name: Test Strategy
    description: A simple test strategy
    trading_pair: BTC/USD
    timeframe: 1h

    indicators:
      - name: sma_20
        type: sma
        parameters:
          period: 20

      - name: rsi_14
        type: rsi
        parameters:
          period: 14

    entry_conditions: rsi_14 < 30
    exit_conditions: rsi_14 > 70
    stop_conditions: rsi_14 < 25

    position_sizing:
      type: percentage
      percentage_of_capital: 0.10

    risk_parameters:
      max_daily_loss: 0.03
      max_drawdown: 0.15
    """
  end

  @doc """
  Generate a valid TOML strategy content for testing.
  """
  def valid_toml_strategy do
    """
    name = "Test Strategy"
    description = "A simple test strategy"
    trading_pair = "BTC/USD"
    timeframe = "1h"
    entry_conditions = "rsi_14 < 30"
    exit_conditions = "rsi_14 > 70"
    stop_conditions = "rsi_14 < 25"

    [[indicators]]
    name = "sma_20"
    type = "sma"
    parameters = { period = 20 }

    [[indicators]]
    name = "rsi_14"
    type = "rsi"
    parameters = { period = 14 }

    [position_sizing]
    type = "percentage"
    percentage_of_capital = 0.10

    [risk_parameters]
    max_daily_loss = 0.03
    max_drawdown = 0.15
    """
  end

  @doc """
  Generate a strategy with user association.

  ## Examples

      iex> strategy_fixture()
      %Strategy{}

      iex> strategy_fixture(user: user, name: "Custom Strategy")
      %Strategy{name: "Custom Strategy"}

  """
  def strategy_fixture(attrs \\ %{}) do
    # Convert keyword list to map if necessary
    attrs = if is_list(attrs), do: Map.new(attrs), else: attrs

    user = attrs[:user] || user_fixture()

    default_attrs = %{
      name: "Test Strategy #{System.unique_integer([:positive])}",
      description: "A test trading strategy",
      format: "yaml",
      content: valid_yaml_strategy(),
      trading_pair: "BTC/USD",
      timeframe: "1h",
      status: "draft"
    }

    # Merge attrs with defaults, ensuring all keys are atoms
    attrs =
      attrs
      |> Map.delete(:user)
      |> Enum.reduce(%{}, fn {k, v}, acc -> Map.put(acc, k, v) end)
      |> then(fn map -> Map.merge(default_attrs, map) end)

    {:ok, strategy} = Strategies.create_strategy(attrs, user)

    strategy
  end

  @doc """
  Generate an active strategy.
  """
  def active_strategy_fixture(attrs \\ %{}) do
    user = attrs[:user] || user_fixture()

    strategy =
      attrs
      |> Map.put(:status, "active")
      |> strategy_fixture()

    strategy
  end

  @doc """
  Generate an inactive strategy.
  """
  def inactive_strategy_fixture(attrs \\ %{}) do
    user = attrs[:user] || user_fixture()

    strategy =
      attrs
      |> Map.put(:status, "inactive")
      |> strategy_fixture()

    strategy
  end

  @doc """
  Generate an archived strategy.
  """
  def archived_strategy_fixture(attrs \\ %{}) do
    user = attrs[:user] || user_fixture()

    strategy =
      attrs
      |> Map.put(:status, "archived")
      |> strategy_fixture()

    strategy
  end

  @doc """
  Generate a strategy with invalid DSL content.
  """
  def invalid_strategy_attrs(attrs \\ %{}) do
    Enum.into(attrs, %{
      name: "Invalid Strategy",
      format: "yaml",
      content: "invalid: yaml: content:",
      trading_pair: "BTC/USD",
      timeframe: "1h"
    })
  end
end
