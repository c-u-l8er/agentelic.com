# agentelic.com — Spec v1 (Implementation-Ready Document Set)
Version: 1.0  
Status: Draft scaffold (normative once the referenced spec files exist)  
Audience: Engineering  
Last updated: 2026-01-24

Agentelic is the **telespaces** layer in the WHS stack:

- **Agentromatic** = workflows (automation graphs + executions + logs)
- **Agentelic** = telespaces (AI-enabled chatrooms that *contain* workflows + agents)
- **Delegatic** = organizations (AI org charts that *contain* telespaces, recursively)

This folder defines the **v1 specification** for implementing Agentelic from scratch, with a bias toward:
- compatibility with existing **Agentromatic** workflow/execution contracts
- compatibility with the **WebHost.Systems** control-plane patterns (auth, tenancy, normalized errors, invariants)
- minimal new primitives: Agentelic should mostly *compose* and *route* existing things

> Important: This README is a scaffold. The rest of the `spec_v1/` document set should be created to make this spec truly “implementation-ready.”

---

## 0) What is a telespace (canonical definition)

A **telespace** is an AI-enabled, multi-room conversation space that:
- stores messages and room membership
- hosts and configures **WHS agents** (assistants/tools available inside rooms)
- installs and runs **Agentromatic workflows** as “automations” tied to room events
- provides an auditable activity timeline:
  - human messages
  - agent messages
  - workflow runs (executions + logs)
  - system events (membership, installs, permissions)

Think: “Slack/Discord-style rooms + AI agents + automation workflows,” with strict tenancy, durable logs, and explicit permission boundaries.

---

## 1) How this spec should be used

### 1.1 Normative vs non-normative
- **Normative** (once created): `spec_v1/*.md` and `spec_v1/adr/*.md`
- **Non-normative**: `project_spec/progress/*` daily logs, notes, scratch docs

If a progress log conflicts with the normative spec, the spec wins.

### 1.2 Recommended reading order (once files exist)
1. `00_MASTER_SPEC.md` — overall system, flows, invariants, acceptance criteria
2. `10_API_CONTRACTS.md` — HTTP/Convex contracts, normalized errors, pagination, idempotency
3. `20_RUNTIME_PROVIDER_INTERFACE.md` — if Agentelic invokes WHS runtimes directly (otherwise reference WebHost.Systems)
4. `30_DATA_MODEL_CONVEX.md` — schema, indexes, invariants, access control
5. `40_SECURITY_SECRETS_COMPLIANCE.md` — threat model, secrets, redaction, abuse controls
6. `50_OBSERVABILITY_BILLING_LIMITS.md` — usage, retention, limits (if needed in v1)
7. `60_TESTING_ACCEPTANCE.md` — unit/integration/E2E plans and release gates
8. `adr/*` — the “why” behind decisions

---

## 2) Architectural stance (how Agentelic integrates with the rest)

### 2.1 Hard boundaries (must remain true)
- **Agentelic does not reinvent workflow execution.**  
  It triggers and observes **Agentromatic** executions, and stores references + summaries.
- **Agentelic does not reinvent agent runtime deployment.**  
  WHS agents are deployed and invoked via **WebHost.Systems** control-plane patterns (or an equivalent control plane).
- **Delegatic remains the org/permissions envelope above Agentelic.**  
  Agentelic must support being “contained” by a Delegatic org structure.

### 2.2 Composition model (canonical)
- A **Delegatic organization** contains:
  - `telespaces[]` (Agentelic)
- A **telespace** contains:
  - `rooms[]` (channels/threads)
  - `members[]` (users + roles)
  - `installedAgents[]` (WHS agents available in-room)
  - `installedWorkflows[]` (Agentromatic workflows attached to events)
- A **room event** (message posted, reaction added, membership change, schedule tick) can:
  - invoke an agent (WHS invocation)
  - trigger an Agentromatic workflow run
  - emit an org-level event for Delegatic orchestration

---

## 3) Core goals and non-goals (v1)

### 3.1 Goals (v1)
- Create/list/update telespaces (tenant-isolated)
- Create/list rooms inside a telespace
- Post messages to rooms and fetch message history (with pagination)
- Install/uninstall:
  - WHS agents into a telespace (availability + configuration)
  - Agentromatic workflows into a telespace (as automations)
- Event triggers:
  - message-created triggers can launch agent invocations and/or workflow executions
- Provide an auditable “room activity view” that merges:
  - messages
  - agent invocations (references)
  - workflow executions/log summaries (references)
  - system events
- Keep the integration simple: prefer references to external systems over duplicating their data.

### 3.2 Non-goals (explicit for v1)
- Real-time voice/video (“telespace” is text-first in v1)
- Public/anonymous spaces (default is authenticated + tenant-controlled)
- Complex enterprise RBAC (start with owner + member roles; delegate org RBAC to Delegatic later)
- Full workflow builder UI (Agentromatic owns that)
- Full agent deployment UI (WebHost.Systems owns that)

---

## 4) Canonical resource identifiers (v1)

Recommended IDs (string, opaque):
- `telespaceId`
- `roomId`
- `messageId`
- `telespaceMemberId` (optional; can be derived)
- `installedAgentId`
- `installedWorkflowId`

Cross-system references:
- `agentId` / `deploymentId` (from WebHost.Systems)
- `workflowId` / `executionId` (from Agentromatic)
- `orgId` (from Delegatic)

IDs should be treated as opaque strings; never encode meaning into them.

---

## 5) Minimum viable event model (v1)

Agentelic must standardize a minimal set of room events that automations can subscribe to:

- `room.message.created`
- `room.message.edited` (optional v1)
- `room.member.joined`
- `room.member.left`
- `telespace.created`
- `telespace.updated`
- `automation.workflow.triggered`
- `automation.agent.invoked`

Each event should have:
- `eventId` (idempotency/dedupe)
- `telespaceId`, `roomId?`
- `actor` (user id or system)
- `timestamp`
- `payload` (bounded size, secret-free)

---

## 6) Security and privacy posture (v1 defaults)

Agentelic must enforce:
- **Tenant isolation** on every read/write
- **Room membership checks** before returning messages
- **No secrets in messages/logs by default**
  - any secret usage must be via references and server-side injection mechanisms
- **Redaction policy** for agent outputs and tool traces (best-effort, deterministic)

If an event triggers a workflow or agent invocation:
- permissions must be checked at trigger time (not only at install time)
- all side-effectful work should be attributable (who/what triggered it)

---

## 7) What should exist in this spec set (files to create next)

This README expects (but does not currently guarantee) the following files to exist:

- `spec_v1/00_MASTER_SPEC.md`
- `spec_v1/10_API_CONTRACTS.md`
- `spec_v1/30_DATA_MODEL_CONVEX.md`
- `spec_v1/40_SECURITY_SECRETS_COMPLIANCE.md`
- `spec_v1/60_TESTING_ACCEPTANCE.md`
- `spec_v1/adr/ADR-0001-*.md` (key architectural decisions)

If you keep the same style as WebHost.Systems, mirror the module numbering:
- 00 / 10 / 20 / 30 / 40 / 50 / 60
…and keep ADRs small, single-decision, and invariant-focused.

---

## 8) v1 acceptance criteria (high level)

Agentelic v1 is “done” when you can:

1. Create a telespace (authenticated user)
2. Create a room inside it
3. Post and list messages (pagination works)
4. Install a WHS agent into the telespace and invoke it from a room
5. Install an Agentromatic workflow as an automation and trigger a run from a room event
6. View a unified room activity timeline including:
   - messages
   - agent invocations (reference + status)
   - workflow executions (reference + status)
7. Verify tenant isolation with at least 3 IDOR tests:
   - cannot read another user’s telespace by id
   - cannot read rooms/messages without membership
   - cannot trigger automations in another telespace

---

## 9) Progress logs

Daily implementation progress logs should go in:
- `project_spec/progress/YYYY-MM-DD.md`

Rules:
- append-only
- no secrets
- link back to the spec sections and ADRs when relevant

---