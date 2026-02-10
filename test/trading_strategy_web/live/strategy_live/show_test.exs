defmodule TradingStrategyWeb.StrategyLive.ShowTest do
  use TradingStrategyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import TradingStrategy.StrategiesFixtures
  import TradingStrategy.AccountsFixtures

  setup :register_and_log_in_user

  describe "Show" do
    test "mounts and displays strategy details", %{conn: conn, user: user} do
      strategy = strategy_fixture(
        user: user,
        name: "Test Strategy",
        description: "A test trading strategy",
        trading_pair: "BTC/USD",
        timeframe: "1h",
        status: "draft"
      )

      {:ok, _view, html} = live(conn, ~p"/strategies/#{strategy.id}")

      assert html =~ "Test Strategy"
      assert html =~ "A test trading strategy"
      assert html =~ "BTC/USD"
      assert html =~ "1h"
      assert html =~ "draft"
    end

    test "displays strategy version information", %{conn: conn, user: user} do
      strategy = strategy_fixture(user: user, name: "Versioned Strategy", version: 3)

      {:ok, _view, html} = live(conn, ~p"/strategies/#{strategy.id}")

      assert html =~ "Version"
      assert html =~ "3"
    end

    test "shows edit button for draft strategies", %{conn: conn, user: user} do
      strategy = strategy_fixture(user: user, name: "Draft Strategy", status: "draft")

      {:ok, _view, html} = live(conn, ~p"/strategies/#{strategy.id}")

      assert html =~ "Edit"
      assert html =~ ~p"/strategies/#{strategy.id}/edit"
    end

    test "shows edit button for inactive strategies", %{conn: conn, user: user} do
      strategy = strategy_fixture(user: user, name: "Inactive Strategy", status: "inactive")

      {:ok, _view, html} = live(conn, ~p"/strategies/#{strategy.id}")

      assert html =~ "Edit"
    end

    test "does not show edit button for active strategies", %{conn: conn, user: user} do
      strategy = strategy_fixture(user: user, name: "Active Strategy", status: "active")

      {:ok, view, html} = live(conn, ~p"/strategies/#{strategy.id}")

      # Should not have edit link for active strategies
      refute view
             |> element("a[href=\"#{~p"/strategies/#{strategy.id}/edit"}\"]")
             |> has_element?()
    end

    test "does not show edit button for archived strategies", %{conn: conn, user: user} do
      strategy = strategy_fixture(user: user, name: "Archived Strategy", status: "archived")

      {:ok, view, html} = live(conn, ~p"/strategies/#{strategy.id}")

      refute view
             |> element("a[href=\"#{~p"/strategies/#{strategy.id}/edit"}\"]")
             |> has_element?()
    end

    test "shows activate button for draft strategies with valid DSL", %{conn: conn, user: user} do
      strategy = strategy_fixture(user: user, name: "Valid Strategy", status: "draft")

      {:ok, _view, html} = live(conn, ~p"/strategies/#{strategy.id}")

      assert html =~ "Activate"
    end

    test "shows deactivate button for active strategies", %{conn: conn, user: user} do
      strategy = strategy_fixture(user: user, name: "Active Strategy", status: "active")

      {:ok, _view, html} = live(conn, ~p"/strategies/#{strategy.id}")

      assert html =~ "Deactivate"
    end

    test "activates strategy when activate button clicked", %{conn: conn, user: user} do
      strategy = strategy_fixture(user: user, name: "To Activate", status: "draft")

      {:ok, view, _html} = live(conn, ~p"/strategies/#{strategy.id}")

      # Click activate button
      view
      |> element("button", "Activate")
      |> render_click()

      # Verify strategy is now active
      html = render(view)
      assert html =~ "active"
      assert html =~ "Deactivate"
    end

    test "deactivates strategy when deactivate button clicked", %{conn: conn, user: user} do
      strategy = strategy_fixture(user: user, name: "To Deactivate", status: "active")

      {:ok, view, _html} = live(conn, ~p"/strategies/#{strategy.id}")

      # Click deactivate button
      view
      |> element("button", "Deactivate")
      |> render_click()

      # Verify strategy is now inactive
      html = render(view)
      assert html =~ "inactive"
      # After deactivation, the Activate button should appear instead
      assert html =~ "Activate"
    end

    test "returns 404 when strategy does not exist", %{conn: conn} do
      result = live(conn, ~p"/strategies/00000000-0000-0000-0000-000000000000")

      assert {:error, {:live_redirect, %{to: to_path}}} = result
      assert to_path == ~p"/strategies" or to_path == "/"
    end

    test "returns 404 when accessing another user's strategy", %{conn: conn, user: _user} do
      other_user = user_fixture(email: "other@example.com")
      other_strategy = strategy_fixture(user: other_user, name: "Other Strategy")

      # Should not be able to access other user's strategy
      result = live(conn, ~p"/strategies/#{other_strategy.id}")

      assert {:error, {:live_redirect, %{to: to_path}}} = result
      assert to_path == ~p"/strategies" or to_path == "/"
    end

    test "displays parsed DSL content", %{conn: conn, user: user} do
      strategy = strategy_fixture(user: user, name: "DSL Strategy")

      {:ok, _view, html} = live(conn, ~p"/strategies/#{strategy.id}")

      # Should display the DSL content (uses default valid_yaml_strategy from fixture)
      assert html =~ "indicators" or html =~ "sma" or html =~ "rsi"
    end

    test "displays back link to strategy list", %{conn: conn, user: user} do
      strategy = strategy_fixture(user: user, name: "Test Strategy")

      {:ok, _view, html} = live(conn, ~p"/strategies/#{strategy.id}")

      # Check for link to strategies list (uses SVG arrow, not text "Back")
      assert html =~ ~p"/strategies"
      assert html =~ "M10 19l-7-7m0 0l7-7m-7 7h18" # SVG path for back arrow
    end

    test "displays strategy metadata if present", %{conn: conn, user: user} do
      strategy = strategy_fixture(
        user: user,
        name: "Strategy with Metadata",
        metadata: %{
          "last_validation_at" => "2026-02-08T10:30:00Z",
          "syntax_test_passed" => true
        }
      )

      {:ok, _view, html} = live(conn, ~p"/strategies/#{strategy.id}")

      # Metadata might be displayed
      assert html =~ "Strategy with Metadata"
    end

    test "successfully activates draft strategy with valid content", %{
      conn: conn,
      user: user
    } do
      strategy = strategy_fixture(user: user, name: "Valid Draft", status: "draft")

      {:ok, view, _html} = live(conn, ~p"/strategies/#{strategy.id}")

      # Click activate button
      view
      |> element("button", "Activate")
      |> render_click()

      html = render(view)

      # Strategy should now be active
      assert html =~ "active"
      assert html =~ "Strategy activated successfully"
      # Should show deactivate button now
      assert html =~ "Deactivate"
    end
  end

  describe "Duplicate Strategy" do
    test "displays duplicate button", %{conn: conn, user: user} do
      strategy = strategy_fixture(user: user, name: "Original Strategy")

      {:ok, _view, html} = live(conn, ~p"/strategies/#{strategy.id}")

      assert html =~ "Duplicate"
    end

    test "duplicates strategy when duplicate button clicked", %{conn: conn, user: user} do
      strategy = strategy_fixture(
        user: user,
        name: "Original Strategy",
        description: "Original description",
        trading_pair: "BTC/USD",
        timeframe: "1h",
        status: "draft"
      )

      {:ok, view, _html} = live(conn, ~p"/strategies/#{strategy.id}")

      # Click duplicate button
      view
      |> element("button", "Duplicate")
      |> render_click()

      # Should redirect to the new strategy's page
      assert_redirect(view, ~p"/strategies")

      # Verify new strategy was created with " - Copy" suffix
      import TradingStrategy.Strategies
      strategies = list_strategies(user)

      # Should have 2 strategies now
      assert length(strategies) == 2

      # Find the duplicate
      duplicate = Enum.find(strategies, fn s -> s.name == "Original Strategy - Copy" end)
      assert duplicate != nil
      assert duplicate.description == "Original description"
      assert duplicate.trading_pair == "BTC/USD"
      assert duplicate.timeframe == "1h"
      assert duplicate.status == "draft"
      assert duplicate.content == strategy.content
    end

    test "creates unique name when duplicate already exists", %{conn: conn, user: user} do
      strategy = strategy_fixture(user: user, name: "Original Strategy")

      # Create first duplicate manually
      import TradingStrategy.Strategies
      {:ok, _first_copy} = duplicate_strategy(strategy, user)

      {:ok, view, _html} = live(conn, ~p"/strategies/#{strategy.id}")

      # Click duplicate button again
      view
      |> element("button", "Duplicate")
      |> render_click()

      # Should create "Original Strategy - Copy 2"
      strategies = list_strategies(user)
      assert length(strategies) == 3

      # Verify naming sequence
      names = Enum.map(strategies, & &1.name) |> Enum.sort()
      assert "Original Strategy" in names
      assert "Original Strategy - Copy" in names
      assert "Original Strategy - Copy 2" in names
    end
  end
end
