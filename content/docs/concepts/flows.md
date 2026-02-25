---
title: "Flows"
description: "Flows - Resolute documentation"
weight: 20
toc: true
---


# Flows

A **Flow** is the top-level container representing a complete workflow definition. It defines what triggers execution, which steps run, and in what order.

## What is a Flow?

A Flow encapsulates:
- **Trigger** - How the workflow starts (manual, schedule, or signal)
- **Steps** - The sequence of nodes to execute
- **State Configuration** - How cursors and state are persisted

Flows map directly to Temporal workflows. When you build a flow, you're defining a workflow that Temporal will execute with full durability guarantees.

## Flow Lifecycle

```
┌─────────────────────────────────────────────────────────────────────┐
│                        Flow Lifecycle                                │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  1. DEFINITION                                                       │
│     └─▶ FlowBuilder creates Flow struct with steps and trigger      │
│                                                                      │
│  2. REGISTRATION                                                     │
│     └─▶ Worker.WithFlow() registers workflow with Temporal          │
│                                                                      │
│  3. TRIGGER                                                          │
│     ├─▶ Manual: API call or CLI command                              │
│     ├─▶ Schedule: Temporal scheduler fires at cron time             │
│     └─▶ Signal: External signal received                             │
│                                                                      │
│  4. EXECUTION                                                        │
│     ├─▶ FlowState initialized, cursors loaded                       │
│     ├─▶ Steps execute sequentially (or in parallel)                  │
│     ├─▶ Results stored in FlowState after each step                 │
│     └─▶ On failure: compensation runs in reverse                     │
│                                                                      │
│  5. COMPLETION                                                       │
│     └─▶ Cursors persisted, workflow marked complete                  │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

## Creating Flows

Use the fluent `FlowBuilder` API to construct flows:

```go
flow := core.NewFlow("my-flow").
    TriggeredBy(core.Manual("api")).
    Then(fetchNode).
    Then(processNode).
    Then(storeNode).
    Build()
```

### FlowBuilder Methods

| Method | Description |
|--------|-------------|
| `NewFlow(name)` | Create a new flow builder with the given name |
| `.TriggeredBy(trigger)` | Set how the flow is initiated |
| `.Then(node)` | Add a sequential step |
| `.ThenParallel(name, ...nodes)` | Add parallel nodes that execute concurrently |
| `.ThenGate(name, config)` | Add a gate step that pauses until a signal is received |
| `.ThenChildren(name, config)` | Add a step that spawns child workflows |
| `.WithHooks(hooks)` | Attach lifecycle callbacks (BeforeFlow, AfterNode, etc.) |
| `.WithState(config)` | Configure state persistence backend |
| `.Build()` | Validate and finalize the flow |

## Sequential Execution

The `.Then()` method adds nodes that execute one after another:

```go
flow := core.NewFlow("etl-pipeline").
    TriggeredBy(core.Schedule("0 * * * *")).  // Every hour
    Then(extractNode).   // Runs first
    Then(transformNode). // Runs after extract completes
    Then(loadNode).      // Runs after transform completes
    Build()
```

Each node waits for the previous node to complete before starting. If any node fails, execution stops and compensation runs (if configured).

## Parallel Execution

Use `.ThenParallel()` to run multiple nodes concurrently:

```go
flow := core.NewFlow("multi-source-sync").
    TriggeredBy(core.Manual("sync")).
    Then(fetchConfigNode).
    ThenParallel("fetch-sources",
        fetchJiraNode,
        fetchConfluenceNode,
        fetchSlackNode,
    ).
    Then(aggregateNode).  // Runs after all parallel nodes complete
    Build()
```

Parallel execution:
- All nodes in the parallel step start simultaneously
- The step completes when **all** parallel nodes finish
- If any node fails, the entire parallel step fails
- Results from all nodes are available in FlowState

### Parallel Step Diagram

```
                    ┌─────────────┐
                    │ fetchConfig │
                    └──────┬──────┘
                           │
           ┌───────────────┼───────────────┐
           │               │               │
           ▼               ▼               ▼
    ┌────────────┐  ┌────────────┐  ┌────────────┐
    │ fetchJira  │  │fetchConfl. │  │ fetchSlack │
    └─────┬──────┘  └─────┬──────┘  └─────┬──────┘
           │               │               │
           └───────────────┼───────────────┘
                           │
                           ▼ (waits for all)
                    ┌─────────────┐
                    │  aggregate  │
                    └─────────────┘
```

## Gate Steps

Use `.ThenGate()` to pause execution until an external signal arrives:

```go
flow := core.NewFlow("deploy-pipeline").
    TriggeredBy(core.Manual("api")).
    Then(runTestsNode).
    ThenGate("approval", core.GateConfig{
        SignalName: "deploy-approval",
        Timeout:    24 * time.Hour,
    }).
    Then(deployNode).
    Build()
```

The flow pauses at the gate until a Temporal signal with a `GateResult` is received. See **[Gates](/docs/concepts/gates/)** for details.

## Child Flow Steps

Use `.ThenChildren()` to spawn child workflows from a parent flow:

```go
flow := core.NewFlow("batch-processor").
    TriggeredBy(core.Schedule("0 * * * *")).
    Then(fetchItemsNode).
    ThenChildren("process-items", core.ChildFlowConfig{
        Flow:        itemProcessingFlow,
        InputMapper: deriveChildInputs,
    }).
    Then(aggregateNode).
    Build()
```

Children execute in parallel by default. Set `Sequential: true` for ordered processing. See **[Child Flows](/docs/concepts/child-flows/)** for details.

## Lifecycle Hooks

Attach callbacks for observability and monitoring:

```go
flow := core.NewFlow("monitored-flow").
    TriggeredBy(core.Schedule("*/15 * * * *")).
    WithHooks(&core.FlowHooks{
        AfterNode: func(ctx core.HookContext) {
            log.Info("node done", "node", ctx.NodeName, "duration", ctx.Duration)
        },
    }).
    Then(fetchNode).
    Build()
```

See **[Hooks](/docs/concepts/hooks/)** for the full callback reference.

## State Configuration

By default, flows persist cursor state to a local `.resolute/` directory. For production, configure a cloud backend:

```go
flow := core.NewFlow("production-sync").
    TriggeredBy(core.Schedule("*/15 * * * *")).
    WithState(core.StateConfig{
        Backend:   s3Backend,  // Your StateBackend implementation
        Namespace: "prod",
    }).
    Then(syncNode).
    Build()
```

The `StateConfig` controls:
- **Backend** - Where cursors are stored (local, S3, GCS, database)
- **Namespace** - Prefix for state keys (useful for multi-tenant setups)

## Flow Execution Details

When a flow executes, the `Execute` method runs:

```go
// Simplified execution logic (from flow.go)
func (f *Flow) Execute(ctx workflow.Context, input FlowInput) error {
    // 1. Initialize state
    state := NewFlowState(input)

    // 2. Load persisted cursors
    state.LoadPersisted(ctx, f.name, f.stateConfig)

    // 3. Execute each step
    for _, step := range f.steps {
        if step.parallel {
            executeParallel(ctx, step, state, &compensations)
        } else {
            executeSequential(ctx, step, state, &compensations)
        }
    }

    // 4. Save updated cursors
    state.SavePersisted(ctx, f.name, f.stateConfig)

    return nil
}
```

### Compensation (Saga Pattern)

If a step fails, Resolute runs compensation nodes in reverse order:

```go
fetchNode := core.NewNode("fetch", fetchData, FetchInput{}).
    OnError(deleteFetchedNode)  // Compensation

processNode := core.NewNode("process", processData, ProcessInput{}).
    OnError(rollbackProcessNode)  // Compensation

flow := core.NewFlow("saga-flow").
    TriggeredBy(core.Manual("api")).
    Then(fetchNode).
    Then(processNode).  // If this fails...
    Then(storeNode).
    Build()

// Execution order on processNode failure:
// 1. fetchNode executes ✓
// 2. processNode fails ✗
// 3. deleteFetchedNode runs (compensation for fetchNode)
// 4. Workflow fails with original error
```

## Accessing Flow Properties

After building, you can inspect the flow:

```go
flow := core.NewFlow("example").
    TriggeredBy(core.Manual("api")).
    Then(myNode).
    Build()

flow.Name()        // "example"
flow.Trigger()     // The trigger configuration
flow.Steps()       // Slice of steps
flow.StateConfig() // State configuration (may be nil for default)
```

## Flow Naming

Flow names:
- Must be unique within a worker
- Become the Temporal workflow type
- Should be descriptive and use kebab-case or snake_case

```go
// Good names
"jira-sync"
"daily_report"
"user-onboarding-flow"

// Avoid
"flow1"           // Not descriptive
"My Flow"         // Spaces may cause issues
"jira-sync-v2.1"  // Version in code, not name
```

## Validation

`Build()` validates the flow and panics on errors:

```go
// These will panic:
core.NewFlow("empty").Build()  // No steps

core.NewFlow("no-trigger").
    Then(myNode).
    Build()  // No trigger

core.NewFlow("nil-node").
    TriggeredBy(core.Manual("api")).
    Then(nil).  // Nil node
    Build()
```

Always call `Build()` during application startup so validation errors surface immediately.

## Best Practices

### 1. Keep Flows Focused

Each flow should have a single responsibility:

```go
// Good: Single purpose
syncFlow := core.NewFlow("jira-sync").
    TriggeredBy(core.Schedule("*/15 * * * *")).
    Then(fetchJira).
    Then(transform).
    Then(store).
    Build()

// Avoid: Too many responsibilities
megaFlow := core.NewFlow("do-everything").
    Then(syncJira).
    Then(syncConfluence).
    Then(generateReports).
    Then(sendEmails).
    Then(cleanupOldData).
    Build()
```

### 2. Use Meaningful Step Names

Parallel steps require explicit names:

```go
// Good: Descriptive name
.ThenParallel("fetch-all-sources", node1, node2, node3)

// Avoid: Generic names
.ThenParallel("step2", node1, node2, node3)
```

### 3. Configure Appropriate Timeouts

Set timeouts at the node level, but consider overall flow duration:

```go
// If each step can take 5 minutes max
fetchNode := core.NewNode("fetch", fetch, input).
    WithTimeout(5 * time.Minute)

transformNode := core.NewNode("transform", transform, input).
    WithTimeout(5 * time.Minute)

// Total flow duration: up to 10 minutes
```

### 4. Test Flows in Isolation

Use `FlowTester` to test flows without Temporal:

```go
func TestMyFlow(t *testing.T) {
    flow := buildMyFlow()
    tester := core.NewFlowTester(t, flow)

    tester.MockActivity("fetch", mockFetch)
    tester.MockActivity("process", mockProcess)

    result := tester.Execute()

    if result.Error != nil {
        t.Fatalf("flow failed: %v", result.Error)
    }
}
```

## Relationship to Temporal

| Resolute Concept | Temporal Concept |
|------------------|------------------|
| Flow | Workflow |
| Flow name | Workflow type |
| Flow.Execute | Workflow function |
| Step | Activity execution(s) |
| FlowInput | Workflow input |

Resolute flows compile down to Temporal workflows. The FlowBuilder DSL provides a more declarative way to define workflows while preserving Temporal's durability guarantees.

## Dynamic Flow Construction

For flows whose structure varies at runtime, use `FlowTemplate` instead of `FlowBuilder`:

```go
tmpl := core.NewFlowTemplate("dynamic-pipeline").
    TriggeredBy(core.Manual("api"))

tmpl.AddStep(fetchNode)
if config.NeedsApproval {
    tmpl.AddGate("review", core.GateConfig{SignalName: "review"})
}
tmpl.AddStep(processNode)

flow := tmpl.Build()
```

See **[Templates](/docs/concepts/templates/)** for the full API.

## See Also

- **[Nodes](/docs/concepts/nodes/)** - Building blocks of flows
- **[Gates](/docs/concepts/gates/)** - Pausing flows for signals
- **[Child Flows](/docs/concepts/child-flows/)** - Spawning child workflows
- **[Templates](/docs/concepts/templates/)** - Dynamic flow construction
- **[Hooks](/docs/concepts/hooks/)** - Lifecycle callbacks
- **[Triggers](/docs/concepts/triggers/)** - How flows start
- **[State](/docs/concepts/state/)** - Runtime state and cursors
- **[Testing](/docs/guides/testing/flow-tester/)** - Testing flows without Temporal
