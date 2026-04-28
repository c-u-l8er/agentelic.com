# Agentelic — User Stories

Canonical user-story catalog. Used for Playwright tests + Claude Design input.

**Scope:** Premium agent builder — spec → template → generate → compile → test → deploy pipeline.
**Unit-test surface covered:** `test/**` (66 tests).

---

## Story 1 · Build agent from spec

- **Persona:** Engineering team creating production agent from SpecPrompt SPEC.md
- **Goal:** Transform SPEC.md into compiled, tested, deployable agent code automatically
- **Prerequisite:** SPEC.md validated; ampersand.json present; framework template pinned
- **Steps:**
  1. Create agent in Studio: `agent_create` with name + spec_path + ampersand_path + framework
  2. Status: draft → building
  3. Build pipeline: parse SPEC.md → resolve template → generate source → compile
  4. Pin `template_version` + `template_hash` for deterministic rebuilds
  5. Build completes with `artifact_hash`
- **Success:** Same `{spec_hash, template_hash}` → identical `artifact_hash` (reproducible)
- **Covers:** `Agents.create`, `Build.run_pipeline`, `Generator.from_spec_and_template`, `Compiler.compile` — ~20 unit tests
- **UI status:** exists-today (Studio)
- **Claude Design hook:** Build console with parse → generate → compile stages + timing + code diff preview

## Story 2 · Run deterministic tests against spec

- **Persona:** QA engineer validating agent behavior against acceptance criteria
- **Goal:** Execute tests derived from spec without hand-writing test code
- **Prerequisite:** Build succeeded; `compiled_tests_hash` present; agent in `testing` status
- **Steps:**
  1. Call `agent_test` MCP tool with agent_id + build_id
  2. Pulls approved compiled tests from SpecPrompt registry
  3. For each test: set up mocked tool state → send input → capture output + tool calls
  4. Validate against assertions (contains, tool_called, constraint_respected)
  5. Return TestRun with pass/fail per test + coverage summary
- **Success:** All tests pass; spec constraints validated; regression suite cached
- **Covers:** `Testing.TestRunner.run`, `Mock.setup_tool_state`, `Assertion.validate_output` — ~18 unit tests
- **UI status:** exists-today
- **Claude Design hook:** Test results dashboard with per-test trace viewer + mocked tool call history + constraint violation inspector

## Story 3 · Deploy to staging with permission review

- **Persona:** DevOps engineer deploying agent to staging
- **Goal:** Deploy with governance validation but no human approval (staging only)
- **Prerequisite:** Build passed tests; agent status `deployable`
- **Steps:**
  1. Call `agent_deploy` with environment=staging, autonomy_level=observe
  2. Delegatic policy check (staging doesn't require approval)
  3. OpenSentience deploys manifest with capability tokens
  4. Status: deploying → active
  5. Agent in observe mode; tool calls logged but sandboxed
- **Success:** Agent live in staging; isolated from prod; all permissions enforced
- **Covers:** `Deploy.deploy_to_environment`, `Deploy.validate_delegatic_policy`, deployment records — ~15 unit tests
- **UI status:** exists-today
- **Claude Design hook:** Deploy pipeline UI with environment picker + autonomy level selector + approval status

## Story 4 · Promote to production with approval gate

- **Persona:** Engineering lead approving production rollout
- **Goal:** Manually gate production; ensure tests passed + policy approved
- **Prerequisite:** Agent tested in staging; governance_policy_hash computed
- **Steps:**
  1. Call `agent_deploy` with environment=production, autonomy_level=act
  2. System requires approval field
  3. Lead reviews build pass/fail, coverage, policy hash
  4. Approve with reason
  5. Record `approved_by` + `approval_reason` in Deployments table
- **Success:** Production agent live; human approval recorded; audit trail preserved
- **Covers:** `Deploy.require_approval_for_production`, `Deploy.validate_approver_role`, `record_approval_decision` — ~10 unit tests
- **UI status:** exists-today
- **Claude Design hook:** Approval modal with build summary + policy checklist + approval reason textarea + timestamp

## Story 5 · Explain test failure with trace

- **Persona:** Engineer debugging why a test failed
- **Goal:** View detailed trace of test execution — mocked tool calls + assertion failures
- **Prerequisite:** Test run failed
- **Steps:**
  1. Click failed test result card
  2. Call `test_explain` with test_run_id + test_index
  3. System returns: given / expected / actual / tool_calls trace / assertion failures
  4. Engineer sees mock setup + why assertion failed
- **Success:** Clear root cause identified; assertion failure inspectable
- **Covers:** `Testing.explain_failure`, `TestResult.format_trace`, `Assertion.explain_mismatch` — ~8 unit tests
- **UI status:** exists-today
- **Claude Design hook:** Collapsible trace viewer — mock setup / input / output / tool calls / assertion breakdown

---

**Note:** Agentelic's web UI at `agentelic.fly.dev/` currently returns 404 (MCP+API only). Stories 1-5 all need a Studio UI built. Strong Claude Design candidate.

**Tests to implement first:** once a Studio landing exists, start with Story 1 (build) + Story 2 (test). Until then, all 5 are `mcp-only`.
