defmodule TradingStrategy.StrategyEditor.BuilderState do
  @moduledoc """
  Structured representation of strategy form data from the Advanced Strategy Builder.

  This struct converts bidirectionally with DSL text and represents the visual
  form state that users interact with in the builder interface.
  """

  @derive Jason.Encoder
  defstruct [
    # Basic Information
    :name,
    :trading_pair,
    :timeframe,
    :description,
    # Indicators
    :indicators,
    # Entry/Exit Conditions
    :entry_conditions,
    :exit_conditions,
    :stop_conditions,
    # Position Sizing
    :position_sizing,
    # Risk Parameters
    :risk_parameters,
    # Metadata (not part of DSL)
    :_comments,
    :_version,
    :_last_sync_at
  ]

  @type t :: %__MODULE__{
          name: String.t() | nil,
          trading_pair: String.t() | nil,
          timeframe: String.t() | nil,
          description: String.t() | nil,
          indicators: [Indicator.t()],
          entry_conditions: String.t() | nil,
          exit_conditions: String.t() | nil,
          stop_conditions: String.t() | nil,
          position_sizing: PositionSizing.t() | nil,
          risk_parameters: RiskParameters.t() | nil,
          _comments: [Comment.t()],
          _version: integer(),
          _last_sync_at: DateTime.t() | nil
        }

  defmodule Indicator do
    @moduledoc """
    Represents a technical indicator in the builder.
    """

    @derive Jason.Encoder
    defstruct [:type, :name, :parameters, :_id]

    @type t :: %__MODULE__{
            type: String.t(),
            name: String.t(),
            parameters: map(),
            _id: String.t()
          }
  end

  defmodule PositionSizing do
    @moduledoc """
    Position sizing configuration for the strategy.
    """

    @derive Jason.Encoder
    defstruct [:type, :percentage_of_capital, :fixed_amount, :_id]

    @type t :: %__MODULE__{
            type: String.t(),
            percentage_of_capital: float() | nil,
            fixed_amount: float() | nil,
            _id: String.t()
          }
  end

  defmodule RiskParameters do
    @moduledoc """
    Risk management parameters for the strategy.
    """

    @derive Jason.Encoder
    defstruct [:max_daily_loss, :max_drawdown, :max_position_size, :_id]

    @type t :: %__MODULE__{
            max_daily_loss: float() | nil,
            max_drawdown: float() | nil,
            max_position_size: float() | nil,
            _id: String.t()
          }
  end

  defmodule Comment do
    @moduledoc """
    Preserved comment from DSL source.
    """

    @derive Jason.Encoder
    defstruct [:line, :column, :text, :preserved_from_dsl]

    @type t :: %__MODULE__{
            line: integer(),
            column: integer(),
            text: String.t(),
            preserved_from_dsl: boolean()
          }
  end

  @doc """
  Create a new empty BuilderState.
  """
  def new do
    %__MODULE__{
      indicators: [],
      _comments: [],
      _version: 1,
      _last_sync_at: nil
    }
  end

  @doc """
  Convert BuilderState to DSL text.
  Delegates to Synchronizer module.
  """
  def to_dsl(%__MODULE__{} = builder_state, comments \\ []) do
    TradingStrategy.StrategyEditor.Synchronizer.builder_to_dsl(builder_state, comments)
  end

  @doc """
  Convert DSL text to BuilderState.
  Delegates to Synchronizer module.
  """
  def from_dsl(dsl_text) when is_binary(dsl_text) do
    TradingStrategy.StrategyEditor.Synchronizer.dsl_to_builder(dsl_text)
  end
end
