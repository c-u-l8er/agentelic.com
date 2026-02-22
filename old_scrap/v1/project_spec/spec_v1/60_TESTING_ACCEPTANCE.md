# agentelic — Testing Plan & Acceptance Criteria (v1)
Version: 1.0  
Status: Normative (v1)  
Audience: Engineering (backend, frontend, infra)  
Last updated: 2026-01-24

This document defines the **minimum viable** testing strategy and **acceptance criteria** for Agentelic v1.

Agentelic context:
- **Agentelic** = telespaces (AI-enabled chatrooms)
- Telespaces can **contain**:
  - **WHS agents** (invoked inside rooms)
  - **Agentromatic workflows** (installed as automations; executions/logs referenced)

Agentelic MUST remain a composition layer:
- it does not reinvent workflow execution (Agentromatic owns that)
- it does not reinvent agent deployment/runtime (WHS owns that)

---

## 1) Testing philosophy (what we optimize for)

### 1.1 Priorities
1. **Tenant isolation correctness** (no cross-tenant reads/writes; no IDOR)
2. **Membership correctness** (room/telespace membership gates all access)
3. **Durable, auditable activity timeline** (messages + automation events + references)
4. **Idempotency and dedupe** (event triggers cannot double-run on retries)
5. **Safe integration** (Agentromatic + WHS integration failures degrade safely)

### 1.2 “Done” definition for v1
Agentelic v1 is considered “done” only when:
- the E2E flows in §5 pass on a clean environment
- all security-focused tests in §6 pass
- the release gates in §9 pass

### 1.3 Test pyramid (recommended)
- **Unit tests (required):** pure validation, permission checks, event dedupe logic
- **Integration tests (required):** database + API correctness, membership enforcement, pagination
- **End-to-end tests (required):** golden user journey across UI + backend, including integrations (mock or sandbox)

---

## 2) Environments & prerequisites

### 2.1 Environments
Agentelic SHOULD maintain three environments:
- **dev**: local developer iteration (may use dev-only flags)
- **staging**: production-like, used for E2E and release gates
- **prod**: hardened; dev-only flags MUST NOT be enabled

### 2.2 Identity and auth prerequisites
Assume an auth provider (recommended: Clerk) and a server-side identity mapping:
- `externalAuthId` (e.g., Clerk user id) maps to internal `users` table row(s)

Testing must validate:
- unauthenticated callers are rejected for protected endpoints
- authenticated callers are tenant-isolated

### 2.3 Integration prerequisites (staging)
Agentelic integrates with:
- **WHS (WebHost.Systems)** for agent invoke
- **Agentromatic** for workflow run + execution/log reference

For staging E2E, you may choose one of two strategies:

**Strategy A — Sandbox real integrations (preferred for at least 1 nightly run)**
- WHS: deploy a deterministic “echo” agent (or fixed template) that supports `invoke/v1`
- Agentromatic: ensure “execute workflow” stub exists and returns an execution id and logs

**Strategy B — Contract mocks (required for fast CI)**
- Provide mock adapters for WHS invoke and Agentromatic run APIs that:
  - behave deterministically
  - produce stable ids and timestamps (or controlled clocks)
  - simulate both success and failure

---

## 3) Unit test plan (required)

### 3.1 Validators and schema enforcement
Write unit tests for:
- `telespace` creation/update validation
  - name constraints
  - optional description constraints
- `room` creation validation
  - name constraints, type constraints (if any)
- `message` validation
  - payload size limits
  - allowed roles/types (`user`, `agent`, `system` if stored)
  - rejection of secret-like fields if the system enforces message redaction policies
- `installedAgent` validation
  - must reference a WHS `agentId` (opaque string)
  - optional `deploymentId` pinning rules (if supported)
- `installedWorkflow` validation
  - must reference an Agentromatic `workflowId`
  - automation trigger spec is valid (event types, filters, enabled flag)

Recommended minimum constraints:
- message body max size (e.g., 32KB) with deterministic truncation behavior
- automation event payload max size (bounded, secret-free)

### 3.2 Access control helpers (membership checks)
Unit tests MUST cover:
- telespace membership checks (owner, admin, member, viewer)
- room membership (if room-level differs from telespace-level)
- permission gates for:
  - posting messages
  - reading message history
  - installing/uninstalling agents
  - installing/uninstalling workflows
  - triggering automations (server-side enforcement at trigger time)

### 3.3 Event model and idempotency (dedupe)
Agentelic MUST provide deterministic dedupe for automation triggers.

Unit tests MUST cover:
- generating/storing an `eventId` for room events
- dedupe on retries:
  - posting a message that triggers an automation must not create multiple workflow runs if the same event is processed twice
- idempotency key conflict behavior:
  - same key + different payload must be rejected (or deterministic consistent behavior must be documented and tested)

### 3.4 Timeline composition logic (activity feed)
Unit tests MUST cover:
- timeline ordering rules:
  - consistent sort key (e.g., `createdAtMs asc`)
- representation rules:
  - message items
  - “agent invoked” items (with references)
  - “workflow execution started/completed” items (with references)
- redaction rules:
  - timeline entries must remain secret-free (at minimum: no raw secret values stored)

---

## 4) Integration test plan (required)

Integration tests exercise:
- persistence layer (e.g., Convex tables)
- API handlers (queries/mutations/http endpoints)
- auth + tenancy enforcement in the real runtime

### 4.1 Telespaces CRUD + membership
Tests:
1. Create telespace as User A ⇒ A is owner
2. User B cannot read telespace by id (unless invited)
3. Invite/join flow (if v1 includes invitations):
   - A invites B
   - B accepts
   - B can now read but cannot admin (role-dependent)
4. Role change:
   - A upgrades/downgrades B
   - permissions change accordingly

### 4.2 Rooms CRUD
Tests:
1. Create room under telespace as owner
2. Members can list rooms (if allowed)
3. Non-members cannot list rooms
4. Room delete/archival behavior (if supported):
   - deleted rooms are not returned in list
   - history retention rules apply (if implemented)

### 4.3 Messages (write, read, pagination)
Tests:
1. Post message
2. List messages returns:
   - correct ordering
   - correct pagination behavior (cursor/limit)
3. Fetch message by id must enforce membership
4. Editing/deleting a message (if supported) must enforce:
   - author or admin rules
   - timeline entries reflect updates (or immutable append-only events)

### 4.4 Installed agents (WHS references)
Tests:
1. Install a WHS agent reference into a telespace
2. Non-admin role cannot install/uninstall (if role-restricted)
3. Installed agent list returns only for members
4. Invalid `agentId` input rejected (format/length constraints)

### 4.5 Agent invocation (WHS integration path)
Tests (mocked or sandbox):
1. In-room invoke request produces:
   - an invocation record (or reference)
   - an activity timeline entry
2. Success path:
   - response text stored or referenced per policy
   - traceId stored (if returned)
3. Failure path:
   - invocation failure produces a safe error summary item
   - no secrets leak in stored errors

### 4.6 Installed workflows (Agentromatic references)
Tests:
1. Install workflow reference into telespace as an automation:
   - binds to event type `room.message.created` (minimum v1)
2. Posting a message triggers a workflow run:
   - exactly one execution created per event (dedupe)
   - activity timeline records execution started/completed (or started + terminal status once known)
3. Failure path:
   - workflow run fails ⇒ timeline shows failure summary
   - rerun policy is not implicit unless spec says so (v1 recommended: no automatic reruns)

---

## 5) End-to-end (E2E) test plan (required)

E2E tests validate the complete user journey. At minimum, implement these flows.

### 5.1 E2E-01: Signup/login → create telespace → create room
Steps:
1. User signs in
2. Create telespace
3. Create a room
4. Verify room appears in rooms list
5. Verify activity timeline exists (empty or contains system events)

Pass criteria:
- no 500s
- routes load and render
- created objects appear in lists immediately (or eventually consistent within defined bounds)

### 5.2 E2E-02: Post messages → read history → pagination
Steps:
1. Post N messages (N >= 30)
2. Load history page 1 (limit 20)
3. Load history page 2 (next 10)
4. Verify ordering and no duplicates/missing messages

Pass criteria:
- pagination cursor works
- message ordering is stable

### 5.3 E2E-03: Install WHS agent → invoke from room
Precondition:
- there exists a WHS agent usable in staging (sandbox or mock)

Steps:
1. Install agent into telespace
2. Invoke agent from room
3. Verify:
   - invocation shows up in activity timeline
   - response text appears (or reference appears, depending on storage policy)
   - errors are normalized and human-readable on failure

Pass criteria:
- invocation succeeds or fails deterministically with correct UI behavior
- no secrets leaked in UI errors or stored timeline records

### 5.4 E2E-04: Install Agentromatic workflow automation → trigger via message
Precondition:
- an Agentromatic workflow exists and is accessible
- Agentromatic run endpoint returns an `executionId`

Steps:
1. Install workflow automation to trigger on `room.message.created`
2. Post a message
3. Verify:
   - workflow execution is created (by reference)
   - timeline contains a “workflow triggered” item
   - execution detail deep link works (if provided)

Pass criteria:
- exactly one workflow execution per event (dedupe)
- user can see status and logs summary (even if logs are fetched from Agentromatic by reference)

### 5.5 E2E-05: Membership boundary (invite + remove)
Steps:
1. User A creates telespace + room
2. User A invites User B (or adds B directly, depending on v1)
3. User B can read and post (role-dependent)
4. User A removes User B
5. User B immediately loses access:
   - cannot read room list
   - cannot read messages
   - cannot trigger automations

Pass criteria:
- access revocation is enforced server-side (not just UI)

---

## 6) Security-focused test suite (required)

### 6.1 Tenant isolation (IDOR) tests (MUST)
Create two users (A, B) and two telespaces (TA owned by A, TB owned by B). Verify:

1. B cannot `getTelespace(TA.id)`
2. B cannot `listRooms(TA.id)`
3. B cannot `getRoomMessageHistory(roomInTA)`
4. B cannot `installWorkflow(TA.id, ...)`
5. B cannot `invokeAgent(TA.id, ...)`

These tests MUST be enforced at the server boundary.

### 6.2 Membership enforcement tests (MUST)
Within a telespace:
- non-member cannot read
- viewer role cannot write (if defined)
- member can write messages but cannot manage installs (if defined)
- only owner/admin can manage membership and installs

### 6.3 Automation abuse / confused deputy tests (MUST)
Automation triggers are a common attack surface.

Tests MUST cover:
- a user cannot install an automation that triggers actions outside permitted scopes (if policy exists)
- automation execution is attributed:
  - records who installed it
  - records what event triggered it
- automation cannot be triggered by a spoofed event:
  - event ingestion/creation is server-controlled
  - eventId cannot be arbitrarily supplied by client to force a run

### 6.4 Secrets leakage tests (MUST)
Ensure that:
- stored messages do not contain secret values from server-side contexts
- error envelopes returned to client do not contain secret values
- activity timeline entries are secret-free
- logs displayed are either:
  - redacted in Agentelic, or
  - fetched from Agentromatic/WHS with redaction applied there (but Agentelic must still avoid persisting raw secrets)

Recommended technique:
- inject a known sentinel secret-like string in a controlled environment and assert it never appears in:
  - DB rows for messages/timeline
  - API responses
  - client-rendered error details

### 6.5 Rate limiting / spam safety (SHOULD for v1; MUST if exposed to untrusted tenants)
If Agentelic is multi-tenant:
- test message posting rate limit triggers
- test automation trigger throttling (per room / per telespace)
- test that throttled automation produces a safe “skipped” timeline entry (optional)

---

## 7) Resilience and failure-mode tests (required)

### 7.1 WHS invocation failures
Simulate:
- WHS returns 5xx
- WHS times out
- WHS returns normalized error (e.g., `LIMIT_EXCEEDED`)

Expect:
- Agentelic records a safe failure entry
- no repeated retries unless explicitly configured
- dedupe still holds (a single event does not cause multiple invocations)

### 7.2 Agentromatic run failures
Simulate:
- run request fails
- execution created but logs unavailable
- execution fails

Expect:
- timeline reflects failure safely
- user can retry manually (if supported), but auto-retry is not implicit in v1 unless spec says so

### 7.3 Partial timeline write failures
If timeline entries are written separately from message writes:
- test atomicity strategy:
  - either message + timeline are in one transaction, OR
  - a repair job is used and tested (SHOULD)

Pass criteria:
- system does not end up in a state where messages are visible but critical membership/audit invariants are broken.

---

## 8) Performance and load testing (recommended)

### 8.1 Message throughput
Minimum targets (tune based on infra):
- posting messages remains responsive under typical room load
- listing messages with pagination remains under defined latency budgets

### 8.2 Timeline query performance
- timeline query should remain performant even with mixed entries
- indexes must support:
  - `by telespaceId + createdAtMs`
  - `by roomId + createdAtMs`

### 8.3 Automation trigger overhead
- triggering automation should not block message posting critical path beyond a bounded amount
- recommended: enqueue automation processing asynchronously and record “queued” timeline entries

---

## 9) Release gates (must-pass checklist)

Before shipping v1 to production, all of the following MUST pass:

1. **Unit tests**: all required suites in §3
2. **Integration tests**: all required suites in §4
3. **E2E tests**: all required flows in §5 (on staging)
4. **Security suite**: all tests in §6
5. **No dev-only flags in prod**:
   - dev anonymous auth modes (if any) are disabled
6. **Error envelope consistency**:
   - errors return stable `code` + safe `message`
7. **Redaction**:
   - no secrets leaked in:
     - logs
     - timeline
     - API responses

---

## 10) Acceptance criteria (system-level definition of done)

Agentelic v1 is “complete” when:

### 10.1 Core telespace UX works
- Create telespace
- Create room
- Post messages
- Read history with pagination

### 10.2 Agents in telespaces work (WHS integration)
- Install WHS agent reference
- Invoke agent from within a room
- See invocation result in a room activity timeline (or safe reference)

### 10.3 Workflows in telespaces work (Agentromatic integration)
- Install Agentromatic workflow as an automation
- Trigger execution from room event
- See execution reference + status in activity timeline
- Dedupe guarantees: one execution per event

### 10.4 Tenant isolation is proven
- At least 3 IDOR tests pass (telespace, room/messages, automation triggers)
- Membership revocation is enforced server-side

### 10.5 Auditability is real
- Mutations produce durable, secret-free timeline entries that are queryable and ordered
- Timeline includes sufficient correlation fields to link:
  - messageId ↔ eventId ↔ invocationId/executionId (as applicable)

---

## 11) Appendix: Minimal test matrix (quick reference)

### Unit (MUST)
- validation: telespace/room/message/install specs
- membership checks: read/write/install permissions
- dedupe/idempotency: eventId behavior
- timeline composition: ordering + redaction

### Integration (MUST)
- telespace CRUD + membership + roles
- rooms CRUD
- messages write/read + pagination
- install/uninstall agent + workflow
- trigger automation → reference created
- error handling: WHS/Agentromatic failure paths

### E2E (MUST)
- E2E-01 create telespace/room
- E2E-02 messages + pagination
- E2E-03 install agent + invoke
- E2E-04 install workflow + trigger
- E2E-05 invite/remove membership boundary

### Security (MUST)
- IDOR suite: cross-tenant reads/writes rejected
- membership enforcement
- secrets leakage checks
- automation spoofing prevention

---