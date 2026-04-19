defmodule Agentelic.MCP.Server do
  @moduledoc """
  MCP JSON-RPC server for Agentelic.

  Implements MCP protocol v2025-03-26 over HTTP.
  Exposes 9 tools for AI-assisted agent development.
  """

  require Logger

  alias Agentelic.MCP.Tools

  @mcp_version "2025-03-26"
  @server_version Mix.Project.config()[:version]

  @doc """
  Handle an incoming JSON-RPC request.

  Returns a JSON-RPC response map.
  """
  @spec handle_request(map()) :: map()
  def handle_request(%{"jsonrpc" => "2.0", "method" => method, "id" => id} = request) do
    params = Map.get(request, "params", %{})

    case dispatch(method, params) do
      {:ok, result} ->
        %{"jsonrpc" => "2.0", "id" => id, "result" => result}

      {:error, code, message} ->
        %{"jsonrpc" => "2.0", "id" => id, "error" => %{"code" => code, "message" => message}}
    end
  end

  def handle_request(%{"jsonrpc" => "2.0", "method" => method}) do
    # Notification (no id) — no response needed
    params = %{}
    dispatch(method, params)
    nil
  end

  def handle_request(_) do
    %{
      "jsonrpc" => "2.0",
      "id" => nil,
      "error" => %{"code" => -32600, "message" => "Invalid Request"}
    }
  end

  @doc """
  Return the server's capabilities for the `initialize` handshake.
  """
  def capabilities do
    %{
      "protocolVersion" => @mcp_version,
      "serverInfo" => %{
        "name" => "agentelic",
        "version" => @server_version
      },
      "capabilities" => %{
        "tools" => %{"listChanged" => false}
      }
    }
  end

  @doc """
  List all available tools (for tools/list).
  """
  def list_tools do
    Tools.definitions()
  end

  # --- Dispatch ---

  defp dispatch("initialize", _params) do
    {:ok, capabilities()}
  end

  defp dispatch("tools/list", _params) do
    {:ok, %{"tools" => list_tools()}}
  end

  defp dispatch("tools/call", %{"name" => tool_name, "arguments" => args}) do
    Tools.call(tool_name, args)
  end

  defp dispatch("tools/call", %{"name" => tool_name}) do
    Tools.call(tool_name, %{})
  end

  defp dispatch(method, _params) do
    {:error, -32601, "Method not found: #{method}"}
  end
end
