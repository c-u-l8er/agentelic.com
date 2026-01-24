# Agentelic v1 — Spec-to-Implementation Realignment Plan
Version: 1.0  
Status: Actionable checklist  
Audience: Engineering  
Last updated: 2026-01-24

This document is a **spec-to-implementation realignment checklist** for Agentelic v1. It is written to be executed even if the only “truth” you have is what’s in `project_spec/` and whatever already exists in the codebase.

It focuses on closing gaps between:
- `spec_v1/00_MASTER_SPEC.md`
- `spec_v1/10_API_CONTRACTS.md`
- `spec_v1/30_DATA_MODEL_CONVEX.md`
- `spec_v1/40_SECURITY_SECRETS_COMPLIANCE.md`
- `spec_v1/60_TESTING_ACCEPTANCE.md`

---

## 0) One-time decisions to lock (to prevent drift)

### D0.1 Canonical ID/identity rule (portfolio-shared)
Decide and document (here + in `10_API_CONTRACTS.md`) the mapping between:
- **External identity** (e.g., Clerk subject) → `externalId` (string)
- **Internal user row** → `users._id` (Convex `Id<"users">`)
- **API IDs**: whether you expose Convex IDs directly as strings or use prefixed IDs (`ts_...`, `room_...`).

**Acceptance (required):**
- Every endpoint and every table uses the same concept for each of:
  - `externalId` (auth provider subject)
  - `userId` (internal user table id)
  - `telespaceId` / `roomId` / `messageId` (internal ids)

### D0.2 “Org linkage” semantics (Agentelic ↔ Delegatic)
Agentelic v1 supports `Telespace.orgId` as an **optional reference** (linking/grouping only). It MUST NOT act as authorization.

**Acceptance (required):**
- You can create a telespace with or without `orgId`.
- Setting `orgId` does not grant access to anyone; telespace membership remains the only gate for rooms/messages.

---

## 1) Spec alignment matrix (what must match)

### 1.1 Roles (must be consistent everywhere)
Normative v1 roles:
- `owner` is derived from `telespaces.ownerUserId`
- membership roles are `admin | member | viewer`

**Required alignment:**
- `00_MASTER_SPEC.md`: MUST state the above.
- `10_API_CONTRACTS.md`: MUST list `admin|member|viewer` in membership responses.
- `30_DATA_MODEL_CONVEX.md`: MUST store roles as the above (with `owner` derived).

### 1.2 Event types (split “automation triggers” vs “activity types”)
Agentelic uses events in two distinct ways:

1) **Automation trigger event types (stable & narrow)**  
Minimum v1 triggers:
- `room.message.created`
- `room.member.joined`
- `room.member.left`

2) **Activity timeline item types (broader)**  
May include installs/invocations/workflow triggers and system events.

**Required alignment:**
- `10_API_CONTRACTS.md` MUST clearly separate these lists and avoid implying that all activity types are automatable triggers.

### 1.3 Error strategy (IDOR-safe)
Agentelic MUST be consistent about whether cross-tenant IDs return:
- `NOT_FOUND` (recommended), or
- `UNAUTHORIZED`.

**Required alignment:**
- `10_API_CONTRACTS.md` and `40_SECURITY_SECRETS_COMPLIANCE.md` MUST match.
- Implementation MUST follow one strategy everywhere.

---

## 2) Data model realignment checklist (Convex)

> Target doc: `spec_v1/30_DATA_MODEL_CONVEX.md` (normative)

### 2.1 `users`
- [ ] Ensure a `users` table exists with:
  - `externalId` (unique)
  - timestamps
- [ ] Implement a single helper to resolve current user:
  - `getOrCreateUserByExternalId(externalId)` (server-only)

**Acceptance:**
- Every mutation/query that needs auth begins by resolving `users._id`.

### 2.2 `telespaces`
- [ ] Ensure `telespaces` has:
  - `ownerUserId: Id<"users">`
  - `orgId?: string` (optional Delegatic reference; opaque string)
  - `name`, `description?`, timestamps, `deletedAtMs?`

**Acceptance:**
- `orgId` can be null/absent without breaking list/get.
- Telepace access ignores `orgId` for authorization decisions.

### 2.3 `telespaceMembers`
- [ ] Enforce uniqueness: only one active membership per `(telespaceId, userId)`.
- [ ] Derive owner permissions from `telespaces.ownerUserId`, not from membership rows.

**Acceptance:**
- You cannot create duplicate active membership entries.
- Removing the owner’s membership row (if it exists) does not “de-owner” the telespace; ownership is the telespace field.

### 2.4 `rooms`, `messages`
- [ ] Rooms must be scoped to a telespace and soft-deletable.
- [ ] Messages must be scoped to a room + telespace and support pagination indexes.

**Acceptance:**
- Message listing is performant and stable under pagination (no duplicates/missing under normal append-only usage).

### 2.5 Installations & automation tables
- [ ] `installedAgents`: references WHS (`whsAgentId`, optional `whsDeploymentId`), per telespace
- [ ] `installedWorkflows`: references Agentromatic (`agentromaticWorkflowId`), per telespace
- [ ] `automations`: event trigger + actions (agent invocation/workflow run)
- [ ] `agentInvocations` and `workflowRuns` reference ledgers exist as append-only records
- [ ] `activityEvents` exists as append-only timeline (secret-free summaries + refs)

**Acceptance:**
- Installing/uninstalling always emits an activity event.
- Triggering an automation always emits an activity event (success or failure), even if upstream fails.

---

## 3) API realignment checklist (HTTP contracts)

> Target doc: `spec_v1/10_API_CONTRACTS.md` (normative)

### 3.1 Ensure API and data model match fields
- [ ] `Telespace.orgId` is optional in API and optional in DB
- [ ] membership roles include `admin|member|viewer` (owner derived)
- [ ] `InstalledAgent` includes policy fields; ensure defaults are documented

**Acceptance:**
- A serialized telespace returned by API can be round-tripped into DB fields without inventing fields.

### 3.2 Idempotency
- [ ] Document which endpoints accept an idempotency key (recommended for:
  - message create
  - automation creation
  - workflow trigger / agent invocation)
- [ ] Implementation should dedupe by stable key where retries are expected.

**Acceptance:**
- Retried requests do not create duplicate messages/automation runs.

### 3.3 Upstream bridge contracts
- [ ] For WHS invocation:
  - include stable `traceId`
  - include metadata linking `{telespaceId, roomId, messageId, automationId}`
- [ ] For Agentromatic execution:
  - include a derived idempotency key based on `(automation/action, eventId)`
  - keep `triggerData` bounded and secret-free

**Acceptance:**
- A single room message event cannot cause duplicate upstream calls when retried.

---

## 4) Security realignment checklist

> Target docs: `spec_v1/40_SECURITY_SECRETS_COMPLIANCE.md` and relevant sections of `10_API_CONTRACTS.md`

### 4.1 “Secrets rule” clarity
- [ ] Never store platform-managed secrets (tokens/API keys) in Agentelic tables.
- [ ] Treat messages as user content that MAY contain secrets.
- [ ] Derived records (activity summaries, automation payload mirrors) MUST be redacted/truncated.

**Acceptance:**
- No table field is designed to hold credentials.
- Activity items and error envelopes never include Authorization headers, API keys, cookies, raw OAuth tokens.

### 4.2 Confused deputy protections
- [ ] Automation triggers must be server-side only (recommended)
- [ ] Automations must be scoped to telespace, and actions must be bounded (rate limits, max actions)
- [ ] “Installed agent/workflow” operations require `owner|admin`

**Acceptance:**
- A `member` cannot install an agent/workflow, and cannot create automations (unless explicitly allowed).

### 4.3 Error strategy
- [ ] Choose and enforce a single IDOR strategy:
  - recommended: cross-tenant IDs return `NOT_FOUND`

**Acceptance:**
- “Get message by id” cannot be used to enumerate other tenants.

---

## 5) Runtime behavior realignment checklist (what code must do)

### 5.1 Posting a message
- [ ] Validate membership
- [ ] Persist message
- [ ] Emit activity event `room.message.created`
- [ ] Compute `eventId` and evaluate automations subscribed to that event
- [ ] Trigger actions with dedupe keys and bounded retries
- [ ] Record outcomes as activity events (success/failure; secret-free)

**Acceptance:**
- Golden path: message → automation triggers → activity shows what happened.

### 5.2 Automation dedupe (minimum viable)
Recommended uniqueness key:
- `(eventId, automationId, actionIndex)` OR `(telespaceId, eventId, automationId, actionIndex)`

**Acceptance:**
- Same event processed twice does not double-trigger side effects.

---

## 6) Testing realignment checklist (Definition of Done drivers)

> Target doc: `spec_v1/60_TESTING_ACCEPTANCE.md`

Minimum required tests to implement (even if lightweight):

### 6.1 Tenant isolation / IDOR
- [ ] Cannot read telespace/room/message by id without membership
- [ ] Cannot list rooms/messages/activity for a telespace without membership

### 6.2 Membership enforcement
- [ ] Non-member cannot post message
- [ ] Member cannot mutate installations/automations unless `admin|owner`

### 6.3 Automation dedupe
- [ ] Same event does not trigger duplicate workflow run or agent invocation

### 6.4 Reference integrity
- [ ] Stored invocation/workflow references are scoped to the same telespace and are not writable cross-telespace

---

## 7) “If libs disagree with spec” procedure (what to change, in what order)

When you find drift between code and spec, apply this order of operations:

1. **If drift affects security/tenant isolation:** change code first to satisfy spec.  
2. **If drift is naming/shape only:** prefer changing spec examples to match established code *if* semantics remain unchanged.  
3. **If drift changes semantics:** write an ADR and update both spec and code to the new decision.

---

## 8) Output artifacts (what you should produce after executing this plan)

- A short PR/commit that:
  - (A) updates the Convex schema / validators to match `30_DATA_MODEL_CONVEX.md`
  - (B) updates API handlers to match `10_API_CONTRACTS.md`
  - (C) adds/updates tests to satisfy `60_TESTING_ACCEPTANCE.md`
- Updated spec files if you consciously change any semantics (with an ADR if needed)

---

## 9) Known current spec gaps this plan explicitly closes

- Adds `telespaces.orgId?: string` to the data model (to match API `orgId`).
- Normalizes membership role language (`admin|member|viewer`, owner derived).
- Ensures event model is not confused between “automation triggers” and “activity types”.
- Ensures secret-free rule is applied to derived artifacts, not user messages.

---