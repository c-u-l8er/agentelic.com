defmodule Agentelic.Agents.Agent do
  @moduledoc """
  Agent Ecto schema — the top-level entity representing a buildable agent.

  Maps to `agentelic.agents` table. See spec section 4.4.1.

  Status state machine: draft → building → testing → deployable → deployed → archived
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @schema_prefix "agentelic"

  @statuses [:draft, :building, :testing, :deployable, :deployed, :archived]
  @product_types [:mcp_server, :agent, :library, :website, :cli]

  @valid_transitions %{
    draft: [:building],
    building: [:testing, :draft],
    testing: [:deployable, :building],
    deployable: [:deployed, :archived],
    deployed: [:archived],
    archived: []
  }

  schema "agents" do
    field :name, :string
    field :slug, :string
    field :description, :string
    field :status, Ecto.Enum, values: @statuses, default: :draft

    # Multi-tenancy (shared Supabase ecosystem)
    field :workspace_id, :binary_id
    field :user_id, :binary_id

    # Spec linkage
    field :spec_path, :string
    field :spec_hash, :string
    field :ampersand_path, :string
    field :ampersand_hash, :string

    # Build metadata
    field :framework, :string
    field :runtime_target, :string
    field :product_type, Ecto.Enum, values: @product_types
    field :last_build_at, :utc_datetime_usec
    field :last_test_at, :utc_datetime_usec

    # Template pinning (agent-level override)
    field :template_pin, :string

    has_many :builds, Agentelic.Builds.Build
    has_many :test_runs, Agentelic.Testing.TestRun
    has_many :deployments, Agentelic.Deploy.Deployment

    timestamps(type: :utc_datetime_usec, inserted_at: :created_at)
  end

  @required_fields [:name, :slug, :workspace_id, :user_id, :spec_path, :framework, :product_type]
  @optional_fields [
    :description,
    :spec_hash,
    :ampersand_path,
    :ampersand_hash,
    :runtime_target,
    :last_build_at,
    :last_test_at,
    :template_pin
  ]

  def changeset(agent, attrs) do
    agent
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_format(:slug, ~r/^[a-z0-9][a-z0-9-]*[a-z0-9]$/,
      message: "must be lowercase alphanumeric with hyphens"
    )
    |> unique_constraint(:slug)
    |> validate_inclusion(:framework, ~w(elixir typescript python))
  end

  def status_changeset(agent, new_status) do
    current = agent.status

    if new_status in Map.get(@valid_transitions, current, []) do
      agent
      |> change(status: new_status)
    else
      agent
      |> change()
      |> add_error(:status, "invalid transition from #{current} to #{new_status}")
    end
  end
end
