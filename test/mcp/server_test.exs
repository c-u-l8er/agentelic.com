defmodule Agentelic.MCP.ServerTest do
  use ExUnit.Case, async: true

  alias Agentelic.MCP.Server

  describe "handle_request/1" do
    test "responds to initialize" do
      request = %{
        "jsonrpc" => "2.0",
        "method" => "initialize",
        "id" => 1,
        "params" => %{}
      }

      response = Server.handle_request(request)

      assert response["jsonrpc"] == "2.0"
      assert response["id"] == 1
      assert response["result"]["protocolVersion"] == "2025-03-26"
      assert response["result"]["serverInfo"]["name"] == "agentelic"
    end

    test "responds to tools/list with all 10 tools" do
      request = %{
        "jsonrpc" => "2.0",
        "method" => "tools/list",
        "id" => 2,
        "params" => %{}
      }

      response = Server.handle_request(request)

      assert response["id"] == 2
      tools = response["result"]["tools"]
      assert length(tools) == 10

      tool_names = Enum.map(tools, & &1["name"])
      assert "agent_create" in tool_names
      assert "agent_ensure" in tool_names
      assert "agent_build" in tool_names
      assert "agent_test" in tool_names
      assert "agent_deploy" in tool_names
      assert "agent_status" in tool_names
      assert "template_list" in tool_names
      assert "template_pin" in tool_names
      assert "spec_validate" in tool_names
      assert "test_explain" in tool_names
    end

    test "each tool has name, description, and inputSchema" do
      tools = Server.list_tools()

      for tool <- tools do
        assert Map.has_key?(tool, "name"), "Tool missing name"
        assert Map.has_key?(tool, "description"), "Tool #{tool["name"]} missing description"
        assert Map.has_key?(tool, "inputSchema"), "Tool #{tool["name"]} missing inputSchema"
        assert tool["inputSchema"]["type"] == "object"
      end
    end

    test "returns error for unknown method" do
      request = %{
        "jsonrpc" => "2.0",
        "method" => "nonexistent/method",
        "id" => 3
      }

      response = Server.handle_request(request)

      assert response["error"]["code"] == -32601
      assert response["error"]["message"] =~ "Method not found"
    end

    test "returns error for invalid request" do
      response = Server.handle_request(%{"invalid" => true})

      assert response["error"]["code"] == -32600
    end

    test "returns nil for notification (no id)" do
      request = %{
        "jsonrpc" => "2.0",
        "method" => "some/notification"
      }

      assert Server.handle_request(request) == nil
    end

    test "spec_validate validates a valid spec" do
      spec_content = File.read!("test/fixtures/customer_support_spec.md")

      request = %{
        "jsonrpc" => "2.0",
        "method" => "tools/call",
        "id" => 4,
        "params" => %{
          "name" => "spec_validate",
          "arguments" => %{"spec_content" => spec_content}
        }
      }

      response = Server.handle_request(request)

      assert response["result"]["valid"] == true
      assert response["result"]["errors"] == []
      assert is_binary(response["result"]["spec_hash"])
    end

    test "spec_validate rejects invalid spec" do
      request = %{
        "jsonrpc" => "2.0",
        "method" => "tools/call",
        "id" => 5,
        "params" => %{
          "name" => "spec_validate",
          "arguments" => %{"spec_content" => "# No sections here"}
        }
      }

      response = Server.handle_request(request)

      assert response["result"]["valid"] == false
      assert length(response["result"]["errors"]) > 0
    end

    test "template_list returns available templates" do
      request = %{
        "jsonrpc" => "2.0",
        "method" => "tools/call",
        "id" => 6,
        "params" => %{
          "name" => "template_list",
          "arguments" => %{}
        }
      }

      response = Server.handle_request(request)

      assert is_list(response["result"]["templates"])
    end

    test "unknown tool returns error" do
      request = %{
        "jsonrpc" => "2.0",
        "method" => "tools/call",
        "id" => 7,
        "params" => %{
          "name" => "nonexistent_tool",
          "arguments" => %{}
        }
      }

      response = Server.handle_request(request)

      assert response["error"]["code"] == -32601
      assert response["error"]["message"] =~ "Unknown tool"
    end
  end

  describe "capabilities/0" do
    test "returns valid MCP capabilities" do
      caps = Server.capabilities()

      assert caps["protocolVersion"] == "2025-03-26"
      assert caps["serverInfo"]["name"] == "agentelic"
      assert caps["capabilities"]["tools"]
    end
  end
end
