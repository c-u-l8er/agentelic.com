defmodule Agentelic.Triggers.SupabaseListener do
  @moduledoc """
  Listen for spec.specs inserts via Supabase Realtime.

  When a new spec is inserted or updated, triggers the build pipeline
  for matching agents in the same workspace.
  """

  use GenServer
  require Logger

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    # Supabase Realtime connection will be configured via env vars
    state = %{
      enabled: Keyword.get(opts, :enabled, false),
      channel: nil
    }

    if state.enabled do
      Logger.info("SupabaseListener starting — listening for spec.specs changes")
    else
      Logger.info("SupabaseListener disabled — set SUPABASE_REALTIME_ENABLED=true to enable")
    end

    {:ok, state}
  end

  @impl true
  def handle_info({:spec_change, payload}, state) do
    Logger.info("Received spec change event: #{inspect(payload)}")

    case payload do
      %{"workspace_id" => ws_id, "spec_hash" => hash} ->
        trigger_pipeline(ws_id, hash)

      _ ->
        Logger.warning("Ignoring malformed spec change event")
    end

    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp trigger_pipeline(workspace_id, spec_hash) do
    Logger.info("Triggering pipeline for workspace #{workspace_id}, spec_hash #{spec_hash}")
    # Pipeline trigger will be wired when full integration is ready
    :ok
  end
end
