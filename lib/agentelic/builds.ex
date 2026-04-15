defmodule Agentelic.Builds do
  @moduledoc """
  Context module for build pipeline management.

  Builds are immutable after :succeeded or :failed.
  """

  alias Agentelic.Builds.Build
  alias Agentelic.Repo

  import Ecto.Query

  def list_builds(agent_id) do
    Build
    |> where([b], b.agent_id == ^agent_id)
    |> order_by([b], desc: b.created_at)
    |> Repo.all()
  end

  def get_build!(id), do: Repo.get!(Build, id)

  def get_build(id), do: Repo.get(Build, id)

  def get_latest_build(agent_id) do
    Build
    |> where([b], b.agent_id == ^agent_id)
    |> order_by([b], desc: b.created_at)
    |> limit(1)
    |> Repo.one()
  end

  def create_build(attrs) do
    %Build{}
    |> Build.changeset(attrs)
    |> Repo.insert()
  end

  def update_build_stage(%Build{} = build, stage_attrs) do
    if Build.immutable?(build) do
      {:error, :immutable, "Build #{build.id} is #{build.status} and cannot be modified"}
    else
      build
      |> Build.stage_changeset(stage_attrs)
      |> Repo.update()
    end
  end

  def next_version(agent_id) do
    case Repo.one(
           from b in Build,
             where: b.agent_id == ^agent_id,
             order_by: [desc: b.created_at],
             limit: 1,
             select: b.version
         ) do
      nil ->
        "0.1.0"

      version ->
        case Version.parse(version) do
          {:ok, v} -> "#{v.major}.#{v.minor}.#{v.patch + 1}"
          _ -> "0.1.0"
        end
    end
  end
end
