defmodule TradingStrategy.Strategies.DSL.Parser do
  @moduledoc """
  Main DSL parser module that delegates to format-specific parsers (YAML, TOML).

  Provides a unified interface for parsing strategy definitions from various formats.
  """

  alias TradingStrategy.Strategies.DSL.{YamlParser, TomlParser}

  @type format :: :yaml | :toml
  @type parse_result :: {:ok, map()} | {:error, String.t()}

  @doc """
  Parses a strategy definition from the given content and format.

  ## Parameters
    - `content`: String containing the strategy definition
    - `format`: Atom indicating the format (:yaml or :toml)

  ## Returns
    - `{:ok, strategy_map}` if parsing succeeds
    - `{:error, reason}` if parsing fails

  ## Examples

      iex> Parser.parse("name: Test\\ntrading_pair: BTC/USD", :yaml)
      {:ok, %{"name" => "Test", "trading_pair" => "BTC/USD"}}

      iex> Parser.parse("invalid yaml: [", :yaml)
      {:error, "Failed to parse YAML: ..."}
  """
  @spec parse(String.t(), format()) :: parse_result()
  def parse(content, format)

  def parse(content, :yaml) when is_binary(content) do
    YamlParser.parse(content)
  end

  def parse(content, :toml) when is_binary(content) do
    TomlParser.parse(content)
  end

  def parse(_content, format) do
    {:error, "Unsupported format: #{inspect(format)}. Supported formats are :yaml and :toml"}
  end

  @doc """
  Parses a strategy definition from a file.

  ## Parameters
    - `file_path`: Path to the strategy file
    - `format`: Atom indicating the format (:yaml or :toml). If nil, inferred from file extension

  ## Returns
    - `{:ok, strategy_map}` if parsing succeeds
    - `{:error, reason}` if file reading or parsing fails

  ## Examples

      iex> Parser.parse_file("strategies/rsi_strategy.yaml")
      {:ok, %{"name" => "RSI Strategy", ...}}

      iex> Parser.parse_file("strategies/rsi_strategy.toml", :toml)
      {:ok, %{"name" => "RSI Strategy", ...}}
  """
  @spec parse_file(Path.t(), format() | nil) :: parse_result()
  def parse_file(file_path, format \\ nil)

  def parse_file(file_path, nil) do
    format = infer_format_from_extension(file_path)
    parse_file(file_path, format)
  end

  def parse_file(file_path, format) when format in [:yaml, :toml] do
    case File.read(file_path) do
      {:ok, content} ->
        parse(content, format)

      {:error, reason} ->
        {:error, "Failed to read file #{file_path}: #{inspect(reason)}"}
    end
  end

  def parse_file(_file_path, format) do
    {:error, "Unsupported format: #{inspect(format)}"}
  end

  @doc """
  Validates that a strategy map contains all required fields.

  This is a lightweight validation - detailed validation happens in the Validator module.

  ## Parameters
    - `strategy`: Map containing parsed strategy data

  ## Returns
    - `{:ok, strategy}` if all required fields are present
    - `{:error, reason}` if required fields are missing
  """
  @spec validate_required_fields(map()) :: {:ok, map()} | {:error, String.t()}
  def validate_required_fields(strategy) when is_map(strategy) do
    required_fields = [
      "name",
      "trading_pair",
      "timeframe",
      "indicators",
      "entry_conditions",
      "exit_conditions",
      "stop_conditions",
      "position_sizing",
      "risk_parameters"
    ]

    missing_fields =
      Enum.filter(required_fields, fn field ->
        not Map.has_key?(strategy, field) or is_nil(strategy[field])
      end)

    case missing_fields do
      [] ->
        {:ok, strategy}

      fields ->
        {:error, "Missing required fields: #{Enum.join(fields, ", ")}"}
    end
  end

  def validate_required_fields(_) do
    {:error, "Strategy must be a map"}
  end

  # Private Functions

  defp infer_format_from_extension(file_path) do
    case Path.extname(file_path) do
      ".yaml" -> :yaml
      ".yml" -> :yaml
      ".toml" -> :toml
      ext -> raise "Cannot infer format from extension: #{ext}"
    end
  end
end
