# Agentelic

Spec-driven agent builder — you write the specification, it generates and runs
the agent. Elixir/OTP with a Phoenix API and an MCP server. Part of the
[ComputeDriven](https://computedriven.com) world.

**Written 2026-08-16.** This repository had no README before that date. Every
figure below was measured that day with the command beside it.

---

## Status, honestly

| | |
|---|---|
| Version | `0.1.0` (`mix.exs`, app `:agentelic`) |
| Tests | **66 passing, 0 failures** — `mix test` |
| Marketing page | **live** — `https://agentelic.com` answers 200 |
| Application | **live on Fly** as app `agentelic`, `PHX_HOST=app.agentelic.com`, region `iad` |
| Evidence rung | `live_deployed` |

**`GET https://app.agentelic.com/` returns 404, and that is the app answering,
not the app being down.** The body is `{"errors":{"detail":"Not Found"}}` —
Phoenix, routing correctly. `lib/agentelic_web/router.ex` declares **POST routes
only**, so every GET 404s by design. The check that actually tells you it is up:

```bash
curl -s -o /dev/null -w '%{http_code}\n' -X POST \
  -H 'content-type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' \
  https://app.agentelic.com/mcp        # -> 200
```

This is written down because a 404 on the root of a deployed service is exactly
the shape of evidence that gets misread as a dead deployment.

## Routes

```
POST /mcp                      MCP server — tools/list, tools/call
POST /api/pipeline/trigger     run a pipeline
POST /api/pipeline/github      GitHub webhook
```

## Quick start

```bash
mix deps.get
mix compile --warnings-as-errors
mix test                       # 66 tests
mix format --check-formatted
mix phx.server                 # local, port from config
```

Deploy is `fly deploy` against `fly.toml` (app `agentelic`, `iad`, internal port
8080, `force_https`).

## The specification is authoritative, and superseded in part

`docs/spec/README.md` is the product specification and drives implementation —
**read it before changing behaviour.** It carries a supersession banner added
2026-08-15, and the banner is the important part:

- **Superseded:** everything specifying Supabase tables, RLS policies, Supabase
  Auth or `amp.profiles` identity. The shared-Supabase data layer was abandoned
  by ruling on **2026-07-30**, replaced by `studbook` — which is a spec with no
  implementation and is blocked on an unruled confidentiality question. **Do not
  build against studbook yet.**
- **Not superseded:** the product, API, UX and protocol design, which is most of
  the document. Read it normally.

The spec was **not rewritten**, deliberately. It is a dated design record, and
rewriting it would fabricate a review nobody performed.

## A standing direction that affects this repository

Ruled 2026-08-15: **compute moves into the ComputeDriven OS, and the Fly.io apps
become storage or nothing.** This app is one of them. It is not being torn down
— **nothing is torn down before its OS-side replacement runs locally** — but do
not plan new Fly-shaped work here without checking `STACK_HUB.md` in the
workspace first.

## The portfolio nav

`amp-nav.js` is a **deployed copy**. The source is
`ampersand-nav/src/amp-nav.js`, fanned out by `sync-nav.sh`. Edits here are lost
on the next sync.

## Conventions

- `mix format`, warnings-as-errors.
- Never commit secrets.
- `old_scrap/` is historical and not authoritative.

## Related

- [computedriven.com](https://computedriven.com) — the discipline this is built under
- [ampersandboxdesign.com](https://ampersandboxdesign.com) — the [&] Protocol it composes under
