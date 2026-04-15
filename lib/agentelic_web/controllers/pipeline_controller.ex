defmodule AgentelicWeb.PipelineController do
  use AgentelicWeb, :controller

  alias Agentelic.Triggers.{CloudEvents, GithubWebhook}

  require Logger

  @doc "POST /api/pipeline/trigger — CloudEvents webhook"
  def trigger(conn, params) do
    case CloudEvents.parse(params) do
      {:ok, trigger} ->
        Logger.info("Pipeline trigger received: #{inspect(trigger)}")
        json(conn, %{status: "accepted", trigger: trigger})

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: reason})
    end
  end

  @doc "POST /api/pipeline/github — GitHub push webhook"
  def github_webhook(conn, params) do
    with :ok <- verify_github_signature(conn),
         {:ok, trigger} <- GithubWebhook.parse_push(params) do
      Logger.info("GitHub webhook trigger: #{inspect(trigger)}")
      json(conn, %{status: "accepted", trigger: trigger})
    else
      {:error, :signature_mismatch} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Invalid webhook signature"})

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: reason})
    end
  end

  defp verify_github_signature(conn) do
    secret = Application.get_env(:agentelic, :github_webhook_secret)

    # Skip verification if no secret is configured (dev/test)
    if is_nil(secret) or secret == "" do
      :ok
    else
      signature = Plug.Conn.get_req_header(conn, "x-hub-signature-256") |> List.first("")

      case conn.assigns[:raw_body] do
        nil ->
          # Raw body not captured — skip verification
          :ok

        body ->
          if GithubWebhook.verify_signature(body, signature, secret) do
            :ok
          else
            {:error, :signature_mismatch}
          end
      end
    end
  end
end
