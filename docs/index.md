# Agentelic Documentation

> **Build agents like software. Spec-driven. Tested. Deployed.**

Welcome to the documentation hub for **Agentelic** — a premium, enterprise-grade
agent builder that brings software engineering discipline to AI agent development.

Agentelic targets the engineering teams that need to ship reliable agents to
production — with versioned specs, deterministic testing, staged rollouts, and
compliance gates. While the market is flooded with no-code agent builders optimized
for demos, Agentelic is optimized for production.

---

## What Agentelic Does

Agentelic is the **engineering layer** of the [&] Protocol ecosystem:

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

**Key capabilities:**

- **Spec-driven builds** — Every agent starts from a SpecPrompt specification.
  Parse, generate, compile, and package in one pipeline.
- **Deterministic testing** — Tests are derived from acceptance criteria, not
  hand-written. Mocked tool calls, output validation, regression suites.
- **Staged deployment** — Staging → canary → production with permission review
  gates and compliance checks.
- **MCP tool surface** — The entire build pipeline is exposed as MCP tools for
  AI-assisted agent development.

---

## Documentation Map


```{toctree}
:maxdepth: 1
:caption: Homepages

[&] Ampersand Box <https://ampersandboxdesign.com>
Graphonomous <https://graphonomous.com>
BendScript <https://bendscript.com>
WebHost.Systems <https://webhost.systems>
Agentelic <https://agentelic.com>
AgenTroMatic <https://agentromatic.com>
Delegatic <https://delegatic.com>
Deliberatic <https://deliberatic.com>
FleetPrompt <https://fleetprompt.com>
GeoFleetic <https://geofleetic.com>
OpenSentience <https://opensentience.org>
SpecPrompt <https://specprompt.com>
TickTickClock <https://ticktickclock.com>
```

```{toctree}
:maxdepth: 1
:caption: Root Docs

[&] Protocol Docs <https://docs.ampersandboxdesign.com>
Graphonomous Docs <https://docs.graphonomous.com>
BendScript Docs <https://docs.bendscript.com>
WebHost.Systems Docs <https://docs.webhost.systems>
Agentelic Docs <https://docs.agentelic.com>
AgenTroMatic Docs <https://docs.agentromatic.com>
Delegatic Docs <https://docs.delegatic.com>
Deliberatic Docs <https://docs.deliberatic.com>
FleetPrompt Docs <https://docs.fleetprompt.com>
GeoFleetic Docs <https://docs.geofleetic.com>
OpenSentience Docs <https://docs.opensentience.org>
SpecPrompt Docs <https://docs.specprompt.com>
TickTickClock Docs <https://docs.ticktickclock.com>
```

```{toctree}
:maxdepth: 2
:caption: Agentelic Docs

spec/README
```

---

## Architecture at a Glance

| Component | Role |
|-----------|------|
| **Agentelic Studio** | Web UI — spec editor, test runner, deploy console |
| **Build Pipeline** | Spec parse → code generate → compile → package |
| **Testing Framework** | Deterministic scenarios, mocked tools, regression suites |
| **Deployment Engine** | Staging → canary → production with governance gates |
| **OpenSentience Runtime** | Agent execution, governance, audit |
| **Graphonomous Memory** | Continual learning knowledge graphs |

---

## MCP Tools

| Tool | Description |
|------|-------------|
| `agent_create` | Create a new agent from a SPEC.md and ampersand.json |
| `agent_build` | Parse spec → generate code → compile → produce artifact |
| `agent_test` | Run deterministic tests derived from acceptance criteria |
| `agent_deploy` | Deploy to staging/canary/production with governance |
| `agent_status` | Full agent status summary |
| `spec_validate` | Validate SPEC.md against SpecPrompt grammar |
| `test_explain` | Explain why a specific test passed/failed |

---

## Ecosystem Integration

| Product | How Agentelic Uses It |
|---------|---------------------|
| **SpecPrompt** | Specs are the primary input to the build pipeline |
| **OpenSentience** | Agents deploy to OpenSentience runtime via manifest packaging |
| **Graphonomous** | Agents connect for continual learning; memory grows with production use |
| **FleetPrompt** | Tested agents can be published to the marketplace |
| **Delegatic** | Multi-agent orchestration specs define agent roles and handoffs |

---

## Project Links

- **Spec:** [Technical Specification](spec/README.md)
- **[&] Protocol ecosystem:** `AmpersandBoxDesign/`

---

*[&] Ampersand Box Design — agentelic.com*
