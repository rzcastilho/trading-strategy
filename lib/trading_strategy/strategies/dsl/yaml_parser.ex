defmodule TradingStrategy.Strategies.DSL.YamlParser do
  @moduledoc """
  YAML parser for strategy definitions using yaml_elixir library.

  Provides safe parsing with atom key conversion and error handling.
  """

  require Logger

  @doc """
  Parses YAML content into a strategy map.

  ## Parameters
    - `content`: String containing YAML strategy definition

  ## Returns
    - `{:ok, strategy_map}` if parsing succeeds
    - `{:error, reason}` if parsing fails

  ## Security Notes
    - Does NOT use `atoms: true` to prevent atom exhaustion attacks
    - All keys are returned as strings
    - User-supplied YAML is never converted to atoms automatically

  ## Examples

      iex> yaml = \"\"\"
      ...> name: RSI Mean Reversion
      ...> trading_pair: BTC/USD
      ...> timeframe: 1h
      ...> \"\"\"
      iex> YamlParser.parse(yaml)
      {:ok, %{"name" => "RSI Mean Reversion", "trading_pair" => "BTC/USD", "timeframe" => "1h"}}
  """
  @spec parse(String.t()) :: {:ok, map()} | {:error, String.t()}
  def parse(content) when is_binary(content) do
    case YamlElixir.read_from_string(content) do
      {:ok, parsed_data} when is_map(parsed_data) and map_size(parsed_data) > 0 ->
        {:ok, normalize_keys(parsed_data)}

      {:ok, parsed_data} when is_map(parsed_data) and map_size(parsed_data) == 0 ->
        {:error, "YAML content is empty"}

      {:ok, parsed_data} ->
        {:error, "Expected YAML to parse as a map, got #{inspect(parsed_data)}"}

      {:error, %YamlElixir.ParsingError{} = error} ->
        {:error, "Failed to parse YAML: #{Exception.message(error)}"}

      {:error, reason} ->
        {:error, "Failed to parse YAML: #{inspect(reason)}"}
    end
  rescue
    error ->
      Logger.error(
        "Unexpected error parsing YAML: #{Exception.format(:error, error, __STACKTRACE__)}"
      )

      {:error, "Unexpected error parsing YAML: #{Exception.message(error)}"}
  end

  def parse(_content) do
    {:error, "YAML content must be a string"}
  end

  @doc """
  Parses YAML from a file.

  ## Parameters
    - `file_path`: Path to YAML file

  ## Returns
    - `{:ok, strategy_map}` if parsing succeeds
    - `{:error, reason}` if file reading or parsing fails
  """
  @spec parse_file(Path.t()) :: {:ok, map()} | {:error, String.t()}
  def parse_file(file_path) do
    case File.read(file_path) do
      {:ok, content} ->
        parse(content)

      {:error, reason} ->
        {:error, "Failed to read YAML file #{file_path}: #{inspect(reason)}"}
    end
  end

  # Private Functions

  # Recursively normalizes all keys in a nested structure to strings
  defp normalize_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} ->
      {normalize_key(key), normalize_keys(value)}
    end)
  end

  defp normalize_keys(list) when is_list(list) do
    Enum.map(list, &normalize_keys/1)
  end

  defp normalize_keys(value), do: value

  # Converts keys to strings
  defp normalize_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_key(key) when is_binary(key), do: key
  defp normalize_key(key), do: to_string(key)
end
