# agentelic — Data Model (Convex) & Access Control (v1)
Version: 1.0  
Status: Draft (normative once adopted)  
Audience: Engineering  
Last updated: 2026-01-24

This document defines the **Convex control-plane data model** for **Agentelic (telespaces)**:
- tables, fields, indexes
- invariants and validation rules
- access control and tenant isolation rules
- retention and deletion semantics
- integration reference shapes for:
  - **WHS agents** (WebHost.Systems: deploy/invoke/telemetry)
  - **Agentromatic workflows** (definitions/executions/logs)

Agentelic stance:
- Agentelic **stores conversations and “space wiring”** (rooms, members, installs, triggers).
- Agentelic **does not duplicate execution engines**:
  - workflow execution remains Agentromatic
  - agent runtime invocation remains WHS (WebHost.Systems)

If any contradictions exist between this document and higher-level product specs, the higher-level *v1 master spec* should win (once written). This doc is intended to be implementation-grade.

---

## 0) Design goals

### 0.1 Goals
1. **Tenant isolation**: no cross-tenant reads/writes (IDOR-safe).
2. **Fast core queries**:
   - list telespaces by owner
   - list rooms in a telespace
   - paginate messages in a room
   - list “activity timeline” for a room/telespace
3. **Composable integrations**:
   - attach WHS agents to telespaces (availability + config)
   - attach Agentromatic workflows as automations
   - store references to runs/invocations (not full transcripts unless explicitly desired)
4. **Auditable**: every mutating operation can emit a durable, secret-free activity event.

### 0.2 Non-goals (v1)
- Enterprise RBAC (fine-grained permissions beyond basic roles).
- Multi-tenant org inheritance (Delegatic will govern org-level containment later).
- Full analytics/billing in Agentelic (WHS owns runtime billing; Agentromatic may own workflow usage).

---

## 1) Cross-cutting conventions

### 1.1 Identity model (recommended baseline)
Agentelic uses Clerk (or equivalent) identity → internal `users` table mapping.

- `users.externalId`: stable external subject id (e.g., Clerk user id), **unique**.
- Every other table that references a user uses `userId: Id<"users">` (internal id).

> If your portfolio standard prefers reusing a shared user store across projects, you can remove the `users` table and use `externalUserId` strings everywhere, but you must keep invariants and indexes equivalent.

### 1.2 Time
Use millisecond timestamps:
- `createdAtMs: number`
- `updatedAtMs?: number` (present on mutable records)
- `deletedAtMs?: number` (soft delete)

### 1.3 IDs
Convex `_id` is the canonical id for storage.
External APIs may also expose stable string IDs, but do not encode meaning into IDs.

### 1.4 Tenancy “owner scope” (v1)
Agentelic v1 uses **user-owned telespaces** (team/org later via Delegatic).

Every telespace MUST have:
- `ownerUserId: Id<"users">`

Other records SHOULD carry `telespaceId` and can rely on membership checks via joins/reads.

### 1.5 Roles (v1 minimal)
Membership roles:
- `owner` (implicit: telespace owner)
- `admin`
- `member`
- `viewer` (read-only)

Policy defaults:
- message posting: `owner|admin|member`
- installs (agents/workflows): `owner|admin`
- manage members: `owner|admin`
- read messages: `owner|admin|member|viewer` (must be a member)

### 1.6 Payload limits (must enforce)
To control cost and avoid accidental secrets explosion:
- `messages.content` max length: **20,000 chars** (server-side enforced).
- `automation trigger payload` max size: **32KB JSON** (truncate or reject).
- `activityEvents.summary` max length: **2,000 chars**.
- Any `metadata` object must be JSON-safe and **<= 8KB** when stringified (recommended).

### 1.7 Secrets rule (normative)
Agentelic MUST NOT store plaintext secrets in:
- installs, automations, activity events, or error details.
Messages are “user content” and may contain secrets; v1 default UX SHOULD discourage secrets, and server-side redaction SHOULD be applied when copying message content into derived records (e.g., activity summaries, automation payloads).

---

## 2) Tables (normative schema)

The following tables are recommended for v1. You can rename tables/fields, but MUST preserve semantics, invariants, and access rules.

### 2.1 `users`
Purpose: map external identity to internal user id.

Fields:
- `_id: Id<"users">`
- `externalId: string` (unique; e.g., Clerk user id)
- `email?: string`
- `name?: string`
- `createdAtMs: number`
- `updatedAtMs: number`

Indexes:
- by `externalId` (unique)

Invariants:
- One row per external identity.

---

### 2.2 `telespaces`
Purpose: top-level container.

Fields:
- `_id: Id<"telespaces">`
- `ownerUserId: Id<"users">`
- `orgId?: string` (optional; Delegatic organization reference id, opaque)
- `name: string`
- `description?: string`
- `visibility: "private"` (v1 only; reserved for future)
- `createdAtMs: number`
- `updatedAtMs: number`
- `deletedAtMs?: number` (soft delete)

Indexes:
- by `ownerUserId`
- by `ownerUserId + updatedAtMs desc`

Invariants:
- `ownerUserId` exists.
- Soft-deleted telespaces MUST be treated as non-readable by non-admin callers, except for audit/export flows (if any).

Semantics (v1):
- `orgId` is a **reference only** (linking/grouping) to a Delegatic organization.
- Agentelic MUST NOT treat `orgId` as authorization. Telespace membership remains the sole gate for telespace/room/message access.
- v1 MAY store `orgId` without verification. If verification is implemented later, it MUST be best-effort and MUST NOT widen access (only restrict or annotate).

---

### 2.3 `telespaceMembers`
Purpose: membership + role for users inside a telespace.

Fields:
- `_id: Id<"telespaceMembers">`
- `telespaceId: Id<"telespaces">`
- `userId: Id<"users">`
- `role: "admin" | "member" | "viewer"`  
  (Note: owner is derived from `telespaces.ownerUserId`.)
- `status: "active" | "invited" | "removed"`
- `invitedByUserId?: Id<"users">`
- `createdAtMs: number`
- `updatedAtMs: number`
- `removedAtMs?: number`

Indexes:
- by `telespaceId + userId` (unique active membership; see invariant)
- by `telespaceId + createdAtMs`
- by `userId + createdAtMs` (for “spaces I’m in” lists)

Invariants:
- There MUST NOT exist more than one `status="active"` membership row for the same `(telespaceId, userId)`.
  - Recommended: enforce by lookup + mutation checks (Convex cannot do true unique constraints; treat as invariant).
- `invited` entries MUST transition to `active` or `removed`.

---

### 2.4 `rooms`
Purpose: rooms/channels inside a telespace.

Fields:
- `_id: Id<"rooms">`
- `telespaceId: Id<"telespaces">`
- `name: string`
- `topic?: string`
- `kind: "channel" | "dm" | "thread_root"` (v1 can start with `"channel"` only)
- `createdByUserId: Id<"users">`
- `createdAtMs: number`
- `updatedAtMs: number`
- `deletedAtMs?: number`

Indexes:
- by `telespaceId + createdAtMs`
- by `telespaceId + updatedAtMs desc`

Invariants:
- `createdByUserId` MUST be a member at creation time.
- If soft-deleted, room messages remain for retention/audit but MUST not be writable.

---

### 2.5 `messages`
Purpose: room messages (text-first).

Fields:
- `_id: Id<"messages">`
- `telespaceId: Id<"telespaces">` (denormalized for auth fast-path)
- `roomId: Id<"rooms">`
- `authorType: "user" | "agent" | "system"`
- `authorUserId?: Id<"users">` (required when `authorType="user"`)
- `authorInstalledAgentId?: Id<"installedAgents">` (required when `authorType="agent"`)
- `content: string`
- `contentFormat: "text" | "markdown"` (v1 can default to `"text"`)
- `replyToMessageId?: Id<"messages">` (optional threading)
- `clientMessageId?: string` (optional idempotency from client)
- `createdAtMs: number`
- `editedAtMs?: number`
- `deletedAtMs?: number`

Indexes:
- by `roomId + createdAtMs` (primary pagination path)
- by `telespaceId + createdAtMs` (for telespace-wide activity)
- by `roomId + clientMessageId` (idempotency support; optional)

Invariants:
- `telespaceId` MUST match the room’s telespace id (validate on write).
- For `authorType="user"`: `authorUserId` required and must be a member with write permission.
- For `authorType="agent"`: `authorInstalledAgentId` required and must belong to the telespace.
- Max content length enforced server-side.

---

### 2.6 `installedAgents`
Purpose: “agents available in this telespace,” backed by WHS.

Fields:
- `_id: Id<"installedAgents">`
- `telespaceId: Id<"telespaces">`
- `displayName: string`
- `status: "installed" | "disabled" | "error"`
- WHS references (do not validate format beyond “string” in DB; validate in API layer):
  - `whsAgentId: string` (required; WebHost.Systems agent id)
  - `whsActiveDeploymentId?: string` (optional; snapshot at install time)
- `invokePolicy` (v1 minimal):
  - `allowInRooms: "all" | "allowlist"`
  - `allowedRoomIds?: Id<"rooms">[]`
- `config` (secret-free JSON):
  - `systemPrompt?: string` (bounded length, e.g., 8k chars)
  - `temperature?: number`
  - `maxSteps?: number`
  - `metadata?: object`
- `createdAtMs: number`
- `updatedAtMs: number`

Indexes:
- by `telespaceId + createdAtMs`
- by `telespaceId + whsAgentId` (optional; helps prevent duplicate installs)

Invariants:
- Install/uninstall MUST be restricted to `owner|admin`.
- `config` MUST NOT include secret values (best-effort validation: deny common key names like `apiKey`, `token`, `secret` unless explicitly allowed later).

---

### 2.7 `installedWorkflows`
Purpose: “workflows available in this telespace,” backed by Agentromatic.

Fields:
- `_id: Id<"installedWorkflows">`
- `telespaceId: Id<"telespaces">`
- `displayName: string`
- `status: "installed" | "disabled" | "error"`
- Agentromatic references:
  - `agentromaticWorkflowId: string` (required)
- Optional snapshot fields (recommended for debuggability, not required):
  - `workflowNameAtInstall?: string`
  - `workflowVersionHint?: string` (if Agentromatic adds versions later)
- `createdAtMs: number`
- `updatedAtMs: number`

Indexes:
- by `telespaceId + createdAtMs`
- by `telespaceId + agentromaticWorkflowId` (optional dedupe)

Invariants:
- Install/uninstall restricted to `owner|admin`.
- This table stores references only; the workflow definition lives in Agentromatic.

---

### 2.8 `automations`
Purpose: attach triggers inside a telespace to agent invocations and/or workflow executions.

Fields:
- `_id: Id<"automations">`
- `telespaceId: Id<"telespaces">`
- `enabled: boolean`
- `name: string`
- `trigger`:
  - `type: "room.message.created" | "room.member.joined" | "schedule.tick"` (v1 minimal)
  - `roomId?: Id<"rooms">` (required for message triggers)
  - `filters?: object` (secret-free; e.g., prefix match, mention match; keep simple)
- `actions: Array<...>` (ordered)
  - action union (v1):
    - `{ kind: "invoke_agent", installedAgentId: Id<"installedAgents">, inputTemplate?: object }`
    - `{ kind: "run_workflow", installedWorkflowId: Id<"installedWorkflows">, triggerDataTemplate?: object }`
- `rateLimit` (v1 minimal, optional):
  - `maxPerMinute?: number`
- `createdByUserId: Id<"users">`
- `createdAtMs: number`
- `updatedAtMs: number`
- `deletedAtMs?: number`

Indexes:
- by `telespaceId + createdAtMs`
- by `telespaceId + enabled`
- by `telespaceId + trigger.type`
- for message triggers: by `trigger.roomId + enabled` (implemented as denormalized index fields; see note below)

Implementation note (Convex indexing):
Convex indexes cannot index nested object keys unless you denormalize. Recommended denormalized fields:
- `triggerType: string` (copy of `trigger.type`)
- `triggerRoomId?: Id<"rooms">`
- `enabled: boolean` (already top-level)

Invariants:
- Creating/updating automations restricted to `owner|admin`.
- All referenced installs MUST belong to the same `telespaceId`.
- `triggerDataTemplate` and `inputTemplate` must be bounded and secret-free (best-effort).

---

### 2.9 `agentInvocations` (reference ledger)
Purpose: store references to WHS invocation attempts triggered from inside telespaces.

Fields:
- `_id: Id<"agentInvocations">`
- `telespaceId: Id<"telespaces">`
- `roomId?: Id<"rooms">`
- `installedAgentId: Id<"installedAgents">`
- `triggerEventId?: Id<"activityEvents">` (optional linkage)
- `requestedByUserId?: Id<"users">` (who triggered it; may be system/automation)
- `status: "queued" | "running" | "success" | "failed" | "canceled"`
- WHS references:
  - `whsTraceId?: string`
  - `whsSessionId?: string`
  - `whsInvocationRequestId?: string` (if WHS returns one)
- `startedAtMs: number`
- `completedAtMs?: number`
- `errorCode?: string`
- `errorMessage?: string` (safe, redacted, bounded length)
- `createdAtMs: number`

Indexes:
- by `telespaceId + createdAtMs desc`
- by `roomId + createdAtMs desc` (for room timeline)

Invariants:
- Must not store raw tool traces or secret values.
- Error message must be safe for UI (no secrets).

---

### 2.10 `workflowRuns` (reference ledger)
Purpose: store references to Agentromatic workflow executions triggered from telespaces.

Fields:
- `_id: Id<"workflowRuns">`
- `telespaceId: Id<"telespaces">`
- `roomId?: Id<"rooms">`
- `installedWorkflowId: Id<"installedWorkflows">`
- `triggerEventId?: Id<"activityEvents">`
- `requestedByUserId?: Id<"users">`
- Agentromatic references:
  - `agentromaticExecutionId?: string` (set once created)
  - `agentromaticWorkflowId: string` (denormalized convenience)
- `status: "queued" | "running" | "success" | "failed" | "canceled"`
- `startedAtMs: number`
- `completedAtMs?: number`
- `errorCode?: string`
- `errorMessage?: string` (safe, bounded)
- `createdAtMs: number`

Indexes:
- by `telespaceId + createdAtMs desc`
- by `roomId + createdAtMs desc`

Invariants:
- References must be consistent with `installedWorkflowId`.
- Do not store raw execution logs here; those live in Agentromatic.

---

### 2.11 `activityEvents` (append-only audit/timeline)
Purpose: a unified, secret-free activity stream suitable for UI timelines.

Fields:
- `_id: Id<"activityEvents">`
- `telespaceId: Id<"telespaces">`
- `roomId?: Id<"rooms">`
- `type: string` (v1 enumerations below)
- `actor`:
  - `type: "user" | "agent" | "system"`
  - `userId?: Id<"users">`
  - `installedAgentId?: Id<"installedAgents">`
- `summary: string` (bounded, secret-free)
- `refs?: object` (ids only; secret-free)
  - e.g. `{ messageId, agentInvocationId, workflowRunId }`
- `dedupeKey?: string` (idempotency; optional)
- `createdAtMs: number`

Indexes:
- by `telespaceId + createdAtMs desc`
- by `roomId + createdAtMs desc`
- by `telespaceId + dedupeKey` (optional for idempotency)

Invariants:
- Append-only: activity events MUST NOT be mutated except in rare admin repair flows.
- `summary` must be secret-free; never copy message content verbatim unless redacted and explicitly allowed.

Recommended `type` enum (v1):
- `telespace.created`
- `telespace.updated`
- `room.created`
- `room.deleted`
- `member.invited`
- `member.joined`
- `member.removed`
- `message.posted`
- `message.edited`
- `automation.created`
- `automation.updated`
- `automation.triggered`
- `agent.invocation.started`
- `agent.invocation.completed`
- `workflow.run.started`
- `workflow.run.completed`

---

## 3) Access control requirements (normative)

### 3.1 Global rule (must)
Every query/mutation/action MUST:
1. Resolve current user (auth) → `users._id`.
2. Enforce **telespace membership** for any operation referencing a telespace/room/message.
3. Enforce **role-based permissions** for writes and installs.

### 3.2 Membership check (must)
A request is authorized for a telespace if:
- `telespaces.ownerUserId === currentUserId`, OR
- there exists `telespaceMembers` row with:
  - `telespaceId` and `userId=currentUserId` and `status="active"`

Room access is granted if telespace access is granted (v1).
Future: room-level membership/permissions can be introduced as an extension.

### 3.3 Write permissions (v1)
Minimum required:
- Post message: `owner|admin|member`
- Edit/delete message: message author OR `owner|admin`
- Create room: `owner|admin|member` (or restrict to admin if desired)
- Install/uninstall agent/workflow: `owner|admin`
- Create/update automation: `owner|admin`
- Manage members (invite/remove/promote): `owner|admin` (owner for role changes recommended)

### 3.4 Confused deputy protection (must)
When running automations:
- Validate trigger authorizations at **trigger time**:
  - if automation triggers from a message event, the triggering message must be in a room in the telespace
  - the automation must be enabled and belong to the telespace
- Validate action references:
  - `installedAgentId` / `installedWorkflowId` must belong to the same telespace
- Record attribution:
  - `requestedByUserId` for user-triggered
  - `actor.type="system"` for automation-triggered (and store `automationId` in refs)

---

## 4) Deletion and retention semantics (normative)

### 4.1 Soft delete (recommended)
Use soft delete for:
- `telespaces`
- `rooms`
- `automations`

Reason: preserves auditability and prevents “dangling timeline” confusion.

### 4.2 Messages deletion (v1 recommendation)
Message deletion options:
- Soft delete by setting `deletedAtMs` and replacing `content` with a tombstone (optional).
- Or keep content and mark deleted (higher risk for privacy).

Recommended v1:
- set `deletedAtMs`
- replace `content` with `"(deleted)"` unless you need edit history (not required in v1)

### 4.3 Retention
Default v1 retention recommendations (can be “no retention job” initially, but define intent):
- `messages`: retain 180 days (or indefinitely for MVP if cost acceptable)
- `activityEvents`: retain 365 days (or indefinitely)
- `agentInvocations` / `workflowRuns`: retain 180 days

If implementing retention:
- prefer scheduled jobs that delete old records by `createdAtMs`
- ensure deletion does not break referential integrity in UI (show “(expired)” refs)

---

## 5) Indexing guidance (Convex-specific)

### 5.1 Message pagination (required)
Primary read path:
- `messages` by `roomId + createdAtMs`

Implementation notes:
- For reverse pagination (“newest first”), query descending if supported, or query ascending with cursors and reverse client-side.
- Avoid fetching by telespace unless implementing global search.

### 5.2 Activity timeline (recommended)
Use `activityEvents` by `roomId + createdAtMs desc` for room timeline UI.
Use `activityEvents` by `telespaceId + createdAtMs desc` for space-wide timeline.

### 5.3 Automation trigger lookups (required for performance)
For message triggers, you need:
- list enabled automations for `(telespaceId, triggerType="room.message.created", triggerRoomId=<roomId>)`.

Denormalize fields:
- `triggerType`
- `triggerRoomId`

Then index:
- `triggerRoomId + enabled + triggerType` (or `telespaceId + triggerRoomId + enabled`, depending on your query shape)

---

## 6) Validation requirements (must)

### 6.1 Schema validation
All mutations must validate inputs:
- types and required fields
- max lengths and payload sizes
- enumerations

Recommended: share Zod schemas between UI and Convex if you have a monorepo shared package.

### 6.2 Cross-table invariants
On writes:
- `messages.telespaceId` must match `rooms.telespaceId`
- membership must exist and be active (unless owner)
- `installedAgents.telespaceId` matches `automations.telespaceId` references
- `installedWorkflows.telespaceId` matches `automations.telespaceId` references

### 6.3 Idempotency
Recommended idempotency points:
- message creation: `(roomId, clientMessageId)` if provided
- activity events: `dedupeKey` for events triggered by automations
- automation triggers: create a per-trigger `dedupeKey`:
  - e.g., `automation:<automationId>:event:<messageId>` to prevent double-run

---

## 7) Integration reference conventions (Agentromatic + WHS)

### 7.1 Agentromatic references
Agentelic should store only:
- `agentromaticWorkflowId` (string)
- `agentromaticExecutionId` (string)

Do not copy workflow definitions or execution logs into Agentelic.

### 7.2 WHS references
Agentelic should store only:
- `whsAgentId` (string)
- `whsActiveDeploymentId` (optional string hint)
- `whsTraceId`, `whsSessionId`, `whsInvocationRequestId` as returned by WHS invocation APIs

Do not store WHS secrets or tokens.

---

## 8) Minimal v1 schema checklist (Definition of Done for data model)
You have a v1-capable Agentelic data model when:
- [ ] You can create a telespace and list telespaces for a user.
- [ ] You can add members and enforce membership checks.
- [ ] You can create rooms and paginate messages by room.
- [ ] You can install an agent and a workflow into a telespace (references only).
- [ ] You can create an automation that triggers on `room.message.created`.
- [ ] You can record references to agent invocations and workflow executions.
- [ ] You can render a room activity timeline from `activityEvents`.
- [ ] You have at least 3 IDOR tests validating:
  - cannot read telespace/room/messages without membership
  - cannot write message without membership + role
  - cannot install automations in a telespace you don’t belong to

---