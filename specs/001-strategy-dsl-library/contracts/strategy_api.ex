# Strategy Management API Contract
#
# This module defines the Elixir behaviour contract for strategy management operations.
# Covers FR-001 through FR-006 (DSL & Strategy Definition)

defmodule TradingStrategy.Contracts.StrategyAPI do
  @moduledoc """
  Contract for creating, validating, and managing trading strategy definitions.

  Strategies are defined using YAML/TOML configuration files (FR-001) and
  must be validated before use in trading sessions (FR-002).
  """

  @type strategy_id :: String.t()
  @type validation_error :: %{field: String.t(), message: String.t()}

  @type strategy_definition :: %{
    strategy_id: strategy_id(),
    name: String.t(),
    description: String.t() | nil,
    trading_pair: String.t(),
    timeframe: String.t(),
    indicators: [indicator_config()],
    entry_conditions: String.t(),
    exit_conditions: String.t(),
    stop_conditions: String.t(),
    position_sizing: position_sizing_config(),
    risk_parameters: risk_config(),
    version: String.t(),
    created_at: DateTime.t()
  }

  @type indicator_config :: %{
    type: atom(),  # :rsi | :macd | :sma | :ema | :bb | :obv | :mfi
    name: String.t(),
    parameters: map()
  }

  @type position_sizing_config :: %{
    type: atom(),  # :percentage | :fixed_amount | :risk_based
    percentage_of_capital: Decimal.t() | nil,
    fixed_amount: Decimal.t() | nil,
    max_position_size: Decimal.t()
  }

  @type risk_config :: %{
    max_daily_loss: Decimal.t(),
    max_drawdown: Decimal.t(),
    stop_loss_percentage: Decimal.t(),
    take_profit_percentage: Decimal.t() | nil
  }

  @doc """
  Parses a strategy definition from a YAML or TOML file.

  ## Parameters
  - `file_path`: Absolute path to strategy configuration file
  - `format`: `:yaml` or `:toml`

  ## Returns
  - `{:ok, strategy_definition}` on successful parse
  - `{:error, parse_error}` if file invalid or malformed

  ## Examples
      iex> parse_strategy("strategies/rsi_mean_reversion.yaml", :yaml)
      {:ok, %{strategy_id: "550e8400-...", name: "RSI Mean Reversion", ...}}

      iex> parse_strategy("invalid.yaml", :yaml)
      {:error, %{reason: :invalid_yaml, details: "Missing required field: entry_conditions"}}
  """
  @callback parse_strategy(file_path :: String.t(), format :: :yaml | :toml) ::
    {:ok, strategy_definition()} | {:error, map()}

  @doc """
  Validates a parsed strategy definition against schema and business rules.

  Performs the following validations (FR-002):
  - Required fields present
  - Indicator types are supported (FR-003)
  - Condition syntax is valid (FR-004)
  - Signal types defined (entry, exit, stop) (FR-005)
  - Risk parameters within acceptable ranges
  - No circular indicator dependencies
  - Position sizing constraints valid

  ## Parameters
  - `strategy`: Parsed strategy definition map

  ## Returns
  - `{:ok, strategy}` if all validations pass
  - `{:error, [validation_error, ...]}` with list of specific errors

  ## Examples
      iex> validate_strategy(%{name: "Test", entry_conditions: "invalid syntax"})
      {:error, [
        %{field: "entry_conditions", message: "Invalid expression: undefined variable 'foo'"},
        %{field: "indicators", message: "Indicator 'foo' referenced but not defined"}
      ]}
  """
  @callback validate_strategy(strategy :: strategy_definition()) ::
    {:ok, strategy_definition()} | {:error, [validation_error()]}

  @doc """
  Creates a new strategy definition in the system.

  Automatically generates strategy_id UUID and sets created_at timestamp.
  Persists to database after successful validation.

  ## Parameters
  - `strategy`: Strategy definition (without strategy_id)

  ## Returns
  - `{:ok, strategy_id}` with generated UUID
  - `{:error, [validation_error, ...]}` if validation fails
  - `{:error, :persistence_failed}` if database write fails
  """
  @callback create_strategy(strategy :: map()) ::
    {:ok, strategy_id()} | {:error, [validation_error()] | :persistence_failed}

  @doc """
  Retrieves a strategy definition by ID.

  ## Parameters
  - `strategy_id`: UUID of the strategy

  ## Returns
  - `{:ok, strategy}` if found
  - `{:error, :not_found}` if strategy_id doesn't exist
  """
  @callback get_strategy(strategy_id :: strategy_id()) ::
    {:ok, strategy_definition()} | {:error, :not_found}

  @doc """
  Lists all strategies, optionally filtered by status.

  ## Parameters
  - `opts`: Keyword list of filters
    - `status`: `:active` | `:archived` (optional)
    - `limit`: Integer (default 50)
    - `offset`: Integer (default 0)

  ## Returns
  - `{:ok, [strategy, ...]}` list of strategies
  """
  @callback list_strategies(opts :: keyword()) ::
    {:ok, [strategy_definition()]}

  @doc """
  Archives a strategy definition (soft delete).

  Archived strategies cannot be used in new trading sessions but
  remain queryable for historical analysis.

  ## Parameters
  - `strategy_id`: UUID of the strategy to archive

  ## Returns
  - `:ok` if successfully archived
  - `{:error, :not_found}` if strategy doesn't exist
  - `{:error, :has_active_sessions}` if strategy currently in use
  """
  @callback archive_strategy(strategy_id :: strategy_id()) ::
    :ok | {:error, :not_found | :has_active_sessions}

  @doc """
  Resolves conflicting signals when entry and exit conditions are both true.

  Implements FR-006 logic:
  - If holding position: exit signal takes priority
  - If flat (no position): entry signal takes priority
  - Ambiguous cases: exit takes priority for risk management

  ## Parameters
  - `strategy`: Strategy definition
  - `current_position`: Current position state (nil if flat)
  - `entry_triggered`: Boolean, true if entry conditions met
  - `exit_triggered`: Boolean, true if exit conditions met

  ## Returns
  - `{:ok, :entry}` if entry signal should be executed
  - `{:ok, :exit}` if exit signal should be executed
  - `{:ok, :no_action}` if neither should execute
  """
  @callback resolve_conflicting_signals(
    strategy :: strategy_definition(),
    current_position :: map() | nil,
    entry_triggered :: boolean(),
    exit_triggered :: boolean()
  ) :: {:ok, :entry | :exit | :no_action}
end
