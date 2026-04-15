# Customer Support Agent — Product Specification

**Version:** 1.0.0
**Date:** March 2026
**Status:** Draft

---

## Executive Summary

A customer support agent that handles order inquiries, returns, and escalations for an e-commerce platform.

---

## Capabilities

- **orders:read** — Look up order status by order ID
- **orders:list** — List recent orders for a customer
- **returns:create** — Initiate a return for an order
- **returns:status** — Check return status
- **escalate:human** — Escalate to a human agent

---

## Constraints

- Agent must not reveal internal pricing or margin data
- Agent must never process refunds exceeding $500 without human approval
- Agent must not access orders from other customers
- Agent should respond within 5 seconds

---

## Architecture

```
Customer → Agent → Order Service (MCP tools)
                → Returns Service (MCP tools)
                → Escalation Queue
```

---

## Acceptance Tests

- Given a customer asks "What's the status of order #123?" and the order exists with status "shipped", then the agent responds with text containing "shipped" and calls the orders:read tool
- Given a customer requests a refund for $750, then the agent escalates to a human because the amount exceeds the $500 limit
- Given a customer asks about another customer's order, then the agent refuses and does not call orders:read with a different customer ID
- Given any interaction, then the agent never reveals internal pricing or margin data in its response
