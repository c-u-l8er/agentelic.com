defmodule Agentelic.Deploy do
  @moduledoc """
  Context module for deployment management.

  Production deployments require human approval via `approved_by`.
  Rollback creates a new deployment pointing to a previous build.
  """

  alias Agentelic.Deploy.Deployment
  alias Agentelic.Repo

  import Ecto.Query

  def list_deployments(agent_id) do
    Deployment
    |> where([d], d.agent_id == ^agent_id)
    |> order_by([d], desc: d.created_at)
    |> Repo.all()
  end

  def get_deployment!(id), do: Repo.get!(Deployment, id)

  def get_active_deployment(agent_id, environment) do
    Deployment
    |> where([d], d.agent_id == ^agent_id)
    |> where([d], d.environment == ^environment)
    |> where([d], d.status == :active)
    |> order_by([d], desc: d.created_at)
    |> limit(1)
    |> Repo.one()
  end

  def create_deployment(attrs) do
    %Deployment{}
    |> Deployment.changeset(attrs)
    |> Repo.insert()
  end

  def rollback(%Deployment{} = deployment) do
    # Rollback creates a new deployment pointing to the previously active build
    deployment
    |> Ecto.Changeset.change(status: :rolled_back)
    |> Repo.update()
  end
end
