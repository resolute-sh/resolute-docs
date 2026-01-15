---
title: "Temporal Foundation"
description: "Temporal Foundation - Resolute documentation"
weight: 80
toc: true
---


# Temporal Foundation

Resolute is built on [Temporal](https://temporal.io), a durable execution platform. Understanding this foundation helps you leverage Resolute effectively and know when to reach for lower-level Temporal features.

## What is Temporal?

Temporal is a platform for building reliable distributed systems. It provides:

- **Durable Execution** - Workflow state survives process crashes and restarts
- **Event Sourcing** - Complete history of every execution step
- **Automatic Retries** - Failed activities retry with configurable policies
- **Visibility** - Search and inspect running/completed workflows
- **Scalability** - Distribute work across many workers

## How Resolute Uses Temporal

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Resolute Layer                               │
│                                                                      │
│   ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐          │
│   │   Flow   │  │   Node   │  │  State   │  │ Provider │          │
│   └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘          │
│        │             │             │             │                  │
│        │     Resolute abstractions compile to Temporal primitives   │
│        │             │             │             │                  │
│        ▼             ▼             ▼             ▼                  │
├─────────────────────────────────────────────────────────────────────┤
│                        Temporal SDK Layer                            │
│                                                                      │
│   ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐          │
│   │ Workflow │  │ Activity │  │ Context  │  │  Worker  │          │
│   └──────────┘  └──────────┘  └──────────┘  └──────────┘          │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
                                   │
                                   │ gRPC
                                   ▼
┌─────────────────────────────────────────────────────────────────────┐
│                        Temporal Server                               │
│                                                                      │
│  ┌────────────────────────────────────────────────────────────┐    │
│  │  History Service  │  Matching Service  │  Frontend Service  │    │
│  └────────────────────────────────────────────────────────────┘    │
│                                                                      │
│  ┌────────────────────────────────────────────────────────────┐    │
│  │                    Persistence Layer                        │    │
│  │            (PostgreSQL, MySQL, Cassandra)                   │    │
│  └────────────────────────────────────────────────────────────┘    │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

## Concept Mapping

| Resolute Concept | Temporal Equivalent | Notes |
|------------------|---------------------|-------|
| **Flow** | Workflow | A Flow compiles to a Temporal workflow definition |
| **Flow.Execute** | Workflow function | The function Temporal calls to run the workflow |
| **Node** | Activity | Nodes wrap activities with type safety |
| **Trigger** | Workflow start mechanism | Manual, Schedule, Signal map to Temporal features |
| **FlowState** | Workflow context + local state | Manages data passing between activities |
| **Provider** | Activity registrations | Groups related activities for registration |
| **Worker** | Worker | Polls Temporal for tasks |
| **RetryPolicy** | `temporal.RetryPolicy` | Direct mapping |
| **Timeout** | `StartToCloseTimeout` | Activity timeout |

## What Resolute Abstracts

### 1. Workflow Definition Boilerplate

**Raw Temporal:**
```go
func MyWorkflow(ctx workflow.Context, input MyInput) error {
    ao := workflow.ActivityOptions{
        StartToCloseTimeout: 5 * time.Minute,
        RetryPolicy: &temporal.RetryPolicy{
            InitialInterval:    time.Second,
            BackoffCoefficient: 2.0,
            MaximumAttempts:    3,
        },
    }
    ctx = workflow.WithActivityOptions(ctx, ao)

    var result1 Activity1Output
    err := workflow.ExecuteActivity(ctx, Activity1, input).Get(ctx, &result1)
    if err != nil {
        return err
    }

    var result2 Activity2Output
    err = workflow.ExecuteActivity(ctx, Activity2, Activity2Input{
        Data: result1.Data,
    }).Get(ctx, &result2)
    if err != nil {
        return err
    }

    return nil
}
```

**Resolute:**
```go
flow := core.NewFlow("my-workflow").
    TriggeredBy(core.Manual("api")).
    Then(core.NewNode("activity1", activity1, input).
        WithTimeout(5 * time.Minute).
        WithRetry(retryPolicy)).
    Then(core.NewNode("activity2", activity2, Activity2Input{}).
        WithInputFunc(func(state *core.FlowState) Activity2Input {
            result1 := core.Get[Activity1Output](state, "activity1")
            return Activity2Input{Data: result1.Data}
        })).
    Build()
```

### 2. Type-Safe Activity Inputs/Outputs

**Raw Temporal:**
```go
// Must manually type assert
var result MyOutput
err := workflow.ExecuteActivity(ctx, myActivity, input).Get(ctx, &result)
```

**Resolute:**
```go
// Compile-time type checking
node := core.NewNode[MyInput, MyOutput]("my-node", myActivity, input)
result := core.Get[MyOutput](state, "my-node")  // Type-safe retrieval
```

### 3. Activity Registration

**Raw Temporal:**
```go
w := worker.New(c, "my-queue", worker.Options{})
w.RegisterWorkflow(MyWorkflow)
w.RegisterActivity(Activity1)
w.RegisterActivity(Activity2)
w.RegisterActivity(Activity3)
// ... for each activity
```

**Resolute:**
```go
core.NewWorker().
    WithFlow(myFlow).
    WithProviders(myProvider).  // Registers all provider activities
    Run()
```

### 4. State Management

**Raw Temporal:**
```go
// Must manage state passing manually
var result1 Out1
err := workflow.ExecuteActivity(ctx, act1, in1).Get(ctx, &result1)

// Transform for next activity
input2 := In2{Data: result1.Data}
var result2 Out2
err = workflow.ExecuteActivity(ctx, act2, input2).Get(ctx, &result2)
```

**Resolute:**
```go
// FlowState handles automatically
// Each node's output is stored and accessible to subsequent nodes
processNode.WithInputFunc(func(state *core.FlowState) ProcessInput {
    fetch := core.Get[FetchOutput](state, "fetch")
    return ProcessInput{Items: fetch.Items}
})
```

## What You Still Get from Temporal

Resolute preserves all Temporal guarantees:

### Durable Execution

If a worker crashes mid-workflow:
1. Temporal preserves the execution history
2. Another worker picks up the workflow
3. Execution resumes from the last completed activity

### Automatic Retries

Activities automatically retry on failure:

```go
node := core.NewNode("flaky", flakyActivity, input).
    WithRetry(core.RetryPolicy{
        InitialInterval:    time.Second,
        BackoffCoefficient: 2.0,
        MaximumInterval:    time.Minute,
        MaximumAttempts:    5,
    })
```

Temporal handles retry timing, backoff, and attempt tracking.

### Event Sourcing

Every execution step is recorded:

```
Workflow Started: my-workflow (id: wf-123)
├── Activity Started: fetch-data
├── Activity Completed: fetch-data (output: {...})
├── Activity Started: process-data
├── Activity Completed: process-data (output: {...})
├── Activity Started: store-data
├── Activity Completed: store-data (output: {...})
Workflow Completed: my-workflow
```

View in Temporal UI at `http://localhost:8233`.

### Visibility and Search

Query workflows via Temporal's visibility API:

```bash
# List running workflows
temporal workflow list --query 'ExecutionStatus="Running"'

# Search by custom attribute
temporal workflow list --query 'WorkflowType="jira-sync"'
```

### Scalability

Multiple workers can process the same queue:

```
Worker A ─┐
Worker B ─┼─── Task Queue ─── Temporal Server
Worker C ─┘
```

Temporal distributes tasks across available workers.

## When to Use Raw Temporal

Resolute handles most use cases, but sometimes you need raw Temporal:

### 1. Child Workflows

For complex workflow hierarchies:

```go
// In your workflow function, use raw Temporal
childRun := workflow.ExecuteChildWorkflow(ctx, ChildWorkflow, input)
var result ChildOutput
err := childRun.Get(ctx, &result)
```

### 2. Signals and Queries

For dynamic workflow interaction:

```go
// Receive signals in workflow
signalChan := workflow.GetSignalChannel(ctx, "my-signal")
selector := workflow.NewSelector(ctx)
selector.AddReceive(signalChan, func(c workflow.ReceiveChannel, more bool) {
    var signal MySignal
    c.Receive(ctx, &signal)
    // Handle signal
})
```

### 3. Timers and Delays

For time-based logic:

```go
// Sleep for a duration
workflow.Sleep(ctx, 5*time.Minute)

// Timer with selector
timerFuture := workflow.NewTimer(ctx, time.Hour)
```

### 4. Advanced Retry Logic

For custom retry handling:

```go
// Custom retry with activity error inspection
for attempt := 0; attempt < maxAttempts; attempt++ {
    err := workflow.ExecuteActivity(ctx, myActivity, input).Get(ctx, &result)
    if err == nil {
        break
    }
    if !isRetryable(err) {
        return err
    }
    workflow.Sleep(ctx, backoff(attempt))
}
```

### 5. Workflow Versioning

For long-running workflow migrations:

```go
v := workflow.GetVersion(ctx, "change-id", workflow.DefaultVersion, 1)
if v == workflow.DefaultVersion {
    // Old behavior
} else {
    // New behavior
}
```

## Accessing Raw Temporal

You can access Temporal primitives when needed:

```go
// Access Temporal client
builder := core.NewWorker().WithConfig(config).WithFlow(flow)
builder.Build()
client := builder.Client()

// Start workflows programmatically
run, err := client.ExecuteWorkflow(ctx, options, "workflow-name", input)

// Query workflow
err := client.QueryWorkflow(ctx, workflowID, "", "query-name", &result)

// Signal workflow
err := client.SignalWorkflow(ctx, workflowID, "", "signal-name", data)
```

## Temporal UI Integration

All Resolute workflows appear in the Temporal Web UI:

- **Workflow List** - See all running/completed flows
- **Workflow Detail** - View execution history, inputs/outputs
- **Activity Details** - Inspect individual node executions
- **Search** - Query by workflow type, status, time range

Access at `http://localhost:8233` (local) or your Temporal Cloud dashboard.

## Best Practices

### 1. Leverage Durable Execution

Design flows to benefit from durability:

```go
// Good: Each step is recoverable
flow := core.NewFlow("robust").
    Then(fetchNode).   // If crash here, fetched data is saved
    Then(processNode). // Restarts from process, not fetch
    Then(storeNode).
    Build()
```

### 2. Use Appropriate Timeouts

Match timeouts to expected activity duration:

```go
// External API call - may be slow
fetchNode := core.NewNode("fetch", fetch, input).
    WithTimeout(5 * time.Minute)

// Local processing - should be fast
processNode := core.NewNode("process", process, input).
    WithTimeout(30 * time.Second)
```

### 3. Configure Retries for Transient Failures

External systems may have temporary issues:

```go
apiNode := core.NewNode("api-call", callAPI, input).
    WithRetry(core.RetryPolicy{
        InitialInterval:    time.Second,
        BackoffCoefficient: 2.0,
        MaximumAttempts:    5,
    })
```

### 4. Monitor via Temporal UI

Regularly check:
- Failed workflow rate
- Activity retry rate
- Queue latency
- Worker health

## Resources

- **[Temporal Documentation](https://docs.temporal.io)** - Official Temporal docs
- **[Temporal Go SDK](https://pkg.go.dev/go.temporal.io/sdk)** - SDK reference
- **[Temporal Cloud](https://temporal.io/cloud)** - Managed Temporal service
- **[Temporal Community](https://community.temporal.io)** - Forums and support

## See Also

- **[Flows](/docs/concepts/flows/)** - How flows map to workflows
- **[Nodes](/docs/concepts/nodes/)** - How nodes map to activities
- **[Workers](/docs/concepts/workers/)** - How workers connect to Temporal
- **[Deployment](/docs/guides/deployment/temporal-cloud/)** - Production deployment
