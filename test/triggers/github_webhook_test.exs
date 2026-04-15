defmodule Agentelic.Triggers.GithubWebhookTest do
  use ExUnit.Case, async: true

  alias Agentelic.Triggers.GithubWebhook

  describe "parse_push/1" do
    test "extracts spec-relevant changes from push event" do
      payload = %{
        "ref" => "refs/heads/main",
        "commits" => [
          %{
            "id" => "abc123",
            "added" => ["docs/spec/SPEC.md"],
            "modified" => [],
            "removed" => []
          }
        ],
        "head_commit" => %{"id" => "abc123"},
        "repository" => %{"full_name" => "org/repo"},
        "pusher" => %{"name" => "developer"}
      }

      assert {:ok, trigger} = GithubWebhook.parse_push(payload)
      assert trigger.ref == "refs/heads/main"
      assert trigger.repo == "org/repo"
      assert trigger.commit_hash == "abc123"
      assert "docs/spec/SPEC.md" in trigger.changed_spec_files
    end

    test "detects ampersand.json changes" do
      payload = %{
        "ref" => "refs/heads/main",
        "commits" => [
          %{
            "added" => [],
            "modified" => [".ampersand.json"],
            "removed" => []
          }
        ],
        "head_commit" => %{"id" => "def456"},
        "repository" => %{"full_name" => "org/repo"},
        "pusher" => %{"name" => "dev"}
      }

      assert {:ok, trigger} = GithubWebhook.parse_push(payload)
      assert ".ampersand.json" in trigger.changed_spec_files
    end

    test "rejects push with no spec changes" do
      payload = %{
        "ref" => "refs/heads/main",
        "commits" => [
          %{
            "added" => ["src/index.ts"],
            "modified" => ["package.json"],
            "removed" => []
          }
        ],
        "head_commit" => %{"id" => "ghi789"},
        "repository" => %{"full_name" => "org/repo"},
        "pusher" => %{"name" => "dev"}
      }

      assert {:error, "No spec files changed in push"} = GithubWebhook.parse_push(payload)
    end

    test "rejects invalid payload" do
      assert {:error, _} = GithubWebhook.parse_push(%{})
    end
  end

  describe "verify_signature/3" do
    test "verifies valid HMAC-SHA256 signature" do
      secret = "webhook-secret"
      payload = ~s({"action":"push"})

      expected =
        :crypto.mac(:hmac, :sha256, secret, payload)
        |> Base.encode16(case: :lower)

      signature = "sha256=" <> expected

      assert GithubWebhook.verify_signature(payload, signature, secret)
    end

    test "rejects invalid signature" do
      refute GithubWebhook.verify_signature("payload", "sha256=wrong", "secret")
    end
  end
end
