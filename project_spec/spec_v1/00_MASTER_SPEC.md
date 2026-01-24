# agentelic — MASTER ENGINEERING SPEC (v1)
Version: 1.0  
Status: Draft (normative once adopted)  
Audience: Engineering  
Last updated: 2026-01-24

Agentelic is the **telespaces** layer in the WHS stack:

- **WHS (WebHost.Systems)** = agents (deploy/invoke/telemetry/billing, runtime providers)
- **Agentromatic** = workflows (DAG definitions, executions, execution logs)
- **Agentelic** = telespaces (AI-enabled chatrooms) that can embed agents + workflows
- **Delegatic** = organizations (nested governance envelope containing telespaces, recursively)

This spec defines Agentelic v1 as an implementation-ready system that:
- stores telespaces/rooms/messages/membership
- installs WHS agents into telespaces and invokes them from rooms
- installs Agentromatic workflows as telespace automations and triggers executions from room events
- renders a unified, auditable “activity timeline” by referencing external execution/invocation records rather than duplicating them

---

## 0) Executive summary

### 0.1 What you are building (v1)
A product that feels like “Slack/Discord rooms + AI agents + automation”, but is spec-first, tenant-safe, and audit-friendly:

- A user can create a **telespace**
- Create **rooms** inside it
- Post **messages**
- “Install” an **agent** (WHS agent reference) into a telespace and invoke it from a room
- “Install” a **workflow automation** (Agentromatic workflow reference) into a telespace and trigger workflow runs from room events
- View a unified room timeline showing:
  - human messages
  - agent invocations (references + status)
  - workflow executions (references + status)
  - system events (membership, installs, permissions)

### 0.2 What you are not building (v1)
- Voice/video
- Public/anonymous spaces
- A workflow builder UI (Agentromatic owns workflow authoring)
- A full agent deployment UI (WHS owns agent deploy/runtime)
- Enterprise-grade RBAC and SCIM (start with minimal roles; Delegatic expands governance)

---

## 1) Scope, goals, non-goals

### 1.1 Goals (v1 MUST)
1. **Telespaces CRUD**
   - create/list/get/update telespaces
2. **Rooms CRUD**
   - create/list/get rooms under a telespace
3. **Messaging**
   - create/list messages in a room with pagination
   - store message metadata (author, timestamps, optional reply/threading markers)
4. **Membership**
   - invite/add/remove members to telespaces (v1 roles: `admin | member | viewer`; `owner` is derived from `telespaces.ownerUserId` and has full control)
   - enforce membership checks for all reads/writes
5. **Installed agents**
   - attach a WHS `agentId` (and optionally `activeDeploymentId` snapshot) to a telespace as an “installed agent”
   - invoke the installed agent from a room
6. **Installed workflows (automations)**
   - attach an Agentromatic `workflowId` to a telespace as an “installed workflow automation”
   - trigger workflow executions from room events (e.g., message created)
7. **Unified activity**
   - produce an append-only activity stream for each room that can render:
     - messages
     - agent invocations (reference + summary)
     - workflow executions (reference + summary)
     - system events

### 1.2 Non-goals (v1 MUST NOT)
- MUST NOT store plaintext secrets in Agentelic tables/logs.
- MUST NOT execute workflows directly (Agentromatic owns workflow engine/executions/logs).
- MUST NOT deploy agents directly (WHS control plane owns deploy/runtime).
- MUST NOT allow cross-tenant reads/writes (IDOR-safe).
- MUST NOT require global “superuser” behavior to operate normal flows.

### 1.3 Assumptions
- Shared identity exists across the portfolio (recommended: Clerk).
- Agentelic has a backend that can enforce authz (recommended: Convex) and can call out to:
  - WHS invocation gateway
  - Agentromatic workflow execution entrypoints
- IDs are opaque strings; no business meaning encoded into IDs.

---

## 2) Key decisions (ADR-style summaries)
These are summarized here; full ADRs should live under `project_spec/spec_v1/adr/`.

1. **ADR-0001: “References, not copies” integration**
   - Agentelic stores references to WHS agents and Agentromatic workflows/executions.
   - Agentelic MAY cache small summaries for UI, but the source of truth remains the owning system.

2. **ADR-0002: Event-driven automations**
   - Agentelic defines a small canonical set of events (`room.message.created`, etc.).
   - Automations subscribe to events and trigger external actions (invoke agent / run workflow).

3. **ADR-0003: Deny-by-default access**
   - Every operation is scoped by telespace membership and role.
   - “Installed agent/workflow” operations require elevated permission (owner/admin).

4. **ADR-0004: Append-only activity timeline**
   - Room activity is append-only (messages + system events + automation events).
   - Mutations should emit activity entries for auditability.

5. **ADR-0005: Idempotency for automation triggers**
   - Event triggers must be deduped with stable `eventId` and idempotency keys when calling external systems.

---

## 3) Glossary (canonical terms)

- **Telespace**: top-level collaborative container (like a workspace).
- **Room**: conversation channel inside a telespace.
- **Message**: a user (or agent) authored message in a room.
- **Member**: a user with access to a telespace (role-bound).
- **Installed agent**: reference to a WHS agent available in a telespace.
- **Invocation**: a WHS agent call performed as a result of a user action or automation.
- **Installed workflow automation**: reference to an Agentromatic workflow attached to a telespace.
- **Execution**: an Agentromatic workflow run (execution + logs).
- **Activity entry**: append-only record of something that happened in a room (message/system/automation).

---

## 4) System architecture

### 4.1 High-level components
1. **Web UI**
   - telespaces list + detail
   - rooms list + room view (messages + activity)
   - “installed agents” management
   - “automations” management
2. **Auth provider** (recommended: Clerk)
3. **Agentelic backend** (recommended: Convex)
   - data model + access control
   - message creation/listing
   - automation triggers and idempotency
   - activity timeline writing
4. **External systems**
   - **WHS control plane / invocation gateway** (invoke agents)
   - **Agentromatic backend** (create executions, read execution logs/status)
   - **Delegatic** (org governance envelope; v1 is references + optional checks)

### 4.2 Boundaries (hard rules)
- Agentelic is the **source of truth** for:
  - telespaces, rooms, messages, membership, installations, automations, room activity entries
- Agentelic is **not** the source of truth for:
  - agent deployment/runtime/telemetry (WHS owns)
  - workflow definitions/executions/logs (Agentromatic owns)
- Agentelic must enforce local access control even if upstream systems also enforce theirs (defense-in-depth).

### 4.3 Data flows (canonical)

#### Flow A — Create telespace
1. User calls `telespaces.create`
2. Backend creates telespace + owner membership
3. Backend emits activity event: `telespace.created` (optional room-less)
4. UI navigates to telespace detail

#### Flow B — Create room
1. User calls `rooms.create({ telespaceId, name })`
2. Backend validates membership + permission
3. Backend creates room
4. Backend emits room activity entry: `room.created`

#### Flow C — Post message
1. User calls `messages.create({ telespaceId, roomId, content })`
2. Backend validates membership
3. Backend creates message record
4. Backend emits room activity entry: `room.message.created`
5. Backend evaluates automations subscribed to `room.message.created` and triggers configured actions (see Flow E/F)

#### Flow D — Install agent (WHS reference)
1. Owner/admin calls `installedAgents.install({ telespaceId, whsAgentId, config })`
2. Backend validates permission and stores reference
3. Backend emits activity entry: `telespace.agent.installed`

#### Flow E — Invoke agent from room (user action or automation)
1. Backend constructs `InvokeRequest` (normalized) from room context + user message
2. Backend calls WHS invocation gateway
3. Backend stores an `agentInvocation` record with status and references (traceId, sessionId, etc.)
4. Backend emits activity entry: `automation.agent.invoked`
5. (Optional) Backend writes an “agent message” into the room when invocation returns

#### Flow F — Install workflow automation (Agentromatic reference) and trigger execution
1. Owner/admin calls `installedWorkflows.install({ telespaceId, agentromaticWorkflowId, trigger })`
2. Backend stores reference + trigger settings
3. Backend emits activity entry: `telespace.workflow.installed`
4. When an event occurs (e.g., message created):
   - Backend generates a stable `eventId`
   - Backend calls Agentromatic `executeWorkflow` (or equivalent) with idempotency key derived from `(installedWorkflowId, eventId)`
   - Backend stores a `workflowRunLink` record referencing `executionId`
   - Backend emits activity entry: `automation.workflow.triggered`

---

## 5) Product requirements (engineering-focused)

### 5.1 Telespaces
MUST:
- create/list/get/update telespaces
- enforce that only members can view a telespace
- support minimal roles:
  - `owner` (full control)
  - `member` (can read/post messages)
  - `viewer` (optional; read-only)
SHOULD:
- support basic invite tokens or invite-by-email flow (implementation choice)

### 5.2 Rooms
MUST:
- create/list/get rooms within a telespace
- ensure room reads/writes require telespace membership
SHOULD:
- support archiving rooms (soft state)

### 5.3 Messages
MUST:
- create messages with:
  - `authorUserId`
  - `content` (string; bounded length)
  - `createdAtMs`
- list messages with pagination:
  - stable ordering (createdAtMs asc or desc, but consistent)
  - cursor-based pagination recommended
MUST NOT:
- accept unbounded payloads
SHOULD:
- support minimal message types:
  - `text`
  - `system` (membership/events)
  - `agent` (responses, tool summaries)
  - `automation` (links to runs)

### 5.4 Installed agents (WHS)
MUST:
- store a reference to a WHS agent:
  - `whsAgentId` (required)
  - `preferredDeploymentId` (optional snapshot)
  - `displayName`, `enabled`
  - `roomAllowlist` (optional)
- enforce permission for installs/uninstalls (owner/admin)
- support invoking an installed agent from a room
SHOULD:
- store only safe, non-secret configuration in Agentelic
  - secrets must be referenced by id or handled in WHS

### 5.5 Installed workflows (Agentromatic automations)
MUST:
- store a reference to an Agentromatic workflow:
  - `agentromaticWorkflowId` (required)
  - `trigger` (event subscription + filters)
  - `enabled`
- trigger workflow execution on subscribed events
- store references to created executions
SHOULD:
- support filters (MVP-safe) such as:
  - “only when message mentions @agent”
  - “only in these rooms”
  - “only if author role is owner/admin”
  - “only if message content matches substring/regex” (regex optional; substring preferred for MVP)

### 5.6 Activity timeline
MUST:
- produce a room-scoped append-only list of activity entries that can render:
  - messages
  - agent invocation references (status + traceId + optional output snippet)
  - workflow execution references (status + executionId + optional error snippet)
  - system events (member joined/left, installs)
MUST:
- include linking fields:
  - `telespaceId`, `roomId`
  - `actorUserId?`
  - `source`: `human | agent | workflow | system`
  - `createdAtMs`
SHOULD:
- allow reconstructing “what happened and why” without reading raw secrets or external logs.

---

## 6) Canonical event model (normative)

### 6.1 Event types (minimum v1)
Agentelic MUST support generating these event types:

- `room.message.created`
- `room.member.joined`
- `room.member.left`
- `telespace.created`
- `telespace.updated`
- `telespace.agent.installed`
- `telespace.agent.uninstalled`
- `telespace.workflow.installed`
- `telespace.workflow.uninstalled`
- `automation.agent.invoked`
- `automation.workflow.triggered`

### 6.2 Event envelope (minimum)
Every event MUST include:

- `eventId` (string, unique and stable)
- `type` (string)
- `telespaceId` (string)
- `roomId?` (string)
- `actor`:
  - `type`: `user | system`
  - `userId?`: string
- `timestampMs` (number)
- `payload` (JSON-safe object, bounded size, secret-free)

### 6.3 Idempotency and dedupe
- For any automation trigger, Agentelic MUST:
  - persist the triggering `eventId`
  - dedupe so the same `(installedAutomationId, eventId)` does not cause duplicate side effects
- When calling external systems, Agentelic SHOULD pass an idempotency key:
  - `idempotencyKey = "agentelic:<installedId>:<eventId>"`

---

## 7) API surface (normative pointers)
This master spec does not define the full API. The full contracts MUST live in:
- `spec_v1/10_API_CONTRACTS.md`

However, the following logical modules MUST exist (names can vary):

- `telespaces.*`
- `rooms.*`
- `messages.*`
- `memberships.*`
- `installedAgents.*`
- `agentInvocations.*` (or equivalent)
- `installedWorkflows.*` (automations)
- `workflowRunLinks.*` (or equivalent)
- `activity.*` (read API for activity stream)

API requirements:
- consistent error envelope with stable `code` and safe `message`
- pagination for list endpoints
- strict authorization checks on every operation
- server-side validation and field bounding (length/size)

---

## 8) Data model (normative pointers)
The full Convex schema and invariants MUST live in:
- `spec_v1/30_DATA_MODEL_CONVEX.md`

Minimum tables/entities (conceptual; names may vary):
- `users` (or resolved via auth)
- `telespaces`
- `telespaceMembers`
- `rooms`
- `messages`
- `activityEntries` (or a combined message/activity model)
- `installedAgents`
- `agentInvocations` (references to WHS invocations)
- `installedWorkflows` (workflow automations)
- `workflowRunLinks` (references to Agentromatic executions)
- `automationDedupe` (or embedded dedupe keys on link tables)

Required invariants (MUST):
- Every row is tenant-scoped by `telespaceId` or `ownerUserId` and enforced consistently.
- Membership is checked for reads/writes to rooms/messages/activity.
- “Installed agent/workflow” entries are scoped to a telespace and cannot be read/modified cross-telespace.
- Dedupe keys for automation triggers are unique and enforced.

---

## 9) Security requirements (implementation-grade)

### 9.1 Tenant isolation (MUST)
- No cross-tenant reads or writes by ID (IDOR safe).
- All list endpoints MUST be scoped by membership and/or telespaceId.
- All “get by id” endpoints MUST verify membership/ownership before returning data.

### 9.2 Secrets handling (MUST)
- Messages, activity entries, and logs MUST be treated as durable artifacts and must be secret-free by design.
- If a workflow/agent requires a secret:
  - Agentelic stores a secret reference id only, or stores nothing and relies on upstream systems (WHS/Agentromatic).
- Errors returned to clients MUST be safe and must not contain secret material.

### 9.3 Prompt injection posture (MUST)
Agentelic is an orchestration surface. To reduce “drive-by actions”:
- default automations SHOULD be off unless explicitly installed/enabled
- automation triggers MUST be scoped and bounded
- any automation that can cause side effects MUST be explicitly configured by an owner/admin
- agent/tool invocation pathways MUST use server-side allowlists (at least per installed agent/workflow)

### 9.4 Abuse controls (SHOULD, minimal v1)
- rate limit message posting per user per telespace (coarse limits acceptable)
- rate limit automation triggers to avoid event storms
- bound message size and payload sizes

Full posture should be specified in:
- `spec_v1/40_SECURITY_SECRETS_COMPLIANCE.md`

---

## 10) Observability and retention (v1)
MUST:
- store enough metadata to debug:
  - who triggered an automation
  - which agent/workflow was invoked
  - which external reference IDs were produced (traceId, executionId)
SHOULD:
- adopt retention defaults:
  - messages: 90 days (configurable later)
  - activity entries: 90 days
  - automation dedupe keys: 30–90 days (must outlive retries)
MUST NOT:
- store raw tool traces or secret-bearing payloads in room messages by default

(Full details belong in `spec_v1/50_OBSERVABILITY_BILLING_LIMITS.md` if needed; v1 can be minimal.)

---

## 11) UI requirements (v1 minimum)
Agentelic UI (whether standalone or embedded into WebHost.Systems dashboard) SHOULD support:

- Telespaces list
- Telespace detail:
  - rooms list
  - installed agents
  - installed workflows/automations
  - members management
- Room view:
  - messages
  - activity timeline (merged view)
  - “invoke agent” action
  - visible automation indicators (“this message triggered X”)

UI is not normative for backend completeness, but v1 acceptance should be demonstrable via UI or scripted API calls.

---

## 12) Testing strategy (minimum viable)
Full plan MUST be in:
- `spec_v1/60_TESTING_ACCEPTANCE.md`

Minimum tests required (MUST):
1. **Tenant isolation / IDOR**
   - cannot read telespace/room/message by id without membership
2. **Membership enforcement**
   - non-member cannot post message
3. **Automation dedupe**
   - same event does not trigger duplicate workflow run
4. **External reference integrity**
   - stored invocation/execution references must belong to the same telespace (at least by internal linking rules)

SHOULD:
- golden-path E2E test:
  - create telespace → create room → post message → invoke agent → trigger workflow → see activity entries

---

## 13) Open questions (must answer before v1 sign-off)
1. Identity mapping across products:
   - Do all systems share Clerk? If not, what is the canonical cross-system user id?
2. Where does automation execution happen:
   - In Agentelic backend only, or can the client directly call WHS/Agentromatic and then report back?
   - v1 recommendation: server-only triggers for safety and dedupe.
3. How are workflow definitions managed for telespace automations:
   - Do you install existing Agentromatic workflows by id only, or allow “copy into telespace”?
4. How does Delegatic governance apply:
   - Does Delegatic membership gate telespace membership, or vice versa?
   - v1 recommendation: independent enforcement; Delegatic provides additional restrictions, not fewer.
5. Do we require “agent messages” to be persisted as messages or as activity entries only?

---

## 14) Acceptance criteria (definition of done for v1)
Agentelic v1 is “done” when you can demonstrate:

1. **Core**
   - Create telespace
   - Create room
   - Add a second member
   - Post messages and page through message history
2. **Agents**
   - Install a WHS agent reference in a telespace
   - Invoke it from a room
   - Record invocation reference and show it in the room activity timeline
3. **Workflows**
   - Install an Agentromatic workflow as an automation in a telespace
   - Trigger a workflow execution from `room.message.created`
   - Record execution reference and show it in the room activity timeline
4. **Security**
   - IDOR tests pass:
     - cannot read another telespace by id
     - cannot read another room’s messages without membership
     - cannot trigger automations in a telespace you don’t belong to
5. **Auditability**
   - Every mutating operation creates a corresponding activity entry (or message/system message) that explains what happened.

---