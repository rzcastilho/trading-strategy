defmodule TradingStrategyWeb.StrategyLive.IndexTest do
  use TradingStrategyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import TradingStrategy.StrategiesFixtures
  import TradingStrategy.AccountsFixtures

  setup :register_and_log_in_user

  describe "Index" do
    test "mounts successfully and displays page title", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/strategies")

      assert html =~ "Strategies"
    end

    test "displays all user's strategies", %{conn: conn, user: user} do
      strategy1 = strategy_fixture(user: user, name: "Momentum Strategy")
      strategy2 = strategy_fixture(user: user, name: "Mean Reversion Strategy")

      {:ok, _view, html} = live(conn, ~p"/strategies")

      assert html =~ "Momentum Strategy"
      assert html =~ "Mean Reversion Strategy"
      assert html =~ strategy1.trading_pair
      assert html =~ strategy2.trading_pair
    end

    test "does not display other users' strategies", %{conn: conn, user: user} do
      _my_strategy = strategy_fixture(user: user, name: "My Strategy")

      other_user = user_fixture(email: "other@example.com")
      _other_strategy = strategy_fixture(user: other_user, name: "Other User Strategy")

      {:ok, _view, html} = live(conn, ~p"/strategies")

      assert html =~ "My Strategy"
      refute html =~ "Other User Strategy"
    end

    test "filters strategies by status - draft", %{conn: conn, user: user} do
      draft_strategy = strategy_fixture(user: user, name: "Draft Strategy", status: "draft")
      _active_strategy = strategy_fixture(user: user, name: "Active Strategy", status: "active")

      {:ok, _view, html} = live(conn, ~p"/strategies?status=draft")

      assert html =~ "Draft Strategy"
      refute html =~ "Active Strategy"
    end

    test "filters strategies by status - active", %{conn: conn, user: user} do
      _draft_strategy = strategy_fixture(user: user, name: "Draft Strategy", status: "draft")
      active_strategy = strategy_fixture(user: user, name: "Active Strategy", status: "active")

      {:ok, _view, html} = live(conn, ~p"/strategies?status=active")

      refute html =~ "Draft Strategy"
      assert html =~ "Active Strategy"
    end

    test "filters strategies by status - inactive", %{conn: conn, user: user} do
      _draft_strategy = strategy_fixture(user: user, name: "Draft Strategy", status: "draft")
      inactive_strategy = strategy_fixture(user: user, name: "Inactive Strategy", status: "inactive")

      {:ok, _view, html} = live(conn, ~p"/strategies?status=inactive")

      refute html =~ "Draft Strategy"
      assert html =~ "Inactive Strategy"
    end

    test "shows empty state when no strategies exist", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/strategies")

      assert html =~ "No strategies" # Text is "No strategies" not "No strategies found"
      assert html =~ "Get started by creating a new strategy"
    end

    test "provides link to create new strategy", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/strategies")

      assert html =~ "New Strategy"
      assert html =~ ~p"/strategies/new"
    end

    test "displays strategy status badges", %{conn: conn, user: user} do
      _draft = strategy_fixture(user: user, name: "Draft", status: "draft")
      _active = strategy_fixture(user: user, name: "Active", status: "active")
      _inactive = strategy_fixture(user: user, name: "Inactive", status: "inactive")

      {:ok, _view, html} = live(conn, ~p"/strategies")

      assert html =~ "draft"
      assert html =~ "active"
      assert html =~ "inactive"
    end

    test "strategy cards are clickable and navigate to detail page", %{conn: conn, user: user} do
      strategy = strategy_fixture(user: user, name: "Test Strategy")

      {:ok, view, _html} = live(conn, ~p"/strategies")

      # Find the link to the strategy detail page
      assert view |> element("a[href=\"#{~p"/strategies/#{strategy.id}"}\"]") |> has_element?()
    end

    test "receives real-time updates when strategy is created", %{conn: conn, user: user} do
      {:ok, view, html} = live(conn, ~p"/strategies")

      refute html =~ "New Strategy Name"

      # Simulate strategy creation
      _strategy = strategy_fixture(user: user, name: "New Strategy Name")

      # Give LiveView time to receive PubSub message
      :timer.sleep(100)

      html = render(view)
      assert html =~ "New Strategy Name"
    end

    test "receives real-time updates when strategy is updated", %{conn: conn, user: user} do
      strategy = strategy_fixture(user: user, name: "Original Name", status: "draft")

      {:ok, view, html} = live(conn, ~p"/strategies")
      assert html =~ "Original Name"
      assert html =~ "draft"

      # Update strategy
      {:ok, _updated} = TradingStrategy.Strategies.update_strategy(
        strategy,
        %{name: "Updated Name", status: "active"},
        user
      )

      # Give LiveView time to receive PubSub message
      :timer.sleep(100)

      html = render(view)
      assert html =~ "Updated Name"
      assert html =~ "active"
    end
  end
end
