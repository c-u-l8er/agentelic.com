defmodule Agentelic.Triggers.GithubWebhook do
  @moduledoc """
  Accept GitHub push events on SPEC.md changes.

  Filters push events for changes to SPEC.md files and triggers
  the build pipeline for affected agents.
  """

  require Logger

  @spec_patterns ~w(SPEC.md spec.md docs/spec/ .ampersand.json)

  @doc """
  Parse a GitHub webhook push event and extract spec-relevant changes.

  Returns `{:ok, trigger}` or `{:error, reason}`.
  """
  @spec parse_push(map()) :: {:ok, map()} | {:error, String.t()}
  def parse_push(%{"ref" => ref, "commits" => commits} = payload) do
    changed_specs =
      commits
      |> Enum.flat_map(fn commit ->
        (Map.get(commit, "added", []) ++
           Map.get(commit, "modified", []))
        |> Enum.filter(&spec_file?/1)
      end)
      |> Enum.uniq()

    case changed_specs do
      [] ->
        {:error, "No spec files changed in push"}

      files ->
        trigger = %{
          ref: ref,
          repo: get_in(payload, ["repository", "full_name"]),
          commit_hash: get_in(payload, ["head_commit", "id"]),
          changed_spec_files: files,
          pusher: get_in(payload, ["pusher", "name"])
        }

        {:ok, trigger}
    end
  end

  def parse_push(_), do: {:error, "Invalid push event payload"}

  @doc """
  Verify GitHub webhook signature (HMAC-SHA256).
  """
  @spec verify_signature(String.t(), String.t(), String.t()) :: boolean()
  def verify_signature(payload_body, signature, secret) do
    expected =
      :crypto.mac(:hmac, :sha256, secret, payload_body)
      |> Base.encode16(case: :lower)

    "sha256=" <> expected == signature
  end

  defp spec_file?(path) do
    Enum.any?(@spec_patterns, &String.contains?(path, &1))
  end
end
