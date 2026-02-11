defmodule TradingStrategy.StrategyEditor.DslParserSimple do
  @moduledoc """
  Simplified string-based DSL parser for Phase 4.

  This parser uses regex and string matching to extract strategy information
  from Elixir DSL text. It's designed to be pragmatic and get Phase 4 working
  quickly while maintaining the ability to upgrade to AST-based parsing later.

  ## Features
  - Extracts strategy name, trading pair, timeframe
  - Parses indicators with parameters
  - Extracts entry/exit/stop conditions
  - Preserves comments
  - Handles position sizing and risk parameters
  """

  alias TradingStrategy.StrategyEditor.BuilderState

  @doc """
  Parse DSL text into a strategy map with comments.

  Returns `{:ok, strategy_map, comments}` or `{:error, reason}`.
  """
  def parse(dsl_text) when is_binary(dsl_text) do
    try do
      strategy_map = %{
        name: extract_strategy_name(dsl_text),
        trading_pair: extract_module_attribute(dsl_text, "@trading_pair"),
        timeframe: extract_module_attribute(dsl_text, "@timeframe"),
        description: extract_module_attribute(dsl_text, "@description"),
        indicators: extract_indicators(dsl_text),
        entry_conditions: extract_conditions(dsl_text, "entry_conditions"),
        exit_conditions: extract_conditions(dsl_text, "exit_conditions"),
        stop_conditions: extract_conditions(dsl_text, "stop_conditions"),
        position_sizing: extract_position_sizing(dsl_text),
        risk_parameters: extract_risk_parameters(dsl_text)
      }

      comments = extract_comments(dsl_text)

      {:ok, strategy_map, comments}
    catch
      :error, reason ->
        {:error, "Parse error: #{inspect(reason)}"}
    end
  end

  # Private Functions

  defp extract_strategy_name(dsl_text) do
    case Regex.run(~r/defstrategy\s+([A-Z][A-Za-z0-9]*)\s+do/, dsl_text) do
      [_, name] ->
        convert_module_name_to_readable(name)

      _ ->
        nil
    end
  end

  defp convert_module_name_to_readable(module_name) do
    module_name
    |> String.replace(~r/([A-Z][a-z]+|[A-Z]+(?=[A-Z][a-z]|\b))/, " \\1")
    |> String.trim()
  end

  defp extract_module_attribute(dsl_text, attribute_name) do
    pattern = ~r/#{Regex.escape(attribute_name)}\s+"([^"]+)"/

    case Regex.run(pattern, dsl_text) do
      [_, value] -> value
      _ -> nil
    end
  end

  defp extract_indicators(dsl_text) do
    ~r/indicator\s+:([a-z0-9_]+),\s*:([a-z0-9_]+)(?:,\s*(.+?))?(?:\n|$)/
    |> Regex.scan(dsl_text)
    |> Enum.map(fn
      [_, name, type, params_str] ->
        %BuilderState.Indicator{
          type: type,
          name: name,
          parameters: parse_parameters(params_str),
          _id: "ind-#{System.unique_integer([:positive])}"
        }

      [_, name, type] ->
        %BuilderState.Indicator{
          type: type,
          name: name,
          parameters: %{},
          _id: "ind-#{System.unique_integer([:positive])}"
        }
    end)
  end

  defp parse_parameters(""), do: %{}
  defp parse_parameters(nil), do: %{}

  defp parse_parameters(params_str) do
    params_str
    |> String.trim()
    |> String.split(~r/,\s*/)
    |> Enum.reduce(%{}, fn param, acc ->
      case String.split(param, ~r/:\s*/, parts: 2) do
        [key, value] ->
          Map.put(acc, String.trim(key), parse_value(String.trim(value)))

        _ ->
          acc
      end
    end)
  end

  defp parse_value(value) do
    cond do
      Regex.match?(~r/^\d+$/, value) ->
        String.to_integer(value)

      Regex.match?(~r/^\d+\.\d+$/, value) ->
        String.to_float(value)

      String.starts_with?(value, "\"") and String.ends_with?(value, "\"") ->
        String.slice(value, 1..-2)

      true ->
        value
    end
  end

  defp extract_conditions(dsl_text, condition_type) do
    pattern = ~r/#{condition_type}\s+do\s*\n(.*?)\n\s*end/s

    case Regex.run(pattern, dsl_text) do
      [_, body] ->
        body
        |> String.trim()
        |> String.replace(~r/\s+/, " ")

      _ ->
        nil
    end
  end

  defp extract_position_sizing(dsl_text) do
    case Regex.run(~r/position_sizing\s+do\s*\n(.*?)\n\s*end/s, dsl_text) do
      [_, body] ->
        parse_position_sizing_body(body)

      _ ->
        nil
    end
  end

  defp parse_position_sizing_body(body) do
    cond do
      String.contains?(body, "percentage_of_capital") ->
        case Regex.run(~r/percentage_of_capital\s+([\d.]+)/, body) do
          [_, value] ->
            %BuilderState.PositionSizing{
              type: "percentage",
              percentage_of_capital: String.to_float(value),
              fixed_amount: nil,
              _id: "pos-#{System.unique_integer([:positive])}"
            }

          _ ->
            nil
        end

      String.contains?(body, "fixed_amount") ->
        case Regex.run(~r/fixed_amount\s+([\d.]+)/, body) do
          [_, value] ->
            %BuilderState.PositionSizing{
              type: "fixed",
              percentage_of_capital: nil,
              fixed_amount: String.to_float(value),
              _id: "pos-#{System.unique_integer([:positive])}"
            }

          _ ->
            nil
        end

      true ->
        nil
    end
  end

  defp extract_risk_parameters(dsl_text) do
    case Regex.run(~r/risk_parameters\s+do\s*\n(.*?)\n\s*end/s, dsl_text) do
      [_, body] ->
        parse_risk_parameters_body(body)

      _ ->
        nil
    end
  end

  defp parse_risk_parameters_body(body) do
    max_daily_loss =
      case Regex.run(~r/max_daily_loss\s+([\d.]+)/, body) do
        [_, value] -> String.to_float(value)
        _ -> nil
      end

    max_drawdown =
      case Regex.run(~r/max_drawdown\s+([\d.]+)/, body) do
        [_, value] -> String.to_float(value)
        _ -> nil
      end

    max_position_size =
      case Regex.run(~r/max_position_size\s+([\d.]+)/, body) do
        [_, value] -> String.to_float(value)
        _ -> nil
      end

    if max_daily_loss || max_drawdown || max_position_size do
      %BuilderState.RiskParameters{
        max_daily_loss: max_daily_loss,
        max_drawdown: max_drawdown,
        max_position_size: max_position_size,
        _id: "risk-#{System.unique_integer([:positive])}"
      }
    else
      nil
    end
  end

  defp extract_comments(dsl_text) do
    dsl_text
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.filter(fn {line, _idx} ->
      String.trim(line) |> String.starts_with?("#")
    end)
    |> Enum.map(fn {line, line_number} ->
      column = String.length(line) - String.length(String.trim_leading(line))

      %BuilderState.Comment{
        line: line_number,
        column: column,
        text: String.trim(line),
        preserved_from_dsl: true
      }
    end)
  end
end
