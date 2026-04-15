defmodule Agentelic.Deploy.Deployment do
  @moduledoc """
  Deployment Ecto schema — records a deployment of a build to an environment.

  Maps to `agentelic.deployments` table. See spec section 4.4.4.

  Production deployments MUST have approved_by set.
  Rollback creates a new deployment pointing to a previous build.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @environments [:staging, :canary, :production]
  @statuses [:deploying, :active, :rolled_back, :failed]
  @autonomy_levels [:observe, :advise, :act]

  schema "agentelic.deployments" do
    belongs_to :agent, Agentelic.Agents.Agent
    belongs_to :build, Agentelic.Builds.Build

    field :workspace_id, :binary_id
    field :environment, Ecto.Enum, values: @environments
    field :status, Ecto.Enum, values: @statuses, default: :deploying

    # Target
    field :runtime_target, :string
    field :runtime_ref, :map

    # Governance
    field :autonomy_level, Ecto.Enum, values: @autonomy_levels, default: :observe
    field :delegatic_org_id, :string
    field :governance_policy_hash, :string

    # Approval (required for production)
    field :approved_by, :string
    field :approval_reason, :string

    timestamps(type: :utc_datetime_usec, inserted_at: :created_at)
  end

  @required_fields [:agent_id, :build_id, :workspace_id, :environment]
  @optional_fields [
    :status,
    :runtime_target,
    :runtime_ref,
    :autonomy_level,
    :delegatic_org_id,
    :governance_policy_hash,
    :approved_by,
    :approval_reason
  ]

  def changeset(deployment, attrs) do
    deployment
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_production_approval()
    |> foreign_key_constraint(:agent_id)
    |> foreign_key_constraint(:build_id)
  end

  defp validate_production_approval(changeset) do
    environment = get_field(changeset, :environment)
    approved_by = get_field(changeset, :approved_by)

    if environment == :production and (is_nil(approved_by) or approved_by == "") do
      add_error(changeset, :approved_by, "is required for production deployments")
    else
      changeset
    end
  end
end
