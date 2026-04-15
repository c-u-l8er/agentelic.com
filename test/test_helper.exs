ExUnit.start(exclude: [:db])

# Only configure Sandbox if the repo is started (requires Supabase running)
if Process.whereis(Agentelic.Repo) do
  Ecto.Adapters.SQL.Sandbox.mode(Agentelic.Repo, :manual)
end
