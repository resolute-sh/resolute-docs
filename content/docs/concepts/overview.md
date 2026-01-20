---
title: "Overview"
description: "Overview - Resolute documentation"
weight: 10
toc: true
---


# Concepts Overview

Resolute is an **Agent Orchestration as Code** framework that provides type-safe, composable abstractions over Temporal workflows. It lets you define complex workflows as code while inheriting Temporal's durability guarantees.

## Design Philosophy

1. **Type Safety** - Generic nodes (`Node[I, O]`) enforce compile-time type checking for inputs and outputs
2. **Composability** - Flows are built from reusable nodes that can be combined in sequence or parallel
3. **Observability** - Every execution step is visible in Temporal's UI with full input/output history
4. **Testability** - Flows can be unit tested without running Temporal using `FlowTester`

## Core Abstractions

| Concept | Description | Go Type |
|---------|-------------|---------|
| **[Flow](/docs/concepts/flows/)** | A complete workflow definition with triggers and steps | `*Flow` |
| **[Node](/docs/concepts/nodes/)** | A typed wrapper around a Temporal activity | `*Node[I, O]` |
| **[Trigger](/docs/concepts/triggers/)** | How a flow is initiated (manual, schedule, signal) | `Trigger` |
| **[FlowState](/docs/concepts/state/)** | Runtime state carrying data through execution | `*FlowState` |
| **[Provider](/docs/concepts/providers/)** | A collection of related activities | `Provider` |
| **[Worker](/docs/concepts/workers/)** | The execution environment for flows | `*Worker` |

## Architecture Overview

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                                  Your Application                             │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                               │
│   ┌─────────────────────────────────────────────────────────────────────┐    │
│   │                             Worker                                    │    │
│   │                                                                       │    │
│   │   ┌─────────────────────────────────────────────────────────────┐   │    │
│   │   │                          Flow                                │   │    │
│   │   │   ┌─────────┐                                               │   │    │
│   │   │   │ Trigger │ ─────────────────────────────────┐            │   │    │
│   │   │   └─────────┘                                  │            │   │    │
│   │   │        │                                       │            │   │    │
│   │   │        ▼                                       ▼            │   │    │
│   │   │   ┌─────────┐    ┌─────────┐    ┌───────────────────┐      │   │    │
│   │   │   │  Node   │───▶│  Node   │───▶│  Parallel Step    │      │   │    │
│   │   │   │  [I,O]  │    │  [I,O]  │    │ ┌─────┐ ┌─────┐  │      │   │    │
│   │   │   └─────────┘    └─────────┘    │ │Node │ │Node │  │      │   │    │
│   │   │        │              │         │ └─────┘ └─────┘  │      │   │    │
│   │   │        ▼              ▼         └───────────────────┘      │   │    │
│   │   │   ┌─────────────────────────────────────────────────┐      │   │    │
│   │   │   │                   FlowState                      │      │   │    │
│   │   │   │  ┌─────────┐  ┌─────────┐  ┌─────────────────┐  │      │   │    │
│   │   │   │  │ Results │  │ Cursors │  │ Input (bytes)   │  │      │   │    │
│   │   │   │  └─────────┘  └─────────┘  └─────────────────┘  │      │   │    │
│   │   │   └─────────────────────────────────────────────────┘      │   │    │
│   │   └─────────────────────────────────────────────────────────────┘   │    │
│   │                                                                       │    │
│   │   ┌─────────────────────────────────────────────────────────────┐   │    │
│   │   │                     Providers                                 │   │    │
│   │   │   ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐   │   │    │
│   │   │   │   Jira   │  │  Ollama  │  │  Qdrant  │  │  Custom  │   │   │    │
│   │   │   │ Provider │  │ Provider │  │ Provider │  │ Provider │   │   │    │
│   │   │   └──────────┘  └──────────┘  └──────────┘  └──────────┘   │   │    │
│   │   └─────────────────────────────────────────────────────────────┘   │    │
│   └─────────────────────────────────────────────────────────────────────┘    │
│                                                                               │
└───────────────────────────────────────────────────────────────────────────────┘
                                       │
                                       │ gRPC
                                       ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│                             Temporal Server                                   │
│   ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────────────┐  │
│   │ Workflow History │  │   Task Queues    │  │   Visibility (Search)    │  │
│   └──────────────────┘  └──────────────────┘  └──────────────────────────┘  │
└──────────────────────────────────────────────────────────────────────────────┘
```

## Execution Model

### 1. Registration Phase

When a Worker starts, it registers flows with Temporal:

```go
worker := core.NewWorker().
    WithConfig(core.WorkerConfig{
        TaskQueue:    "my-queue",
        TemporalHost: "localhost:7233",
    }).
    WithFlow(myFlow).
    WithProvider(jiraProvider).
    Run()
```

The worker:
1. Connects to Temporal server via gRPC
2. Registers the flow as a workflow type
3. Registers all provider activities
4. Starts polling the task queue

### 2. Trigger Phase

Flows start when their trigger fires:

| Trigger Type | How It Fires |
|--------------|--------------|
| `Manual(id)` | API call or `temporal workflow start` CLI |
| `Schedule(cron)` | Temporal's built-in scheduler (e.g., `"*/15 * * * *"`) |
| `Signal(name)` | External signal sent to a running workflow |

### 3. Execution Phase

When triggered, the flow executes:

```
┌────────────────────────────────────────────────────────────────────┐
│                      Flow Execution                                 │
├────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  1. Initialize FlowState                                           │
│     └─▶ Load persisted cursors from StateBackend                   │
│                                                                     │
│  2. For each Step:                                                  │
│     ├─▶ Sequential: Execute node, store result in FlowState        │
│     ├─▶ Parallel: Execute nodes concurrently, await all            │
│     └─▶ Conditional: Evaluate predicate, pick branch               │
│                                                                     │
│  3. On failure:                                                     │
│     └─▶ Run compensation nodes in reverse (Saga pattern)           │
│                                                                     │
│  4. On success:                                                     │
│     └─▶ Persist updated cursors to StateBackend                    │
│                                                                     │
└────────────────────────────────────────────────────────────────────┘
```

### 4. Activity Execution

Each Node wraps a Temporal activity:

```go
// Node definition
fetchNode := core.NewNode("fetch", fetchIssues, FetchInput{}).
    WithTimeout(1 * time.Minute).
    WithRetry(core.RetryPolicy{
        MaximumAttempts: 3,
    })

// When executed:
// 1. WithInputFunc builds input from FlowState
// 2. Activity runs with timeout and retry
// 3. Output stored in FlowState under node name
// 4. Next node can access via core.Get[T](state, "fetch")
```

## Data Flow

Data flows through the workflow via FlowState:

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Data Flow                                    │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│   ┌──────────┐         ┌──────────┐         ┌──────────┐           │
│   │  fetch   │         │transform │         │   store  │           │
│   │  Node    │         │  Node    │         │   Node   │           │
│   └────┬─────┘         └────┬─────┘         └────┬─────┘           │
│        │                    │                    │                  │
│        │ FetchOutput        │ TransformOutput    │ StoreOutput      │
│        │                    │                    │                  │
│        ▼                    ▼                    ▼                  │
│   ┌─────────────────────────────────────────────────────────────┐  │
│   │                       FlowState                              │  │
│   │                                                              │  │
│   │  results: {                                                  │  │
│   │    "fetch":     FetchOutput{Issues: [...]}                   │  │
│   │    "transform": TransformOutput{Documents: [...]}            │  │
│   │    "store":     StoreOutput{Key: "..."}                      │  │
│   │  }                                                           │  │
│   │                                                              │  │
│   │  cursors: {                                                  │  │
│   │    "jira-issues": Cursor{Position: "2024-01-15T10:00:00Z"}   │  │
│   │  }                                                           │  │
│   └─────────────────────────────────────────────────────────────┘  │
│        ▲                    ▲                    ▲                  │
│        │                    │                    │                  │
│        │ WithInputFunc      │ WithInputFunc      │ WithInputFunc    │
│        │ reads "fetch"      │ reads "transform"  │ reads "store"    │
│        │                    │                    │                  │
│   ┌────┴─────┐         ┌────┴─────┐         ┌────┴─────┐           │
│   │transform │         │   store  │         │  notify  │           │
│   │  Node    │         │   Node   │         │   Node   │           │
│   └──────────┘         └──────────┘         └──────────┘           │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### Typed Access

FlowState uses generics for type-safe access:

```go
// Store typed output
core.Set(state, "fetch", FetchOutput{Issues: issues})

// Retrieve with type safety (panics on type mismatch)
result := core.Get[FetchOutput](state, "fetch")

// Retrieve with default fallback
result := core.GetOr(state, "fetch", FetchOutput{})
```

## Temporal Foundation

Resolute inherits powerful guarantees from Temporal:

| Capability | How Resolute Uses It |
|------------|---------------------|
| **Durable Execution** | Workflow state survives worker restarts and crashes |
| **Automatic Retries** | `WithRetry()` configures retry policies per node |
| **Event Sourcing** | Complete execution history visible in Temporal UI |
| **Timeouts** | `WithTimeout()` sets activity timeouts |
| **Scalability** | Run multiple workers on the same task queue |
| **Versioning** | Use Temporal's workflow versioning for migrations |

### What Temporal Handles

- Task scheduling and distribution
- Workflow state persistence
- Activity retry with backoff
- Visibility and search
- Timer management (for schedules)

### What Resolute Adds

- Type-safe node composition
- Fluent builder API for flow definition
- Provider abstraction for reusable activities
- FlowState for inter-node data passing
- Cursor tracking for incremental processing
- FlowTester for unit testing without Temporal

## Comparison with Raw Temporal

| Aspect | Raw Temporal SDK | Resolute |
|--------|------------------|----------|
| **Workflow Definition** | Imperative code with workflow functions | Declarative `FlowBuilder` DSL |
| **Activity Typing** | Manual type assertions | Generic `Node[I, O]` |
| **State Management** | Manual via workflow context | `FlowState` with typed accessors |
| **Provider Pattern** | Build your own | Built-in `Provider` interface |
| **Testing** | Requires Temporal test environment | `FlowTester` mocks activities |

See [Temporal Foundation](/docs/concepts/temporal-foundation/) for a deeper comparison.

## Quick Reference

### Building a Flow

```go
flow := core.NewFlow("my-flow").
    TriggeredBy(core.Schedule("0 * * * *")).  // Every hour
    Then(fetchNode).                           // Sequential
    ThenParallel("parallel-step",              // Parallel
        processNodeA,
        processNodeB,
    ).
    Then(storeNode).
    Build()
```

### Creating a Node

```go
node := core.NewNode("fetch", fetchActivity, FetchInput{}).
    WithInputFunc(func(state *core.FlowState) FetchInput {
        return FetchInput{Since: state.GetCursor("source").TimeOr(time.Now())}
    }).
    WithTimeout(5 * time.Minute).
    WithRetry(core.RetryPolicy{MaximumAttempts: 3}).
    WithCompensation(compensateNode)
```

### Running a Worker

```go
core.NewWorker().
    WithConfig(core.WorkerConfig{
        TaskQueue:    "my-queue",
        TemporalHost: "localhost:7233",
    }).
    WithFlow(flow).
    WithProvider(myProvider).
    Run()
```

## Next Steps

Dive deeper into each concept:

- **[Flows](/docs/concepts/flows/)** - Workflow composition and execution
- **[Nodes](/docs/concepts/nodes/)** - Typed activity wrappers
- **[State](/docs/concepts/state/)** - Runtime state and cursors
- **[Triggers](/docs/concepts/triggers/)** - Manual, schedule, and signal triggers
- **[Providers](/docs/concepts/providers/)** - Reusable activity collections
- **[Workers](/docs/concepts/workers/)** - Execution environment configuration
