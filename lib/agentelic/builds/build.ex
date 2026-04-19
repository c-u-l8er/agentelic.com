defmodule Agentelic.Builds.Build do
  @moduledoc """
  Build Ecto schema — an immutable record of a pipeline execution.

  Maps to `agentelic.builds` table. See spec section 4.4.2.

  Determinism invariant: same {spec_hash, template_hash} → same artifact_hash.
  Builds are immutable after :succeeded or :failed.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @schema_prefix "agentelic"

  @statuses [:pending, :parsing, :generating, :compiling, :testing, :succeeded, :failed]

  schema "builds" do
    belongs_to :agent, Agentelic.Agents.Agent

    field :workspace_id, :binary_id
    field :version, :string
    field :status, Ecto.Enum, values: @statuses, default: :pending

    # Pipeline stage results + timing
    field :parse_result, :map
    field :parse_duration_ms, :integer
    field :generation_result, :map
    field :generation_duration_ms, :integer
    field :compile_result, :map
    field :compile_duration_ms, :integer
    field :test_result, :map
    field :test_duration_ms, :integer

    # Artifact
    field :artifact_hash, :string
    field :artifact_path, :string
    field :error_message, :string

    # Provenance — full hash chain for deterministic reproducibility
    field :spec_hash, :string
    field :ampersand_hash, :string
    field :template_version, :string
    field :template_hash, :string
    field :commit_hash, :string
    field :compiled_tests_hash, :string

    timestamps(type: :utc_datetime_usec, inserted_at: :created_at)
  end

  @required_fields [:agent_id, :workspace_id, :version, :spec_hash]
  @optional_fields [
    :status,
    :parse_result,
    :parse_duration_ms,
    :generation_result,
    :generation_duration_ms,
    :compile_result,
    :compile_duration_ms,
    :test_result,
    :test_duration_ms,
    :artifact_hash,
    :artifact_path,
    :error_message,
    :ampersand_hash,
    :template_version,
    :template_hash,
    :commit_hash,
    :compiled_tests_hash
  ]

  def changeset(build, attrs) do
    build
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_format(:version, ~r/^\d+\.\d+\.\d+/, message: "must be semver format")
    |> unique_constraint([:agent_id, :version],
      message: "version already exists for this agent"
    )
    |> foreign_key_constraint(:agent_id)
  end

  def stage_changeset(build, stage_attrs) do
    build
    |> cast(stage_attrs, [
      :status,
      :parse_result,
      :parse_duration_ms,
      :generation_result,
      :generation_duration_ms,
      :compile_result,
      :compile_duration_ms,
      :test_result,
      :test_duration_ms,
      :artifact_hash,
      :artifact_path,
      :error_message,
      :template_version,
      :template_hash,
      :compiled_tests_hash
    ])
  end

  def immutable?(%__MODULE__{status: status}) when status in [:succeeded, :failed], do: true
  def immutable?(_), do: false
end
