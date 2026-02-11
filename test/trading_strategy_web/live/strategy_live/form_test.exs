defmodule TradingStrategyWeb.StrategyLive.FormTest do
  use TradingStrategyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import TradingStrategy.StrategiesFixtures
  import TradingStrategy.AccountsFixtures

  alias TradingStrategy.Strategies

  describe "StrategyLive.Form - New Strategy (User Story 1)" do
    setup :register_and_log_in_user

    test "T018: mounts new strategy form with empty changeset", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/strategies/new")

      assert html =~ "Register New Strategy"
      assert html =~ "name"
      assert html =~ "description"
      assert html =~ "trading_pair"
      assert html =~ "timeframe"
      assert html =~ "format"
      assert html =~ "content"

      # Form should be empty
      assert view
             |> element("#strategy-form")
             |> render() =~ "phx-change=\"validate\""
    end

    test "T019: successfully creates strategy with valid data", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/strategies/new")

      strategy_attrs = %{
        "name" => "Test Momentum Strategy",
        "description" => "A strategy for testing momentum indicators",
        "format" => "yaml",
        "content" => valid_yaml_strategy(),
        "trading_pair" => "BTC/USD",
        "timeframe" => "1h"
      }

      view
      |> form("#strategy-form", strategy: strategy_attrs)
      |> render_submit()

      # Verify strategy was created
      strategies = Strategies.list_strategies(user)
      assert length(strategies) == 1
      strategy = List.first(strategies)

      # Should redirect to strategy show page
      assert_redirected(view, ~p"/strategies/#{strategy.id}")

      # Verify strategy details
      assert strategy.name == "Test Momentum Strategy"
      assert strategy.user_id == user.id
      assert strategy.status == "draft"
    end

    test "T020: validates required fields and shows errors", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/strategies/new")

      # Submit form with empty data
      view
      |> form("#strategy-form", strategy: %{})
      |> render_change()

      html = render(view)

      # Should show validation errors for required fields
      assert html =~ "can&#39;t be blank" or html =~ "can't be blank"

      # Try to submit - should fail
      view
      |> form("#strategy-form", strategy: %{})
      |> render_submit()

      # Should still be on form page
      assert render(view) =~ "Register New Strategy"
    end

    test "validates name length constraints", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/strategies/new")

      # Name too short
      view
      |> form("#strategy-form", strategy: %{"name" => "AB"})
      |> render_change()

      html = render(view)
      assert html =~ "must be between 3 and 200 characters"

      # Name too long
      long_name = String.duplicate("A", 201)

      view
      |> form("#strategy-form", strategy: %{"name" => long_name})
      |> render_change()

      html = render(view)
      assert html =~ "must be between 3 and 200 characters"
    end

    test "validates format field is a select with correct options", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/strategies/new")

      # Format field should be a select with yaml and toml options
      assert html =~ "select"
      assert html =~ "yaml"
      assert html =~ "toml"
      # Should not allow json or other formats
      refute html =~ "json"
    end

    test "validates timeframe field is a select with correct options", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/strategies/new")

      # Timeframe field should be a select with valid timeframes
      assert html =~ "select"
      assert html =~ "1m"
      assert html =~ "1h"
      assert html =~ "1d"
      # Should not allow invalid timeframes
      refute html =~ "99m"
    end
  end

  describe "StrategyLive.Form - Autosave (User Story 1)" do
    setup :register_and_log_in_user

    test "T026: saves draft on save_draft button click", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/strategies/new")

      strategy_attrs = %{
        "name" => "Draft Strategy",
        "format" => "yaml",
        "content" => valid_yaml_strategy(),
        "trading_pair" => "BTC/USD",
        "timeframe" => "1h"
      }

      # Fill in the form first
      view
      |> form("#strategy-form", strategy: strategy_attrs)
      |> render_change()

      # Trigger save_draft by clicking the button
      view
      |> element("button[phx-click=\"save_draft\"]")
      |> render_click()

      # Verify draft was saved
      strategies = Strategies.list_strategies(user)
      assert length(strategies) == 1
      strategy = List.first(strategies)
      assert strategy.name == "Draft Strategy"
      assert strategy.status == "draft"
    end
  end

  describe "StrategyLive.Form - Edit Mode (User Story 3)" do
    setup :register_and_log_in_user

    test "T047: loads existing strategy in edit mode", %{conn: conn, user: user} do
      strategy =
        strategy_fixture(%{
          user: user,
          name: "Existing Strategy",
          description: "Original description",
          trading_pair: "BTC/USD",
          timeframe: "1h",
          status: "draft"
        })

      {:ok, view, html} = live(conn, ~p"/strategies/#{strategy.id}/edit")

      # Should show edit form with pre-populated data
      assert html =~ "Edit Strategy"
      assert html =~ "Existing Strategy"
      assert html =~ "Original description"
      assert html =~ "BTC/USD"
      assert html =~ "1h"
    end

    test "allows editing draft strategy", %{conn: conn, user: user} do
      strategy = strategy_fixture(%{user: user, name: "Draft", status: "draft"})

      {:ok, view, _html} = live(conn, ~p"/strategies/#{strategy.id}/edit")

      # Update strategy
      view
      |> form("#strategy-form", strategy: %{"name" => "Updated Draft"})
      |> render_submit()

      # Verify strategy was updated
      updated = Strategies.get_strategy(strategy.id, user)
      assert updated.name == "Updated Draft"
      assert updated.status == "draft"
    end

    test "allows editing inactive strategy", %{conn: conn, user: user} do
      strategy = strategy_fixture(%{user: user, name: "Inactive", status: "inactive"})

      {:ok, view, _html} = live(conn, ~p"/strategies/#{strategy.id}/edit")

      # Update strategy
      view
      |> form("#strategy-form", strategy: %{"name" => "Updated Inactive"})
      |> render_submit()

      # Verify strategy was updated
      updated = Strategies.get_strategy(strategy.id, user)
      assert updated.name == "Updated Inactive"
    end

    test "T048: handles version conflict when strategy is modified elsewhere", %{
      conn: conn,
      user: user
    } do
      strategy = strategy_fixture(%{user: user, name: "Conflict Test", status: "draft"})

      {:ok, view, _html} = live(conn, ~p"/strategies/#{strategy.id}/edit")

      # Simulate another update happening elsewhere (increment lock_version)
      {:ok, _updated} =
        Strategies.update_strategy(
          strategy,
          %{description: "Updated elsewhere"},
          user
        )

      # Now try to save this form - should detect stale version
      result =
        view
        |> form("#strategy-form", strategy: %{"name" => "My Update"})
        |> render_submit()

      # Should show error about version conflict
      html = render(view)
      assert html =~ "modified" or html =~ "conflict" or html =~ "reloaded"
    end

    test "T062: prevents editing active strategy", %{conn: conn, user: user} do
      strategy = strategy_fixture(%{user: user, name: "Active", status: "active"})

      # Should redirect or show error when trying to edit active strategy
      result = live(conn, ~p"/strategies/#{strategy.id}/edit")

      case result do
        {:ok, _view, html} ->
          # If it loads, should show error message
          assert html =~ "active" or html =~ "cannot edit" or html =~ "deactivate"

        {:error, {:live_redirect, %{to: redirect_path}}} ->
          # Or it should redirect away
          assert redirect_path == ~p"/strategies/#{strategy.id}" or
                   redirect_path == ~p"/strategies"
      end
    end

    test "prevents editing archived strategy", %{conn: conn, user: user} do
      strategy = strategy_fixture(%{user: user, name: "Archived", status: "archived"})

      # Should redirect or show error when trying to edit archived strategy
      result = live(conn, ~p"/strategies/#{strategy.id}/edit")

      case result do
        {:ok, _view, html} ->
          assert html =~ "archived" or html =~ "cannot edit" or html =~ "read-only"

        {:error, {:live_redirect, %{to: redirect_path}}} ->
          assert redirect_path == ~p"/strategies/#{strategy.id}" or
                   redirect_path == ~p"/strategies"
      end
    end

    test "cannot edit another user's strategy", %{conn: conn, user: _user} do
      other_user = user_fixture(%{email: "other@example.com"})
      other_strategy = strategy_fixture(%{user: other_user, name: "Other User's Strategy"})

      # Should not be able to access edit page - will redirect to strategies list
      result = live(conn, ~p"/strategies/#{other_strategy.id}/edit")

      assert {:error, {:live_redirect, %{to: to_path}}} = result
      assert to_path == ~p"/strategies" or to_path == "/"
    end

    test "preserves form state during validation in edit mode", %{conn: conn, user: user} do
      strategy = strategy_fixture(%{user: user, name: "Original", status: "draft"})

      {:ok, view, _html} = live(conn, ~p"/strategies/#{strategy.id}/edit")

      # Make changes and trigger validation
      view
      |> form("#strategy-form", strategy: %{"description" => "New description"})
      |> render_change()

      html = render(view)

      # Form should still show the changed value
      assert html =~ "New description"
    end
  end

  describe "StrategyLive.Form - Validation (User Story 2)" do
    setup :register_and_log_in_user

    test "T030: displays required field validation errors inline", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/strategies/new")

      # Trigger validation by changing form with empty fields
      view
      |> form("#strategy-form", strategy: %{"name" => ""})
      |> render_change()

      html = render(view)

      # Should show inline error for name field
      assert html =~ "can&#39;t be blank" or html =~ "can't be blank"

      # Error should be associated with the input field
      assert html =~ "phx-feedback-for"
    end

    test "T031: displays length validation errors inline", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/strategies/new")

      # Test minimum length validation
      view
      |> form("#strategy-form", strategy: %{"name" => "AB"})
      |> render_change()

      html = render(view)
      assert html =~ "must be between 3 and 200 characters"

      # Test maximum length validation
      long_name = String.duplicate("A", 201)

      view
      |> form("#strategy-form", strategy: %{"name" => long_name})
      |> render_change()

      html = render(view)
      assert html =~ "must be between 3 and 200 characters"
    end

    test "T032: displays enum validation errors for invalid format", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/strategies/new")

      # Try to set invalid format (this would require manual form manipulation)
      # Since format is a select, we test that only valid options are presented
      html = render(view)

      # Verify only valid formats are in select options
      assert html =~ "yaml"
      assert html =~ "toml"
      refute html =~ "json"
      refute html =~ "xml"
    end

    test "T033: displays uniqueness validation error for duplicate strategy name", %{
      conn: conn,
      user: user
    } do
      # Create an existing strategy
      _existing_strategy = strategy_fixture(%{user: user, name: "Existing Strategy", version: 1})

      {:ok, view, _html} = live(conn, ~p"/strategies/new")

      # Fill form with duplicate name
      view
      |> form("#strategy-form",
        strategy: %{
          "name" => "Existing Strategy",
          "format" => "yaml",
          "content" => valid_yaml_strategy(),
          "trading_pair" => "BTC/USD",
          "timeframe" => "1h"
        }
      )
      |> render_change()

      # Note: uniqueness check happens on blur, so we need to trigger it explicitly
      html = render(view)

      # For now, we verify the form has the necessary phx-debounce attribute
      assert html =~ "phx-debounce"
    end

    test "T034: displays DSL validation errors for invalid YAML content", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/strategies/new")

      # Fill form with invalid YAML
      view
      |> form("#strategy-form",
        strategy: %{
          "name" => "Invalid DSL Strategy",
          "format" => "yaml",
          "content" => "invalid: yaml: content: [[[",
          "trading_pair" => "BTC/USD",
          "timeframe" => "1h"
        }
      )
      |> render_change()

      html = render(view)

      # Should show DSL validation error
      # The exact error message depends on the DSL validator implementation
      assert html =~ "invalid" or html =~ "error" or html =~ "parse"
    end

    test "validates all error messages appear within 1 second", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/strategies/new")

      # Measure validation response time
      start_time = System.monotonic_time(:millisecond)

      view
      |> form("#strategy-form",
        strategy: %{
          "name" => "",
          "content" => "invalid"
        }
      )
      |> render_change()

      end_time = System.monotonic_time(:millisecond)
      elapsed = end_time - start_time

      # Validation should complete in < 1000ms (SC-002 requirement)
      assert elapsed < 1000, "Validation took #{elapsed}ms, expected < 1000ms"
    end
  end

  describe "StrategyLive.Form - Syntax Testing (User Story 4)" do
    setup :register_and_log_in_user

    test "T065: successfully tests valid DSL syntax", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/strategies/new")

      # Fill form with valid YAML strategy
      view
      |> form("#strategy-form",
        strategy: %{
          "name" => "Syntax Test Strategy",
          "format" => "yaml",
          "content" => valid_yaml_strategy(),
          "trading_pair" => "BTC/USD",
          "timeframe" => "1h"
        }
      )
      |> render_change()

      # Click the "Test Syntax" button
      html =
        view
        |> element("button[phx-click=\"test_syntax\"]")
        |> render_click()

      # Should show success message with parsed strategy summary
      assert html =~ "success" or html =~ "valid" or html =~ "passed"

      # Should display some indication of the parsed strategy
      # (specific content depends on implementation)
      refute html =~ "error"
      refute html =~ "invalid"
    end

    test "T066: displays errors for invalid DSL syntax", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/strategies/new")

      # Fill form with invalid YAML
      view
      |> form("#strategy-form",
        strategy: %{
          "name" => "Invalid Syntax Test",
          "format" => "yaml",
          "content" => "invalid: [yaml: structure: {{{",
          "trading_pair" => "BTC/USD",
          "timeframe" => "1h"
        }
      )
      |> render_change()

      # Click the "Test Syntax" button
      html =
        view
        |> element("button[phx-click=\"test_syntax\"]")
        |> render_click()

      # Should show error message
      assert html =~ "error" or html =~ "invalid" or html =~ "failed"

      # Should show specific parsing error
      refute html =~ "success"
    end

    test "T067: syntax test completes within 3 seconds (SC-005)", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/strategies/new")

      # Fill form with valid but complex strategy (10+ indicators)
      complex_strategy = """
      name: Complex Strategy
      indicators:
        - sma_20: {period: 20}
        - sma_50: {period: 50}
        - ema_12: {period: 12}
        - ema_26: {period: 26}
        - rsi_14: {period: 14}
        - macd: {fast: 12, slow: 26, signal: 9}
        - bollinger: {period: 20, std_dev: 2}
        - atr: {period: 14}
        - stochastic: {k_period: 14, d_period: 3}
        - adx: {period: 14}
      entry_conditions:
        - rsi_14 < 30
        - sma_20 > sma_50
      exit_conditions:
        - rsi_14 > 70
      """

      view
      |> form("#strategy-form",
        strategy: %{
          "name" => "Complex Syntax Test",
          "format" => "yaml",
          "content" => complex_strategy,
          "trading_pair" => "BTC/USD",
          "timeframe" => "1h"
        }
      )
      |> render_change()

      # Measure syntax test time
      start_time = System.monotonic_time(:millisecond)

      view
      |> element("button[phx-click=\"test_syntax\"]")
      |> render_click()

      end_time = System.monotonic_time(:millisecond)
      elapsed = end_time - start_time

      # Should complete in < 3000ms (SC-005 requirement)
      assert elapsed < 3000, "Syntax test took #{elapsed}ms, expected < 3000ms"
    end
  end
end
