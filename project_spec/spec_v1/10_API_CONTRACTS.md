# agentelic — API Contracts (v1)
Version: 1.0  
Status: Draft (normative once implemented)  
Audience: Engineering (backend + frontend)  
Last updated: 2026-01-24

This document defines the **API contracts** for **Agentelic** (telespaces) in an implementation-ready way:
- request/response envelopes
- normalized errors
- auth/tenancy rules
- resource shapes
- endpoints for telespaces, rooms, messages, installations, automations, and activity

Agentelic integration intent:
- **Agentromatic** owns workflows/executions/logs; Agentelic stores **references** and triggers runs.
- **WebHost.Systems (WHS)** owns agents/deploy/invoke/telemetry; Agentelic stores **references** and triggers invocations.
- **Delegatic** owns org containment and governance; Agentelic supports optional `orgId` and policy hooks.

---

## 1) Principles

### 1.1 Control vs execution (hard rule)
Agentelic is a **collaboration + routing** product:
- It stores telespace/room/message data.
- It triggers external execution:
  - WHS agent invocations
  - Agentromatic workflow executions

Agentelic MUST NOT re-implement:
- workflow execution engines (Agentromatic owns)
- runtime provider adapters (WHS owns)

### 1.2 Stability rules
- Contracts MUST be versioned under `/v1`.
- Additive changes are preferred:
  - new optional fields
  - new endpoints
- Breaking changes MUST be introduced as `/v2` or explicitly versioned resources.

### 1.3 Error consistency (required)
All non-2xx responses MUST use the normalized error envelope in §3.

### 1.4 Pagination (required)
List endpoints MUST support cursor pagination:
- request: `limit` + optional `cursor`
- response: `items` + optional `nextCursor`

### 1.5 Idempotency (required for writes that can be retried)
For endpoints that create a durable record or trigger external work, clients SHOULD send an idempotency key:
- `Idempotency-Key: <opaque string>`

Server MUST ensure:
- same idempotency key + same authenticated user + same endpoint semantics ⇒ returns the same result
- idempotency keys do not leak across tenants

### 1.6 Time representation
- Store and return timestamps as `...AtMs` (epoch milliseconds) for simplicity.
- If you also return ISO strings, they MUST be derived and consistent.

---

## 2) Common types

### 2.1 IDs
All IDs are opaque strings:
- `telespaceId`, `roomId`, `messageId`
- `installedAgentId`, `installedWorkflowId`, `automationId`
- `activityId` (or `eventId`)

Cross-system references:
- `whsAgentId` (WebHost.Systems agent id)
- `whsDeploymentId` (optional; if pinning a specific deployment)
- `agentromaticWorkflowId`
- `agentromaticExecutionId`

### 2.2 Roles
#### 2.2.1 Telespace membership roles (v1)
`TelespaceRole`:
- `owner` (full control)
- `admin` (manage rooms/installations/automations)
- `member` (post messages, read history, invoke allowed agents/workflows per policy)
- `viewer` (read-only)

Role semantics are defined in §4 (AuthZ rules).

### 2.3 Pagination
`PageCursor` is an opaque string.
The server may encode offsets, last-seen ids, or timestamps. Clients MUST treat it as opaque.

`Page<T>` response shape:
~~~json
{
  "items": [],
  "nextCursor": "string or null"
}
~~~

### 2.4 Content limits (recommended baseline)
Server SHOULD enforce:
- message content max: 20_000 chars (text)
- event payload max: 32 KB (JSON after serialization)
- automation trigger data max: 32 KB (JSON after serialization)
- headers/body snippets stored for errors/log summaries MUST be bounded

---

## 3) Normalized errors (REQUIRED)

### 3.1 Error envelope
All non-2xx responses MUST be:
~~~json
{
  "error": {
    "code": "STRING_ENUM",
    "message": "Safe, user-displayable summary",
    "requestId": "opaque string",
    "details": {
      "hint": "optional safe hint",
      "fields": {
        "fieldName": "optional field-level error"
      }
    }
  }
}
~~~

### 3.2 Error codes (v1)
Agentelic MUST use these codes (additive allowed):

Auth:
- `UNAUTHENTICATED`
- `UNAUTHORIZED`

Resource:
- `NOT_FOUND`
- `CONFLICT` (e.g., name collisions, idempotency conflicts)
- `INVALID_REQUEST` (schema/validation failure)

Limits:
- `RATE_LIMITED`
- `LIMIT_EXCEEDED` (plan/entitlement or server-set limits)

Execution/integration:
- `UPSTREAM_ERROR` (WHS/Agentromatic failed)
- `UPSTREAM_TIMEOUT`
- `AUTOMATION_DISABLED`

Server:
- `INTERNAL_ERROR`

### 3.3 Validation errors
On validation failure, `details.fields` SHOULD be populated with stable keys.
Example:
~~~json
{
  "error": {
    "code": "INVALID_REQUEST",
    "message": "Invalid message payload",
    "requestId": "req_...",
    "details": {
      "fields": {
        "content": "Required",
        "roomId": "Invalid format"
      }
    }
  }
}
~~~

---

## 4) Authentication & Authorization

### 4.1 Authentication
All endpoints (except future public webhooks) require an authenticated caller.

Recommended (portfolio-aligned) mechanism:
- `Authorization: Bearer <Clerk JWT>`

### 4.2 Tenant isolation (hard rule)
Every row and every operation MUST be tenant-isolated. In v1, the default tenant is the authenticated **user**.

If an optional `orgId` is present (Delegatic integration), tenant isolation must be enforced by:
- verifying the caller has membership in that org (Delegatic-provided check or replicated membership table)
- enforcing org-level policy constraints

### 4.3 Telespace access rules (v1 baseline)
- To read a telespace/room/messages, the caller MUST be a telespace member.
- To mutate telespace settings / install agents/workflows / manage automations:
  - role MUST be `owner` or `admin` (unless otherwise specified)
- To invite/remove members:
  - role MUST be `owner` or `admin`
  - `owner` role transfers are out of scope in v1 (optional post-v1)

### 4.4 Defense-in-depth (recommended)
Even when integrated with Delegatic:
- Agentelic MUST still enforce telespace membership checks, not rely solely on Delegatic.

---

## 5) Resource shapes (v1)

### 5.1 Telespace
~~~json
{
  "telespaceId": "ts_...",
  "orgId": "org_... (optional)",
  "name": "string",
  "description": "string or null",
  "createdAtMs": 0,
  "updatedAtMs": 0,
  "archivedAtMs": 0,
  "defaults": {
    "messageRetentionDays": 30,
    "allowGuestInvites": false
  }
}
~~~

Notes:
- `archivedAtMs` null/absent means active.
- `defaults` can be expanded additively.

### 5.2 Room
~~~json
{
  "roomId": "room_...",
  "telespaceId": "ts_...",
  "name": "string",
  "topic": "string or null",
  "type": "channel | thread",
  "createdAtMs": 0,
  "updatedAtMs": 0,
  "archivedAtMs": 0
}
~~~

### 5.3 Message
Message content is text-first in v1.
~~~json
{
  "messageId": "msg_...",
  "telespaceId": "ts_...",
  "roomId": "room_...",
  "author": {
    "type": "user | agent | system",
    "userId": "optional",
    "installedAgentId": "optional"
  },
  "content": {
    "type": "text",
    "text": "string"
  },
  "metadata": {
    "clientMessageId": "optional",
    "replyToMessageId": "optional"
  },
  "createdAtMs": 0,
  "editedAtMs": 0,
  "deletedAtMs": 0
}
~~~

### 5.4 InstalledAgent (WHS reference)
An installed agent represents making a WHS agent available inside a telespace.
~~~json
{
  "installedAgentId": "ia_...",
  "telespaceId": "ts_...",
  "displayName": "string",
  "whsAgentId": "string",
  "whsDeploymentId": "string or null",
  "status": "enabled | disabled",
  "policy": {
    "allowedInRoomIds": ["room_..."],
    "allowUserInvoke": true,
    "maxInvocationsPerMinute": 20
  },
  "createdAtMs": 0,
  "updatedAtMs": 0
}
~~~

Notes:
- If `whsDeploymentId` is null, invocations should route to the WHS agent’s active deployment.
- `policy` is an Agentelic-level safety restriction; it MUST NOT widen access beyond WHS entitlements.

### 5.5 InstalledWorkflow (Agentromatic reference)
An installed workflow represents attaching an Agentromatic workflow to a telespace for visibility/automation.
~~~json
{
  "installedWorkflowId": "iw_...",
  "telespaceId": "ts_...",
  "displayName": "string",
  "agentromaticWorkflowId": "string",
  "status": "enabled | disabled",
  "createdAtMs": 0,
  "updatedAtMs": 0
}
~~~

### 5.6 Automation
An automation binds an Agentelic event to an action: invoke agent and/or run workflow.
~~~json
{
  "automationId": "auto_...",
  "telespaceId": "ts_...",
  "name": "string",
  "status": "enabled | disabled",
  "trigger": {
    "eventType": "room.message.created | room.member.joined | ...",
    "roomId": "optional room scope",
    "filter": {
      "messageContains": "optional substring",
      "authorTypeIn": ["user"]
    }
  },
  "actions": [
    {
      "type": "invokeAgent",
      "installedAgentId": "ia_...",
      "inputTemplate": {
        "mode": "messages",
        "system": "optional system prompt string",
        "user": "optional template string"
      }
    },
    {
      "type": "runWorkflow",
      "installedWorkflowId": "iw_...",
      "triggerDataTemplate": {
        "mode": "json",
        "template": { "event": "..." }
      }
    }
  ],
  "createdAtMs": 0,
  "updatedAtMs": 0
}
~~~

Notes:
- Templates MUST be deterministic and bounded. v1 MAY start with “pass-through event payload” only.

### 5.7 Activity item (unified room timeline)
Activity is the merged feed of: messages, invocations, workflow runs, and system events.
~~~json
{
  "activityId": "act_...",
  "telespaceId": "ts_...",
  "roomId": "room_...",
  "type": "message | agent_invocation | workflow_execution | system_event",
  "createdAtMs": 0,
  "summary": "string",
  "refs": {
    "messageId": "optional",
    "installedAgentId": "optional",
    "whsAgentId": "optional",
    "invocationTraceId": "optional",
    "installedWorkflowId": "optional",
    "agentromaticWorkflowId": "optional",
    "agentromaticExecutionId": "optional"
  },
  "payload": {
    "bounded": "object"
  }
}
~~~

---

## 6) Endpoints (HTTP form, v1)

Base path:
- `/v1`

All requests:
- MUST include `Authorization: Bearer <JWT>`
- SHOULD include `Idempotency-Key` for create/trigger endpoints

All responses:
- success: 2xx with JSON body
- error: non-2xx with §3 error envelope

### 6.1 Telespaces

#### 6.1.1 Create telespace
`POST /v1/telespaces`

Request:
~~~json
{
  "name": "string",
  "description": "string or null",
  "orgId": "string or null"
}
~~~

Response:
~~~json
{
  "telespace": { "telespaceId": "ts_...", "name": "..." }
}
~~~

AuthZ:
- any authenticated user can create (org checks optional if `orgId` provided)

Idempotency:
- RECOMMENDED via `Idempotency-Key`

#### 6.1.2 List telespaces
`GET /v1/telespaces?limit=50&cursor=...`

Response:
~~~json
{
  "items": [{ "telespaceId": "ts_...", "name": "..." }],
  "nextCursor": "string or null"
}
~~~

AuthZ:
- returns telespaces where caller is a member (or owner)

#### 6.1.3 Get telespace
`GET /v1/telespaces/:telespaceId`

Response:
~~~json
{ "telespace": { } }
~~~

AuthZ:
- member required

#### 6.1.4 Update telespace
`PATCH /v1/telespaces/:telespaceId`

Request (patch):
~~~json
{
  "name": "string (optional)",
  "description": "string or null (optional)",
  "defaults": {
    "messageRetentionDays": 30
  }
}
~~~

Response:
~~~json
{ "ok": true }
~~~

AuthZ:
- `owner` or `admin`

#### 6.1.5 Archive telespace (optional v1)
`POST /v1/telespaces/:telespaceId/archive`

Response:
~~~json
{ "ok": true }
~~~

AuthZ:
- `owner` only (recommended)

---

### 6.2 Membership & invites (v1 minimal)

#### 6.2.1 List members
`GET /v1/telespaces/:telespaceId/members?limit=200&cursor=...`

Response:
~~~json
{
  "items": [
    { "userId": "u_...", "role": "owner", "joinedAtMs": 0 }
  ],
  "nextCursor": "string or null"
}
~~~

AuthZ:
- member required (or `admin` only; choose and be consistent; recommended: member can list)

#### 6.2.2 Invite by email (optional v1)
`POST /v1/telespaces/:telespaceId/invites`

Request:
~~~json
{
  "email": "string",
  "role": "admin | member | viewer"
}
~~~

Response:
~~~json
{
  "invite": {
    "inviteId": "inv_...",
    "telespaceId": "ts_...",
    "email": "string",
    "role": "member",
    "status": "pending",
    "createdAtMs": 0
  }
}
~~~

AuthZ:
- `owner` or `admin`

Security notes:
- avoid leaking whether an email exists as an account in error messages

#### 6.2.3 Accept invite (optional v1)
`POST /v1/telespaces/:telespaceId/invites/:inviteId/accept`

Response:
~~~json
{ "ok": true }
~~~

AuthZ:
- caller must match invite email/identity per implementation rules

#### 6.2.4 Remove member
`DELETE /v1/telespaces/:telespaceId/members/:userId`

Response:
~~~json
{ "ok": true }
~~~

AuthZ:
- `owner` or `admin`
- MUST NOT allow removing the last owner in v1

---

### 6.3 Rooms

#### 6.3.1 Create room
`POST /v1/telespaces/:telespaceId/rooms`

Request:
~~~json
{
  "name": "string",
  "topic": "string or null",
  "type": "channel | thread"
}
~~~

Response:
~~~json
{ "room": { "roomId": "room_...", "telespaceId": "ts_..." } }
~~~

AuthZ:
- `owner`/`admin` (recommended), or allow `member` for v1 (pick one)

Idempotency:
- recommended

#### 6.3.2 List rooms
`GET /v1/telespaces/:telespaceId/rooms?limit=100&cursor=...`

Response:
~~~json
{ "items": [{ "roomId": "room_...", "name": "..." }], "nextCursor": null }
~~~

AuthZ:
- member required

#### 6.3.3 Get room
`GET /v1/rooms/:roomId`

Response:
~~~json
{ "room": { } }
~~~

AuthZ:
- member of the room’s telespace required

#### 6.3.4 Update room (optional v1)
`PATCH /v1/rooms/:roomId`

Request:
~~~json
{
  "name": "string (optional)",
  "topic": "string or null (optional)",
  "archivedAtMs": 0
}
~~~

Response:
~~~json
{ "ok": true }
~~~

AuthZ:
- `owner`/`admin`

---

### 6.4 Messages

#### 6.4.1 Post message
`POST /v1/rooms/:roomId/messages`

Request:
~~~json
{
  "content": { "type": "text", "text": "string" },
  "metadata": { "clientMessageId": "optional", "replyToMessageId": "optional" }
}
~~~

Response:
~~~json
{ "message": { "messageId": "msg_...", "roomId": "room_..." } }
~~~

AuthZ:
- telespace member with role `member+` required

Idempotency:
- STRONGLY recommended using `Idempotency-Key` (or `metadata.clientMessageId` if you choose to support it)

#### 6.4.2 List messages
`GET /v1/rooms/:roomId/messages?limit=50&cursor=...`

Optional filters (server MAY support):
- `beforeAtMs`
- `afterAtMs`

Response:
~~~json
{ "items": [{ "messageId": "msg_...", "content": { "type": "text", "text": "..." } }], "nextCursor": "..." }
~~~

AuthZ:
- member required

#### 6.4.3 Edit message (optional v1)
`PATCH /v1/messages/:messageId`

Request:
~~~json
{
  "content": { "type": "text", "text": "new text" }
}
~~~

Response:
~~~json
{ "ok": true }
~~~

AuthZ:
- author is the caller OR `admin+` (recommended)
- edits MUST preserve auditability (keep original content in an internal audit log or store prior versions)

#### 6.4.4 Delete message (optional v1)
`DELETE /v1/messages/:messageId`

Response:
~~~json
{ "ok": true }
~~~

AuthZ:
- author OR `admin+`
- deletion SHOULD be soft-delete (set `deletedAtMs`)

---

### 6.5 Activity (unified timeline)

#### 6.5.1 List room activity
`GET /v1/rooms/:roomId/activity?limit=100&cursor=...`

Response:
~~~json
{
  "items": [
    { "activityId": "act_...", "type": "message", "refs": { "messageId": "msg_..." } }
  ],
  "nextCursor": "string or null"
}
~~~

AuthZ:
- member required

Notes:
- Activity MAY include the messages themselves, but SHOULD at least include references so the UI can render a consistent feed.

---

### 6.6 Installations — WHS agents

#### 6.6.1 Install a WHS agent into a telespace
`POST /v1/telespaces/:telespaceId/installedAgents`

Request:
~~~json
{
  "displayName": "string",
  "whsAgentId": "string",
  "whsDeploymentId": "string or null",
  "policy": {
    "allowedInRoomIds": ["room_..."],
    "allowUserInvoke": true,
    "maxInvocationsPerMinute": 20
  }
}
~~~

Response:
~~~json
{ "installedAgent": { "installedAgentId": "ia_...", "telespaceId": "ts_..." } }
~~~

AuthZ:
- `owner`/`admin`

Idempotency:
- recommended (install operations are commonly retried)

#### 6.6.2 List installed agents
`GET /v1/telespaces/:telespaceId/installedAgents?limit=200&cursor=...`

Response:
~~~json
{ "items": [{ "installedAgentId": "ia_...", "whsAgentId": "..." }], "nextCursor": null }
~~~

AuthZ:
- member required (or `admin+` only; pick one; recommended: member can view what is installed)

#### 6.6.3 Uninstall agent
`DELETE /v1/telespaces/:telespaceId/installedAgents/:installedAgentId`

Response:
~~~json
{ "ok": true }
~~~

AuthZ:
- `owner`/`admin`

---

### 6.7 Invocations — invoke installed WHS agent from a room

#### 6.7.1 Invoke agent (non-streaming)
`POST /v1/rooms/:roomId/agents/:installedAgentId/invoke`

Request:
~~~json
{
  "input": {
    "messages": [
      { "role": "user", "content": "Hello" }
    ]
  },
  "sessionId": "optional opaque string",
  "metadata": {
    "traceId": "optional",
    "source": "room_ui"
  }
}
~~~

Response:
~~~json
{
  "result": {
    "output": { "text": "string" },
    "sessionId": "string or null",
    "traceId": "string"
  },
  "activity": {
    "activityId": "act_..."
  }
}
~~~

AuthZ:
- telespace member required
- MUST enforce installed-agent policy:
  - `status=enabled`
  - room allowed (if restricted)
  - `allowUserInvoke=true` if caller is a user
  - rate limits / quotas (as implemented)

Integration requirement:
- Agentelic MUST normalize WHS failures into `UPSTREAM_ERROR` / `UPSTREAM_TIMEOUT`.

Idempotency:
- recommended (invocations can be retried by clients on network failures)

#### 6.7.2 Invoke agent (streaming; SSE) (optional v1)
`POST /v1/rooms/:roomId/agents/:installedAgentId/invoke/stream`

Response: SSE stream of events.
Event shapes SHOULD align with WHS `invoke/v1` SSE model if used, but Agentelic may wrap it.

---

### 6.8 Installations — Agentromatic workflows

#### 6.8.1 Install a workflow into a telespace
`POST /v1/telespaces/:telespaceId/installedWorkflows`

Request:
~~~json
{
  "displayName": "string",
  "agentromaticWorkflowId": "string"
}
~~~

Response:
~~~json
{ "installedWorkflow": { "installedWorkflowId": "iw_...", "telespaceId": "ts_..." } }
~~~

AuthZ:
- `owner`/`admin`

Idempotency:
- recommended

#### 6.8.2 List installed workflows
`GET /v1/telespaces/:telespaceId/installedWorkflows?limit=200&cursor=...`

Response:
~~~json
{ "items": [{ "installedWorkflowId": "iw_...", "agentromaticWorkflowId": "..." }], "nextCursor": null }
~~~

AuthZ:
- member required (recommended)

#### 6.8.3 Uninstall workflow
`DELETE /v1/telespaces/:telespaceId/installedWorkflows/:installedWorkflowId`

Response:
~~~json
{ "ok": true }
~~~

AuthZ:
- `owner`/`admin`

---

### 6.9 Run workflow — trigger installed Agentromatic workflow from a room

#### 6.9.1 Run workflow (non-streaming)
`POST /v1/rooms/:roomId/workflows/:installedWorkflowId/run`

Request:
~~~json
{
  "triggerData": {
    "eventType": "room.message.created",
    "messageId": "msg_...",
    "text": "..."
  }
}
~~~

Response:
~~~json
{
  "result": {
    "agentromaticExecutionId": "string",
    "agentromaticWorkflowId": "string"
  },
  "activity": {
    "activityId": "act_..."
  }
}
~~~

AuthZ:
- telespace member required
- MUST enforce installed-workflow status and any per-workflow policy (if present)

Integration requirement:
- Agentelic MUST call Agentromatic using a server-side credentialed path (do not rely on clients calling Agentromatic directly if that breaks tenant isolation or identity mapping).
- Failures MUST be normalized as `UPSTREAM_ERROR` / `UPSTREAM_TIMEOUT`.

Idempotency:
- recommended

---

### 6.10 Automations (event → actions)

#### 6.10.1 Create automation
`POST /v1/telespaces/:telespaceId/automations`

Request:
~~~json
{
  "name": "string",
  "trigger": {
    "eventType": "room.message.created",
    "roomId": "optional",
    "filter": { "messageContains": "optional substring" }
  },
  "actions": [
    { "type": "invokeAgent", "installedAgentId": "ia_...", "inputTemplate": { "mode": "messages" } },
    { "type": "runWorkflow", "installedWorkflowId": "iw_...", "triggerDataTemplate": { "mode": "json", "template": {} } }
  ]
}
~~~

Response:
~~~json
{ "automation": { "automationId": "auto_..." } }
~~~

AuthZ:
- `owner`/`admin`

Idempotency:
- recommended

Validation rules (required):
- referenced `installedAgentId` / `installedWorkflowId` MUST belong to the same telespace
- action lists MUST be bounded (e.g., max 10 actions)
- templates MUST be bounded in size

#### 6.10.2 List automations
`GET /v1/telespaces/:telespaceId/automations?limit=200&cursor=...`

Response:
~~~json
{ "items": [{ "automationId": "auto_...", "name": "..." }], "nextCursor": null }
~~~

AuthZ:
- member required (or `admin+` only; recommended: member can view enabled automations)

#### 6.10.3 Update automation
`PATCH /v1/telespaces/:telespaceId/automations/:automationId`

Request:
~~~json
{
  "name": "string (optional)",
  "status": "enabled | disabled (optional)",
  "trigger": { "eventType": "..." },
  "actions": []
}
~~~

Response:
~~~json
{ "ok": true }
~~~

AuthZ:
- `owner`/`admin`

#### 6.10.4 Delete automation
`DELETE /v1/telespaces/:telespaceId/automations/:automationId`

Response:
~~~json
{ "ok": true }
~~~

AuthZ:
- `owner`/`admin`

---

## 7) Event triggering semantics (v1)

### 7.1 Canonical event types (minimum)
Agentelic MUST standardize these event type strings:
- `room.message.created`
- `room.member.joined`
- `room.member.left`

Agentelic MAY add:
- `room.message.edited`
- `telespace.created`
- `telespace.updated`

### 7.2 Dedupe / idempotency for automations
When an event occurs (e.g., message created) and automations are evaluated:
- Agentelic MUST compute/assign a stable `eventId` for dedupe.
- For each automation action triggered by an event, Agentelic MUST avoid double-triggering:
  - store `(eventId, automationId, actionIndex)` as a unique key (recommended)
  - or use a derived idempotency key when calling upstream systems

### 7.3 Failure handling
If one action in an automation fails:
- v1 recommended behavior: continue remaining actions unless policy says otherwise
- failures MUST be recorded as activity/system events (secret-free summaries)
- do not retry aggressively by default; apply bounded retries with backoff if implemented

---

## 8) Upstream integration contracts (bridges)

### 8.1 WHS invocation mapping (recommended)
Agentelic should call WHS invocation gateway with:
- a stable `traceId` (if provided)
- metadata linking back to:
  - `telespaceId`, `roomId`, `messageId`, `automationId` (where applicable)

Agentelic should store:
- returned `traceId` and `sessionId` (opaque)
- a bounded summary for activity feed (never secrets)

### 8.2 Agentromatic execution mapping (recommended)
Agentelic should trigger Agentromatic workflow execution with:
- `workflowId` = `agentromaticWorkflowId`
- `triggerData` derived from the room event (bounded, secret-free)
Agentelic should store:
- returned `executionId`
- link in the activity feed

---

## 9) Security requirements (API-level)

Required:
- Tenant isolation on every endpoint.
- Membership checks on every telespace/room/message read/write.
- Do not leak existence of resources across tenants:
  - return `NOT_FOUND` rather than `UNAUTHORIZED` for cross-tenant ids (recommended), but be consistent.
- No plaintext secrets in:
  - request/response bodies
  - error envelopes
  - activity payloads

Recommended:
- Rate limit:
  - message posting
  - agent invocation
  - workflow triggering
- Payload redaction best-effort for agent outputs (if you later persist transcripts).

---

## 10) Open questions (to resolve as ADRs)
These should become ADRs under `spec_v1/adr/`:

1. **API surface choice:** pure Convex functions vs Convex HTTP router vs separate web API.
2. **Identity linkage across products:** shared Clerk instance vs bridging tokens.
3. **Org containment semantics:** if `orgId` is present, who is the source of truth (Delegatic vs replicated)?
4. **Template language:** how automation templates are expressed (must be safe, deterministic, bounded).
5. **Activity feed storage:** store denormalized summaries vs dynamic joins.

---