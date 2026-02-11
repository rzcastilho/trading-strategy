defmodule TradingStrategy.StrategyEditor.ValidationResult do
  @moduledoc """
  Represents the outcome of DSL syntax and semantic validation.

  Validation results include:
  - Syntax errors (invalid DSL structure)
  - Semantic errors (invalid indicator types, condition logic)
  - Warnings (unsupported features, performance issues)
  - Unsupported DSL features list
  """

  defstruct [
    :valid,
    :errors,
    :warnings,
    :unsupported,
    :validated_at
  ]

  @type t :: %__MODULE__{
          valid: boolean(),
          errors: [ValidationError.t()],
          warnings: [ValidationWarning.t()],
          unsupported: [String.t()],
          validated_at: DateTime.t()
        }

  defmodule ValidationError do
    @moduledoc """
    Represents a validation error with location and context.
    """

    defstruct [:type, :message, :line, :column, :path, :severity]

    @type t :: %__MODULE__{
            type: :syntax | :semantic | :parser_crash,
            message: String.t(),
            line: integer() | nil,
            column: integer() | nil,
            path: [String.t()] | nil,
            severity: :error | :warning
          }

    @doc """
    Create a new validation error.

    ## Examples

        iex> ValidationError.new(:syntax, "Missing bracket", line: 10)
        %ValidationError{type: :syntax, message: "Missing bracket", line: 10, ...}
    """
    def new(type, message, opts \\ []) do
      %__MODULE__{
        type: type,
        message: message,
        line: Keyword.get(opts, :line),
        column: Keyword.get(opts, :column),
        path: Keyword.get(opts, :path),
        severity: Keyword.get(opts, :severity, :error)
      }
    end
  end

  defmodule ValidationWarning do
    @moduledoc """
    Represents a validation warning with suggestion.
    """

    defstruct [:type, :message, :suggestion]

    @type t :: %__MODULE__{
            type: :unsupported_feature | :incomplete_data | :performance,
            message: String.t(),
            suggestion: String.t() | nil
          }

    @doc """
    Create a new validation warning.

    ## Examples

        iex> ValidationWarning.new(:unsupported_feature, "Custom functions not supported", "Edit in DSL mode")
        %ValidationWarning{type: :unsupported_feature, message: "...", suggestion: "..."}
    """
    def new(type, message, suggestion \\ nil) do
      %__MODULE__{
        type: type,
        message: message,
        suggestion: suggestion
      }
    end
  end

  @doc """
  Create a successful validation result (no errors).

  ## Examples

      iex> ValidationResult.success()
      %ValidationResult{valid: true, errors: [], warnings: [], ...}
  """
  def success do
    %__MODULE__{
      valid: true,
      errors: [],
      warnings: [],
      unsupported: [],
      validated_at: DateTime.utc_now()
    }
  end

  @doc """
  Create a failed validation result with errors.

  ## Examples

      iex> ValidationResult.failure([
      ...>   %ValidationError{
      ...>     type: :syntax,
      ...>     message: "Unbalanced parentheses",
      ...>     line: 12,
      ...>     column: 45
      ...>   }
      ...> ])
      %ValidationResult{valid: false, errors: [...], ...}
  """
  def failure(errors) when is_list(errors) do
    %__MODULE__{
      valid: false,
      errors: errors,
      warnings: [],
      unsupported: [],
      validated_at: DateTime.utc_now()
    }
  end

  @doc """
  Create a validation result with warnings (valid but with caveats).

  ## Examples

      iex> ValidationResult.with_warnings(warnings, unsupported_features)
      %ValidationResult{valid: true, warnings: [...], unsupported: [...]}
  """
  def with_warnings(warnings, unsupported \\ []) when is_list(warnings) do
    %__MODULE__{
      valid: true,
      errors: [],
      warnings: warnings,
      unsupported: unsupported,
      validated_at: DateTime.utc_now()
    }
  end

  @doc """
  Check if validation passed (no errors).
  """
  def valid?(%__MODULE__{valid: valid}), do: valid

  @doc """
  Check if validation failed (has errors).
  """
  def invalid?(%__MODULE__{valid: valid}), do: not valid

  @doc """
  Check if validation has warnings.
  """
  def has_warnings?(%__MODULE__{warnings: warnings}), do: warnings != []

  @doc """
  Check if validation has unsupported features.
  """
  def has_unsupported?(%__MODULE__{unsupported: unsupported}), do: unsupported != []

  @doc """
  Get count of errors.
  """
  def error_count(%__MODULE__{errors: errors}), do: length(errors)

  @doc """
  Get count of warnings.
  """
  def warning_count(%__MODULE__{warnings: warnings}), do: length(warnings)

  @doc """
  Convert validation result to map for JSON serialization.
  """
  def to_map(%__MODULE__{} = result) do
    %{
      valid: result.valid,
      errors: Enum.map(result.errors, &error_to_map/1),
      warnings: Enum.map(result.warnings, &warning_to_map/1),
      unsupported: result.unsupported,
      validated_at: DateTime.to_iso8601(result.validated_at)
    }
  end

  # Private Functions

  defp error_to_map(%ValidationError{} = error) do
    %{
      type: error.type,
      message: error.message,
      line: error.line,
      column: error.column,
      path: error.path,
      severity: error.severity
    }
  end

  defp warning_to_map(%ValidationWarning{} = warning) do
    %{
      type: warning.type,
      message: warning.message,
      suggestion: warning.suggestion
    }
  end
end
