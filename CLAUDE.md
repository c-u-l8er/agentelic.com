# Agentelic — Enterprise Agent Builder

Premium, enterprise-grade agent builder that brings software engineering discipline to AI agent development. Spec-driven builds, deterministic testing, staged deployments.

## Source-of-truth spec

- `docs/spec/README.md` — Agentelic product specification

## Role in [&] Ecosystem

Agentelic is the **engineering layer**:

```
SpecPrompt (Standards) → Agentelic (Engineering) → OpenSentience (Runtime) → Graphonomous (Memory)
```

Every agent starts from a SpecPrompt specification, is tested deterministically, and deployed through staged rollouts with compliance gates.

## Key features

- Spec-driven build pipeline (parse → generate → compile → package)
- Deterministic testing derived from acceptance criteria
- Staged deployment (staging → canary → production) with governance gates
- MCP tool surface for AI-assisted agent development

## The landing page is GENERATED and GATED — do not hand-edit `index.html`

`index.html` is emitted by `node build-site.mjs` from `records/surface.json` +
`src/`. **A direct edit is overwritten on the next build.** Then
`node launch-gate.mjs` reads the emitted artifact and refuses to publish it if
anything in it disagrees with the record.

```
records/surface.json  →  build-site.mjs  →  index.html  →  launch-gate.mjs
       ↑                       ↓                                 ↓
   frozen record       recomputes the template          97 checks over the
                       hashes from priv/templates/      ARTIFACT, not the source
```

- `npm run test:launch` — build then gate. **Set the Cloudflare Pages build
  command to this, never to a plain build**, or an unproven artifact gets served.
- The two template SHA-256 values on the page are **not copied** from the record.
  They are recomputed from `priv/templates/` with `compute_template_hash/1`'s own
  algorithm (`lib/agentelic/templates/registry.ex`) and the build exits non-zero
  on a mismatch. That is the site's whole evidence claim.
- **No `mailto:` anywhere** (Travis's call, 2026-08-11) — the gate refuses one.
  Corrections go to the issue tracker.
- Page-level treatment is `ProjectAmp2/agents/SHELL.md`. The tokens block in
  `src/shell.css` between `TOKENS-START`/`TOKENS-END` is this site's own;
  everything below `TOKENS-END` is the shared shell.
- `amp-nav.js` at the repo root is lane N's, fanned out by `sync-nav.sh`. The
  build does not touch it.

## Status — corrected 2026-08-16, by measurement

This file said *"spec + marketing site. No implementation code yet."* **That was
false**, and it had been for long enough that a site lane was briefed from it.
Measured on 2026-08-16:

| | |
|---|---|
| `mix test` | **66 tests, 0 failures** (`:db` tag excluded by default) |
| `POST https://app.agentelic.com/mcp` `tools/list` | **HTTP 200 — 10 tools**, not the 7 `AGENTS.md` calls "planned" |
| `tools/call template_list` | **200** — 2 templates, both hashes reproduced from this tree |
| `GET https://app.agentelic.com/api/agents` | **HTTP 500** — the persistence read path is broken on the deployed app |
| `GET https://app.agentelic.com/` | **404 by design** — `router.ex` declares POST routes only |
| checkout / billing / subscription code | **zero matches** across `lib/`, `test/`, `config/` |

So: the MCP surface is `live_deployed`, the pipeline and test runner are
`in_tree`, staged deployment and anything commercial are `spec`. The page states
those four rungs separately rather than averaging them.

**The $49/mo and $199/seat prices are labelled `proposed` and flagged
[TRAVIS].** They price accounts and seats that do not exist in the source.
Whether Agentelic sells anything is not this page's call — it was not deleted on
one, either.
