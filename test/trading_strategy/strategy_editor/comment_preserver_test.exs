defmodule TradingStrategy.StrategyEditor.CommentPreserverTest do
  @moduledoc """
  Property-based tests for comment preservation during DSL transformations.

  Verifies SC-009: Comments preserved through 100+ round-trip synchronizations.
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias TradingStrategy.StrategyEditor.{Synchronizer, BuilderState}

  @simple_strategy_template """
  defstrategy SimpleStrategy do
    @trading_pair "BTC/USD"
    @timeframe "1h"

    # RSI indicator for oversold detection
    indicator :rsi_14, :rsi, period: 14

    # Entry when oversold
    entry_conditions do
      rsi_14 < 30
    end

    # Exit when overbought
    exit_conditions do
      rsi_14 > 70
    end

    # Position sizing
    position_sizing do
      percentage_of_capital 0.10
    end

    # Risk management
    risk_parameters do
      max_daily_loss 0.03
      max_drawdown 0.15
      max_position_size 0.10
    end
  end
  """

  describe "comment preservation (SC-009)" do
    test "simple strategy preserves comments through 100 round-trips" do
      # Track comments through multiple transformations
      {:ok, initial_state} = Synchronizer.dsl_to_builder(@simple_strategy_template)
      initial_comments = initial_state._comments || []

      # Verify we extracted comments
      assert length(initial_comments) >= 4,
             "Expected at least 4 comments, got #{length(initial_comments)}"

      # Perform 100 round-trips: DSL → Builder → DSL → Builder → ...
      final_comments = perform_round_trips(initial_state, initial_comments, 100)

      # Verify comments survived
      assert length(final_comments) >= length(initial_comments),
             "Lost comments during round-trips: started with #{length(initial_comments)}, ended with #{length(final_comments)}"

      # Verify comment content matches
      comment_texts = Enum.map(final_comments, & &1.text)
      expected_texts = Enum.map(initial_comments, & &1.text)

      assert MapSet.new(comment_texts) == MapSet.new(expected_texts),
             "Comment text changed during transformations"
    end

    test "comments survive modifications to builder state" do
      {:ok, initial_state} = Synchronizer.dsl_to_builder(@simple_strategy_template)
      initial_comments = initial_state._comments || []

      # Modify strategy (change RSI period)
      modified_state = %{
        initial_state
        | indicators: [
            %BuilderState.Indicator{
              type: "rsi",
              name: "rsi_14",
              # Changed from 14 to 21
              parameters: %{"period" => 21},
              _id: Ecto.UUID.generate()
            }
          ]
      }

      # Convert back to DSL
      {:ok, modified_dsl} = Synchronizer.builder_to_dsl(modified_state, initial_comments)

      # Parse again
      {:ok, final_state} = Synchronizer.dsl_to_builder(modified_dsl)
      final_comments = final_state._comments || []

      # Comments should still be present
      assert length(final_comments) >= length(initial_comments) * 0.9,
             "Lost too many comments after modification"

      # Key comments should survive
      initial_comment_texts = Enum.map(initial_comments, & &1.text)
      final_comment_texts = Enum.map(final_comments, & &1.text)

      # At least 80% of comments should be preserved
      preserved_count =
        Enum.count(initial_comment_texts, fn text ->
          text in final_comment_texts
        end)

      preservation_rate = preserved_count / length(initial_comment_texts)

      assert preservation_rate >= 0.8,
             "Preservation rate #{preservation_rate * 100}% below 80% threshold"
    end

    @tag :property
    property "comments are preserved regardless of strategy size" do
      check all(
              indicator_count <- integer(1..20),
              comment_count <- integer(1..50)
            ) do
        dsl_with_comments = generate_dsl_with_comments(indicator_count, comment_count)

        # Parse DSL
        {:ok, builder_state} = Synchronizer.dsl_to_builder(dsl_with_comments)
        extracted_comments = builder_state._comments || []

        # Convert back to DSL
        {:ok, regenerated_dsl} = Synchronizer.builder_to_dsl(builder_state, extracted_comments)

        # Parse again
        {:ok, final_state} = Synchronizer.dsl_to_builder(regenerated_dsl)
        final_comments = final_state._comments || []

        # Verify comment count (allow small loss due to formatting)
        assert length(final_comments) >= length(extracted_comments) * 0.9,
               "Too many comments lost: #{length(extracted_comments)} → #{length(final_comments)}"
      end
    end

    test "inline comments preserved on same line as code" do
      dsl_with_inline = """
      defstrategy InlineCommentStrategy do
        @trading_pair "BTC/USD"  # Main trading pair
        @timeframe "1h"  # Hourly timeframe

        indicator :rsi_14, :rsi, period: 14  # Momentum indicator

        entry_conditions do
          rsi_14 < 30  # Oversold condition
        end

        exit_conditions do
          rsi_14 > 70  # Overbought condition
        end

        position_sizing do
          percentage_of_capital 0.10  # 10% of capital per trade
        end

        risk_parameters do
          max_daily_loss 0.03  # 3% max daily loss
          max_drawdown 0.15  # 15% max drawdown
          max_position_size 0.10  # 10% max position
        end
      end
      """

      # Round-trip transformation
      {:ok, builder_state} = Synchronizer.dsl_to_builder(dsl_with_inline)
      comments = builder_state._comments || []

      # Should extract inline comments
      assert length(comments) >= 6, "Expected at least 6 inline comments"

      # Convert back
      {:ok, regenerated_dsl} = Synchronizer.builder_to_dsl(builder_state, comments)

      # Verify comments are present in output
      comment_count = String.split(regenerated_dsl, "#") |> length()
      assert comment_count >= 7, "Inline comments not preserved in DSL output"
    end

    test "block comments preserved above sections" do
      dsl_with_blocks = """
      defstrategy BlockCommentStrategy do
        @trading_pair "BTC/USD"
        @timeframe "1h"

        # ============================================
        # INDICATORS SECTION
        # Define all technical indicators here
        # ============================================
        indicator :rsi_14, :rsi, period: 14
        indicator :sma_20, :sma, period: 20

        # ============================================
        # ENTRY CONDITIONS
        # Define when to open a position
        # ============================================
        entry_conditions do
          rsi_14 < 30 and close > sma_20
        end

        # ============================================
        # EXIT CONDITIONS
        # Define when to close a position
        # ============================================
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

      # Multiple round-trips
      {:ok, state1} = Synchronizer.dsl_to_builder(dsl_with_blocks)
      comments1 = state1._comments || []

      {:ok, dsl2} = Synchronizer.builder_to_dsl(state1, comments1)
      {:ok, state2} = Synchronizer.dsl_to_builder(dsl2)
      comments2 = state2._comments || []

      {:ok, dsl3} = Synchronizer.builder_to_dsl(state2, comments2)
      {:ok, state3} = Synchronizer.dsl_to_builder(dsl3)
      comments3 = state3._comments || []

      # Block comments should survive
      assert length(comments3) >= 10,
             "Block comments lost: #{length(comments1)} → #{length(comments3)}"
    end
  end

  # Helper Functions

  defp perform_round_trips(initial_state, initial_comments, n) do
    Enum.reduce(1..n, {initial_state, initial_comments}, fn iteration, {state, comments} ->
      # Builder → DSL
      {:ok, dsl_text} = Synchronizer.builder_to_dsl(state, comments)

      # DSL → Builder
      {:ok, new_state} = Synchronizer.dsl_to_builder(dsl_text)
      new_comments = new_state._comments || comments

      if rem(iteration, 10) == 0 do
        IO.puts("Round-trip #{iteration}: #{length(new_comments)} comments")
      end

      {new_state, new_comments}
    end)
    # Return final comments
    |> elem(1)
  end

  defp generate_dsl_with_comments(indicator_count, comment_count) do
    indicators =
      for i <- 1..indicator_count do
        """
          # Indicator #{i} comment
          indicator :indicator_#{i}, :sma, period: #{10 + i}
        """
      end

    additional_comments =
      for i <- 1..comment_count do
        "  # Additional comment #{i}\n"
      end

    """
    defstrategy GeneratedStrategy do
      @trading_pair "BTC/USD"
      @timeframe "1h"

    #{Enum.join(indicators)}

    #{Enum.join(additional_comments)}

      entry_conditions do
        indicator_1 > 100
      end

      exit_conditions do
        indicator_1 < 100
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
  end
end
