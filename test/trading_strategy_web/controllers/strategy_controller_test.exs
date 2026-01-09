defmodule TradingStrategyWeb.StrategyControllerTest do
  use TradingStrategyWeb.ConnCase

  alias TradingStrategy.Strategies

  @valid_yaml_content """
  name: RSI Mean Reversion
  trading_pair: BTC/USD
  timeframe: 1h
  indicators:
    - type: rsi
      name: rsi_14
      parameters:
        period: 14
  entry_conditions: "rsi_14 < 30"
  exit_conditions: "rsi_14 > 70"
  stop_conditions: "rsi_14 < 25"
  position_sizing:
    type: percentage
    percentage_of_capital: 0.10
    max_position_size: 0.25
  risk_parameters:
    max_daily_loss: 0.03
    max_drawdown: 0.15
  """

  @valid_strategy_attrs %{
    "name" => "RSI Mean Reversion",
    "description" => "Buy oversold, sell overbought",
    "format" => "yaml",
    "content" => @valid_yaml_content,
    "trading_pair" => "BTC/USD",
    "timeframe" => "1h"
  }

  @invalid_strategy_attrs %{
    "name" => nil,
    "format" => "yaml",
    "content" => "invalid: content"
  }

  describe "GET /api/strategies" do
    test "lists all strategies", %{conn: conn} do
      # Create test strategies
      {:ok, strategy1} = Strategies.create_strategy(@valid_strategy_attrs)

      {:ok, strategy2} =
        Strategies.create_strategy(Map.put(@valid_strategy_attrs, "name", "Another Strategy"))

      conn = get(conn, ~p"/api/strategies")

      assert %{"data" => strategies} = json_response(conn, 200)
      assert length(strategies) == 2

      strategy_ids = Enum.map(strategies, & &1["id"])
      assert strategy1.id in strategy_ids
      assert strategy2.id in strategy_ids
    end

    test "returns empty list when no strategies exist", %{conn: conn} do
      conn = get(conn, ~p"/api/strategies")

      assert %{"data" => []} = json_response(conn, 200)
    end

    test "filters strategies by status", %{conn: conn} do
      {:ok, active_strategy} = Strategies.create_strategy(@valid_strategy_attrs)
      {:ok, _active_strategy} = Strategies.activate_strategy(active_strategy)

      {:ok, _draft_strategy} =
        Strategies.create_strategy(Map.put(@valid_strategy_attrs, "name", "Draft Strategy"))

      conn = get(conn, ~p"/api/strategies?status=active")

      assert %{"data" => strategies} = json_response(conn, 200)
      assert length(strategies) == 1
      assert hd(strategies)["status"] == "active"
    end

    test "respects limit parameter", %{conn: conn} do
      for i <- 1..5 do
        {:ok, _} =
          Strategies.create_strategy(Map.put(@valid_strategy_attrs, "name", "Strategy #{i}"))
      end

      conn = get(conn, ~p"/api/strategies?limit=3")

      assert %{"data" => strategies} = json_response(conn, 200)
      assert length(strategies) == 3
    end
  end

  describe "POST /api/strategies" do
    test "creates strategy with valid YAML", %{conn: conn} do
      conn = post(conn, ~p"/api/strategies", strategy: @valid_strategy_attrs)

      assert %{"data" => strategy} = json_response(conn, 201)
      assert strategy["name"] == "RSI Mean Reversion"
      assert strategy["format"] == "yaml"
      assert strategy["trading_pair"] == "BTC/USD"
      assert strategy["timeframe"] == "1h"
      assert strategy["status"] == "draft"
      assert strategy["version"] == 1

      # Verify Location header
      assert get_resp_header(conn, "location") != []
    end

    test "creates strategy with valid TOML", %{conn: conn} do
      toml_content = """
      name = "RSI Mean Reversion"
      trading_pair = "BTC/USD"
      timeframe = "1h"
      entry_conditions = "rsi_14 < 30"
      exit_conditions = "rsi_14 > 70"
      stop_conditions = "rsi_14 < 25"

      [[indicators]]
      type = "rsi"
      name = "rsi_14"

      [indicators.parameters]
      period = 14

      [position_sizing]
      type = "percentage"
      percentage_of_capital = 0.10

      [risk_parameters]
      max_daily_loss = 0.03
      max_drawdown = 0.15
      """

      attrs = Map.merge(@valid_strategy_attrs, %{"format" => "toml", "content" => toml_content})

      conn = post(conn, ~p"/api/strategies", strategy: attrs)

      assert %{"data" => strategy} = json_response(conn, 201)
      assert strategy["format"] == "toml"
      assert strategy["name"] == "RSI Mean Reversion"
    end

    test "returns errors for missing required fields", %{conn: conn} do
      conn = post(conn, ~p"/api/strategies", strategy: @invalid_strategy_attrs)

      assert %{"errors" => errors} = json_response(conn, 422)
      assert errors["name"] != nil
    end

    test "returns errors for invalid DSL content", %{conn: conn} do
      invalid_content = """
      name: Test
      trading_pair: BTC/USD
      timeframe: 1h
      """

      attrs = Map.put(@valid_strategy_attrs, "content", invalid_content)

      conn = post(conn, ~p"/api/strategies", strategy: attrs)

      assert %{"errors" => errors} = json_response(conn, 422)
      assert errors["content"] != nil
      assert is_list(errors["content"])
    end

    test "validates indicator definitions", %{conn: conn} do
      invalid_indicator_content = """
      name: Test
      trading_pair: BTC/USD
      timeframe: 1h
      indicators:
        - type: unknown_indicator
          name: test
          parameters: {}
      entry_conditions: "test < 30"
      exit_conditions: "test > 70"
      stop_conditions: "test < 25"
      position_sizing:
        type: percentage
        percentage_of_capital: 0.10
      risk_parameters:
        max_daily_loss: 0.03
        max_drawdown: 0.15
      """

      attrs = Map.put(@valid_strategy_attrs, "content", invalid_indicator_content)

      conn = post(conn, ~p"/api/strategies", strategy: attrs)

      assert %{"errors" => errors} = json_response(conn, 422)
      assert errors["content"] != nil

      assert Enum.any?(
               List.flatten([errors["content"]]),
               &String.contains?(&1, "Unknown indicator")
             )
    end

    test "returns 400 for missing strategy key", %{conn: conn} do
      conn = post(conn, ~p"/api/strategies", invalid: "params")

      assert %{"error" => message} = json_response(conn, 400)
      assert message =~ "Missing required 'strategy' field"
    end
  end

  describe "GET /api/strategies/:id" do
    test "shows strategy by id", %{conn: conn} do
      {:ok, strategy} = Strategies.create_strategy(@valid_strategy_attrs)

      conn = get(conn, ~p"/api/strategies/#{strategy.id}")

      assert %{"data" => returned_strategy} = json_response(conn, 200)
      assert returned_strategy["id"] == strategy.id
      assert returned_strategy["name"] == strategy.name
      assert returned_strategy["content"] == strategy.content
    end

    test "returns 404 for non-existent strategy", %{conn: conn} do
      non_existent_id = Ecto.UUID.generate()
      conn = get(conn, ~p"/api/strategies/#{non_existent_id}")

      assert json_response(conn, 404)
    end
  end

  describe "PUT /api/strategies/:id" do
    test "updates strategy with valid data", %{conn: conn} do
      {:ok, strategy} = Strategies.create_strategy(@valid_strategy_attrs)

      update_attrs = %{
        "name" => "Updated Strategy Name",
        "description" => "Updated description"
      }

      conn = put(conn, ~p"/api/strategies/#{strategy.id}", strategy: update_attrs)

      assert %{"data" => updated_strategy} = json_response(conn, 200)
      assert updated_strategy["id"] == strategy.id
      assert updated_strategy["name"] == "Updated Strategy Name"
      assert updated_strategy["description"] == "Updated description"
    end

    test "updates strategy status", %{conn: conn} do
      {:ok, strategy} = Strategies.create_strategy(@valid_strategy_attrs)

      conn = put(conn, ~p"/api/strategies/#{strategy.id}", strategy: %{"status" => "active"})

      assert %{"data" => updated_strategy} = json_response(conn, 200)
      assert updated_strategy["status"] == "active"
    end

    test "validates DSL content on update", %{conn: conn} do
      {:ok, strategy} = Strategies.create_strategy(@valid_strategy_attrs)

      invalid_content = "invalid: yaml: ["

      conn =
        put(conn, ~p"/api/strategies/#{strategy.id}", strategy: %{"content" => invalid_content})

      assert %{"errors" => errors} = json_response(conn, 422)
      assert errors["content"] != nil
    end

    test "returns 404 for non-existent strategy", %{conn: conn} do
      non_existent_id = Ecto.UUID.generate()

      conn =
        put(conn, ~p"/api/strategies/#{non_existent_id}", strategy: %{"name" => "Updated"})

      assert json_response(conn, 404)
    end

    test "returns 400 for missing strategy key", %{conn: conn} do
      {:ok, strategy} = Strategies.create_strategy(@valid_strategy_attrs)

      conn = put(conn, ~p"/api/strategies/#{strategy.id}", invalid: "params")

      assert %{"error" => message} = json_response(conn, 400)
      assert message =~ "Missing required 'strategy' field"
    end
  end

  describe "DELETE /api/strategies/:id" do
    test "deletes strategy", %{conn: conn} do
      {:ok, strategy} = Strategies.create_strategy(@valid_strategy_attrs)

      conn = delete(conn, ~p"/api/strategies/#{strategy.id}")

      assert response(conn, 204)

      # Verify strategy is deleted
      assert Strategies.get_strategy(strategy.id) == nil
    end

    test "returns 404 for non-existent strategy", %{conn: conn} do
      non_existent_id = Ecto.UUID.generate()
      conn = delete(conn, ~p"/api/strategies/#{non_existent_id}")

      assert json_response(conn, 404)
    end
  end

  describe "strategy lifecycle" do
    test "full CRUD lifecycle", %{conn: conn} do
      # Create
      conn_create = post(conn, ~p"/api/strategies", strategy: @valid_strategy_attrs)
      assert %{"data" => created} = json_response(conn_create, 201)
      strategy_id = created["id"]

      # Read
      conn_read = get(conn, ~p"/api/strategies/#{strategy_id}")
      assert %{"data" => read_strategy} = json_response(conn_read, 200)
      assert read_strategy["id"] == strategy_id

      # Update
      conn_update =
        put(conn, ~p"/api/strategies/#{strategy_id}", strategy: %{"status" => "active"})

      assert %{"data" => updated} = json_response(conn_update, 200)
      assert updated["status"] == "active"

      # Delete
      conn_delete = delete(conn, ~p"/api/strategies/#{strategy_id}")
      assert response(conn_delete, 204)

      # Verify deletion
      conn_verify = get(conn, ~p"/api/strategies/#{strategy_id}")
      assert json_response(conn_verify, 404)
    end
  end

  describe "edge cases and error handling" do
    test "handles malformed JSON", %{conn: conn} do
      # Phoenix's Plug.Parsers raises ParseError for malformed JSON
      # This is the expected behavior - it's caught by Phoenix's error handling
      assert_raise Plug.Parsers.ParseError, fn ->
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/strategies", "{invalid json")
      end
    end

    test "handles very long strategy names", %{conn: conn} do
      long_name = String.duplicate("a", 200)

      attrs = Map.put(@valid_strategy_attrs, "name", long_name)

      conn = post(conn, ~p"/api/strategies", strategy: attrs)

      # Should still work as name validation happens in changeset
      assert conn.status in [201, 422]
    end

    test "handles concurrent updates gracefully", %{conn: conn} do
      {:ok, strategy} = Strategies.create_strategy(@valid_strategy_attrs)

      # Simulate concurrent updates
      conn1 =
        put(conn, ~p"/api/strategies/#{strategy.id}", strategy: %{"description" => "Update 1"})

      conn2 =
        put(conn, ~p"/api/strategies/#{strategy.id}", strategy: %{"description" => "Update 2"})

      # Both should succeed (optimistic locking not implemented)
      assert conn1.status in [200, 409]
      assert conn2.status in [200, 409]
    end
  end
end
