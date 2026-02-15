defmodule TradingStrategy.StrategyFixtures do
  @moduledoc """
  Test fixtures for strategy configurations used across test suite.

  Provides composable fixture builders for strategies of varying complexity:
  - Simple: 1-2 indicators, ~10-20 lines DSL
  - Medium: 5-10 indicators, ~50-100 lines DSL
  - Complex: 20-30 indicators, ~200-400 lines DSL
  - Large: 50+ indicators, 1000+ lines DSL

  ## Usage

      import TradingStrategy.StrategyFixtures

      test "converts simple strategy" do
        builder_state = simple_sma_strategy()
        assert {:ok, dsl_text} = Synchronizer.builder_to_dsl(builder_state)
      end

  ## Design

  Fixtures use composable builders with sensible defaults to enable:
  1. DRY test code (reusable components)
  2. Progressive complexity (simple -> medium -> complex -> large)
  3. Clear naming convention (complexity_domain_variant)
  4. Type safety (returns proper structs)

  Large fixtures (50+ indicators) are loaded from .exs files in
  test/support/fixtures/strategies/ for maintainability.
  """

  alias TradingStrategy.StrategyEditor.BuilderState
  alias TradingStrategy.StrategyEditor.BuilderState.{Indicator, PositionSizing}

  @doc """
  Base strategy builder with defaults.

  Can be overridden with specific values:

      base_strategy(%{name: "Custom Strategy", indicators: [...]})
  """
  def base_strategy(overrides \\ %{}) do
    defaults = %BuilderState{
      name: "Test Strategy",
      trading_pair: "BTC/USD",
      timeframe: "1h",
      description: nil,
      indicators: [],
      entry_conditions: "",
      exit_conditions: "",
      stop_conditions: nil,
      position_sizing: default_position_sizing(),
      risk_parameters: nil,
      _comments: [],
      _version: 1,
      _last_sync_at: nil
    }

    struct!(defaults, Map.to_list(overrides))
  end

  @doc """
  Default position sizing configuration.
  """
  def default_position_sizing do
    %PositionSizing{
      type: "fixed",
      fixed_amount: 1000.0,
      percentage_of_capital: nil,
      _id: generate_id()
    }
  end

  @doc """
  Generate unique ID for entities.
  """
  defp generate_id do
    "test-#{System.unique_integer([:positive])}"
  end

  # ========================================================================
  # Simple Strategies (1-2 indicators)
  # ========================================================================

  @doc """
  Simple RSI strategy with 1 indicator.

  Returns a strategy with:
  - 1 RSI indicator (period 14)
  - Simple entry/exit conditions
  - Default position sizing

  DSL output: ~15 lines
  """
  def simple_sma_strategy do
    base_strategy(%{
      name: "Simple SMA Strategy",
      indicators: [
        sma_indicator("sma_20", 20)
      ],
      entry_conditions: "close > sma_20",
      exit_conditions: "close < sma_20"
    })
  end

  @doc """
  Simple EMA crossover strategy with 2 indicators.

  Returns a strategy with:
  - 2 EMA indicators (fast/slow)
  - Crossover entry/exit logic

  DSL output: ~25 lines
  """
  def simple_ema_crossover do
    base_strategy(%{
      name: "EMA Crossover",
      indicators: [
        ema_indicator("ema_fast", 12),
        ema_indicator("ema_slow", 26)
      ],
      entry_conditions: "crossover(ema_fast, ema_slow)",
      exit_conditions: "crossunder(ema_fast, ema_slow)"
    })
  end

  # ========================================================================
  # Medium Strategies (5-10 indicators)
  # ========================================================================

  @doc """
  Medium strategy with 5 indicators and extensive comments.

  Returns a strategy with:
  - 2 SMA indicators
  - 2 EMA indicators
  - 1 RSI indicator
  - Moderate complexity entry/exit logic
  - Extensive inline comments for comment preservation testing (US3)

  DSL output: ~80 lines
  """
  def medium_5_indicators do
    load_fixture_file("medium/5_indicators.exs")
  end

  @doc """
  Medium trend following strategy with complex entry/exit logic.

  DSL output: ~120 lines
  """
  def medium_trend_following do
    base_strategy(%{
      name: "Trend Following Strategy",
      indicators: [
        sma_indicator("sma_20", 20),
        sma_indicator("sma_50", 50),
        sma_indicator("sma_200", 200),
        rsi_indicator("rsi_14", 14),
        macd_indicator("macd", 12, 26, 9),
        adx_indicator("adx_14", 14),
        atr_indicator("atr_14", 14),
        bollinger_bands_indicator("bb_20", 20, 2.0)
      ],
      entry_conditions: """
      close > sma_200 and
      sma_20 > sma_50 and
      macd.line > macd.signal and
      rsi_14 > 50 and
      adx_14 > 25
      """,
      exit_conditions: """
      close < sma_20 or
      macd.line < macd.signal or
      rsi_14 < 40
      """
    })
  end

  # ========================================================================
  # Complex Strategies (20-30 indicators)
  # ========================================================================

  @doc """
  Complex strategy with 20 indicators for performance testing.

  DSL output: ~350 lines
  """
  def complex_20_indicators do
    load_fixture_file("complex/20_indicators.exs")
  end

  @doc """
  Complex multi-timeframe strategy.

  DSL output: ~300 lines
  """
  def complex_multi_timeframe do
    load_fixture_file("complex/multi_timeframe.exs")
  end

  # ========================================================================
  # Large Strategies (50+ indicators, 1000+ lines)
  # ========================================================================

  @doc """
  Large strategy with 50 indicators for stress testing.

  DSL output: 1000+ lines
  """
  def large_50_indicators do
    load_fixture_file("large/50_indicators.exs")
  end

  @doc """
  Large strategy with extensive comments for comment preservation testing.

  DSL output: 1000+ lines with 20+ comment blocks
  """
  def large_with_comments do
    load_fixture_file("large/with_comments.exs")
  end

  # ========================================================================
  # Invalid/Error Fixtures (for US6 error handling tests)
  # ========================================================================

  @doc """
  Invalid syntax fixture (missing closing bracket).
  """
  def invalid_syntax do
    load_fixture_file("invalid/syntax_error.exs")
  end

  @doc """
  Invalid indicator reference fixture.
  """
  def invalid_indicator_ref do
    load_fixture_file("invalid/indicator_ref.exs")
  end

  # ========================================================================
  # Parameterized Builders
  # ========================================================================

  @doc """
  Generate strategy with N indicators (all SMA).

  Useful for performance testing with varying complexity.

  ## Examples

      strategy_with_n_indicators(10)  # 10 SMA indicators
      strategy_with_n_indicators(50)  # 50 SMA indicators
  """
  def strategy_with_n_indicators(n) when is_integer(n) and n > 0 do
    indicators =
      for i <- 1..n do
        sma_indicator("sma_#{i * 10}", i * 10)
      end

    base_strategy(%{
      name: "#{n} Indicator Strategy",
      indicators: indicators,
      entry_conditions: "close > sma_10",
      exit_conditions: "close < sma_10"
    })
  end

  # ========================================================================
  # Component Builders
  # ========================================================================

  @doc """
  Build SMA indicator with given name and period.
  """
  def sma_indicator(name, period) do
    %Indicator{
      type: "sma",
      name: name,
      parameters: %{"period" => period, "source" => "close"},
      _id: generate_id()
    }
  end

  @doc """
  Build EMA indicator with given name and period.
  """
  def ema_indicator(name, period) do
    %Indicator{
      type: "ema",
      name: name,
      parameters: %{"period" => period, "source" => "close"},
      _id: generate_id()
    }
  end

  @doc """
  Build RSI indicator with given name and period.
  """
  def rsi_indicator(name, period) do
    %Indicator{
      type: "rsi",
      name: name,
      parameters: %{"period" => period, "source" => "close"},
      _id: generate_id()
    }
  end

  @doc """
  Build MACD indicator with given name and periods.
  """
  def macd_indicator(name, fast_period, slow_period, signal_period) do
    %Indicator{
      type: "macd",
      name: name,
      parameters: %{
        "fast_period" => fast_period,
        "slow_period" => slow_period,
        "signal_period" => signal_period,
        "source" => "close"
      },
      _id: generate_id()
    }
  end

  @doc """
  Build ADX indicator with given name and period.
  """
  def adx_indicator(name, period) do
    %Indicator{
      type: "adx",
      name: name,
      parameters: %{"period" => period},
      _id: generate_id()
    }
  end

  @doc """
  Build ATR indicator with given name and period.
  """
  def atr_indicator(name, period) do
    %Indicator{
      type: "atr",
      name: name,
      parameters: %{"period" => period},
      _id: generate_id()
    }
  end

  @doc """
  Build Bollinger Bands indicator with given name, period, and std dev.
  """
  def bollinger_bands_indicator(name, period, std_dev) do
    %Indicator{
      type: "bollinger_bands",
      name: name,
      parameters: %{
        "period" => period,
        "std_dev" => std_dev,
        "source" => "close"
      },
      _id: generate_id()
    }
  end

  # ========================================================================
  # Fixture Loading
  # ========================================================================

  @doc """
  Load fixture data from .exs file.

  Fixtures are stored in test/support/fixtures/strategies/
  organized by complexity: simple/, medium/, complex/, large/, invalid/
  """
  def load_fixture_file(relative_path) do
    fixture_path =
      Path.join([
        __DIR__,
        "strategies",
        relative_path
      ])

    if File.exists?(fixture_path) do
      {data, _bindings} = Code.eval_file(fixture_path)
      data
    else
      # Return placeholder until fixture files are created
      base_strategy(%{name: "Placeholder (#{relative_path})"})
    end
  end

  @doc """
  Validate fixture structure.

  Returns :ok if valid, {:error, reason} otherwise.
  """
  def validate_fixture(fixture) when is_map(fixture) do
    cond do
      !Map.has_key?(fixture, :name) or is_nil(fixture.name) ->
        {:error, "name is required"}

      !Map.has_key?(fixture, :indicators) or !is_list(fixture.indicators) ->
        {:error, "indicators must be a list"}

      true ->
        :ok
    end
  end

  def validate_fixture(_), do: {:error, "fixture must be a map"}
end
