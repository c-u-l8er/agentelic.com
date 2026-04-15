defmodule AgentelicWeb.ConnCase do
  @moduledoc """
  Test case for tests that require setting up a connection.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      @endpoint AgentelicWeb.Endpoint

      use AgentelicWeb, :verified_routes

      import Plug.Conn
      import Phoenix.ConnTest
      import AgentelicWeb.ConnCase
    end
  end

  setup tags do
    if Process.whereis(Agentelic.Repo) do
      Agentelic.DataCase.setup_sandbox(tags)
    end

    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
