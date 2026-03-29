# Agentelic — Enterprise Agent Builder

Premium, enterprise-grade agent builder that brings software engineering discipline to AI agent development. Spec-driven builds, deterministic testing, staged deployments.

## Source-of-truth spec

- `docs/spec/README.md` — Agentelic product specification

## Role in [&] Ecosystem

Agentelic is the **engineering layer**:

```
SpecPrompt (Standards) → Agentelic (Engineering) → OpenSentience (Runtime) → Graphonomous (Memory)
```

Every agent starts from a SpecPrompt specification, is tested deterministically, and deployed through staged rollouts with compliance gates.

## Key features

- Spec-driven build pipeline (parse → generate → compile → package)
- Deterministic testing derived from acceptance criteria
- Staged deployment (staging → canary → production) with governance gates
- MCP tool surface for AI-assisted agent development

## Status

This is a spec + marketing site. No implementation code yet. Implementation will be Elixir/OTP.
