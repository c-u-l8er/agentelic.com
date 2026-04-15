defmodule Agentelic.Publisher do
  @moduledoc """
  Emit ConsolidationEvent to FleetPrompt on build success.

  Uses CloudEvents v1 envelope format over HTTP POST.
  """

  require Logger

  @source "agentelic.com"
  @event_type "org.pulse.consolidation_event"

  @doc """
  Publish a build success event.

  Emits a ConsolidationEvent with the artifact details for FleetPrompt consumption.
  """
  @spec publish_build_success(map(), map()) :: :ok | {:error, String.t()}
  def publish_build_success(build, agent) do
    event = build_cloudevent(build, agent)

    Logger.info("Publishing ConsolidationEvent for build #{build.id}")

    case deliver(event) do
      :ok ->
        Logger.info("ConsolidationEvent delivered for build #{build.id}")
        :ok

      {:error, reason} = err ->
        Logger.error("ConsolidationEvent delivery failed for build #{build.id}: #{reason}")
        err
    end
  end

  @doc false
  def build_cloudevent(build, agent) do
    %{
      "specversion" => "1.0",
      "type" => @event_type,
      "source" => @source,
      "id" => Ecto.UUID.generate(),
      "time" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "datacontenttype" => "application/json",
      "data" => %{
        "agent_id" => to_string(agent.id),
        "agent_name" => agent.name,
        "build_id" => to_string(build.id),
        "version" => build.version,
        "artifact_hash" => build.artifact_hash,
        "spec_hash" => build.spec_hash,
        "template_version" => build.template_version,
        "workspace_id" => to_string(agent.workspace_id),
        "status" => "succeeded"
      }
    }
  end

  defp deliver(event) do
    webhook_url = Application.get_env(:agentelic, :fleetprompt_webhook_url)

    if is_nil(webhook_url) or webhook_url == "" do
      Logger.debug("FleetPrompt webhook URL not configured — skipping delivery")
      :ok
    else
      case Req.post(webhook_url,
             json: event,
             headers: [
               {"ce-specversion", "1.0"},
               {"ce-type", event["type"]},
               {"ce-source", event["source"]},
               {"ce-id", event["id"]},
               {"content-type", "application/cloudevents+json"}
             ],
             receive_timeout: 10_000
           ) do
        {:ok, %{status: status}} when status in 200..299 ->
          :ok

        {:ok, %{status: status, body: body}} ->
          {:error, "FleetPrompt returned #{status}: #{inspect(body)}"}

        {:error, exception} ->
          {:error, "FleetPrompt request failed: #{Exception.message(exception)}"}
      end
    end
  end
end
