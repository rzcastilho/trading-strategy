defmodule TradingStrategy.StrategyEditor.CommentPreserver do
  @moduledoc """
  Preserves DSL comments during builder → DSL transformations using Sourceror.

  This module uses the Sourceror library to parse Elixir DSL with comments intact,
  transform the AST based on builder changes, and format back to text with comments
  preserved in their original positions.

  ## Features

  - Zero production dependencies (Sourceror wraps native Elixir API)
  - Deterministic formatting ensures idempotence (SC-009)
  - Supports 100+ round-trip transformations
  - Comment positions automatically tracked by line/column

  ## Example

      # Original DSL with comments
      dsl_text = \"\"\"
      # This is my RSI strategy
      defstrategy MyStrategy do
        # Check RSI indicator
        indicator :rsi_14, :rsi, period: 14
      end
      \"\"\"

      # Parse with comments
      {:ok, ast, comments} = CommentPreserver.parse(dsl_text)

      # Transform AST (e.g., change RSI period to 21)
      new_ast = update_rsi_period(ast, 21)

      # Format back with comments preserved
      {:ok, output} = CommentPreserver.format(new_ast, comments)

      # Output still contains comments in correct positions!
  """

  alias Sourceror.Zipper

  @doc """
  Parse DSL text into AST with comments preserved.

  Returns `{:ok, ast, comments}` on success, where:
  - `ast` is the Elixir AST
  - `comments` is a list of comment metadata for Sourceror

  Returns `{:error, reason}` on parse failure.
  """
  def parse(dsl_text) when is_binary(dsl_text) do
    case Sourceror.parse_string(dsl_text) do
      {:ok, ast} ->
        # Sourceror parses comments automatically
        comments = extract_comments(dsl_text)
        {:ok, ast, comments}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Format AST back to DSL text with comments preserved.

  Uses Sourceror's deterministic formatter to ensure:
  - Comments are reattached at correct positions
  - Consistent indentation (2 spaces)
  - No trailing whitespace
  - Idempotent output (multiple format calls produce identical results)
  """
  def format(ast, comments \\ []) do
    try do
      # Use Sourceror to format with comments
      formatted =
        ast
        |> Sourceror.Zipper.zip()
        |> Sourceror.Zipper.root()
        |> Sourceror.to_string(comments: comments)

      {:ok, formatted}
    rescue
      e ->
        {:error, "Formatting failed: #{Exception.message(e)}"}
    end
  end

  @doc """
  Extract comments from DSL source text.

  Returns a list of comment metadata structures that Sourceror can use
  to preserve comments during transformations.
  """
  def extract_comments(dsl_text) when is_binary(dsl_text) do
    lines = String.split(dsl_text, "\n", trim: false)

    lines
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_number} ->
      extract_line_comments(line, line_number)
    end)
  end

  defp extract_line_comments(line, line_number) do
    case Regex.run(~r/^(\s*)#(.*)$/, line) do
      [_full, indent, text] ->
        [
          %{
            line: line_number,
            column: String.length(indent) + 1,
            text: "##{text}",
            previous_eol_count: 0,
            next_eol_count: 1
          }
        ]

      nil ->
        # Check for inline comments (after code)
        case Regex.run(~r/^(.*?)\s+#(.*)$/, line) do
          [_full, _code, text] ->
            # Find column position of comment
            comment_pos =
              String.length(line) - String.length(String.trim_leading(line)) - String.length(text) -
                1

            [
              %{
                line: line_number,
                column: max(comment_pos, 1),
                text: "##{text}",
                previous_eol_count: 0,
                next_eol_count: 0
              }
            ]

          nil ->
            []
        end
    end
  end

  @doc """
  Merge builder state comments with existing DSL comments.

  When the builder modifies a strategy, we need to:
  1. Preserve comments from the original DSL
  2. Add any new comments from builder metadata

  Returns a merged list of comments sorted by line number.
  """
  def merge_comments(dsl_comments, builder_comments) do
    # Convert builder comments to Sourceror format
    sourceror_comments =
      Enum.map(builder_comments, fn comment ->
        %{
          line: comment.line,
          column: comment.column,
          text: comment.text,
          previous_eol_count: 0,
          next_eol_count: 1
        }
      end)

    # Merge and deduplicate (prefer DSL comments if same position)
    (dsl_comments ++ sourceror_comments)
    |> Enum.uniq_by(fn c -> {c.line, c.column} end)
    |> Enum.sort_by(fn c -> {c.line, c.column} end)
  end

  @doc """
  Validate that comments are preserved after round-trip transformation.

  This is used in property-based tests to verify SC-009 (100+ round-trips).
  Returns `:ok` if comments match, `{:error, diff}` otherwise.
  """
  def validate_preservation(original_comments, transformed_comments) do
    original_text = Enum.map(original_comments, & &1.text) |> Enum.sort()
    transformed_text = Enum.map(transformed_comments, & &1.text) |> Enum.sort()

    if original_text == transformed_text do
      :ok
    else
      missing = original_text -- transformed_text
      added = transformed_text -- original_text

      {:error,
       %{
         missing: missing,
         added: added,
         expected_count: length(original_text),
         actual_count: length(transformed_text)
       }}
    end
  end
end
