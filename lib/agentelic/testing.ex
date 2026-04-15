defmodule Agentelic.Testing do
  @moduledoc """
  Context module for test run management.
  """

  alias Agentelic.Testing.TestRun
  alias Agentelic.Repo

  import Ecto.Query

  def list_test_runs(agent_id) do
    TestRun
    |> where([t], t.agent_id == ^agent_id)
    |> order_by([t], desc: t.created_at)
    |> Repo.all()
  end

  def get_test_run!(id), do: Repo.get!(TestRun, id)

  def get_test_run(id), do: Repo.get(TestRun, id)

  def get_latest_test_run(build_id) do
    TestRun
    |> where([t], t.build_id == ^build_id)
    |> order_by([t], desc: t.created_at)
    |> limit(1)
    |> Repo.one()
  end

  def create_test_run(attrs) do
    %TestRun{}
    |> TestRun.changeset(attrs)
    |> Repo.insert()
  end
end
