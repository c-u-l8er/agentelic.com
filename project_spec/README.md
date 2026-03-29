# Agentelic.com — Product Specification

**Date:** February 22, 2026
**Status:** v1.1
**Author:** [&] Ampersand Box Design
**License:** Proprietary (open-core model)

---

## Executive Summary

Agentelic is a **premium, enterprise-grade agent builder** that brings software engineering discipline to agent development. While the market is flooded with no-code agent builders optimized for demos, Agentelic targets the engineering teams that need to ship reliable agents to production — with versioned specs, deterministic testing, staged rollouts, and compliance gates.

Agentelic is the **engineering layer** of the [&] Ampersand Box portfolio:

```
SpecPrompt (Standards)    → defines agent behavior as versioned specs
    ↓
Agentelic (Engineering)   → builds, tests, deploys agents against specs  ← THIS
    ↓
OpenSentience (Runtime)   → governs, executes, observes agents locally
    ↓
Graphonomous (Memory)     → continual learning knowledge graphs
    ↓
FleetPrompt (Distribution) · Delegatic (Orchestration)
```

---

## 1. The Problem

According to LangChain's State of AI Agents 2026 survey, **57% of organizations now have agents in production** — but **32% cite quality as the #1 barrier** to scaling. Gartner predicts over **40% of agentic AI projects will be scrapped by 2027** — not because the models fail, but because organizations struggle to operationalize them. The failure isn't the AI — it's the engineering process around it.

The market in Feb 2026 is split: 20+ no-code builders (Gumloop, Lindy, Zapier) optimize for impressive first demos. Enterprise platforms like **OpenAI Frontier** (launched Feb 5, 2026) and **Salesforce AgentForce** provide governance but demand total lock-in. Neither serves engineering teams that need spec-driven design, deterministic testing, version control, compliance gates, and tool portability.

Meanwhile, only 52% of organizations run offline evaluations on test sets (LangChain survey) and 89% have implemented some form of observability — showing teams want reliability but don't have the tooling for it.

**Key market data:**
- AI agent builder market: $8B (2025) → $48B (2030) at 43.3% CAGR (BCC Research)
- Anthropic now captures 40% of enterprise LLM spend, up from 12% two years ago (Beam AI)
- McKinsey: Only 23% of enterprises are scaling AI agents; 39% remain stuck in experimentation
- PwC: 8 in 10 enterprises now use some form of agent-based AI

---

## 2. Design Principles

1. **Spec-driven** — Every agent starts from a SpecPrompt specification
2. **Testable** — Deterministic testing against specs, not probabilistic hope
3. **Versioned** — Git-native version control for agents, specs, and configs
4. **Governed** — Staged deployment with permission review gates
5. **Observable** — Full telemetry from build to production
6. **Local-first** — Deploys to OpenSentience, not a proprietary cloud

---

## 3. Competitive Positioning

| Dimension | Agentelic | No-Code Builders | OpenAI Frontier | Salesforce AgentForce | Dev Frameworks |
|-----------|-----------|-------------------|-----------------|-----------------------|----------------|
| Primary user | Engineering teams | Business users | Enterprise IT | IT + CRM teams | Developers |
| Spec-driven | Built-in (SpecPrompt) | None | None | None | Manual |
| Testing | Deterministic, first-class | None | Eval loops | Limited | DIY |
| Deployment | Git-native + OpenSentience | Cloud-only | OpenAI cloud | Salesforce cloud | Varies |
| Lock-in | None (MIT + MCP) | Medium | OpenAI | Salesforce | Minimal |
| Learning | Graphonomous | None | Feedback loops | None | None |
| Compliance | Built-in templates | None | IAM-based | Salesforce audit | Custom |
| Price | $49–custom/mo | $20–100/mo | Enterprise sales | Enterprise sales | Free/Paid |

---

## 4. Architecture

### 4.1 Component Stack

```
┌──────────────────────────────────────────────┐
│           Agentelic Studio (Web UI)           │
│   Spec editor · Test runner · Deploy console │
├──────────────────────────────────────────────┤
│              Build Pipeline                   │
│   Spec parse → Generate → Test → Package     │
├──────────────────────────────────────────────┤
│            Testing Framework                  │
│   Deterministic scenarios · Regression suites │
│   Mocked tool calls · Output validation      │
├──────────────────────────────────────────────┤
│           Deployment Engine                   │
│   Staging → Canary → Production              │
│   Permission review · Compliance gates       │
├──────────────────────────────────────────────┤
│          OpenSentience Runtime                │
│   Agent execution · Governance · Audit       │
├──────────────────────────────────────────────┤
│         Graphonomous Memory                   │
│   Continual learning · Knowledge graphs      │
└──────────────────────────────────────────────┘
```

### 4.2 Build Pipeline

```
SPEC.md
    │
    ▼
┌─────────────────┐
│ Spec Parser      │ Parse SpecPrompt format into
│                  │ structured requirements
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Code Generator   │ Generate agent implementation
│                  │ from parsed spec
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Test Generator   │ Generate deterministic test
│                  │ scenarios from acceptance criteria
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Test Runner      │ Execute tests with mocked
│                  │ tools and validated outputs
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Package Builder  │ Create OpenSentience-compatible
│                  │ agent manifest + bundle
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Deploy Engine    │ Stage → Canary → Production
│                  │ with permission review gates
└─────────────────┘
```

### 4.3 Deterministic Testing

```elixir
defmodule Agentelic.Test do
  @moduledoc """
  Deterministic testing framework for agents.
  Tests are derived from SpecPrompt acceptance criteria.
  """

  defmacro test_spec(spec_path) do
    # Parse SPEC.md
    # Generate test cases from acceptance criteria
    # Mock all MCP tool calls
    # Validate outputs against expected behavior
    # Report pass/fail with detailed traces
  end
end

# Generated test example:
describe "customer-support-v2" do
  test "returns order status for valid order" do
    # Arrange: mock orders:read tool
    mock_tool("orders:read", %{order_id: "123"}, %{status: "shipped"})

    # Act: send query to agent
    result = Agent.handle("What's the status of order #123?")

    # Assert: output matches spec criteria
    assert result.contains?("shipped")
    assert result.tool_calls == [{"orders:read", %{order_id: "123"}}]
    refute result.contains?("internal pricing")  # constraint check
  end

  test "escalates refunds over $500 to human" do
    result = Agent.handle("I want a refund for $750")
    assert result.escalated? == true
    assert result.escalation_reason =~ "exceeds $500 limit"
  end
end
```

### 4.4 Data Model (Ecto Schemas)

#### 4.4.1 Agents

```elixir
defmodule Agentelic.Agents.Agent do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "agents" do
    field :name, :string
    field :slug, :string
    field :description, :string
    field :status, Ecto.Enum, values: [:draft, :building, :testing, :deployable, :deployed, :archived]

    # Spec linkage
    field :spec_path, :string              # Path to SPEC.md (relative to project root)
    field :spec_hash, :string              # SHA-256 of SPEC.md at last build
    field :ampersand_path, :string         # Path to ampersand.json
    field :ampersand_hash, :string         # SHA-256 of ampersand.json at last build

    # Build metadata
    field :framework, :string              # e.g. "elixir", "typescript", "python"
    field :runtime_target, :string         # e.g. "opensentience", "cloudflare", "agentcore"
    field :last_build_at, :utc_datetime_usec
    field :last_test_at, :utc_datetime_usec

    belongs_to :user, Agentelic.Accounts.User, type: :binary_id
    has_many :builds, Agentelic.Builds.Build
    has_many :test_runs, Agentelic.Testing.TestRun
    has_many :deployments, Agentelic.Deploy.Deployment

    timestamps()
  end
end
```

**Invariants:**
- `slug` is globally unique, lowercase alphanumeric + hyphens
- `spec_hash` and `ampersand_hash` are recomputed on every build — stale hashes trigger a rebuild warning
- Status transitions: `draft → building → testing → deployable → deployed → archived`
- Only agents in `deployable` or `deployed` status can be published to FleetPrompt

#### 4.4.2 Builds

```elixir
defmodule Agentelic.Builds.Build do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "builds" do
    belongs_to :agent, Agentelic.Agents.Agent, type: :binary_id
    field :version, :string                # semver from SPEC.md frontmatter
    field :status, Ecto.Enum, values: [:pending, :parsing, :generating, :compiling, :succeeded, :failed]

    # Pipeline stages (each stores timing + output)
    field :parse_result, :map              # Parsed SpecPrompt.Spec struct as map
    field :parse_duration_ms, :integer
    field :generation_result, :map         # Generated code artifacts manifest
    field :generation_duration_ms, :integer
    field :compile_result, :map            # Compilation output (warnings, errors)
    field :compile_duration_ms, :integer

    # Artifact
    field :artifact_hash, :string          # SHA-256 of build output bundle
    field :artifact_path, :string          # Storage path for the bundle
    field :error_message, :string          # Human-readable error if failed

    # Provenance
    field :spec_hash, :string              # SHA-256 of SPEC.md at build time
    field :ampersand_hash, :string         # SHA-256 of ampersand.json at build time
    field :commit_hash, :string            # Git commit hash (optional)

    timestamps()
  end
end
```

**Invariants:**
- Builds are immutable after `succeeded` or `failed`
- `artifact_hash` is computed from the bundle contents — identical specs produce identical hashes (deterministic builds)
- `{agent_id, version}` is unique — no duplicate version numbers per agent

#### 4.4.3 Test Runs

```elixir
defmodule Agentelic.Testing.TestRun do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "test_runs" do
    belongs_to :agent, Agentelic.Agents.Agent, type: :binary_id
    belongs_to :build, Agentelic.Builds.Build, type: :binary_id
    field :status, Ecto.Enum, values: [:pending, :running, :passed, :failed, :error]

    # Results
    field :total_tests, :integer, default: 0
    field :passed_tests, :integer, default: 0
    field :failed_tests, :integer, default: 0
    field :error_tests, :integer, default: 0
    field :duration_ms, :integer

    # Individual test results
    embeds_many :results, Agentelic.Testing.TestResult
    field :coverage_summary, :map          # Which acceptance criteria were exercised

    timestamps()
  end
end

defmodule Agentelic.Testing.TestResult do
  use Ecto.Schema

  embedded_schema do
    field :test_name, :string              # Derived from acceptance test text
    field :given, :string                  # Precondition from SPEC.md
    field :expected, :string               # Expected behavior from SPEC.md
    field :actual, :string                 # Actual agent output
    field :status, Ecto.Enum, values: [:passed, :failed, :error]
    field :duration_ms, :integer
    field :tool_calls, {:array, :map}      # Recorded tool invocations
    field :assertions, {:array, :map}      # Each assertion: {type, expected, actual, passed}
    field :error_message, :string
  end
end
```

#### 4.4.4 Deployments

```elixir
defmodule Agentelic.Deploy.Deployment do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "deployments" do
    belongs_to :agent, Agentelic.Agents.Agent, type: :binary_id
    belongs_to :build, Agentelic.Builds.Build, type: :binary_id
    field :environment, Ecto.Enum, values: [:staging, :canary, :production]
    field :status, Ecto.Enum, values: [:deploying, :active, :rolled_back, :failed]

    # Target
    field :runtime_target, :string         # opensentience, cloudflare, agentcore
    field :runtime_ref, :map               # Provider-specific deployment reference

    # Governance
    field :autonomy_level, Ecto.Enum, values: [:observe, :advise, :act]
    field :delegatic_org_id, :string       # Delegatic org reference
    field :governance_policy_hash, :string # Hash of applied Delegatic policy at deploy time

    # Approval
    field :approved_by, :string            # Human approver for production deploys
    field :approval_reason, :string

    timestamps()
  end
end
```

**Invariants:**
- Production deployments MUST have `approved_by` set (canary and staging do not require approval)
- Only `passed` test runs can generate deployments
- `governance_policy_hash` captures the Delegatic policy at deploy time for audit reproducibility
- Rollback creates a new deployment pointing to a previous build — it does not mutate the original

### 4.5 API Surface (MCP Tools)

Agentelic exposes its build pipeline as MCP tools, enabling AI-assisted agent development:

| Tool | Input | Output | Description |
|------|-------|--------|-------------|
| `agent_create` | name, spec_path, ampersand_path, framework | agent_id, status | Create a new agent from a SPEC.md and ampersand.json |
| `agent_build` | agent_id | build_id, status, errors | Parse spec → generate code → compile → produce artifact |
| `agent_test` | agent_id, build_id | test_run_id, results | Run deterministic tests derived from acceptance criteria |
| `agent_deploy` | agent_id, build_id, environment, autonomy_level | deployment_id, status | Deploy to staging/canary/production with governance |
| `agent_status` | agent_id | agent, latest_build, latest_test, deployments | Full agent status summary |
| `spec_validate` | spec_path | errors, warnings | Validate SPEC.md against SpecPrompt grammar |
| `test_explain` | test_run_id, test_index | detailed_trace | Explain why a specific test passed/failed with full tool call trace |

### 4.6 Build Pipeline Specification

The build pipeline is a four-stage process. Each stage has typed input and output:

```
Stage 1: PARSE
  Input:  SPEC.md (raw markdown)
  Output: SpecPrompt.Spec (structured parsed spec — see SpecPrompt data model)
  Errors: Missing required sections, invalid frontmatter, malformed capability/test lines

Stage 2: GENERATE
  Input:  SpecPrompt.Spec + ampersand.json + framework template
  Output: Generated source files (agent module, tool bindings, config)
  Method: Template-based generation keyed on framework (Elixir, TypeScript, Python)
  Rules:
    - Each capability in the spec maps to a tool binding in the generated code
    - Each constraint maps to a runtime guard or validation check
    - Architecture section provides structural hints to the generator
    - The generator is deterministic: same spec + same template version = same output

Stage 3: COMPILE
  Input:  Generated source files
  Output: Compiled artifact (mix release, npm bundle, Python wheel)
  Errors: Syntax errors, type errors, missing dependencies

Stage 4: TEST
  Input:  Compiled artifact + acceptance tests from SPEC.md
  Output: TestRun with individual TestResults
  Method: For each acceptance test:
    1. Parse Given/When precondition → set up mocked tool state
    2. Send the precondition text as agent input
    3. Capture agent output + tool calls
    4. Validate output against Expected using:
       - Contains assertions (expected text appears in output)
       - Tool call assertions (expected tools were called with expected args)
       - Constraint assertions (no hard constraint was violated)
       - Negative assertions (forbidden content does not appear)
```

### 4.7 Deterministic Testing DSL (Normative)

```elixir
defmodule Agentelic.Test.DSL do
  @moduledoc """
  Deterministic testing DSL for agents built from SpecPrompt specs.
  Tests are generated from acceptance criteria, not hand-written.
  """

  @type assertion ::
    {:contains, String.t()} |
    {:not_contains, String.t()} |
    {:tool_called, tool_name :: String.t(), args :: map()} |
    {:tool_not_called, tool_name :: String.t()} |
    {:escalated, boolean()} |
    {:escalation_reason, Regex.t()} |
    {:response_time_ms, :lt, integer()}

  @type mock_spec :: %{
    tool_name: String.t(),
    match_args: map(),
    return: term()
  }

  @type test_case :: %{
    name: String.t(),
    given: String.t(),
    expected: String.t(),
    mocks: [mock_spec()],
    assertions: [assertion()],
    timeout_ms: integer()
  }

  @doc "Generate test cases from parsed SpecPrompt acceptance tests."
  @spec from_spec(SpecPrompt.Spec.t()) :: [test_case()]
  def from_spec(spec) do
    for test <- spec.acceptance_tests do
      %{
        name: test.given,
        given: test.given,
        expected: test.expected,
        mocks: infer_mocks(test, spec.capabilities),
        assertions: infer_assertions(test, spec.constraints),
        timeout_ms: 30_000
      }
    end
  end
end
```

---

## 5. Ecosystem Integration

| Product | How Agentelic Uses It |
|---------|---------------------|
| **SpecPrompt** | Specs are the primary input to the build pipeline |
| **OpenSentience** | Agents deploy to OpenSentience runtime via manifest packaging |
| **Graphonomous** | Agents connect for continual learning; memory grows with production use |
| **FleetPrompt** | Tested agents can be published to the marketplace |
| **Delegatic** | Multi-agent orchestration specs define agent roles and handoffs |

---

## 6. Gap Analysis & Competitive Landscape

### 6.1 Market Gap: The Demo-to-Production Gap

This is now the most-cited problem in the industry. LangChain's 2026 survey shows 57% of orgs have agents in production but quality (32%) and latency (20%) are top blockers. Gartner predicts **40% of agentic AI projects will be scrapped by 2027**. Kore.ai writes: "Agents don't fail because they're too advanced — they fail because they're not engineered for reality." OpenAI Frontier, launched Feb 5, 2026, is the highest-profile attempt to bridge this gap — but at the cost of complete vendor lock-in. Agentelic is the open alternative.

### 6.2 Enterprise Agent Platforms

| Platform | Focus | Gap Agentelic Fills |
|----------|-------|---------------------|
| **OpenAI Frontier** (Feb 2026) | Enterprise agent OS | Vendor lock-in (OpenAI), no spec-driven design, no deterministic testing |
| Salesforce AgentForce | CRM agents | Salesforce lock-in, CRM-only scope |
| Microsoft Agent Framework | Multi-agent orchestration | Azure lock-in, AutoGen convergence still early |
| Google Gemini Enterprise | Enterprise AI | Google lock-in, limited agent governance |
| Vellum | Visual builder + evals | No spec-driven design, no local deployment |
| Kore.ai | Enterprise agent platform | Proprietary, focused on conversational AI |

### 6.3 No-Code Agent Builders

| Platform | Focus | Gap Agentelic Fills |
|----------|-------|---------------------|
| Gumloop | No-code automation | No testing, no specs, no compliance |
| Lindy | AI employees | Cloud-only, no versioning, no audit |
| n8n | Workflow automation | Not agent-native, limited AI |
| Zapier AI | Workflow agents | Zapier ecosystem lock-in |

### 6.4 Industry Validation

1. **LangChain State of AI Agents 2026**: 57% in production, 32% cite quality as #1 barrier, only 52% run offline evals. Validates Agentelic's deterministic testing thesis.
2. **Gartner Prediction**: 40% of agentic AI projects scrapped by 2027 due to operationalization failures.
3. **OpenAI Frontier** (Feb 5, 2026): Enterprise agent platform launch — validates agent builder market. Fortune calls it OpenAI's bid for the enterprise OS.
4. **Anthropic Market Share**: 40% of enterprise LLM spend, up from 12%. Enterprise chooses reliability over frontier — aligns with Agentelic's thesis.
5. **McKinsey**: Only 23% of enterprises scaling AI agents; 39% stuck in experimentation. Gap is operationalization, not capability.
6. **Microsoft Agent Framework** (Dec 2025): Merging AutoGen + Semantic Kernel. PwC: 8 in 10 enterprises use some form of agent AI.

---

## 7. Pricing

| Tier | Price | Features |
|------|-------|----------|
| Builder | $49/mo | 5 agents, spec-driven design, testing, local deployment |
| Team | $199/mo/seat | Unlimited agents, staging + prod environments, RBAC, compliance templates, Graphonomous integration |
| Enterprise | Custom | Dedicated infra, SSO/SAML, custom compliance, SLA, managed Graphonomous, white-glove onboarding |

### 7.1 Revenue Projections

| Year | Pro Users | Team Seats | Enterprise | ARR |
|------|-----------|------------|------------|-----|
| Y1 | 200 | 50 | 2 | $263K |
| Y2 | 600 | 200 | 8 | $868K |
| Y3 | 1,200 | 500 | 20 | $1.82M |
| Y5 | 3,000 | 1,500 | 50 | $5.4M |

---

## 8. Implementation Roadmap

| Phase | Weeks | Deliverables |
|-------|-------|-------------|
| 0: Foundation | 1–6 | Spec parser, basic code generation, CLI tool |
| 1: Testing | 7–12 | Deterministic test framework, mocking system, regression runner |
| 2: Studio | 13–20 | Web UI for spec editing, test running, deployment |
| 3: Deploy | 21–26 | OpenSentience deployment integration, staging/prod, canary |
| 4: Enterprise | 27–36 | SSO, compliance templates, audit exports, managed instances |

---

## 9. Success Criteria

| Metric | MVP (9 months) | PMF (18 months) |
|--------|----------------|-----------------|
| Paying customers | 50+ | 500+ |
| ARR | $50K+ | $500K+ |
| Agents built | 500+ | 10,000+ |
| Enterprise clients | 2+ | 10+ |
| NPS | 40+ | 60+ |

---

*[&] Ampersand Box Design — agentelic.com*
