defmodule Agentelic.Agents do
  @moduledoc """
  Context module for agent lifecycle management.
  """

  alias Agentelic.Agents.Agent
  alias Agentelic.Repo

  import Ecto.Query

  def list_agents(workspace_id) do
    Agent
    |> where([a], a.workspace_id == ^workspace_id)
    |> where([a], a.status != :archived)
    |> order_by([a], desc: a.updated_at)
    |> Repo.all()
  end

  def get_agent!(id), do: Repo.get!(Agent, id)

  def get_agent(id), do: Repo.get(Agent, id)

  def create_agent(attrs) do
    %Agent{}
    |> Agent.changeset(attrs)
    |> Repo.insert()
  end

  def update_agent(%Agent{} = agent, attrs) do
    agent
    |> Agent.changeset(attrs)
    |> Repo.update()
  end

  def transition_status(%Agent{} = agent, new_status) do
    agent
    |> Agent.status_changeset(new_status)
    |> Repo.update()
  end

  def archive_agent(%Agent{} = agent) do
    transition_status(agent, :archived)
  end

  def get_agent_with_associations(id) do
    Agent
    |> Repo.get(id)
    |> case do
      nil -> nil
      agent -> Repo.preload(agent, [:builds, :test_runs, :deployments])
    end
  end
end
