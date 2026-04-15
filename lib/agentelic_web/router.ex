defmodule AgentelicWeb.Router do
  use AgentelicWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  # MCP JSON-RPC endpoint
  scope "/mcp", AgentelicWeb do
    pipe_through :api

    post "/", MCPController, :handle
  end

  # REST API + webhook endpoints
  scope "/api", AgentelicWeb do
    pipe_through :api

    # Pipeline triggers
    post "/pipeline/trigger", PipelineController, :trigger
    post "/pipeline/github", PipelineController, :github_webhook

    # Agent CRUD
    resources "/agents", AgentController, only: [:index, :show, :create]
  end
end
