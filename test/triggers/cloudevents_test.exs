defmodule Agentelic.Triggers.CloudEventsTest do
  use ExUnit.Case, async: true

  alias Agentelic.Triggers.CloudEvents

  describe "parse/1" do
    test "parses valid ConsolidationEvent" do
      payload = %{
        "specversion" => "1.0",
        "type" => "org.pulse.consolidation_event",
        "source" => "specprompt.com",
        "id" => "event-123",
        "data" => %{
          "workspace_id" => "ws-456",
          "source_hash" => "abc123def456",
          "agent_id" => "agent-789",
          "spec_path" => "/specs/customer-support.md"
        }
      }

      assert {:ok, trigger} = CloudEvents.parse(payload)
      assert trigger.workspace_id == "ws-456"
      assert trigger.spec_hash == "abc123def456"
      assert trigger.agent_id == "agent-789"
      assert trigger.source == "specprompt.com"
    end

    test "rejects wrong event type" do
      payload = %{
        "type" => "com.example.other_event",
        "data" => %{}
      }

      assert {:error, msg} = CloudEvents.parse(payload)
      assert msg =~ "Unexpected event type"
    end

    test "rejects missing event type" do
      assert {:error, "Missing event type"} = CloudEvents.parse(%{})
    end

    test "rejects missing data" do
      payload = %{
        "type" => "org.pulse.consolidation_event"
      }

      assert {:error, "Missing or invalid event data"} = CloudEvents.parse(payload)
    end
  end
end
