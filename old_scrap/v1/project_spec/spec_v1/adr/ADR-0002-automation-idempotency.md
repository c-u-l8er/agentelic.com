# ADR-0002: Automation Idempotency & Dedupe (Agentelic)
- **Status:** Accepted
- **Date:** 2026-01-24
- **Owners:** Engineering
- **Decision scope:** How Agentelic prevents duplicate automation side effects when room events are retried/replayed or processed more than once.
- **Related specs:**
  - `project_spec/spec_v1/00_MASTER_SPEC.md` (Event model + automations)
  - `project_spec/spec_v1/10_API_CONTRACTS.md` (Idempotency-Key guidance, automations endpoints)
  - `project_spec/spec_v1/30_DATA_MODEL_CONVEX.md` (automation + activity + reference ledgers)
  - `project_spec/spec_v1/40_SECURITY_SECRETS_COMPLIANCE.md` (confused deputy + abuse controls)

---

## Context

Agentelic “telespaces” attach automations to room events, e.g. `room.message.created`. An automation can cause side effects such as:
- invoking a WHS agent
- triggering an Agentromatic workflow run

In practice, the same event can be processed multiple times due to:
- client retries (network flake, tab refresh, mobile resend)
- server retries (transient upstream errors)
- queue/cron replays
- concurrent workers racing to process the same event
- “at least once” delivery semantics if/when an event bus is introduced

Without explicit idempotency, duplicated event processing can lead to:
- multiple WHS invocations (cost + spam + unintended actions)
- multiple workflow executions for one message (cost + confusion)
- inconsistent activity timelines (duplicate “triggered” entries)
- security incidents (confused deputy amplification)

Constraints:
- Multi-tenant: dedupe must be scoped and must not allow cross-tenant interference.
- Deterministic, safe: no secret values stored in dedupe keys or logs.
- Simple MVP: we want a robust baseline without adding a complex distributed lock service.

---

## Decision

### 1) Define a canonical `eventId` for automation triggers
For every automation-relevant room event, Agentelic MUST assign a stable `eventId`.

MVP rule:
- For `room.message.created`, `eventId` MUST be derived from the persisted message identity:
  - `eventId = "msg:" + <messageId>`
- For other event types, use similarly stable resource ids, e.g.:
  - `member.joined` → `"member_joined:" + <membershipChangeId>`
  - `room.created` → `"room_created:" + <roomId>`

If a stable primary resource id does not exist for an event type, Agentelic MUST create a durable event record first and use its id.

Rationale:
- The dedupe key must be stable across retries and process restarts.
- Message creation is the canonical “cause” for message-created automations; tying the event id to message id is the simplest correct choice.

### 2) Dedupe at the “side effect” boundary, not only at the “event” boundary
Agentelic MUST dedupe **each action** within an automation, not just the automation trigger as a whole.

Canonical action identity:
- `(automationId, eventId, actionIndex)` where:
  - `automationId` is the automation record id
  - `eventId` is the canonical event id for the triggering event
  - `actionIndex` is the 0-based index in `automation.actions[]` at trigger time

This tuple is called the **Action Dedupe Key**.

Rationale:
- An automation can have multiple actions. Some may succeed while later actions fail.
- Retrying the event should not re-run already-successful actions.
- Per-action dedupe enables safe partial progress and avoids “all-or-nothing” coupling.

### 3) Persist a durable dedupe record before initiating the side effect
Before calling any upstream system (WHS invoke, Agentromatic run), Agentelic MUST create a durable dedupe record for the action with status transitions.

Minimum state machine (per action):
- `claimed` (dedupe record created; action should be executed by this claimant)
- `succeeded` (terminal)
- `failed` (terminal, with bounded safe error summary)
- `skipped` (terminal; disabled by policy or filtered out)

The dedupe record MUST include:
- `telespaceId` (tenant scoping)
- `roomId` (optional)
- `automationId`
- `eventId`
- `actionIndex`
- `status`
- timestamps (`createdAtMs`, `completedAtMs?`)
- upstream reference ids, if available:
  - WHS: `traceId`, `sessionId?`, `requestId?`
  - Agentromatic: `executionId`, `workflowId`
- safe error summary fields (`errorCode`, `errorMessage` bounded)

Uniqueness rule:
- There MUST NOT exist more than one active dedupe record for the same `(telespaceId, automationId, eventId, actionIndex)`.

Implementation note (Convex):
- Convex does not enforce unique constraints; enforce by consistent lookup-before-insert and rejecting duplicates.
- If a record already exists:
  - If status is terminal (`succeeded|skipped`): do not re-run; return the existing reference.
  - If status is `claimed` and “fresh”: treat as in-flight and do not start another.
  - If status is `claimed` but “stale”: see §5.

### 4) Upstream calls MUST use idempotency keys derived from the Action Dedupe Key
Agentelic SHOULD pass an idempotency key to upstream systems when possible.

Canonical upstream idempotency key string:
- `idempotencyKey = "agentelic:auto:" + <automationId> + ":evt:" + <eventId> + ":a:" + <actionIndex>`

Rules:
- The idempotency key MUST NOT include secret values or user-provided content.
- The idempotency key MUST be stable across retries.

This provides defense-in-depth:
- Even if Agentelic’s own dedupe fails (bug/race), upstream systems can still dedupe.

### 5) Define “stale claim” handling to avoid permanent deadlocks
Because “claimed” can get stuck if the worker crashes mid-action, Agentelic MUST define a stale-claim policy.

MVP stale claim rule:
- A `claimed` record is considered **stale** if `nowMs - createdAtMs > CLAIM_TTL_MS`.
- Recommended default: `CLAIM_TTL_MS = 5 minutes` for non-streaming actions.

When a claim is stale, Agentelic MAY:
- transition it to `failed` with `errorCode = "STALE_CLAIM"` and proceed to create a new claim, OR
- “take over” the claim by updating a `claimedBy` field (if implemented) and proceeding

The chosen behavior MUST be deterministic and audited (via activity/system events), and MUST not duplicate side effects if the original action might still be running.

MVP-safe stance:
- Prefer marking stale as `failed` and allow explicit retry; do not automatically run high-risk side effects on stale recovery unless the action is known-idempotent.

### 6) Activity timeline entries are also deduped
Agentelic writes activity events such as:
- `automation.triggered`
- `agent.invocation.started|completed`
- `workflow.run.started|completed`

These must not be duplicated on retries.

Rule:
- Activity events emitted as a result of automation processing MUST include a `dedupeKey` derived from the Action Dedupe Key and the event type, e.g.:
  - `dedupeKey = "act:" + <type> + ":" + <automationId> + ":" + <eventId> + ":" + <actionIndex>`

If an activity event with the same `dedupeKey` already exists, Agentelic MUST NOT write another.

---

## Consequences

### Positive
- Prevents duplicate runs and invocations under at-least-once processing semantics.
- Keeps the room activity timeline clean and audit-friendly.
- Enables safe partial progress: successful actions are not repeated when retrying later actions.
- Adds defense-in-depth by also using upstream idempotency keys.

### Tradeoffs / costs
- Requires additional tables/records (dedupe ledger) and extra reads/writes per action.
- Requires a stale-claim policy (complexity) to prevent deadlocks.
- “Exactly-once” is not guaranteed in the presence of unknown side effects; the system is “effectively once” for the actions we can dedupe, assuming upstream cooperation or idempotent behavior.

---

## Implementation Notes (guidance)

### Data model placement
Recommended approaches (either is acceptable; pick one and implement consistently):
1. **Dedicated dedupe table** (preferred):
   - `automationActionRuns` (or similar) storing the Action Dedupe Key and status.
2. **Embed dedupeKey in existing ledgers**:
   - add a `dedupeKey` field to `agentInvocations` and `workflowRuns` and enforce uniqueness by lookup.

The dedicated table is usually clearer and supports partial progress across multi-action automations.

### Error handling strategy
- Upstream failures should mark the action as `failed` with:
  - stable `errorCode` (e.g., `UPSTREAM_ERROR`, `UPSTREAM_TIMEOUT`, `LIMIT_EXCEEDED`)
  - bounded safe `errorMessage` (no secrets)
- The automation engine should continue or stop depending on a simple policy:
  - MVP recommended: continue remaining actions unless explicitly configured to stop on failure.

### Security & abuse controls
- Rate limit automation evaluation per room and per telespace to avoid event storms.
- Enforce strict payload size limits:
  - never persist full message content into dedupe records or upstream idempotency keys
- Ensure “actor context” (who triggered) is recorded separately from dedupe keys; dedupe keys must remain deterministic and secret-free.

---

## Alternatives considered

### A) Best-effort dedupe only (no durable records)
Rejected: race conditions and retries would still duplicate side effects.

### B) Deduping only at automation level (not per action)
Rejected: causes duplicate successful actions when later actions fail and the event is retried.

### C) Distributed lock service (e.g., Redis locks)
Deferred: adds operational complexity and is unnecessary for MVP given a durable DB-backed dedupe ledger.

---

## Acceptance criteria
- For a single `room.message.created` event, each automation action runs at most once even if:
  - the trigger handler is invoked multiple times
  - the client retries message posting
  - the system crashes and restarts mid-processing
- Activity timeline does not contain duplicate automation entries for the same action and event.
- Upstream calls use idempotency keys derived from `(automationId, eventId, actionIndex)` when possible.
- No secrets or message content are stored in dedupe keys, idempotency keys, or activity dedupe keys.
