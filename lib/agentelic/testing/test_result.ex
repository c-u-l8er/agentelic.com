defmodule Agentelic.Testing.TestResult do
  @moduledoc """
  Embedded schema for individual test results within a TestRun.

  See spec section 4.4.3.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false

  embedded_schema do
    field :test_name, :string
    field :given, :string
    field :expected, :string
    field :actual, :string
    field :status, Ecto.Enum, values: [:passed, :failed, :error]
    field :duration_ms, :integer
    field :tool_calls, {:array, :map}, default: []
    field :assertions, {:array, :map}, default: []
    field :error_message, :string
  end

  def changeset(result, attrs) do
    result
    |> cast(attrs, [
      :test_name,
      :given,
      :expected,
      :actual,
      :status,
      :duration_ms,
      :tool_calls,
      :assertions,
      :error_message
    ])
    |> validate_required([:test_name, :status])
  end
end
