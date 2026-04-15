defmodule AgentelicWeb.AgentController do
  use AgentelicWeb, :controller

  alias Agentelic.Agents.Agent
  alias Agentelic.Repo

  import Ecto.Query

  def index(conn, params) do
    workspace_id = Map.get(params, "workspace_id")

    agents =
      Agent
      |> maybe_filter_workspace(workspace_id)
      |> order_by([a], desc: a.updated_at)
      |> Repo.all()

    json(conn, %{agents: Enum.map(agents, &agent_json/1)})
  end

  def show(conn, %{"id" => id}) do
    case Repo.get(Agent, id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "Agent not found"})

      agent ->
        agent = Repo.preload(agent, [:builds, :test_runs, :deployments])
        json(conn, %{agent: agent_json(agent)})
    end
  end

  def create(conn, params) do
    slug =
      params
      |> Map.get("name", "")
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "-")
      |> String.trim("-")

    changeset = Agent.changeset(%Agent{}, Map.put(params, "slug", slug))

    case Repo.insert(changeset) do
      {:ok, agent} ->
        conn
        |> put_status(:created)
        |> json(%{agent: agent_json(agent)})

      {:error, changeset} ->
        errors =
          Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)

        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: errors})
    end
  end

  defp maybe_filter_workspace(query, nil), do: query

  defp maybe_filter_workspace(query, workspace_id) do
    where(query, [a], a.workspace_id == ^workspace_id)
  end

  defp agent_json(agent) do
    %{
      id: agent.id,
      name: agent.name,
      slug: agent.slug,
      status: agent.status,
      framework: agent.framework,
      product_type: agent.product_type,
      spec_path: agent.spec_path,
      spec_hash: agent.spec_hash,
      created_at: agent.created_at,
      updated_at: agent.updated_at
    }
  end
end
