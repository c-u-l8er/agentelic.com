# agentelic — Security, Secrets, and Compliance (v1)
Version: 1.0  
Status: Normative draft  
Audience: Engineering  
Last updated: 2026-01-24

This document defines the **security, secrets, and compliance requirements** for **Agentelic (telespaces)**.

Agentelic context:
- **Agentelic = telespaces** (AI-enabled chatrooms)
- Telespaces can **contain Agentromatic workflows** (automation graphs + executions/logs)
- Workflows run using **WHS agents** (WebHost.Systems deployed agents/runtimes) or equivalent control-plane runtime

This spec is written to be compatible with:
- Agentromatic’s workflow execution/log model (conditions are safe; executions snapshot definitions)
- WebHost.Systems’ control-plane principles (auth, tenant isolation, normalized errors, secrets, telemetry)

Normative language:
- **MUST / MUST NOT / SHOULD / MAY** are used intentionally.

---

## 1) Security objectives (what we protect)

### 1.1 Primary assets
Agentelic MUST protect:
1. **Message content** (room/telespace messages, edits, reactions)
2. **Membership and access control state**
   - who can access which telespace/room
   - role assignments and permissions
3. **Automation configuration**
   - installed workflows and their triggers
   - installed agents and their invocation configuration
4. **Audit / activity timeline integrity**
   - “who did what” and “what ran because of what”
5. **Secrets** (strictly by reference)
   - Agentelic MUST NOT store or emit secret values, but it must safely reference secret ids
6. **Cross-product references**
   - workflowId/executionId (Agentromatic)
   - agentId/deploymentId/sessionId (WHS)
   - orgId (Delegatic)

### 1.2 Security goals (v1)
Agentelic v1 MUST:
- Prevent cross-tenant access (no IDOR)
- Prevent unauthorized access within a tenant (membership enforcement)
- Prevent “confused deputy” escalation (automations must not run with broader privileges than the triggering context)
- Prevent secret leakage via logs, messages, tool traces, errors, or analytics
- Provide auditability sufficient to reconstruct causality:
  - user action → event → automation trigger → workflow execution / agent invocation

### 1.3 Security boundaries (explicit)
Agentelic is a **collaboration plane** and must enforce:
- **Tenant boundary** at the API/data access layer (every read/write is tenant-scoped)
- **Telespace boundary** for membership/role checks
- **Room boundary** for message visibility and posting rights
- **Automation boundary** for triggers and actions (run-time authorization)

Agentelic MUST treat:
- Agentromatic execution engine as a separate subsystem
- WHS agent deployment/invocation as a separate subsystem
- Delegatic org governance as a separate subsystem

Agentelic MUST NOT “trust” external systems to enforce Agentelic rules; it must enforce its own rules and also pass sufficient context for defense-in-depth.

---

## 2) Threat model (practical)

### 2.1 Actors
- **Legitimate user** (member of a telespace)
- **Telespace admin/owner**
- **Malicious tenant user** (attempts escalation or cross-tenant access)
- **External attacker** (no auth; tries to hit endpoints directly)
- **Compromised client** (XSS, token theft, extension exfiltration)
- **Compromised automation** (malicious prompt, tool output injection)
- **Compromised runtime provider** (WHS data plane compromise risk is assumed possible)

### 2.2 Attack surfaces (non-exhaustive)
- API endpoints (list/get/create/update)
- Message posting and rendering (XSS / HTML injection)
- Automation triggers on message content (prompt injection)
- Agent invocation routes (tool misuse, SSRF via tools, exfiltration)
- Workflow triggers and triggerData payloads (secret leakage, over-permission)
- Logs and activity timeline rendering (data leakage)
- Integrations (webhooks, OAuth callbacks if added later)
- Client-side analytics/telemetry (PII leakage)

### 2.3 Required mitigations (v1)
Agentelic MUST implement mitigations for:

#### T1: Cross-tenant data access (IDOR)
- Every get/list/update/delete MUST validate ownership/tenant membership.
- IDs MUST NOT be treated as authorization.
- “Attach” operations (org→telespace, telespace→workflow, telespace→agent) MUST verify that the actor has rights to both sides (or explicitly document and enforce the delegation rule).

#### T2: Unauthorized room message access
- Message reads MUST require membership in the telespace AND visibility of the room.
- Private rooms (if supported) MUST enforce an additional room-level membership set.

#### T3: Confused deputy via automations
- Automations MUST run under an explicit **actor context**:
  - who triggered it (user/system)
  - which telespace/room triggered it
  - what permissions are allowed for this automation
- Automations MUST NOT run with “owner” privileges unless explicitly configured and approved.
- Agent invocations triggered by messages MUST be constrained by telespace-level allowlists (agent/tool policy).

#### T4: Secret leakage (messages, logs, errors, analytics)
- Secrets MUST NOT appear in:
  - messages (unless explicitly allowed and clearly labeled; v1 default is “no secrets in messages”)
  - workflow triggerData stored by Agentelic
  - activity timeline entries
  - logs/traces and error envelopes
  - analytics payloads
- Use “secret references” (ids) only.

#### T5: Prompt injection / tool output injection
- Agentelic MUST treat message content as untrusted input.
- When messages trigger agent invocations/workflows, the system MUST apply:
  - strict tool allowlists
  - explicit “system prompt” constraints for the room (no secrets; no privilege escalation)
  - output sanitization and redaction (best-effort) before persistence or display

#### T6: Abuse / DoS
- APIs MUST rate-limit:
  - message posting
  - automation triggers
  - agent invocations
- Enforce payload size limits for message bodies and attachments metadata.

#### T7: XSS and unsafe rendering
- Message rendering MUST escape or sanitize user content.
- Markdown rendering (if enabled) MUST run with a strict allowlist of tags/attributes.
- Links MUST be sanitized and opened with safe defaults (no `javascript:` URLs).

---

## 3) Authentication and identity

### 3.1 Auth provider (recommended)
Agentelic SHOULD use the same identity provider as the rest of the stack (recommended: Clerk), but the spec requires only that:
- every request can be mapped to a stable **user identity**
- the mapping to an internal `users` row is enforced server-side

### 3.2 Identity mapping (required semantics)
Agentelic MUST implement:
- `currentUser = resolveFromAuthToken()`
- `userRow = ensureUserRow(currentUser.externalId)` (server-side)

If unauthenticated:
- endpoints MUST return `UNAUTHENTICATED` unless explicitly marked public (v1 recommends zero public endpoints).

### 3.3 Session security
- Auth tokens MUST NOT be logged.
- Tokens MUST NOT be stored in durable message or activity records.
- Client-side storage SHOULD avoid long-lived tokens where possible (use provider defaults).

---

## 4) Authorization and access control (tenant isolation)

### 4.1 Tenant model (v1 baseline)
At minimum, Agentelic MUST support a “single-tenant per user” model:
- a telespace is owned by one user
- members can be added, but the owner remains the authority

If Delegatic org membership is integrated:
- tenant scope MAY become “orgId” or “teamId”
- HOWEVER, Agentelic MUST still enforce telespace membership locally.

### 4.2 Roles (v1 minimum)
Agentelic MUST support at least:
- `owner`
- `admin`
- `member`
- `viewer`

Role enforcement MUST cover:
- creating rooms
- inviting/removing members
- installing/uninstalling workflows and agents
- configuring automation triggers
- posting messages (viewer MAY be read-only)
- viewing activity timeline and run details

### 4.3 Authorization checks (required patterns)
Every API must follow this pattern:
1. Resolve current user
2. Resolve telespace by id (if applicable)
3. Verify membership and required role
4. Perform operation

For “read by id”:
- MUST check that the object belongs to the telespace and the telespace is visible to the user.

For list operations:
- MUST scope the query by user’s membership and return only authorized resources.

### 4.4 “Attach” operations (cross-system references)
When attaching external references:

#### 4.4.1 Attach workflow (Agentromatic)
To attach `workflowId` into a telespace:
- actor MUST be authorized to modify the telespace
- server SHOULD verify (best-effort) that the actor has access to that workflow in Agentromatic
  - if a direct verification call is not available, store a “verificationStatus: unverified” and require verification before enabling triggers
- enabling triggers MUST require verification or a policy exception explicitly configured

#### 4.4.2 Attach agent (WHS)
To attach `agentId` into a telespace:
- actor MUST be authorized to modify the telespace
- server SHOULD verify that the actor owns or is entitled to invoke that agent in the WHS control plane
- invocation MUST include a scoped actor context (see §7)

### 4.5 No silent privilege widening
- If a telespace is moved under a Delegatic org (or attached), Agentelic MUST NOT silently grant access to new users.
- Any widening of access MUST be explicit and auditable (membership change record).

---

## 5) Data handling, privacy, and retention

### 5.1 Data classification (v1)
Agentelic data should be classified as:
- **Content**: messages, attachments metadata, room names
- **Control**: membership, roles, automation configs
- **Operational**: activity events, run references, status summaries
- **Derived**: embeddings/summaries (if implemented later; v1 can omit)

### 5.2 Data minimization (required)
Agentelic MUST:
- store only what it needs to provide the product experience
- avoid persisting full third-party payloads by default
- store references to workflow executions and agent invocations instead of copying large logs/transcripts

### 5.3 Retention (v1 defaults)
Agentelic MUST define and implement retention policies (defaults may be adjusted later):
- Messages: 180 days (configurable per telespace later)
- Activity events: 180 days
- Automation run references: 180 days (store status + ids; do not duplicate logs)
- Error records: 30–90 days (bounded and redacted)

If a tiering/billing layer is added, retention MAY become tier-based.

### 5.4 Deletion semantics
Agentelic SHOULD implement soft delete for telespaces and rooms to preserve auditability.
If hard delete is supported:
- MUST require owner confirmation
- MUST document the impact on audit trails and automation references
- MUST scrub or invalidate stored references where appropriate

---

## 6) Secrets strategy (normative)

### 6.1 Core rule (MUST)
Agentelic MUST NOT store plaintext secret values in:
- telespace configs
- room configs
- messages
- activity events
- automation configs
- logs or error envelopes

### 6.2 Secret references only
Agentelic MAY store **secret references** (ids), such as:
- `secretId: "SLACK_BOT_TOKEN_ID"`
- `secretRef: { provider: "vault", id: "..." }`

Rules:
- secret references MUST be treated as sensitive metadata and access-controlled
- secret references MUST NOT be rendered to unauthorized clients
- secret references MUST NOT be embedded in prompts unless explicitly allowed and safe

### 6.3 Secret injection model (server-side only)
When an agent invocation or workflow step needs a secret:
- the secret MUST be injected server-side into the execution environment (WHS provider injection or equivalent)
- the client MUST NOT receive the secret value
- logs MUST NOT include the secret value (best-effort redaction)

### 6.4 Redaction requirements
Agentelic MUST implement best-effort redaction for:
- known secret ids (mask values if they appear)
- common credential patterns (API keys, bearer tokens, private keys)

Redaction MUST apply before:
- persistence into activity timeline
- returning API responses to clients
- sending analytics events

---

## 7) Automation safety (workflows and agents inside telespaces)

### 7.1 Trigger safety and idempotency
Room events that trigger automations MUST include:
- `eventId` (unique id for dedupe)
- `telespaceId`, `roomId`
- `actor` (user/system)
- `timestamp`

When triggering:
- Agentelic MUST dedupe triggers by `(installedAutomationId, eventId)` to prevent replay duplicates.
- Triggers MUST have bounded payload sizes.

### 7.2 Actor context propagation (confused deputy prevention)
Agentelic MUST propagate a structured actor context into downstream systems:
- `triggeredBy`: `{ type: "user"|"system", userId?, telespaceId, roomId, messageId? }`
- `permissionsContext`: the effective role/permission scope at trigger time

Downstream invocation MUST NOT default to “owner” privileges.

### 7.3 Tool/agent invocation constraints
For WHS agent invocations initiated from a telespace:
- Agentelic MUST support a per-telespace allowlist of:
  - which agents can be invoked
  - optional tool policies (allow/deny lists) if the invocation protocol supports it
- If the WHS invocation protocol supports “toolPolicy”, Agentelic SHOULD set it to the narrowest possible set.

### 7.4 Workflow invocation constraints
For Agentromatic workflow executions initiated from a telespace:
- Agentelic MUST supply only a bounded, redacted triggerData payload.
- Agentelic MUST NOT include secrets.
- Agentelic SHOULD avoid embedding full message histories; provide message references instead where possible.

### 7.5 Output safety
Agent responses and workflow outputs that are shown in-room MUST:
- be escaped/sanitized for rendering
- be redacted best-effort for secrets
- include attribution:
  - which agent/workflow produced it
  - correlation identifiers for audit/debug

---

## 8) Logging, auditability, and evidence

### 8.1 Audit events (required)
Agentelic MUST record append-only, secret-free audit events for:
- telespace create/update/delete
- room create/update/delete
- membership invite/accept/remove/role change
- automation installed/uninstalled/enabled/disabled
- agent installed/uninstalled/enabled/disabled
- automation trigger fired (with eventId and downstream references)
- policy or configuration changes affecting security

Each audit event MUST include:
- `at` (timestamp)
- `actor` (user/system)
- `telespaceId` (and `roomId` if relevant)
- `type` (stable string)
- `correlationId` (if any)
- `details` (bounded, redacted)

### 8.2 Correlation with external systems
Agentelic SHOULD store references:
- `workflowExecutionRef: { workflowId, executionId }`
- `agentInvocationRef: { agentId, traceId, sessionId? }`

Agentelic MUST treat these references as untrusted for authorization:
- they are for navigation/debug, not for access control.

---

## 9) Transport security and API hardening

### 9.1 TLS
All client ↔ server traffic MUST use TLS in production.

### 9.2 CORS
CORS policies SHOULD be restrictive:
- allow only known origins for browser clients.

### 9.3 Input validation
All endpoints MUST validate inputs:
- reject unknown fields where feasible
- enforce string length bounds
- enforce pagination bounds
- enforce message size limits

### 9.4 Normalized errors
Errors returned to clients MUST be normalized:
- `code` (stable)
- `message` (safe)
- optional `details` (MUST NOT contain secrets)

Recommended codes:
- `UNAUTHENTICATED`
- `UNAUTHORIZED`
- `NOT_FOUND`
- `INVALID_REQUEST`
- `LIMIT_EXCEEDED`
- `CONFLICT`
- `INTERNAL`

---

## 10) Compliance posture (v1)

### 10.1 Privacy expectations
Agentelic SHOULD be built to support a future SOC2-style posture:
- access controls are enforced and testable
- audit events exist for privileged actions
- secrets are never logged or stored in plaintext

Agentelic v1 is not “certified”, but MUST NOT block future compliance.

### 10.2 Data export and deletion
If a user requests export:
- Agentelic SHOULD support exporting telespace content and audit events (bounded) in a structured format.

If a user requests deletion:
- deletion semantics MUST be documented and consistent (see §5.4).

### 10.3 PII handling
Agentelic MUST assume messages may contain PII and therefore:
- avoid sending message content to third-party analytics by default
- require explicit opt-in for storing transcripts outside the core DB

---

## 11) Security testing checklist (v1)

### 11.1 Tenant isolation (MUST)
At minimum, add tests for:
- cannot read telespace by id without membership
- cannot list rooms/messages for telespace without membership
- cannot post message without membership
- cannot install workflow/agent without admin role
- cannot trigger automation for telespace you cannot access

### 11.2 Confused deputy (MUST)
- Ensure an automation trigger cannot run with a broader scope than the triggering user’s role.
- Ensure “owner-only” actions remain owner-only even when triggered by system events.

### 11.3 Secret leakage (MUST)
- Ensure secrets never appear in:
  - activity event payloads
  - error envelopes
  - logs shown in UI
- Ensure redaction catches basic token patterns.

### 11.4 XSS (MUST)
- Ensure message rendering escapes HTML by default.
- If Markdown is supported, ensure sanitization prevents script injection.

### 11.5 Abuse controls (SHOULD)
- Rate limit message posting and automation triggers.
- Ensure payload limits reject oversized messages/trigger payloads.

---

## 12) Security acceptance criteria (Definition of Done)

Agentelic security is “v1 complete” when:

1. **Tenant isolation**:
   - All read/write endpoints enforce membership/role checks.
   - At least 3 IDOR tests pass (telespace, room/messages, automation trigger).

2. **Automation safety**:
   - Automations are deduped by eventId and cannot be replayed to cause duplicate side effects.
   - Actor context is propagated and prevents privilege escalation.

3. **Secrets**:
   - No plaintext secrets are stored or returned by any endpoint.
   - Redaction is applied to outputs before persistence and display.

4. **Auditability**:
   - All mutating operations emit a durable, secret-free audit event with attribution and timestamps.
   - Downstream references (workflow execution, agent invocation) are stored for navigation/debug.

5. **Client safety**:
   - Message rendering is safe against XSS in the default configuration.
   - Error responses do not leak internal details or secrets.

---