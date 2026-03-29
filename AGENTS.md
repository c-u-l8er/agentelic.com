# Agentelic — Agent Interface

Agentelic is the enterprise agent builder for the [&] Protocol ecosystem. It builds, tests, and deploys agents from SpecPrompt specifications.

## MCP Tools (planned)

| Tool | Description |
|------|-------------|
| `agent_create` | Create a new agent from a SPEC.md and ampersand.json |
| `agent_build` | Parse spec → generate code → compile → produce artifact |
| `agent_test` | Run deterministic tests derived from acceptance criteria |
| `agent_deploy` | Deploy to staging/canary/production with governance |
| `agent_status` | Full agent status summary |
| `spec_validate` | Validate SPEC.md against SpecPrompt grammar |
| `test_explain` | Explain why a specific test passed/failed |

## Pipeline Position

```
SpecPrompt (define) → Agentelic (build + test) → FleetPrompt (distribute) → OpenSentience (run)
```

## Status

Spec complete. Implementation pending. See `docs/spec/README.md`.
