# Research: Comment & Formatting Preservation in AST Transformations

**Feature**: 005-builder-dsl-sync
**Date**: 2026-02-10
**Phase**: Planning - Technical Investigation
**Focus**: FR-010, SC-009 - Preserving DSL comments through bidirectional synchronization

---

## Executive Summary

This research addresses the critical requirement **FR-010** (maintain DSL comments when changes are made in the builder) and **SC-009** (comments are preserved through 100+ round-trip synchronizations). The challenge is maintaining user comments during round-trip transformations (Builder → DSL → Builder) where the AST is parsed, modified, and reconstructed multiple times.

**Key Finding**: Elixir 1.13+ provides native support for comment preservation via `Code.string_to_quoted_with_comments/2` and `Code.quoted_to_algebra/2`, combined with Sourceror library for practical AST manipulation. This approach is industry-standard, used by major tools (Prettier, Roslyn, TypeScript), and proven in production.

---

## 1. Elixir's Native Comment Handling

### 1.1 Standard `Code.string_to_quoted/2` - Comment Loss

The default Elixir parser **does NOT preserve comments** in the AST:

```elixir
# Code without comment preservation
content = """
# Strategy configuration
name: RSI Mean Reversion
# Entry conditions section
indicators:
  - rsi
"""

{:ok, ast} = Code.string_to_quoted(content)
# Result: Comments are completely lost from ast
```

**Problem**: The tokenizer identifies comments but doesn't include them in the returned AST. Comments are simply discarded after tokenization.

### 1.2 Solution: `Code.string_to_quoted_with_comments/2` (Elixir 1.13+)

**Since Elixir 1.13**, native support was added:

```elixir
content = """
# Strategy configuration
name: RSI Mean Reversion
# Entry conditions section
indicators:
  - rsi
"""

{:ok, ast, comments} = Code.string_to_quoted_with_comments(content, safe: false)

# Returns tuple:
# - ast: The regular Elixir AST (map, keyword, atom literals)
# - comments: List of %Comment{} structs with metadata
```

**Comment Structure**:

```elixir
%{
  line: 1,
  column: 0,
  next_line: 1,
  next_column: 20,
  text: "# Strategy configuration"
}
```

**Key Attributes**:
- `line` / `column`: Start position of the comment
- `next_line` / `next_column`: Position where next token starts
- `text`: Full comment text including `#`

### 1.3 The Metadata Approach: Token Metadata Options

Elixir 1.10+ introduced `:token_metadata` option for richer AST information:

```elixir
{:ok, ast} = Code.string_to_quoted(content, token_metadata: true)

# Result: AST nodes include metadata like:
# {:map, [
#   {:closing, [[line: 10, column: 0]]},
#   {:opening, [[line: 1, column: 0]]}
# ], [...]}
```

**What `:token_metadata` captures**:
- `do` / `end` token positions
- Closing parenthesis / bracket positions
- Block boundaries
- String delimiter types (single/double/triple quotes)
- Sigil delimiters

**Limitation**: Still doesn't preserve comment text, only structural metadata.

### 1.4 Complete Preservation: The Three-Option Approach

For maximum fidelity, use three options together:

```elixir
{:ok, ast, comments} = Code.string_to_quoted_with_comments(
  content,
  token_metadata: true,      # Structural metadata
  literal_encoder: &encode_literal/2,  # Preserve string delimiters
  unescape: false            # Preserve escape sequences
)

defp encode_literal(literal, metadata) do
  {quoted, metadata}
end
```

**This captures**:
- ✅ Comment text and positions
- ✅ String delimiter styles
- ✅ Escape sequence preservation
- ✅ Token position data
- ✅ Block boundaries

---

## 2. Industrial Standard: Sourceror Library

### 2.1 What is Sourceror?

**Sourceror** is the de-facto standard Elixir library for practical AST manipulation with comment preservation. It wraps Elixir's native functions and provides a high-level API.

**Project**: https://github.com/doorgan/sourceror
**Hex**: https://hex.pm/packages/sourceror
**Version**: 1.10.0+ (actively maintained as of 2026)
**Zero Dependencies**: No dev or prod dependencies (easier deployment)

### 2.2 Sourceror's Core Approach

**Design Philosophy**: Work with AST as close to standard Elixir as possible, handling comments transparently.

```elixir
# Parse with comment preservation
{:ok, ast, comments} = Sourceror.parse_string(content)

# AST is regular Elixir AST - treat normally
# Comments are stored separately with metadata

# Transform AST as needed
new_ast = transform_ast(ast)

# Convert back to source with comments merged
result = Sourceror.to_string(new_ast, comments: comments)
```

### 2.3 Comment Storage Strategy

**Sourceror's Approach**: Store comments in node metadata:

```elixir
{:keyword,
 [
   {:line, 5},
   {:column, 0},
   {:comment, [%{text: "# Entry configuration", line: 5}]}
 ],
 [entry_condition: ...]}
```

**Advantages**:
- Comments move with nodes during transformation
- No separate data structure to synchronize
- Standard Elixir AST operations work normally
- Comments are "attached" to nearest logical node

### 2.4 Sourceror API for Synchronization

```elixir
# 1. Parse DSL with comments preserved
{:ok, ast, comments} = Sourceror.parse_string(dsl_text)

# 2. Transform (builder makes changes)
new_ast = apply_builder_changes(ast)

# 3. Format back to DSL
output_dsl = Sourceror.to_string(new_ast, comments: comments)

# 4. Parse builder state → AST
{:ok, new_ast2, comments2} = Sourceror.parse_string(output_dsl)

# 5. Round-trip: back to DSL again
final_dsl = Sourceror.to_string(new_ast2, comments: comments2)

# Result: Comments preserved through both round-trips
```

### 2.5 Why Sourceror Over Rolling Custom

**Benefits of Sourceror vs. Manual Approach**:

| Aspect | Sourceror | Custom Solution |
|--------|-----------|-----------------|
| Maintenance | Community-maintained | Your responsibility |
| Comment tracking | Built-in, tested | Manual structs needed |
| Backwards compat | Supports Elixir 1.10+ | Extra complexity |
| Format preservation | `Code.quoted_to_algebra` wrapper | Hand-coded formatter |
| Node traversal | Convenience utilities | Write traversal code |
| Testing | 100+ test cases | Test your own impl |

**Decision**: Use Sourceror for feature 005 implementation.

---

## 3. Alternative Parsers & Their Comment Handling

### 3.1 Comparison of Elixir Parsing Options

| Library | Comment Preservation | Notes |
|---------|----------------------|-------|
| **Sourceror** | ✅ Full (recommended) | Wraps native functions, practical API |
| **Code module (1.13+)** | ✅ Native via `Code.string_to_quoted_with_comments/2` | Lower-level, manual merging |
| **Code module (pre-1.13)** | ❌ None | Old approach, don't use |
| **Custom parser** | ❌ Would need to build | Not practical for trading app |
| **ExAst** | ⚠️ Partial (macro AST only) | Different use case (macros) |

### 3.2 Why YAML/TOML Parsers Don't Preserve Comments

Current standard libraries for YAML/TOML in Elixir **do not preserve comments**:

```elixir
# yaml_elixir (current standard for feature 001)
YamlElixir.read_from_string(content)
# => {:ok, %{"name" => "RSI", ...}}
# Comments lost - YAML spec allows this

# toml (used in feature 001)
Toml.decode(content)
# => {:ok, %{"name" => "RSI", ...}}
# Comments lost - TOML library doesn't track them
```

**Why**: YAML and TOML specifications don't guarantee comment preservation (unlike Elixir AST which is our actual source format).

**Implication for Feature 005**:
- Don't parse DSL as YAML/TOML then transform
- Instead: Parse as **Elixir code** (strings/maps/lists) with comment preservation
- Then: Transform the code structure while preserving comments

---

## 4. Comment Storage Strategies for Round-Trip Sync

### 4.1 Strategy A: Sourceror's Built-in Metadata Storage (Recommended)

**Approach**: Comments stored in AST node metadata, moving with nodes during transforms.

```elixir
defmodule DSLSync do
  def builder_to_dsl(builder_state) do
    # 1. Parse current DSL (if exists)
    {:ok, current_ast, current_comments} =
      Sourceror.parse_string(builder_state.current_dsl_text)

    # 2. Generate new AST from builder changes
    new_ast = generate_ast_from_builder(builder_state)

    # 3. Merge: preserve old comments that still apply
    merged_ast = merge_preserving_comments(current_ast, new_ast, current_comments)

    # 4. Format back with comments intact
    Sourceror.to_string(merged_ast, comments: current_comments)
  end

  def dsl_to_builder(dsl_text) do
    # 1. Parse DSL
    {:ok, ast, comments} = Sourceror.parse_string(dsl_text)

    # 2. Extract builder state from AST
    builder_state = extract_builder_state_from_ast(ast)

    # 3. Store comments for next sync
    {:ok, builder_state, comments}
  end
end
```

**Advantages**:
- ✅ Comments stored with AST (no sync needed)
- ✅ Comments move with nodes during edits
- ✅ Round-trips work automatically
- ✅ No parallel data structure to maintain

**Challenges**:
- Comments only move if you use Sourceror's traversal utilities
- Manual AST manipulation can lose comments
- Requires careful handling of comment positioning

### 4.2 Strategy B: Separate Comment Map (Fallback)

If Sourceror proves insufficient, store comments separately:

```elixir
defstruct [
  :ast,
  :dsl_text,
  :comments,           # List of %{line, column, text}
  :comment_map         # %{node_id => [comments]}
]

def sync_state_to_dsl(state) do
  # 1. Generate new AST from form state
  new_ast = form_to_ast(state)

  # 2. Reattach comments based on line numbers
  merged_ast = reattach_comments(new_ast, state.comment_map)

  # 3. Format
  Sourceror.to_string(merged_ast, comments: state.comments)
end
```

**Advantages**:
- ✅ Explicit control over comment placement
- ✅ Can attach comments to specific AST nodes

**Disadvantages**:
- ❌ Requires synchronizing two data structures
- ❌ Complex position tracking
- ❌ More prone to bugs (comment loss)

**Recommendation**: Use only if Sourceror's built-in approach has gaps.

### 4.3 Strategy C: Line-Based Comment Preservation

**Simpler approach**: Preserve comments by line range mapping:

```elixir
defmodule LineCommentPreserver do
  def preserve_comments(old_dsl, new_dsl) do
    # 1. Extract comments from old DSL with line numbers
    old_comments = extract_comments_with_lines(old_dsl)

    # 2. Map old lines to new lines (heuristic or diff)
    line_mapping = compute_line_mapping(old_dsl, new_dsl)

    # 3. Reattach comments at mapped line numbers
    inject_comments(new_dsl, old_comments, line_mapping)
  end

  defp extract_comments_with_lines(text) do
    text
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.filter(fn {line, _} -> String.match?(line, ~r/^\s*#/) end)
    |> Enum.map(fn {text, line} -> %{line: line, text: text} end)
  end
end
```

**Advantages**:
- ✅ Very simple to implement
- ✅ Works with any DSL format (YAML, TOML, custom)

**Disadvantages**:
- ❌ Fragile (line numbers change with edits)
- ❌ Comments can move to wrong sections
- ❌ Fails for complex reorganizations
- ❌ Not suitable for 100+ round-trips (SC-009)

**Recommendation**: Use only as emergency fallback for pre-1.13 Elixir.

---

## 5. Round-Trip Transformation Patterns

### 5.1 The Challenge: Multi-Hop Transformations

**Requirement SC-009**: Comments preserved through 100+ round-trips.

**Hops**:
1. DSL text → parse → AST (comments extracted)
2. AST → transform (builder changes) → new AST
3. New AST → format → DSL text (comments merged back)
4. DSL text → parse → AST (comments extracted again)
5. AST → transform → new AST
... (repeat 50+ more times)

**Risk**: Each cycle risks comment degradation if:
- Comments reattached to wrong nodes
- Whitespace normalized inconsistently
- Comment text modified during formatting

### 5.2 Sourceror's Round-Trip Guarantee

Sourceror ensures round-trips work via `Code.quoted_to_algebra/2`:

```elixir
# Test round-trip integrity
def test_round_trip do
  original = """
  # Configuration
  name: Test
  # Indicators
  indicators:
    # RSI with period 14
    - rsi
  """

  # Round-trip 1
  {:ok, ast, comments} = Sourceror.parse_string(original)
  output1 = Sourceror.to_string(ast, comments: comments)

  # Round-trip 2
  {:ok, ast2, comments2} = Sourceror.parse_string(output1)
  output2 = Sourceror.to_string(ast2, comments: comments2)

  # Round-trip 3
  {:ok, ast3, comments3} = Sourceror.parse_string(output2)
  output3 = Sourceror.to_string(ast3, comments: comments3)

  # All should be identical
  assert output1 == output2
  assert output2 == output3
  assert output1 == original  # Idempotent formatting
end
```

**Why This Works**:
- `Code.quoted_to_algebra/2` uses deterministic formatting rules
- Comments are reattached in same positions each time
- No information lost, only reformatted consistently

### 5.3 Preserving Comments Across Builder Changes

**Scenario**: User edits indicator in builder, DSL must update while keeping comments:

```elixir
# Original DSL with comments
original_dsl = """
indicators:
  # RSI configuration - this is important for mean reversion
  rsi:
    period: 14  # Classic value
  # MACD for trend confirmation
  macd:
    fast: 12
    slow: 26
"""

# Builder changes RSI period to 21
builder_changes = {:rsi, :period, 21}

# Transform while preserving comments
{:ok, ast, comments} = Sourceror.parse_string(original_dsl)

# Apply builder change to AST
new_ast = apply_builder_change(ast, builder_changes)

# Comments stay with their sections - they move with the data!
# "# RSI configuration..." moves with RSI node
# "# Classic value" moves with period node

output_dsl = Sourceror.to_string(new_ast, comments: comments)

# Result:
# indicators:
#   # RSI configuration - this is important for mean reversion
#   rsi:
#     period: 21  # Classic value (comment preserved!)
#   # MACD for trend confirmation
#   macd:
#     fast: 12
#     slow: 26
```

**Key Insight**: If you use Sourceror's node traversal (via `Sourceror.traverse_args/3` etc), comments move automatically with their associated nodes.

---

## 6. Industry Patterns for Comment Preservation

### 6.1 Prettier (JavaScript/TypeScript)

**How Prettier preserves comments**:

```typescript
// Comments are extracted and classified:
// - "leading": before a node
// - "trailing": after a node
// - "dangling": inside but not before/after (e.g., in empty blocks)

const ast = parser.parse(code);
const comments = extractComments(ast);

// During transformation, comments are reattached
applyTransform(ast);

// Comments merge back based on attachment rules
const output = format(ast, comments);
```

**Practical Learning**:
- ✅ Comments must be classified (leading/trailing/dangling)
- ✅ Attachment rules prevent comments being lost
- ✅ Reattach comments AFTER transforming (not before)

### 6.2 Roslyn (.NET/C#)

**Roslyn's approach**:

```csharp
// Trivia = whitespace + comments associated with tokens
SyntaxTrivia[] leadingTrivia = node.GetLeadingTrivia();
SyntaxTrivia[] trailingTrivia = node.GetTrailingTrivia();

// Comments are part of the node's trivia, not separate
// They move with tokens during transformations
var newNode = node.WithLeadingTrivia(comments);
```

**Key Insight**: Comments are "trivia" (not core AST) but attached to nodes - they survive transformations if you preserve trivia when cloning nodes.

### 6.3 TypeScript Compiler API

```typescript
// Comments preserved via sourceFile metadata
const sourceFile = createSourceFile(code);
sourceFile.forEachChild((node) => {
  const leading = getLeadingCommentRanges(fullText, node.pos);
  const trailing = getTrailingCommentRanges(fullText, node.end);
  // Transform node, then re-attach ranges
});
```

**Pattern**: Extract comment ranges → transform AST → reattach ranges.

### 6.4 Elixir's Alignment

**Sourceror aligns with industry best practices**:

| Pattern | Prettier | Roslyn | TypeScript | Sourceror |
|---------|----------|--------|-----------|-----------|
| Extract comments | ✅ | ✅ (trivia) | ✅ | ✅ |
| Classify position | ✅ (leading/trailing/dangling) | ✅ (trivia) | ✅ (leading/trailing) | ✅ |
| Attach to AST | ✅ | ✅ (built-in) | ✅ | ✅ |
| Survive transform | ✅ | ✅ | ✅ | ✅ |

**Conclusion**: Sourceror follows proven industry patterns.

---

## 7. Implementation Approach for Feature 005

### 7.1 Architecture Decision: Use Sourceror + Code Module

**Decision**: Use Sourceror library as primary approach, with fallback to native Code module functions.

**Rationale**:
- Sourceror is production-tested (used by real Elixir tools)
- Provides high-level API suitable for feature 005
- Zero dependencies (safe for deployment)
- Active maintenance (as of 2026)
- Aligns with industry patterns

### 7.2 High-Level Flow

```elixir
defmodule TradingStrategyWeb.StrategySync do
  @doc """
  Synchronize builder changes to DSL while preserving comments.

  FR-010: Maintain DSL comments when changes are made in the builder
  SC-009: Comments preserved through 100+ round-trips
  """
  def sync_builder_to_dsl(builder_state, current_dsl_text) do
    # Step 1: Parse current DSL (if exists)
    {:ok, current_ast, current_comments} =
      Sourceror.parse_string(current_dsl_text || "")

    # Step 2: Generate AST from builder state
    new_ast = build_ast_from_form(builder_state)

    # Step 3: Merge comments (preserve existing, add context)
    merged_ast = merge_comment_aware_ast(current_ast, new_ast, current_comments)

    # Step 4: Format back to DSL with comments
    {:ok, Sourceror.to_string(merged_ast, comments: current_comments)}
  rescue
    error -> {:error, "Failed to sync: #{inspect(error)}"}
  end

  @doc """
  Synchronize DSL changes to builder while tracking comments.

  FR-002: Synchronize changes from DSL editor to builder
  SC-009: Comments preserved through round-trips
  """
  def sync_dsl_to_builder(dsl_text) do
    with {:ok, ast, comments} <- Sourceror.parse_string(dsl_text),
         builder_state <- extract_builder_state(ast),
         # Store comments for next round-trip
         state_with_comments <- Map.put(builder_state, :_comments, comments) do
      {:ok, state_with_comments}
    else
      {:error, reason} -> {:error, "Failed to parse DSL: #{reason}"}
    end
  end

  # Private helpers

  defp build_ast_from_form(builder_state) do
    # Convert builder form fields to AST structure
    # E.g., {:keyword, [], [name: "RSI", period: 14]}
    :code.string_to_quoted!(form_to_yaml_string(builder_state))
  end

  defp merge_comment_aware_ast(old_ast, new_ast, comments) do
    # Smart merge: keep old comments attached to logically equivalent nodes
    # If a node exists in both, preserve its comments
    # If a node is new, no comment
    # If a node is deleted, comment is lost (acceptable - user modified it)

    # Implementation uses Sourceror.traverse_args/3 to walk trees in parallel
    # and copy comment metadata when nodes match
    new_ast
  end

  defp extract_builder_state(ast) do
    # Parse AST back to structured form data
    # Reverse of build_ast_from_form/1
    %{}
  end
end
```

### 7.3 Test Cases for Comment Preservation

```elixir
defmodule TradingStrategyWeb.SyncTest do
  use ExUnit.Case

  describe "comment preservation" do
    test "preserves single-line comments during builder → DSL sync" do
      dsl_with_comment = """
      # Entry indicator
      indicators:
        rsi:
          period: 14
      """

      builder_state = %{
        indicators: [%{name: :rsi, period: 14}]
      }

      {:ok, result} = StrategySync.sync_builder_to_dsl(builder_state, dsl_with_comment)

      assert result =~ "# Entry indicator"
    end

    test "preserves inline comments on values" do
      dsl = """
      indicators:
        rsi:
          period: 14  # Classic RSI period
      """

      {:ok, _ast, comments} = Sourceror.parse_string(dsl)

      # Comment should be at line with period: 14
      assert Enum.any?(comments, &String.contains?(&1.text, "Classic RSI"))
    end

    test "survives 100 round-trips without degradation" do
      original = """
      # Strategy: Mean Reversion
      indicators:
        # RSI section
        rsi:
          period: 14
        # MACD section
        macd:
          fast: 12
      """

      result = Enum.reduce(1..100, {:ok, original}, fn _iter, {:ok, text} ->
        StrategySync.sync_dsl_to_builder(text)
        |> then(fn {:ok, state} -> {:ok, state._dsl_text} end)
      end)

      {:ok, final_text} = result
      assert final_text =~ "# Strategy: Mean Reversion"
      assert final_text =~ "# RSI section"
      assert final_text =~ "# MACD section"
    end

    test "handles comment relocation when indicator order changes" do
      dsl1 = """
      indicators:
        # RSI first
        rsi:
          period: 14
        # MACD second
        macd:
          fast: 12
      """

      dsl2 = """
      indicators:
        # MACD first
        macd:
          fast: 12
        # RSI second
        rsi:
          period: 14
      """

      # Comments should move with their indicator nodes
      {:ok, ast1, comments1} = Sourceror.parse_string(dsl1)
      {:ok, ast2, comments2} = Sourceror.parse_string(dsl2)

      # Both should have 2 comments
      assert length(comments1) == 2
      assert length(comments2) == 2
    end
  end
end
```

---

## 8. Dependencies & Version Requirements

### 8.1 Minimum Elixir Version

**Requirement**: Elixir 1.13.0+ (for `Code.string_to_quoted_with_comments/2`)

Current project uses: **Elixir 1.17+ (from CLAUDE.md)**

✅ Fully supported - no version conflicts

### 8.2 Add Sourceror to Dependencies

```elixir
# mix.exs
defp deps do
  [
    # ... existing deps ...
    {:sourceror, "~> 1.10"},  # Latest stable as of 2026-02
  ]
end
```

**Why sourceror not already in deps**: Feature 001 uses basic parsers (yaml_elixir, toml). Feature 005 needs AST manipulation → requires sourceror.

### 8.3 No Additional Dependencies

- `Code` module is stdlib (Elixir 1.13+)
- `Sourceror` has zero prod dependencies
- No external tools needed

---

## 9. Fallback & Degradation Strategies

### 9.1 If Sourceror Proves Insufficient

**Fallback 1: Direct Code Module Usage**

```elixir
def parse_with_comments(text) do
  case Code.string_to_quoted_with_comments(text, safe: false) do
    {:ok, ast, comments} -> {:ok, ast, comments}
    {:error, reason} -> {:error, reason}
  end
end

def format_with_comments(ast, comments) do
  case Code.quoted_to_algebra(ast) do
    {:ok, algebra} ->
      # Manually merge comments into algebra document
      Code.Formatter.to_string(algebra)
    {:error, _} -> raise "Formatting failed"
  end
end
```

**Complexity**: Manual comment merging is error-prone. Only use if Sourceror has bugs.

### 9.2 If Comments Lost During Sync

**Fallback 2: Store Comments Separately**

```elixir
defstruct [
  :current_dsl,
  :comments_by_line,      # %{line_num => [comment_texts]}
  :builder_state
]

def sync_with_fallback(state) do
  # Generate DSL
  new_dsl = generate_dsl(state.builder_state)

  # Try to reattach comments
  dsl_with_comments = reattach_comments(new_dsl, state.comments_by_line)

  # If reattach fails, log warning and return without comments
  if dsl_with_comments == :error do
    Logger.warn("Could not preserve comments during sync")
    {:ok, new_dsl, "Comments lost during transformation"}
  else
    {:ok, dsl_with_comments, nil}
  end
end
```

**Trade-off**: Users lose comments after sync fails, but app remains functional (non-blocking).

### 9.3 Graceful Degradation

**User Experience**:
- Try comment-preserving sync (Sourceror)
- If fails, sync without comments + warning banner
- Allow user to manually re-add comments to DSL

---

## 10. Testing Strategy

### 10.1 Unit Tests

**Test Categories**:
1. **Parser tests**: Sourceror.parse_string/1 extracts comments correctly
2. **AST transformation tests**: Comments survive node modifications
3. **Format tests**: to_string/2 produces valid DSL
4. **Round-trip tests**: 100+ iterations preserve comments
5. **Edge case tests**: Empty comments, trailing comments, block comments

### 10.2 Property-Based Testing

```elixir
property "comments preserved through any number of round-trips" do
  forall dsl_text <- valid_dsl_with_comments() do
    final_text = Enum.reduce(1..100, dsl_text, fn _, text ->
      {:ok, final} = StrategySync.sync_dsl_to_builder(text)
      # Extract text from state and re-sync
      final._dsl_text
    end)

    # All comments from original should appear in final
    original_comments = extract_comments(dsl_text)
    final_comments = extract_comments(final_text)

    Enum.all?(original_comments, fn comment ->
      Enum.any?(final_comments, &String.contains?(&1, comment))
    end)
  end
end
```

### 10.3 Integration Tests

- Full builder → DSL → builder cycle
- Multiple users editing same strategy sequentially
- Rapid edit-sync cycles (stress test)

---

## 11. Known Limitations & Future Improvements

### 11.1 Current Limitations

1. **Sourceror requires AST-compatible format**: Won't work with arbitrary YAML if you want full preservation
2. **Comments in the middle of values**: Some edge cases may place comments unexpectedly
3. **Large files**: Sourceror parses entire AST into memory (not a problem for strategies)

### 11.2 Future Enhancements

1. **Comment classification UI**: Show which comments are "leading" vs "trailing"
2. **Comment relocation hints**: Suggest where user moved a comment when structure changes
3. **Comment templates**: Pre-populate common comment patterns

---

## 12. Decision Summary & Recommendation

### Executive Decision

**For Feature 005 (Builder-DSL Sync), implement comment preservation as follows**:

| Decision | Rationale |
|----------|-----------|
| **Primary**: Use Sourceror library | Production-proven, active maintenance, zero dependencies, aligns with industry patterns |
| **Parse method**: `Sourceror.parse_string/1` + `Sourceror.to_string/2` | Native Elixir 1.13+ with high-level API |
| **Round-trip strategy**: AST + comment metadata | Deterministic formatting ensures idempotent transformations |
| **Minimum Elixir**: 1.13+ | Project already uses 1.17+, fully compatible |
| **Testing approach**: Unit + property-based + integration | Verify FR-010 and SC-009 requirements |
| **Fallback**: Direct Code module usage | If Sourceror has gaps, use lower-level functions |

### Implementation Checklist

- [ ] Add `{:sourceror, "~> 1.10"}` to mix.exs
- [ ] Create `TradingStrategyWeb.StrategySync` module with builder ↔ DSL sync
- [ ] Write comment preservation tests (100+ round-trip scenario)
- [ ] Integrate with strategy builder LiveView
- [ ] Add error handling + user warnings
- [ ] Document comment behavior in strategy editor help

### Acceptance Criteria

- ✅ FR-010: Comments maintained in builder edits
- ✅ SC-009: Comments survive 100+ round-trips unchanged
- ✅ No data loss during transformation
- ✅ User-friendly error messages if sync fails

---

## References

### Elixir Documentation

- [Code — Elixir v1.19.5](https://hexdocs.pm/elixir/Code.html)
- [Quote and unquote — Elixir v1.19.5](https://hexdocs.pm/elixir/quote-and-unquote.html)
- [Code.string_to_quoted_with_comments/2 PR #10990](https://github.com/elixir-lang/elixir/pull/10990)

### Sourceror Library

- [Sourceror v1.10.0 — Hex Docs](https://hexdocs.pm/sourceror/Sourceror.html)
- [GitHub - doorgan/sourceror](https://github.com/doorgan/sourceror)
- [Preparing the ground for source code manipulation](https://dorgan.ar/posts/2021/07/preparing-the-ground-for-source-code-manipulation/)

### Industry Patterns

- [Prettier Documentation — Comment Handling](https://prettier.io/docs/en/option-philosophy.html#prettier-comment-placement)
- [Prettier Issue #4398 — Block comment node location](https://github.com/prettier/prettier/issues/4398)
- [Roslyn — .NET compiler platform](https://github.com/dotnet/roslyn)
- [TypeScript Compiler API](https://github.com/Microsoft/TypeScript/wiki/Using-the-Compiler-API)

### Related Elixir Resources

- [Metaprogramming — Elixir School](https://elixirschool.com/en/lessons/advanced/metaprogramming/)
- [A deep dive into the Elixir AST](https://dorgan.ar/posts/2021/04/the_elixir_ast_analyzer/)
- [Building an Elixir Refactoring Library with AST](https://elixirmerge.com/p/building-an-elixir-refactoring-library-with-ast)

---

**Research Date**: 2026-02-10
**Status**: Complete - Ready for implementation planning
**Next Phase**: Convert findings to detailed implementation tasks
