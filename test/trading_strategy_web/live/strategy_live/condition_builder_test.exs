defmodule TradingStrategyWeb.StrategyLive.ConditionBuilderTest do
  use TradingStrategyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import TradingStrategy.AccountsFixtures

  describe "ConditionBuilder component - Integration tests" do
    setup %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)
      %{user: user, conn: conn}
    end

    test "entry condition builder - adds and removes conditions", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/strategies/new")

      # Verify entry condition builder renders
      assert has_element?(view, "#entry-condition-builder")
      assert render(view) =~ "Entry Conditions"
      assert render(view) =~ "No entry conditions configured yet"

      # Add entry condition
      view
      |> element("#entry-condition-builder button", "Add Condition")
      |> render_click()

      assert render(view) =~ "New Entry Condition"
      assert render(view) =~ "Left Side"
      assert render(view) =~ "Operator"
      assert render(view) =~ "Right Side"

      # Submit condition: RSI < 30
      view
      |> form("#entry-condition-builder-add-form",
        condition: %{left: "rsi", operator: "lt", right: "30"}
      )
      |> render_submit()

      # Verify condition was added
      html = render(view)
      assert html =~ "rsi"
      assert html =~ "30"
      assert html =~ "Total conditions: 1"

      # Remove condition
      view
      |> element("#entry-condition-builder button[phx-click='remove_condition'][phx-value-index='0']")
      |> render_click()

      # Verify condition was removed
      refute render(view) =~ "rsi"
      assert render(view) =~ "No entry conditions configured yet"
    end

    test "exit condition builder - adds conditions with operators", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/strategies/new")

      # Verify exit condition builder renders
      assert has_element?(view, "#exit-condition-builder")
      assert render(view) =~ "Exit Conditions"
      assert render(view) =~ "No exit conditions configured yet"

      # Add exit condition
      view
      |> element("#exit-condition-builder button", "Add Condition")
      |> render_click()

      assert render(view) =~ "New Exit Condition"

      # Submit condition: RSI > 70
      view
      |> form("#exit-condition-builder-add-form",
        condition: %{left: "rsi", operator: "gt", right: "70"}
      )
      |> render_submit()

      # Verify condition was added
      html = render(view)
      assert html =~ "rsi"
      assert html =~ "70"
      assert html =~ "Exit Logic Summary"
    end

    test "entry condition builder - adds multiple conditions with connectors", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/strategies/new")

      # Add first condition: RSI < 30
      view
      |> element("#entry-condition-builder button", "Add Condition")
      |> render_click()

      view
      |> form("#entry-condition-builder-add-form",
        condition: %{left: "rsi", operator: "lt", right: "30"}
      )
      |> render_submit()

      # Add second condition with AND connector: price > sma_20
      view
      |> element("#entry-condition-builder button", "Add Condition")
      |> render_click()

      view
      |> form("#entry-condition-builder-add-form",
        condition: %{left: "price", operator: "gt", right: "sma_20", connector: "and"}
      )
      |> render_submit()

      html = render(view)
      assert html =~ "rsi"
      assert html =~ "price"
      assert html =~ "AND"
      assert html =~ "Total conditions: 2"
      assert html =~ "Entry Logic Summary"
    end

    test "condition builder - cancels add form", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/strategies/new")

      # Open entry condition add form
      view
      |> element("#entry-condition-builder button", "Add Condition")
      |> render_click()

      assert render(view) =~ "New Entry Condition"

      # Cancel
      view
      |> element("#entry-condition-builder button", "Cancel")
      |> render_click()

      # Form should be hidden
      refute render(view) =~ "New Entry Condition"
      assert render(view) =~ "No entry conditions configured yet"
    end

    test "condition builder - supports various operators", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/strategies/new")

      # Open add form to see available operators
      view
      |> element("#entry-condition-builder button", "Add Condition")
      |> render_click()

      html = render(view)
      # Verify operators are available
      assert html =~ "Greater than"
      assert html =~ "Less than"
      assert html =~ "Equal to"
      assert html =~ "Crosses above"
      assert html =~ "Crosses below"
    end
  end
end
