# ADR-0001: References, Not Copies (Agentelic integrations)
- **Status:** Accepted
- **Date:** 2026-01-24
- **Owners:** Engineering
- **Decision Scope:** How Agentelic stores and renders integrations to WHS (agents) and Agentromatic (workflows)

---

## Context

Agentelic is the **telespaces** layer:
- It stores **telespaces/rooms/membership/messages** and renders a unified, auditable room timeline.
- It can **invoke WHS agents** from rooms and can **trigger Agentromatic workflows** from room events.

WHS and Agentromatic already define their own sources of truth:
- **WHS (WebHost.Systems)** owns: agent definitions, deployments, invocation gateway, telemetry, billing/limits.
- **Agentromatic** owns: workflow definitions (DAG), executions, execution logs, condition evaluation, snapshotting.

If Agentelic duplicates those records (copying workflow definitions, execution logs, invocation transcripts, telemetry events), it introduces:
- data divergence (multiple “truths”)
- increased storage/cost
- higher risk of secret leakage (logs and tool traces are common leakage points)
- unclear compliance posture (where is the authoritative record stored?)

We need a simple, composable integration model that keeps Agentelic lightweight and safe while still providing a great in-room UX.

---

## Decision

### 1) Agentelic stores **references**, not copies (normative)

Agentelic MUST store only **opaque identifiers** and **bounded, secret-free summaries** for external system artifacts.

Specifically:

- For WHS invocations, Agentelic stores references like:
  - `whsAgentId` (required on installed agent)
  - `whsDeploymentId?` (optional pin)
  - `whsTraceId?`, `whsSessionId?`, `whsInvocationRequestId?` (as returned by WHS)
  - **optional** `outputSnippet` (bounded, redacted; never full tool traces)

- For Agentromatic runs, Agentelic stores references like:
  - `agentromaticWorkflowId` (on installed workflow)
  - `agentromaticExecutionId` (on run link)
  - **optional** `statusSummary` / `errorSnippet` (bounded, redacted)

Agentelic MUST NOT copy:
- workflow definitions (nodes/edges/trigger configs)
- execution logs or full event histories
- WHS telemetry events or billing usage details
- raw model transcripts/tool traces unless explicitly introduced later with strong redaction + retention controls

Agentelic remains the source of truth only for:
- telespaces/rooms/membership/messages
- installation wiring (installed agents/workflows)
- automations (event → actions)
- activity/timeline entries (append-only, secret-free)

---

### 2) “Activity timeline” is reference-first (normative)

Agentelic’s room timeline MUST be renderable from:
- Agentelic-native events (messages, membership changes, installs)
- reference entries pointing to external artifacts (invocation/execution references)

Activity entries MUST include:
- stable `type`
- `telespaceId`, `roomId`
- `actor` attribution (`user | system | agent`)
- `createdAtMs`
- `refs` to external ids (as applicable)

The timeline MAY include bounded summaries/snippets for UX, but must treat them as **non-authoritative**.

---

### 3) External details are fetched on demand (recommended)

When the UI needs deeper details (e.g., execution logs, full invocation output), it SHOULD:
- navigate to the owning product UI (deep link), OR
- fetch details from the owning product API on demand (server-side recommended)

Agentelic MUST NOT rely on clients directly calling WHS/Agentromatic in ways that weaken tenant isolation.
If Agentelic provides a “details proxy” endpoint later, it MUST:
- enforce Agentelic membership/role checks
- enforce cross-system authorization (best-effort)
- pass through only redacted/safe payloads

---

### 4) Verification is explicit, not assumed (v1-safe)

For cross-system references (workflowId, agentId, telespaceId):
- Agentelic MAY store an optional `verificationStatus: unverified|verified|failed`.
- Automations that cause side effects SHOULD require verified references before being enabled, unless explicitly overridden by an admin policy.

This prevents “dangling references” from becoming silent failure modes.

---

## Consequences

### Positive
- **Single source of truth** per subsystem (WHS/Agentromatic/Agentelic).
- Lower cost and less duplication.
- Reduced risk of secret leakage (Agentelic avoids persisting the most dangerous payload classes).
- Clear boundaries for debugging and compliance: “go to the owning system for the full record.”
- Easier evolution: Agentelic can integrate with multiple workflow/agent providers by swapping reference types.

### Negative / Tradeoffs
- Some UI views require on-demand fetches or deep links (slightly more latency).
- Partial availability: if WHS/Agentromatic is down, Agentelic can still show references but not full details.
- Requires careful correlation and good UX for “reference unavailable” states.

---

## Alternatives considered

### A) Copy full execution/invocation records into Agentelic
Rejected due to:
- high divergence risk
- secret leakage risk
- unclear ownership of retention/deletion/compliance obligations

### B) Mirror only “safe logs” into Agentelic
Deferred. This can be added later as an explicit feature with:
- strict redaction
- tier-based retention
- explicit user controls
But it is not the default.

### C) Make Agentelic the orchestrator-of-record for workflows/agents
Rejected for v1 because it collapses boundaries and duplicates core responsibilities already captured in WHS and Agentromatic.

---

## Implementation notes (guidance)

### Data model alignment
Agentelic tables should store:
- `installedAgents.whsAgentId` (+ optional deployment hint)
- `installedWorkflows.agentromaticWorkflowId`
- `agentInvocations` reference ledger:
  - status + `whsTraceId` + bounded `errorMessage`
- `workflowRuns` reference ledger:
  - status + `agentromaticExecutionId` + bounded `errorMessage`
- `activityEvents.refs` linking to:
  - `messageId`, `agentInvocationId`, `workflowRunId`
  - and optionally the external ids for quick navigation

### Redaction
Any summary/snippet stored in Agentelic MUST be:
- bounded (size limits enforced server-side)
- best-effort redacted (no tokens/secrets)
- safe to render in UI (escape/sanitize)

### Failure modes
If an external reference cannot be fetched:
- show the activity entry with “details unavailable”
- preserve the reference for later inspection
- never “fill in” with guessed details

---

## Revisit criteria

Revisit this ADR if:
- users need full transcripts/logs inside telespaces for compliance workflows,
- external APIs are too slow/unreliable and caching becomes necessary,
- Agentelic adds offline/history export features that require denormalized snapshots.

If revisited, introduce a new ADR for any “copying” feature with:
- explicit scope
- retention policy
- redaction guarantees
- authorization model
- migration strategy

---

## Related specs
- `ProjectWHS/agentelic.com/project_spec/spec_v1/00_MASTER_SPEC.md`
- `ProjectWHS/agentelic.com/project_spec/spec_v1/10_API_CONTRACTS.md`
- `ProjectWHS/agentelic.com/project_spec/spec_v1/30_DATA_MODEL_CONVEX.md`
- `ProjectWHS/agentelic.com/project_spec/spec_v1/40_SECURITY_SECRETS_COMPLIANCE.md`

Also conceptually aligned with:
- Agentromatic execution snapshotting and logs ownership
- WebHost.Systems control-plane vs data-plane boundary and telemetry integrity