---
title: "Hooks"
description: "Hooks - Resolute documentation"
weight: 60
toc: true
---

# Hooks

**Hooks** provide lifecycle callbacks at flow, step, and node execution boundaries. Use them for observability, cost tracking, metrics, and audit logging.

## What are Hooks?

Hooks fire at well-defined points during flow execution:

```
┌─────────────────────────────────────────────────────────────────────┐
│                        Hook Execution Points                         │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  BeforeFlow ─────────────────────────────────────────── AfterFlow   │
│  │                                                           │      │
│  │  BeforeStep ──────────────────────────── AfterStep        │      │
│  │  │                                           │            │      │
│  │  │  BeforeNode ──── [execute] ──── AfterNode │            │      │
│  │  │  BeforeNode ──── [execute] ──── AfterNode │            │      │
│  │  │                                           │            │      │
│  │  BeforeStep ──────────────────────────── AfterStep        │      │
│  │  │                                           │            │      │
│  │  │  BeforeNode ──── [execute] ──── AfterNode │            │      │
│  │  │                                           │            │      │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

All callbacks are optional. Nil callbacks are safely skipped — you only implement what you need.

## FlowHooks

```go
type FlowHooks struct {
    BeforeFlow func(HookContext)
    AfterFlow  func(HookContext)
    BeforeStep func(HookContext)
    AfterStep  func(HookContext)
    BeforeNode func(HookContext)
    AfterNode  func(HookContext)
    OnCost     func(CostEntry)
}
```

## HookContext

Every callback receives a `HookContext` with structured metadata about the current execution point:

```go
type HookContext struct {
    FlowName string
    StepName string
    NodeName string
    Duration time.Duration  // populated in After* callbacks only
    Error    error          // populated in After* callbacks only
}
```

| Field | Before* | After* |
|-------|---------|--------|
| `FlowName` | Always set | Always set |
| `StepName` | Set in step/node hooks | Set in step/node hooks |
| `NodeName` | Set in node hooks | Set in node hooks |
| `Duration` | Zero | Actual execution duration |
| `Error` | nil | Error if execution failed |

## Attaching Hooks

Use `.WithHooks()` on a FlowBuilder or FlowTemplate:

```go
flow := core.NewFlow("my-flow").
    TriggeredBy(core.Schedule("*/15 * * * *")).
    WithHooks(&core.FlowHooks{
        AfterNode: func(ctx core.HookContext) {
            log.Info("node completed",
                "flow", ctx.FlowName,
                "node", ctx.NodeName,
                "duration", ctx.Duration,
            )
        },
    }).
    Then(fetchNode).
    Then(processNode).
    Build()
```

## Cost Tracking

The `OnCost` callback receives `CostEntry` events emitted by nodes (typically LLM providers like `resolute-ollama`):

```go
type CostEntry struct {
    NodeName  string
    Model     string
    Provider  string
    TokensIn  int
    TokensOut int
    CostUSD   float64
    Duration  time.Duration
    Metadata  map[string]string
}
```

```go
flow := core.NewFlow("ai-pipeline").
    TriggeredBy(core.Manual("api")).
    WithHooks(&core.FlowHooks{
        OnCost: func(entry core.CostEntry) {
            metrics.RecordTokenUsage(entry.Model, entry.TokensIn, entry.TokensOut)
            metrics.RecordCostUSD(entry.Provider, entry.CostUSD)
        },
    }).
    Then(embedNode).
    Then(classifyNode).
    Build()
```

## Determinism Constraint

Hooks run inside Temporal's deterministic workflow context. They must **not** perform I/O directly (HTTP calls, database writes, file operations). For side effects, enqueue activities from within the callback:

```go
// Bad: direct I/O in hook
AfterFlow: func(ctx core.HookContext) {
    db.Insert(ctx)  // will break Temporal determinism
}

// Good: use hooks for in-memory operations only
AfterFlow: func(ctx core.HookContext) {
    metrics.Record(ctx.FlowName, ctx.Duration)  // in-memory counter
}
```

## Use Cases

| Use Case | Callbacks | Description |
|----------|-----------|-------------|
| Execution logging | `BeforeFlow`, `AfterFlow` | Log flow start/end with duration |
| Step monitoring | `AfterStep` | Track step failures and durations |
| Node-level metrics | `AfterNode` | Record per-node execution time and errors |
| LLM cost tracking | `OnCost` | Aggregate token usage and USD cost |
| Audit trail | `BeforeNode`, `AfterNode` | Record which nodes ran and their outcomes |

## See Also

- **[Flows](/docs/concepts/flows/)** — How hooks integrate with flow execution
- **[Providers](/docs/concepts/providers/)** — Providers that emit cost events
