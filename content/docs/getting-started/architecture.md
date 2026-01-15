---
title: "Architecture"
description: "Architecture - Resolute documentation"
weight: 50
toc: true
---


# Architecture

How Resolute works and relates to Temporal.

:::info Coming Soon
This page is under development.
:::

## High-Level Architecture

_Diagram and explanation coming in Phase 1_

## Resolute vs Raw Temporal

| Aspect | Raw Temporal | Resolute |
|--------|--------------|----------|
| Workflow Definition | Imperative code | Declarative builder |
| Type Safety | Manual | Generic nodes `Node[I,O]` |
| State Management | Manual signals/queries | Built-in FlowState |
| Patterns | Implement yourself | Built-in (Saga, pagination) |
| Testing | Temporal test framework | FlowTester harness |

## When to Use Resolute

- Building data pipelines
- Multi-step integrations
- Scheduled batch processing
- Any workflow that benefits from declarative definition
