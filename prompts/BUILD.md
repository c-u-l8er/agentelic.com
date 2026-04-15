# Agentelic — Implementation Build Prompt
**Version:** 1.0 | **Date:** April 2026 | **Type:** Full Implementation (Build Pipeline + MCP + Supabase)

---

## Your Mission

You are building **Agentelic** — the engineering layer of the [&] Protocol dark factory pipeline. Agentelic takes SpecPrompt specifications as input and produces tested, deployable agent artifacts through a deterministic 4-stage pipeline with template-based code generation.

**Read `docs/spec/README.md` fully before writing a single line.** It is the authoritative spec.

Agentelic is the **build stage** of the dark factory pipeline:
```
SpecPrompt (spec in) → Agentelic (build) → OS-008 (enforce) → FleetPrompt (distribute) → RuneFort (observe)
```

---

## Target Stack

```
Language:   Elixir 1.17+ / OTP 27
Pipeline:   4-stage build (PARSE → TEST INTAKE → GENERATE → COMPILE/TEST)
MCP:        JSON-RPC over HTTP (agent_create, agent_build, agent_test, agent_deploy,
            agent_status, template_list, template_pin, spec_validate, test_explain)
Database:   PostgreSQL via shared Supabase (agentelic.* schema, migration range 080-089)
Auth:       Supabase Auth (shared [&] ecosystem — amp.profiles, amp.workspaces)
Testing:    ExUnit + deterministic test DSL from spec acceptance criteria
Deploy:     Fly.io (MCP server + build pipeline worker)
```

---

## Repository Structure

Create this structure inside `agentelic.com/`:

```
agentelic.com/
├── lib/
│   ├── agentelic/
│   │   ├── agents/
│   │   │   └── agent.ex              # Agentelic.Agents.Agent Ecto schema (section 4.4.1)
│   │   ├── builds/
│   │   │   └── build.ex              # Agentelic.Builds.Build Ecto schema (section 4.4.2)
│   │   ├── testing/
│   │   │   ├── test_run.ex           # Agentelic.Testing.TestRun schema (section 4.4.3)
│   │   │   ├── test_result.ex        # Agentelic.Testing.TestResult embedded schema
│   │   │   ├── dsl.ex                # Agentelic.Test.DSL — test case generation from specs
│   │   │   ├── runner.ex             # Agentelic.Testing.Runner — execute tests with mocks
│   │   │   └── compiled_intake.ex    # Agentelic.Testing.CompiledIntake — SpecPrompt test bridge
│   │   ├── deploy/
│   │   │   └── deployment.ex         # Agentelic.Deploy.Deployment schema (section 4.4.4)
│   │   ├── pipeline/
│   │   │   ├── orchestrator.ex       # Agentelic.Pipeline.Orchestrator — 4-stage pipeline runner
│   │   │   ├── parser.ex             # Stage 1: PARSE — SpecPrompt.Spec parsing
│   │   │   ├── test_intake.ex        # Stage 1.5: TEST INTAKE — compiled test loading
│   │   │   ├── generator.ex          # Stage 2: GENERATE — template-based code generation
│   │   │   ├── compiler.ex           # Stage 3: COMPILE — build artifact
│   │   │   └── tester.ex             # Stage 4: TEST — run deterministic tests
│   │   ├── templates/
│   │   │   ├── registry.ex           # Agentelic.Templates.Registry — template version management
│   │   │   ├── manifest.ex           # Agentelic.Templates.Manifest — template manifest schema
│   │   │   └── renderer.ex           # Agentelic.Templates.Renderer — EEx template expansion
│   │   ├── triggers/
│   │   │   ├── supabase_listener.ex  # Listen for spec.specs inserts via Supabase Realtime
│   │   │   ├── cloudevents.ex        # Accept CloudEvents webhooks
│   │   │   └── github_webhook.ex     # Accept GitHub push events on SPEC.md changes
│   │   ├── publisher.ex              # Emit ConsolidationEvent to FleetPrompt on build success
│   │   └── mcp/
│   │       ├── server.ex             # MCP JSON-RPC server (section 4.5)
│   │       └── tools.ex              # Tool definitions and handlers
│   ├── agentelic.ex                  # Application entry point
│   └── agentelic_web/
│       ├── router.ex                 # Phoenix router (API + webhook endpoints)
│       └── controllers/
│           ├── pipeline_controller.ex # POST /api/pipeline/trigger, /api/pipeline/github
│           └── agent_controller.ex   # REST API for agents
├── test/
│   ├── pipeline/
│   │   ├── parser_test.exs
│   │   ├── generator_test.exs
│   │   └── tester_test.exs
│   ├── testing/
│   │   ├── dsl_test.exs
│   │   └── compiled_intake_test.exs
│   ├── templates/
│   │   └── registry_test.exs
│   └── fixtures/
│       ├── customer_support_spec.md  # Customer-support SPEC.md from SpecPrompt section 3.3
│       └── compiled_tests.json       # Pre-compiled test assertions
├── priv/
│   └── templates/                    # Bundled default templates (small set for MVP)
│       ├── elixir/
│       │   └── mcp-server/
│       │       ├── template.json
│       │       ├── mix.exs.eex
│       │       └── lib/agent.ex.eex
│       └── typescript/
│           └── mcp-server/
│               ├── template.json
│               ├── package.json.eex
│               └── src/agent.ts.eex
├── mix.exs
├── Dockerfile
└── fly.toml
```

---

## Implementation Order

### Phase 0: Foundation (weeks 1-6)

1. **Set up Phoenix project** with Ecto, Supabase config
2. **Implement Ecto schemas** (sections 4.4.1-4.4.4)
   - `Agentelic.Agents.Agent` with workspace_id, user_id, product_type, status state machine
   - `Agentelic.Builds.Build` with template_version, template_hash, compiled_tests_hash
   - `Agentelic.Testing.TestRun` with workspace_id, compiled_tests_hash
   - `Agentelic.Deploy.Deployment` with workspace_id, governance_policy_hash, approved_by
3. **Implement spec parser** (`pipeline/parser.ex`)
   - Consume SpecPrompt SPEC.md files → `SpecPrompt.Spec` struct
   - Compute spec_hash (SHA-256)
   - Validate required sections
4. **Implement CLI** — `agent_create`, `agent_build`, `agent_status` commands

### Phase 0.5: Templates (weeks 6-8)

1. **Implement template registry** (`templates/registry.ex`)
   - List templates by `{framework, product_type}`
   - Version pinning: agent-level > workspace-level > global default
   - Template immutability enforcement
2. **Implement template manifest** schema and validation
3. **Implement template renderer** (`templates/renderer.ex`)
   - EEx-based template expansion
   - Input: `SpecPrompt.Spec` + `ampersand.json` + template files
   - Output: generated source files
4. **Bundle starter templates** in `priv/templates/`

### Phase 1: Testing Framework (weeks 9-14)

1. **Implement Test DSL** (`testing/dsl.ex`)
   - `from_spec/1` — generate test cases from SpecPrompt acceptance tests
   - Assertion types: `:contains`, `:not_contains`, `:tool_called`, `:tool_not_called`, `:escalated`, `:constraint_respected`
   - Mock specs: `{tool_name, match_args, return}`
2. **Implement compiled test intake** (`testing/compiled_intake.ex`)
   - Load SpecPrompt.CompiledTest[] from JSON
   - Only approved tests (approved == true) are used
   - Fallback: generate compilation prompt for LLM-assisted compilation
   - Cache by `{spec_hash, test_index}`
3. **Implement test runner** (`testing/runner.ex`)
   - Mock MCP tool calls based on test case mocks
   - Capture agent output + tool calls
   - Validate against assertions
   - Produce TestRun with individual TestResults
4. **Write tests** using customer-support fixture

### Phase 2: Pipeline Orchestrator (weeks 9-14, parallel with testing)

1. **Implement 4-stage pipeline** (`pipeline/orchestrator.ex`)
   - Stage 1: PARSE — call parser, produce SpecPrompt.Spec
   - Stage 1.5: TEST INTAKE — load compiled tests, record compiled_tests_hash on Build
   - Stage 2: GENERATE — call template renderer with pinned template version
   - Stage 3: COMPILE — shell out to `mix compile` / `npm run build` / etc.
   - Stage 4: TEST — call test runner, evaluate pass/fail
   - Record timing for each stage on Build
   - Deterministic: same `{spec_hash, template_hash}` → same `artifact_hash`

### Phase 3: MCP Server (weeks 15-18)

1. **Implement MCP server** (`mcp/server.ex`)
   - JSON-RPC over HTTP, MCP protocol v2025-03-26
   - 9 tools: `agent_create`, `agent_build`, `agent_test`, `agent_deploy`, `agent_status`, `template_list`, `template_pin`, `spec_validate`, `test_explain`
2. **Implement pipeline triggers** (`triggers/`)
   - Supabase Realtime listener on `spec.specs` inserts/updates
   - CloudEvents webhook at `POST /api/pipeline/trigger`
   - GitHub webhook at `POST /api/pipeline/github`
3. **Implement publisher** (`publisher.ex`)
   - On build success, emit `ConsolidationEvent` to FleetPrompt
   - CloudEvents v1 envelope format

### Phase 4: Supabase Migration (weeks 15-18, parallel)

1. **Create migration** in `ampersand-supabase/migrations/` (range 080-089):
   - `080_agentelic_schema.sql` — create `agentelic.agents`, `agentelic.builds`, `agentelic.test_runs`, `agentelic.deployments`
   - `081_agentelic_rls.sql` — RLS policies scoped to `workspace_id`
2. **All tables use workspace-based RLS** matching `kag.*`, `rune.*` pattern

### Phase 5: Deploy Engine (weeks 19-24)

1. **Implement deployment stages** — staging → canary → production
2. **Production approval gate** — `approved_by` must be workspace admin
3. **Rollback support** — new deployment pointing to previous build
4. **OpenSentience integration** — manifest packaging for OpenSentience runtime

---

## Key Constraints

- **Builds are deterministic.** Same `{spec_hash, template_hash}` → same `artifact_hash`. No floating "latest" template references.
- **Templates are immutable.** Once published, a template version never changes. New versions require new records.
- **Only approved compiled tests are used.** Unapproved tests are skipped. This is the trust boundary.
- **Production deployments require human approval.** `approved_by` must be a workspace admin.
- **Agentelic does NOT make LLM calls for test compilation.** The compiled test intake generates a prompt; the agent or user executes it. Agentelic is a tool, not an agent.
- **Pipeline triggers validate source_hash.** A stale spec hash rejects the trigger.
- **workspace_id is required on all tables.** RLS enforces multi-tenant isolation.
- **user_id on agents is audit-only.** Created_by at agent creation; RLS uses workspace_id.

---

## Integration Points

| System | Direction | Protocol | What |
|--------|-----------|----------|------|
| **SpecPrompt** | SpecPrompt → Agentelic | CloudEvents / Supabase Realtime / GitHub | ConsolidationEvent triggers build pipeline |
| **FleetPrompt** | Agentelic → FleetPrompt | CloudEvents / Supabase Realtime | ConsolidationEvent on build success (artifact shipped) |
| **OS-008 Harness** | Agentelic ↔ OS-008 | MCP | Harness orchestrates build agent sessions |
| **OpenSentience** | Agentelic → OpenSentience | Manifest packaging | Deploy agents to OpenSentience runtime |
| **Graphonomous** | Agentelic → Graphonomous | MCP | Store build history, learned heuristics |
| **Delegatic** | Agentelic → Delegatic | MCP | Deploy gates, compliance checks |
| **PRISM** | Agentelic → PRISM | OutcomeSignal | Deploy success/regression feedback |

---

## Success Criteria

- [x] `agent_create` creates agent from customer-support SPEC.md
- [x] `agent_build` runs the 4-stage pipeline and produces a build artifact
- [x] Same `{spec_hash, template_hash}` always produces same `artifact_hash` (deterministic)
- [x] `agent_test` runs deterministic tests with mocked tool calls and produces pass/fail results
- [x] Compiled test intake loads approved SpecPrompt.CompiledTest[] and converts to Test.DSL format
- [x] Template pinning works at agent-level, workspace-level, and global default
- [x] MCP server discovers tools via `tools/list` and executes all 9 tools
- [x] Pipeline triggers fire on SpecPrompt ConsolidationEvent (all 3 transports)
- [x] Build success emits ConsolidationEvent to FleetPrompt
- [x] Production deployment requires `approved_by` validation against workspace admin
- [x] Supabase migration applies cleanly alongside existing `amp.*`, `kag.*`, `rune.*` schemas
