defmodule AgentelicWeb.MCPController do
  use AgentelicWeb, :controller

  alias Agentelic.MCP.Server

  def handle(conn, params) do
    case Server.handle_request(params) do
      nil ->
        # Notification — no response
        send_resp(conn, 204, "")

      response ->
        json(conn, response)
    end
  end
end
