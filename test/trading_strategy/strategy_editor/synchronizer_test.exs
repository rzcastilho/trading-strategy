defmodule TradingStrategy.StrategyEditor.SynchronizerTest do
  use ExUnit.Case, async: true

  alias TradingStrategy.StrategyEditor.{
    Synchronizer,
    BuilderState
  }

  describe "builder_to_dsl/2" do
    # T022: Test simple strategy with one indicator
    test "converts simple strategy with one indicator" do
      builder_state = %BuilderState{
        name: "Simple RSI Strategy",
        trading_pair: "BTC/USD",
        timeframe: "1h",
        description: "Buy when RSI is oversold",
        indicators: [
          %BuilderState.Indicator{
            type: "rsi",
            name: "rsi_14",
            parameters: %{"period" => 14},
            _id: "ind-1"
          }
        ],
        entry_conditions: "rsi_14 < 30",
        exit_conditions: "rsi_14 > 70",
        stop_conditions: nil,
        position_sizing: %BuilderState.PositionSizing{
          type: "percentage",
          percentage_of_capital: 0.10,
          fixed_amount: nil,
          _id: "pos-1"
        },
        risk_parameters: %BuilderState.RiskParameters{
          max_daily_loss: 0.03,
          max_drawdown: 0.15,
          max_position_size: 0.10,
          _id: "risk-1"
        },
        _comments: [],
        _version: 1,
        _last_sync_at: nil
      }

      assert {:ok, dsl_text} = Synchronizer.builder_to_dsl(builder_state)
      assert is_binary(dsl_text)
      assert String.contains?(dsl_text, "defstrategy SimpleRSIStrategy")
      assert String.contains?(dsl_text, "indicator :rsi_14, :rsi, period: 14")
      assert String.contains?(dsl_text, "entry_conditions do")
      assert String.contains?(dsl_text, "rsi_14 < 30")
    end

    # T023: Test multiple indicators (up to 20, SC-005)
    test "handles multiple indicators (up to 20)" do
      indicators =
        for i <- 1..20 do
          %BuilderState.Indicator{
            type: "sma",
            name: "sma_#{i * 10}",
            parameters: %{"period" => i * 10},
            _id: "ind-#{i}"
          }
        end

      builder_state = %BuilderState{
        name: "Multi Indicator Strategy",
        trading_pair: "ETH/USD",
        timeframe: "4h",
        indicators: indicators,
        entry_conditions: "sma_10 > sma_20",
        exit_conditions: "sma_10 < sma_20",
        position_sizing: %BuilderState.PositionSizing{
          type: "percentage",
          percentage_of_capital: 0.05,
          _id: "pos-1"
        },
        risk_parameters: %BuilderState.RiskParameters{
          max_daily_loss: 0.02,
          max_drawdown: 0.10,
          max_position_size: 0.05,
          _id: "risk-1"
        },
        _comments: [],
        _version: 1,
        _last_sync_at: nil
      }

      assert {:ok, dsl_text} = Synchronizer.builder_to_dsl(builder_state)
      assert is_binary(dsl_text)

      # Verify all 20 indicators are present
      for i <- 1..20 do
        assert String.contains?(dsl_text, "sma_#{i * 10}")
      end
    end

    # T024: Test preserving existing DSL comments (FR-010, SC-009)
    test "preserves existing DSL comments" do
      builder_state = %BuilderState{
        name: "Commented Strategy",
        trading_pair: "BTC/USD",
        timeframe: "1d",
        indicators: [
          %BuilderState.Indicator{
            type: "rsi",
            name: "rsi_14",
            parameters: %{"period" => 14},
            _id: "ind-1"
          }
        ],
        entry_conditions: "rsi_14 < 30",
        exit_conditions: "rsi_14 > 70",
        position_sizing: %BuilderState.PositionSizing{
          type: "percentage",
          percentage_of_capital: 0.10,
          _id: "pos-1"
        },
        risk_parameters: %BuilderState.RiskParameters{
          max_daily_loss: 0.03,
          max_drawdown: 0.15,
          max_position_size: 0.10,
          _id: "risk-1"
        },
        _comments: [
          %BuilderState.Comment{
            line: 1,
            column: 1,
            text: "# This is a simple RSI strategy",
            preserved_from_dsl: true
          },
          %BuilderState.Comment{
            line: 10,
            column: 3,
            text: "# Entry when oversold",
            preserved_from_dsl: true
          }
        ],
        _version: 1,
        _last_sync_at: nil
      }

      assert {:ok, dsl_text} = Synchronizer.builder_to_dsl(builder_state, builder_state._comments)
      assert String.contains?(dsl_text, "# This is a simple RSI strategy")
      assert String.contains?(dsl_text, "# Entry when oversold")
    end

    # T025: Test properly formatted DSL with correct indentation (FR-016)
    test "generates properly formatted DSL with correct indentation" do
      builder_state = %BuilderState{
        name: "Formatted Strategy",
        trading_pair: "BTC/USD",
        timeframe: "1h",
        indicators: [
          %BuilderState.Indicator{
            type: "rsi",
            name: "rsi_14",
            parameters: %{"period" => 14},
            _id: "ind-1"
          }
        ],
        entry_conditions: "rsi_14 < 30 && volume > 1000",
        exit_conditions: "rsi_14 > 70",
        position_sizing: %BuilderState.PositionSizing{
          type: "percentage",
          percentage_of_capital: 0.10,
          _id: "pos-1"
        },
        risk_parameters: %BuilderState.RiskParameters{
          max_daily_loss: 0.03,
          max_drawdown: 0.15,
          max_position_size: 0.10,
          _id: "risk-1"
        },
        _comments: [],
        _version: 1,
        _last_sync_at: nil
      }

      assert {:ok, dsl_text} = Synchronizer.builder_to_dsl(builder_state)

      # Verify proper formatting
      lines = String.split(dsl_text, "\n")

      # Check that nested blocks are indented
      assert Enum.any?(lines, fn line ->
               # 2-space indent for nested blocks
               String.match?(line, ~r/^  [a-z]/)
             end)

      # Check that defstrategy is not indented
      assert Enum.any?(lines, fn line ->
               String.starts_with?(line, "defstrategy ")
             end)

      # Verify no trailing whitespace
      assert Enum.all?(lines, fn line ->
               not String.ends_with?(line, " ")
             end)
    end

    test "returns error for invalid builder state" do
      invalid_state = %BuilderState{
        # Invalid: name is required
        name: nil,
        trading_pair: "BTC/USD",
        timeframe: "1h",
        indicators: [],
        _comments: [],
        _version: 1
      }

      assert {:error, reason} = Synchronizer.builder_to_dsl(invalid_state)
      assert reason =~ "name"
    end
  end

  describe "dsl_to_builder/1" do
    # T035: Test parsing simple strategy with one indicator
    test "parses simple strategy with one indicator" do
      dsl_text = """
      defstrategy SimpleRSIStrategy do
        @trading_pair "BTC/USD"
        @timeframe "1h"
        @description "Buy when RSI is oversold"

        indicator :rsi_14, :rsi, period: 14

        entry_conditions do
          rsi_14 < 30
        end

        exit_conditions do
          rsi_14 > 70
        end

        position_sizing do
          percentage_of_capital 0.10
        end

        risk_parameters do
          max_daily_loss 0.03
          max_drawdown 0.15
          max_position_size 0.10
        end
      end
      """

      assert {:ok, builder_state} = Synchronizer.dsl_to_builder(dsl_text)
      assert %BuilderState{} = builder_state
      assert builder_state.name == "Simple RSI Strategy"
      assert builder_state.trading_pair == "BTC/USD"
      assert builder_state.timeframe == "1h"
      assert builder_state.description == "Buy when RSI is oversold"

      # Verify indicator was parsed
      assert length(builder_state.indicators) == 1
      indicator = hd(builder_state.indicators)
      assert indicator.type == "rsi"
      assert indicator.name == "rsi_14"
      assert indicator.parameters["period"] == 14

      # Verify conditions
      assert builder_state.entry_conditions =~ "rsi_14 < 30"
      assert builder_state.exit_conditions =~ "rsi_14 > 70"

      # Verify position sizing
      assert builder_state.position_sizing.type == "percentage"
      assert builder_state.position_sizing.percentage_of_capital == 0.10

      # Verify risk parameters
      assert builder_state.risk_parameters.max_daily_loss == 0.03
      assert builder_state.risk_parameters.max_drawdown == 0.15
      assert builder_state.risk_parameters.max_position_size == 0.10
    end

    # T036: Test handling complex strategy (20 indicators + 10 conditions, SC-005)
    test "handles complex strategy with 20 indicators and 10 conditions" do
      # Generate DSL with 20 indicators
      indicator_definitions =
        for i <- 1..20 do
          "  indicator :sma_#{i * 10}, :sma, period: #{i * 10}"
        end
        |> Enum.join("\n")

      # Generate complex entry conditions with 10 conditions
      entry_conditions =
        for i <- 1..10 do
          "    sma_#{i * 10} > sma_#{(i + 1) * 10}"
        end
        |> Enum.join(" &&\n")

      dsl_text = """
      defstrategy ComplexMultiIndicatorStrategy do
        @trading_pair "ETH/USD"
        @timeframe "4h"

      #{indicator_definitions}

        entry_conditions do
      #{entry_conditions}
        end

        exit_conditions do
          sma_10 < sma_20
        end

        position_sizing do
          percentage_of_capital 0.05
        end

        risk_parameters do
          max_daily_loss 0.02
          max_drawdown 0.10
          max_position_size 0.05
        end
      end
      """

      assert {:ok, builder_state} = Synchronizer.dsl_to_builder(dsl_text)
      assert %BuilderState{} = builder_state

      # Verify all 20 indicators were parsed
      assert length(builder_state.indicators) == 20

      # Verify indicator names and parameters
      for i <- 1..20 do
        indicator =
          Enum.find(builder_state.indicators, fn ind ->
            ind.name == "sma_#{i * 10}"
          end)

        assert indicator != nil
        assert indicator.type == "sma"
        assert indicator.parameters["period"] == i * 10
      end

      # Verify complex conditions were preserved
      assert String.contains?(builder_state.entry_conditions, "sma_10 > sma_20")
      assert String.contains?(builder_state.entry_conditions, "sma_100 > sma_110")
    end

    # T037: Test extracting and preserving comments
    test "extracts and preserves comments" do
      dsl_text = """
      # This is a simple RSI strategy
      defstrategy CommentedStrategy do
        @trading_pair "BTC/USD"
        @timeframe "1d"

        # RSI indicator for oversold/overbought detection
        indicator :rsi_14, :rsi, period: 14

        # Entry when oversold
        entry_conditions do
          rsi_14 < 30
        end

        # Exit when overbought
        exit_conditions do
          rsi_14 > 70
        end

        position_sizing do
          percentage_of_capital 0.10
        end

        risk_parameters do
          max_daily_loss 0.03
          max_drawdown 0.15
          max_position_size 0.10
        end
      end
      """

      assert {:ok, builder_state} = Synchronizer.dsl_to_builder(dsl_text)
      assert %BuilderState{} = builder_state

      # Verify comments were extracted
      assert length(builder_state._comments) > 0

      # Verify specific comments are present
      comment_texts = Enum.map(builder_state._comments, & &1.text)
      assert Enum.any?(comment_texts, &String.contains?(&1, "simple RSI strategy"))
      assert Enum.any?(comment_texts, &String.contains?(&1, "Entry when oversold"))
      assert Enum.any?(comment_texts, &String.contains?(&1, "Exit when overbought"))

      # Verify all comments are marked as preserved from DSL
      assert Enum.all?(builder_state._comments, & &1.preserved_from_dsl)
    end

    # T038: Test handling indicator deletion
    test "handles indicator deletion" do
      # Original DSL with 3 indicators
      original_dsl = """
      defstrategy IndicatorDeletionTest do
        @trading_pair "BTC/USD"
        @timeframe "1h"

        indicator :rsi_14, :rsi, period: 14
        indicator :sma_20, :sma, period: 20
        indicator :ema_50, :ema, period: 50

        entry_conditions do
          rsi_14 < 30 && sma_20 > ema_50
        end

        exit_conditions do
          rsi_14 > 70
        end

        position_sizing do
          percentage_of_capital 0.10
        end

        risk_parameters do
          max_daily_loss 0.03
          max_drawdown 0.15
          max_position_size 0.10
        end
      end
      """

      # Parse original
      assert {:ok, builder_state} = Synchronizer.dsl_to_builder(original_dsl)
      assert length(builder_state.indicators) == 3

      # Modified DSL with one indicator removed (ema_50 deleted)
      modified_dsl = """
      defstrategy IndicatorDeletionTest do
        @trading_pair "BTC/USD"
        @timeframe "1h"

        indicator :rsi_14, :rsi, period: 14
        indicator :sma_20, :sma, period: 20

        entry_conditions do
          rsi_14 < 30
        end

        exit_conditions do
          rsi_14 > 70
        end

        position_sizing do
          percentage_of_capital 0.10
        end

        risk_parameters do
          max_daily_loss 0.03
          max_drawdown 0.15
          max_position_size 0.10
        end
      end
      """

      # Parse modified
      assert {:ok, modified_builder_state} = Synchronizer.dsl_to_builder(modified_dsl)

      # Verify only 2 indicators remain
      assert length(modified_builder_state.indicators) == 2

      # Verify ema_50 was removed
      indicator_names = Enum.map(modified_builder_state.indicators, & &1.name)
      assert "rsi_14" in indicator_names
      assert "sma_20" in indicator_names
      refute "ema_50" in indicator_names

      # Verify entry conditions were updated (no longer references ema_50)
      refute String.contains?(modified_builder_state.entry_conditions, "ema_50")
    end

    test "returns error for invalid DSL syntax" do
      invalid_dsl = """
      defstrategy InvalidSyntax do
        @trading_pair "BTC/USD"
        @timeframe "1h"

        # Missing closing parenthesis
        indicator :rsi_14, :rsi, period: 14

        entry_conditions do
          rsi_14 < 30
        # Missing end
      """

      assert {:error, reason} = Synchronizer.dsl_to_builder(invalid_dsl)
      assert is_binary(reason)
      # Error should indicate syntax problem
      assert reason =~ ~r/(syntax|parse|missing|unexpected)/i
    end

    test "returns error for semantically invalid DSL" do
      invalid_dsl = """
      defstrategy SemanticError do
        @trading_pair "BTC/USD"
        @timeframe "1h"

        # Reference undefined indicator
        entry_conditions do
          undefined_indicator < 30
        end

        exit_conditions do
          undefined_indicator > 70
        end

        position_sizing do
          percentage_of_capital 0.10
        end

        risk_parameters do
          max_daily_loss 0.03
          max_drawdown 0.15
          max_position_size 0.10
        end
      end
      """

      assert {:error, reason} = Synchronizer.dsl_to_builder(invalid_dsl)
      assert is_binary(reason)
      # Error should indicate undefined indicator
      assert reason =~ ~r/(undefined|not found|unknown)/i
    end
  end

  # Phase 6: User Story 4 - Concurrent Edit Prevention Tests

  describe "concurrent edit prevention" do
    # T067: Test last-modified timestamp determines authoritative source
    test "last-modified timestamp determines authoritative source" do
      # Create a base builder state
      builder_state = %BuilderState{
        name: "Concurrent Edit Test",
        trading_pair: "BTC/USD",
        timeframe: "1h",
        indicators: [
          %BuilderState.Indicator{
            type: "rsi",
            name: "rsi_14",
            parameters: %{"period" => 14},
            _id: "ind-1"
          }
        ],
        entry_conditions: "rsi_14 < 30",
        exit_conditions: "rsi_14 > 70",
        position_sizing: %BuilderState.PositionSizing{
          type: "percentage",
          percentage_of_capital: 0.10,
          _id: "pos-1"
        },
        risk_parameters: %BuilderState.RiskParameters{
          max_daily_loss: 0.03,
          max_drawdown: 0.15,
          max_position_size: 0.10,
          _id: "risk-1"
        },
        _comments: [],
        _version: 1,
        _last_sync_at: DateTime.utc_now()
      }

      # Convert to DSL (simulating builder edit)
      assert {:ok, dsl_text} = Synchronizer.builder_to_dsl(builder_state)

      # Simulate concurrent DSL edit (newer timestamp)
      modified_dsl = String.replace(dsl_text, "rsi_14 < 30", "rsi_14 < 25")

      # Parse back the DSL with version tracking
      assert {:ok, modified_builder_state} =
               Synchronizer.dsl_to_builder(modified_dsl, prev_version: builder_state._version)

      # The DSL change should be reflected because it has a newer timestamp
      assert modified_builder_state.entry_conditions =~ "rsi_14 < 25"
      assert modified_builder_state._version == builder_state._version + 1
    end

    # T068: Test pending changes from both editors handled correctly
    test "pending changes from both editors handled correctly" do
      # Original state
      original_builder = %BuilderState{
        name: "Pending Changes Test",
        trading_pair: "ETH/USD",
        timeframe: "4h",
        indicators: [
          %BuilderState.Indicator{
            type: "sma",
            name: "sma_20",
            parameters: %{"period" => 20},
            _id: "ind-1"
          }
        ],
        entry_conditions: "sma_20 > close",
        exit_conditions: "sma_20 < close",
        position_sizing: %BuilderState.PositionSizing{
          type: "percentage",
          percentage_of_capital: 0.10,
          _id: "pos-1"
        },
        risk_parameters: %BuilderState.RiskParameters{
          max_daily_loss: 0.03,
          max_drawdown: 0.15,
          max_position_size: 0.10,
          _id: "risk-1"
        },
        _comments: [],
        _version: 1,
        _last_sync_at: DateTime.utc_now()
      }

      # Simulate builder edit (change position sizing)
      builder_modified = %{
        original_builder
        | position_sizing: %BuilderState.PositionSizing{
            type: "percentage",
            percentage_of_capital: 0.15,
            _id: "pos-1"
          },
          _version: 2
      }

      # Convert builder changes to DSL
      assert {:ok, builder_dsl} = Synchronizer.builder_to_dsl(builder_modified)

      # Simulate DSL edit (change entry condition)
      dsl_modified =
        String.replace(builder_dsl, "sma_20 > close", "sma_20 > close && volume > 1000")

      # Parse DSL back
      assert {:ok, final_state} = Synchronizer.dsl_to_builder(dsl_modified)

      # Both changes should be reflected
      # Builder change preserved
      assert final_state.position_sizing.percentage_of_capital == 0.15
      # DSL change applied
      assert String.contains?(final_state.entry_conditions, "volume > 1000")
    end

    # T069: Test synchronization completes before processing new opposite-editor changes
    test "synchronization completes before processing new opposite-editor changes" do
      # Create initial state
      initial_state = %BuilderState{
        name: "Sequential Sync Test",
        trading_pair: "BTC/USD",
        timeframe: "1h",
        indicators: [
          %BuilderState.Indicator{
            type: "rsi",
            name: "rsi_14",
            parameters: %{"period" => 14},
            _id: "ind-1"
          }
        ],
        entry_conditions: "rsi_14 < 30",
        exit_conditions: "rsi_14 > 70",
        position_sizing: %BuilderState.PositionSizing{
          type: "percentage",
          percentage_of_capital: 0.10,
          _id: "pos-1"
        },
        risk_parameters: %BuilderState.RiskParameters{
          max_daily_loss: 0.03,
          max_drawdown: 0.15,
          max_position_size: 0.10,
          _id: "risk-1"
        },
        _comments: [],
        _version: 1,
        _last_sync_at: DateTime.utc_now()
      }

      # First sync: Builder → DSL
      assert {:ok, dsl_v1} = Synchronizer.builder_to_dsl(initial_state)

      # Verify DSL conversion completed
      assert String.contains?(dsl_v1, "rsi_14 < 30")

      # Second sync: DSL → Builder (modify in DSL) with version tracking
      dsl_v2 = String.replace(dsl_v1, "period: 14", "period: 21")

      assert {:ok, builder_v2} =
               Synchronizer.dsl_to_builder(dsl_v2, prev_version: initial_state._version)

      # Verify DSL→Builder sync completed before allowing next change
      assert Enum.find(builder_v2.indicators, fn ind -> ind.name == "rsi_14" end).parameters[
               "period"
             ] == 21

      assert builder_v2._version == initial_state._version + 1

      # Third sync: Builder → DSL (modify in builder)
      builder_v3 = %{
        builder_v2
        | entry_conditions: "rsi_14 < 25",
          _version: builder_v2._version + 1
      }

      assert {:ok, dsl_v3} = Synchronizer.builder_to_dsl(builder_v3)

      # Verify final state has both changes applied sequentially
      # DSL edit preserved
      assert String.contains?(dsl_v3, "period: 21")
      # Builder edit applied
      assert String.contains?(dsl_v3, "rsi_14 < 25")
    end
  end
end
