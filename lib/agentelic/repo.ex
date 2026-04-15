defmodule Agentelic.Repo do
  use Ecto.Repo,
    otp_app: :agentelic,
    adapter: Ecto.Adapters.Postgres
end
