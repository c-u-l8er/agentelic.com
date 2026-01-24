# agentelic — project_spec/progress — Daily Engineering Progress Logs

This folder contains **daily, append-only engineering progress logs** for the `agentelic` implementation effort.

- These logs are **non-normative** (they do not define requirements).
- The **normative spec** lives in `project_spec/spec_v1/`.
- The purpose is to track **what changed**, **why**, and **what’s next**, day-by-day, in an auditable way.

Agentelic context (one-liner):
- **Agentelic = telespaces** (AI-enabled chatrooms) that can contain **Agentromatic workflows** executed by **WHS agents**, and can later be nested/owned by **Delegatic organizations**.

If a log conflicts with `project_spec/spec_v1/`, **the spec wins**.

---

## Folder structure

- `progress/README.md` — this index + conventions (you are here)
- `progress/YYYY-MM-DD.md` — one file per day

Recommended: create a new file for each day you do meaningful work, even if the log is short.

---

## Naming convention

Daily logs MUST be named:

- `YYYY-MM-DD.md` (UTC date recommended)

Examples:
- `2026-01-24.md`
- `2026-01-25.md`

---

## Writing rules (conventions)

### 1) Append-only
- Do **not** rewrite history.
- If you need to correct something from a prior day, add a note in today’s log under **Corrections**.

### 2) Keep it implementation-focused
Prefer:
- “Implemented telespace membership checks + invitation accept flow”
over
- “Worked on auth stuff”

### 3) Spec alignment is explicit
Each log SHOULD include references to the relevant spec sections (and ADRs if present), e.g.:
- `spec_v1/00_MASTER_SPEC.md` (or equivalent, once added)
- `spec_v1/10_API_CONTRACTS.md`
- `spec_v1/30_DATA_MODEL_CONVEX.md`
- `spec_v1/40_SECURITY_SECRETS_COMPLIANCE.md`
- `spec_v1/60_TESTING_ACCEPTANCE.md`

### 4) No secrets
Never include:
- API keys, tokens, credentials, private URLs containing secrets, or personal user data.

Use placeholders:
- `CLERK_JWT_ISSUER_DOMAIN=***`
- `https://<deployment>.convex.site`
- `CF_API_TOKEN=***`

### 5) Prefer “what shipped” + “what’s next”
Every log SHOULD make it easy to answer:
- What is newly working end-to-end today?
- What remains blocked?

---

## Daily log template

Copy/paste this into a new `YYYY-MM-DD.md` file:

---

# YYYY-MM-DD — Progress Log
Project: **agentelic**  
Focus: (1 short phrase)  
Owner: Engineering

## Summary (1–3 bullets)
- …
- …

## Spec/ADR alignment notes
- ✅ Implemented: (reference relevant spec sections)
- ⚠️ Deviations: (explain why; plan to reconcile)
- ❓ Open questions discovered: (link to spec “Open questions” if applicable)

## What shipped today
### Telespaces (core)
- …

### Messaging / presence (if applicable)
- …

### Workflows-in-telespaces (Agentromatic integration)
- …

### UI / Dashboard (if applicable)
- …

## API / Contracts
- Added/changed endpoints:
  - …
- Notes on auth / tenancy / error envelopes / idempotency:
  - …

## Data model / migrations
- Schema changes:
  - …
- Invariants enforced:
  - …
- Backfills or migrations performed:
  - …

## Security & privacy
- Access control / tenant isolation:
  - …
- Secrets handling / redaction:
  - …
- Abuse / rate limits (if applicable):
  - …

## Observability
- Logging / tracing:
  - …
- Metrics (if applicable):
  - …

## Validation performed
- Local run steps:
  - …
- Typecheck/tests:
  - …
- Manual verification:
  - …

## Known issues / risks
- …

## Next steps
- [ ] …
- [ ] …

## Corrections (if needed)
- …

---

## Suggested index section (optional)

If you want this README to act as an index, keep an “Index” section updated manually:

### Index
- `YYYY-MM-DD.md` — short title

(Keeping it manual is fine; automation can come later.)

---

## Why this exists

This folder supports:
- auditability (“what changed when?”),
- implementation pacing (“are we converging on v1 acceptance criteria?”),
- easier handoffs and reviews.

Remember: progress logs describe *implementation history*; `project_spec/spec_v1/` defines *requirements*.