defmodule Agentelic.Triggers.CloudEvents do
  @moduledoc """
  Accept CloudEvents webhooks for pipeline triggers.

  Expects CloudEvents v1 envelope format with type `org.pulse.consolidation_event`.
  Validates source_hash before triggering the pipeline.
  """

  require Logger

  @event_type "org.pulse.consolidation_event"

  @doc """
  Parse and validate a CloudEvents webhook payload.

  Returns `{:ok, trigger}` or `{:error, reason}`.
  """
  @spec parse(map()) :: {:ok, map()} | {:error, String.t()}
  def parse(payload) do
    with :ok <- validate_event_type(payload),
         {:ok, data} <- extract_data(payload) do
      trigger = %{
        source: Map.get(payload, "source", ""),
        type: Map.get(payload, "type", ""),
        workspace_id: Map.get(data, "workspace_id"),
        spec_hash: Map.get(data, "source_hash"),
        agent_id: Map.get(data, "agent_id"),
        spec_path: Map.get(data, "spec_path")
      }

      {:ok, trigger}
    end
  end

  defp validate_event_type(%{"type" => @event_type}), do: :ok
  defp validate_event_type(%{"type" => type}), do: {:error, "Unexpected event type: #{type}"}
  defp validate_event_type(_), do: {:error, "Missing event type"}

  defp extract_data(%{"data" => data}) when is_map(data), do: {:ok, data}
  defp extract_data(_), do: {:error, "Missing or invalid event data"}
end
