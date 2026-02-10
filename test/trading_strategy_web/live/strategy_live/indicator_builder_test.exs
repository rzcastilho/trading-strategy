defmodule TradingStrategyWeb.StrategyLive.IndicatorBuilderTest do
  use TradingStrategyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import TradingStrategy.AccountsFixtures

  alias TradingStrategyWeb.StrategyLive.IndicatorBuilder

  describe "IndicatorBuilder component" do
    setup %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)
      %{user: user, conn: conn}
    end

    test "component integration test - adds and removes indicators", %{conn: conn} do
      # Navigate to the strategy form page which uses the component
      {:ok, view, _html} = live(conn, ~p"/strategies/new")

      # Verify component renders empty state
      assert has_element?(view, "#indicator-builder")
      assert render(view) =~ "No indicators configured yet"

      # Clicking Add Indicator button should show the form
      view
      |> element("#indicator-builder button", "Add Indicator")
      |> render_click()

      assert render(view) =~ "Select Indicator Type"

      # Select RSI indicator type
      view
      |> element("#indicator-builder select")
      |> render_change(%{"value" => "rsi"})

      assert render(view) =~ "Configure Relative Strength Index"
      assert render(view) =~ "Period"

      # Submit the indicator form
      view
      |> form("#indicator-builder-add-form", indicator: %{type: "rsi", period: "14"})
      |> render_submit()

      # Verify indicator was added
      assert render(view) =~ "Relative Strength Index (RSI)"
      assert render(view) =~ "period: 14"
      assert render(view) =~ "Total indicators: 1"

      # Remove the indicator
      view
      |> element("#indicator-builder button[phx-click='remove_indicator'][phx-value-index='0']")
      |> render_click()

      # Verify indicator was removed
      refute render(view) =~ "Relative Strength Index (RSI)"
      assert render(view) =~ "No indicators configured yet"
    end

    test "component adds multiple indicators", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/strategies/new")

      # Add RSI indicator
      view
      |> element("#indicator-builder button", "Add Indicator")
      |> render_click()

      view
      |> element("#indicator-builder select")
      |> render_change(%{"value" => "rsi"})

      view
      |> form("#indicator-builder-add-form", indicator: %{type: "rsi", period: "14"})
      |> render_submit()

      # Add SMA indicator
      view
      |> element("#indicator-builder button", "Add Indicator")
      |> render_click()

      view
      |> element("#indicator-builder select")
      |> render_change(%{"value" => "sma"})

      view
      |> form("#indicator-builder-add-form", indicator: %{type: "sma", period: "20"})
      |> render_submit()

      # Verify both indicators are present
      assert render(view) =~ "Relative Strength Index (RSI)"
      assert render(view) =~ "Simple Moving Average (SMA)"
      assert render(view) =~ "Total indicators: 2"
    end

    test "component cancels add form", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/strategies/new")

      # Open add form
      view
      |> element("#indicator-builder button", "Add Indicator")
      |> render_click()

      assert render(view) =~ "Select Indicator Type"

      # Cancel
      view
      |> element("#indicator-builder button", "Cancel")
      |> render_click()

      # Form should be hidden
      refute render(view) =~ "Select Indicator Type"
      assert render(view) =~ "No indicators configured yet"
    end

    test "component handles MACD with multiple parameters", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/strategies/new")

      # Add MACD indicator
      view
      |> element("#indicator-builder button", "Add Indicator")
      |> render_click()

      view
      |> element("#indicator-builder select")
      |> render_change(%{"value" => "macd"})

      view
      |> form("#indicator-builder-add-form",
        indicator: %{
          type: "macd",
          fast_period: "12",
          slow_period: "26",
          signal_period: "9"
        }
      )
      |> render_submit()

      html = render(view)
      assert html =~ "MACD"
      assert html =~ "fast_period: 12"
      assert html =~ "slow_period: 26"
      assert html =~ "signal_period: 9"
    end
  end
end
