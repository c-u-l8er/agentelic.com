defmodule Agentelic.Testing.TestRun do
  @moduledoc """
  TestRun Ecto schema — records a test execution against a build.

  Maps to `agentelic.test_runs` table. See spec section 4.4.3.
  workspace_id is required for RLS multi-tenant isolation.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @schema_prefix "agentelic"

  @statuses [:pending, :running, :passed, :failed, :error]

  schema "test_runs" do
    belongs_to :agent, Agentelic.Agents.Agent
    belongs_to :build, Agentelic.Builds.Build

    field :workspace_id, :binary_id
    field :test_suite, :string
    field :compiled_tests_hash, :string
    field :status, Ecto.Enum, values: @statuses, default: :pending

    # Aggregate results
    field :total_tests, :integer, default: 0
    field :passed_tests, :integer, default: 0
    field :failed_tests, :integer, default: 0
    field :error_tests, :integer, default: 0
    field :duration_ms, :integer

    # Individual results
    embeds_many :results, Agentelic.Testing.TestResult, on_replace: :delete

    field :coverage_summary, :map

    timestamps(type: :utc_datetime_usec, inserted_at: :created_at, updated_at: false)
  end

  @required_fields [:agent_id, :build_id, :workspace_id]
  @optional_fields [
    :test_suite,
    :compiled_tests_hash,
    :status,
    :total_tests,
    :passed_tests,
    :failed_tests,
    :error_tests,
    :duration_ms,
    :coverage_summary
  ]

  def changeset(test_run, attrs) do
    test_run
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> cast_embed(:results)
    |> foreign_key_constraint(:agent_id)
    |> foreign_key_constraint(:build_id)
  end
end
