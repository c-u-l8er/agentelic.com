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
       ↑                       ↓              idanim.js         ↓
   frozen record       recomputes the         contact.js   148 checks over the
                       template hashes,            ↓        ARTIFACT, not the
                       then records the     records/build.json      source
                       sha256 of every            ↑
                       input and output    the gate recomputes every one of them
```

**Do not hand-type a check count.** The gate prints its own total; 148 is what it
printed on 2026-08-17, up from 103 in a single session.

- `npm run test:launch` — build then gate. **Set the Cloudflare Pages build
  command to this, never to a plain build**, or an unproven artifact gets served.
- The two template SHA-256 values on the page are **not copied** from the record.
  They are recomputed from `priv/templates/` with `compute_template_hash/1`'s own
  algorithm (`lib/agentelic/templates/registry.ex`) and the build exits non-zero
  on a mismatch. That is the site's whole evidence claim.
- **No `mailto:` anywhere** (Travis's call, 2026-08-11) — the gate refuses one.
  **Corrections go to a Formspree form** (`https://formspree.io/f/xaewoadr`, the
  endpoint `computedriven.com` posts to; SHELL.md r9, ruled by Travis
  2026-08-17). It is a real `<form action method="POST">`, so it posts with
  JavaScript off; `/contact.js` only upgrades it to an inline reply and prints
  "sent" **only on an actual 2xx**. The gate refuses if the `action` is not the
  endpoint the record declares, or if the `_gotcha` honeypot is missing — a
  honeypot dropped in a refactor fails silently. The issue tracker stays as the
  second, public route.
- **The two gate holes SHELL.md r6 names are closed here, and both were PROVEN
  open first.**
  1. *The retraction blocklist counts now; it used to exempt by class name.*
     Appending the retracted sentence three times to `retracted.paragraph` put
     "Start building today" on the artifact **four times** and the gate approved
     it, 114/0. It now bounds occurrences in both directions: zero outside the
     retraction, **at most one inside it**.
  2. *Nothing proved the artifact came from this build.* A build made to throw
     after its own checks left the previous `index.html` on disk and the gate
     passed over it. `records/build.json` now records the sha256 of every input
     read and every file written, as the last act of a successful emit, and the
     gate refuses on any drift — plus an independent recompilation of the CSS,
     `/contact.js` and every literal run of `src/landing.html`, so a deleted
     manifest is not the only thing standing there.
- **The computed-colour resolver** (SHELL.md r7/r8). Contrast checks read
  *declared tokens*; r7's header-CTA defect (`.top nav a` at 0,2,1 beating `.btn`
  at 0,1,0, painting `--fg2` on the accent at **1.19:1**) passed every one of them
  on the sibling surfaces. The gate now resolves the cascade over the emitted
  artifact against each `.btn`'s real ancestor chain, at 1600/1280/800/390.
  **This nav carries no `.btn` today**, so the CSS defect was latent here rather
  than shipped — the `:not(.btn)` scoping is in `src/shell.css` so the next lane
  to add a header CTA does not inherit an invisible one.
- **r8: strip HTML comments as their own pass before stripping tags.** `<[^>]+>`
  stops at the first `>`, so a comment containing one is only half-removed. On
  this artifact a single realistic source comment leaked **93 characters** of
  invisible text into `text`, which the bare-email scan and the text-floor check
  both read.
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
