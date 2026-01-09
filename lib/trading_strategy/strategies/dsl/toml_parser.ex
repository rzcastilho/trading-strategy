defmodule TradingStrategy.Strategies.DSL.TomlParser do
  @moduledoc """
  TOML parser for strategy definitions using the toml library.

  TOML provides explicit typing and no indentation sensitivity, making it
  a good alternative to YAML for simpler configurations.
  """

  require Logger

  @doc """
  Parses TOML content into a strategy map.

  ## Parameters
    - `content`: String containing TOML strategy definition

  ## Returns
    - `{:ok, strategy_map}` if parsing succeeds
    - `{:error, reason}` if parsing fails

  ## Examples

      iex> toml = \"\"\"
      ...> name = "RSI Mean Reversion"
      ...> trading_pair = "BTC/USD"
      ...> timeframe = "1h"
      ...> \"\"\"
      iex> TomlParser.parse(toml)
      {:ok, %{"name" => "RSI Mean Reversion", "trading_pair" => "BTC/USD", "timeframe" => "1h"}}
  """
  @spec parse(String.t()) :: {:ok, map()} | {:error, String.t()}
  def parse(content) when is_binary(content) do
    case Toml.decode(content) do
      {:ok, parsed_data} when is_map(parsed_data) ->
        {:ok, normalize_data(parsed_data)}

      {:error, reason} ->
        {:error, "Failed to parse TOML: #{format_toml_error(reason)}"}
    end
  rescue
    error ->
      Logger.error(
        "Unexpected error parsing TOML: #{Exception.format(:error, error, __STACKTRACE__)}"
      )

      {:error, "Unexpected error parsing TOML: #{Exception.message(error)}"}
  end

  def parse(_content) do
    {:error, "TOML content must be a string"}
  end

  @doc """
  Parses TOML from a file.

  ## Parameters
    - `file_path`: Path to TOML file

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
        {:error, "Failed to read TOML file #{file_path}: #{inspect(reason)}"}
    end
  end

  # Private Functions

  # Recursively normalizes TOML data structure:
  # - Converts atom keys to strings
  # - Normalizes nested maps and lists
  # - Preserves TOML's native datetime types
  defp normalize_data(map) when is_map(map) do
    Map.new(map, fn {key, value} ->
      {normalize_key(key), normalize_data(value)}
    end)
  end

  defp normalize_data(list) when is_list(list) do
    Enum.map(list, &normalize_data/1)
  end

  # Preserve native types (integers, floats, booleans, datetimes)
  defp normalize_data(value), do: value

  # Converts keys to strings
  defp normalize_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_key(key) when is_binary(key), do: key
  defp normalize_key(key), do: to_string(key)

  # Formats TOML error messages for better readability
  defp format_toml_error({:invalid, message}) when is_binary(message) do
    message
  end

  defp format_toml_error(error) when is_tuple(error) do
    case error do
      {:invalid, line, message} ->
        "Line #{line}: #{message}"

      other ->
        inspect(other)
    end
  end

  defp format_toml_error(error) do
    inspect(error)
  end
end
