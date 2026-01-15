---
title: "Nodes"
description: "Nodes - Resolute documentation"
weight: 30
toc: true
---


# Nodes

A **Node** wraps a Temporal activity with type-safe inputs and outputs. Nodes are the building blocks of flows, encapsulating individual units of work.

## What is a Node?

A Node represents a single step in a workflow that:
- Executes an activity function
- Has typed input (`I`) and output (`O`)
- Can be configured with retry policies, timeouts, and rate limiting
- Optionally has compensation logic for rollback

```go
// Node[I, O] where:
// I = Input type (must be serializable)
// O = Output type (must be serializable)

type Node[I, O any] struct {
    name          string
    activity      func(context.Context, I) (O, error)
    input         I
    options       ActivityOptions
    outputKey     string
    compensation  ExecutableNode
    rateLimiterID string
}
```

## Creating Nodes

Use `NewNode` to create a typed node:

```go
// Define input/output types
type FetchInput struct {
    URL     string
    Timeout time.Duration
}

type FetchOutput struct {
    Data      []byte
    StatusCode int
}

// Define the activity function
func fetchData(ctx context.Context, input FetchInput) (FetchOutput, error) {
    // ... implementation
    return FetchOutput{Data: data, StatusCode: 200}, nil
}

// Create the node
fetchNode := core.NewNode("fetch-data", fetchData, FetchInput{
    URL:     "https://api.example.com/data",
    Timeout: 30 * time.Second,
})
```

### Type Inference

Go infers generic types from the activity function:

```go
// The compiler infers Node[FetchInput, FetchOutput]
node := core.NewNode("fetch", fetchData, FetchInput{})
```

## Node Configuration

### Timeouts

Set the maximum time an activity can run:

```go
node := core.NewNode("slow-operation", slowOp, input).
    WithTimeout(10 * time.Minute)
```

Default timeout is 5 minutes. If the activity doesn't complete within the timeout, Temporal marks it as failed.

### Retry Policies

Configure how failures are retried:

```go
node := core.NewNode("flaky-api", callAPI, input).
    WithRetry(core.RetryPolicy{
        InitialInterval:    time.Second,      // First retry after 1s
        BackoffCoefficient: 2.0,              // Double delay each retry
        MaximumInterval:    time.Minute,      // Cap delay at 1 minute
        MaximumAttempts:    5,                // Give up after 5 attempts
    })
```

| Field | Description | Default |
|-------|-------------|---------|
| `InitialInterval` | Delay before first retry | 1 second |
| `BackoffCoefficient` | Multiplier for each subsequent retry | 2.0 |
| `MaximumInterval` | Maximum delay between retries | 1 minute |
| `MaximumAttempts` | Total attempts (0 = unlimited) | 3 |

### Rate Limiting

Prevent overwhelming external APIs:

```go
// Per-node rate limit
node := core.NewNode("api-call", callAPI, input).
    WithRateLimit(100, time.Minute)  // 100 requests per minute
```

For multiple nodes calling the same API, use a shared rate limiter:

```go
// Shared rate limiter across multiple nodes
apiLimiter := core.NewSharedRateLimiter("external-api", 100, time.Minute)

node1 := core.NewNode("fetch-users", fetchUsers, input).
    WithSharedRateLimit(apiLimiter)

node2 := core.NewNode("fetch-orders", fetchOrders, input).
    WithSharedRateLimit(apiLimiter)

// Both nodes share the 100 req/min limit
```

### Output Keys

By default, node output is stored in FlowState under the node's name. Override with `.As()`:

```go
node := core.NewNode("fetch-jira-issues", fetchIssues, input).
    As("issues")  // Store output as "issues" instead of "fetch-jira-issues"

// Access in subsequent nodes:
issues := core.Get[FetchOutput](state, "issues")
```

### Compensation

Attach a compensation node for Saga pattern rollback:

```go
createOrderNode := core.NewNode("create-order", createOrder, orderInput).
    OnError(cancelOrderNode)  // Run if subsequent steps fail

// cancelOrderNode is a separate node that undoes the order creation
cancelOrderNode := core.NewNode("cancel-order", cancelOrder, CancelInput{})
```

## Dynamic Input with InputFunc

For inputs that depend on previous node outputs, use `WithInputFunc`:

```go
// Static input - same every execution
staticNode := core.NewNode("fetch", fetchData, FetchInput{
    URL: "https://api.example.com",
})

// Dynamic input - computed from FlowState
dynamicNode := core.NewNode("process", processData, ProcessInput{}).
    WithInputFunc(func(state *core.FlowState) ProcessInput {
        fetchResult := core.Get[FetchOutput](state, "fetch")
        return ProcessInput{
            Data:   fetchResult.Data,
            Format: "json",
        }
    })
```

### Input Resolution Order

1. If `WithInputFunc` is set, it's called with current FlowState
2. Otherwise, the static input provided to `NewNode` is used
3. Magic markers in the input are resolved (see below)

## Magic Markers

Magic markers let you reference state values declaratively in input structs:

```go
type ProcessInput struct {
    Data   []byte
    Cursor core.CursorRef  // Magic marker for cursor
    PrevID core.OutputRef  // Magic marker for previous output
}

processNode := core.NewNode("process", processData, ProcessInput{
    Data:   nil,  // Will be populated
    Cursor: core.CursorFor("my-source"),
    PrevID: core.Output("fetch", "ID"),  // Get ID field from fetch output
})
```

Available markers:
- `core.CursorFor(source)` - Resolves to the cursor for the named source
- `core.Output(node, field)` - Resolves to a field from a previous node's output

## Node Execution

When a node executes:

```
┌─────────────────────────────────────────────────────────────────────┐
│                       Node Execution                                 │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  1. RATE LIMIT CHECK                                                 │
│     └─▶ If rate limiter configured, wait for token                  │
│                                                                      │
│  2. INPUT RESOLUTION                                                 │
│     ├─▶ Call WithInputFunc if configured                            │
│     └─▶ Resolve magic markers (CursorRef, OutputRef)                 │
│                                                                      │
│  3. ACTIVITY EXECUTION                                               │
│     ├─▶ Apply timeout and retry policy                               │
│     └─▶ Execute activity via Temporal                                │
│                                                                      │
│  4. RESULT STORAGE                                                   │
│     └─▶ Store output in FlowState under OutputKey()                  │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### Error Handling

If the activity fails:
1. Temporal retries according to RetryPolicy
2. If all retries exhausted, the node fails
3. The flow's compensation chain runs (if configured)
4. The workflow fails with the original error

## ExecutableNode Interface

All nodes implement `ExecutableNode`:

```go
type ExecutableNode interface {
    Name() string
    Execute(ctx workflow.Context, state *FlowState) error
    HasCompensation() bool
    Compensate(ctx workflow.Context, state *FlowState) error
}
```

This interface allows flows to work with nodes polymorphically, regardless of their specific input/output types.

## Node Methods Reference

| Method | Description |
|--------|-------------|
| `NewNode(name, activity, input)` | Create a new node |
| `.WithTimeout(duration)` | Set activity timeout |
| `.WithRetry(policy)` | Configure retry behavior |
| `.WithRateLimit(n, duration)` | Add per-node rate limiting |
| `.WithSharedRateLimit(limiter)` | Use shared rate limiter |
| `.WithInputFunc(fn)` | Compute input dynamically |
| `.As(key)` | Override output key in FlowState |
| `.OnError(node)` | Attach compensation node |
| `.Name()` | Get node name |
| `.OutputKey()` | Get output storage key |
| `.Input()` | Get static input (for testing) |
| `.HasCompensation()` | Check if compensation is configured |

## Activity Function Signature

All activity functions must follow this pattern:

```go
func activityName(ctx context.Context, input InputType) (OutputType, error)
```

Rules:
- First parameter must be `context.Context`
- Second parameter is your input struct
- Returns `(OutputType, error)`
- Input and output types must be serializable (JSON-compatible)

```go
// Valid activity signatures
func fetchData(ctx context.Context, input FetchInput) (FetchOutput, error)
func processItems(ctx context.Context, input ProcessInput) (ProcessOutput, error)
func sendEmail(ctx context.Context, input EmailInput) (EmailOutput, error)

// Invalid signatures
func badActivity(input SomeInput) (SomeOutput, error)  // Missing context
func badActivity2(ctx context.Context) error           // Missing input
func badActivity3(ctx context.Context, input SomeInput) SomeOutput  // Missing error
```

## Best Practices

### 1. Keep Activities Idempotent

Activities may be retried. Design them to be safe to re-run:

```go
func createUser(ctx context.Context, input CreateUserInput) (CreateUserOutput, error) {
    // Check if user already exists (idempotency)
    existing, err := db.GetUserByEmail(input.Email)
    if err == nil && existing != nil {
        return CreateUserOutput{UserID: existing.ID}, nil  // Already created
    }

    // Create new user
    user, err := db.CreateUser(input)
    if err != nil {
        return CreateUserOutput{}, fmt.Errorf("create user: %w", err)
    }

    return CreateUserOutput{UserID: user.ID}, nil
}
```

### 2. Use Heartbeats for Long Operations

For long-running activities, use heartbeats to report progress:

```go
func longOperation(ctx context.Context, input LongInput) (LongOutput, error) {
    for i, item := range input.Items {
        // Report progress
        activity.RecordHeartbeat(ctx, fmt.Sprintf("Processing %d/%d", i+1, len(input.Items)))

        // Check for cancellation
        if ctx.Err() != nil {
            return LongOutput{}, ctx.Err()
        }

        processItem(item)
    }
    return LongOutput{Processed: len(input.Items)}, nil
}

// Configure heartbeat timeout
node := core.NewNode("long-op", longOperation, input).
    WithTimeout(1 * time.Hour).
    WithHeartbeatTimeout(30 * time.Second)  // Fail if no heartbeat for 30s
```

### 3. Keep Inputs/Outputs Small

Temporal has payload size limits. Avoid passing large data through activities:

```go
// Bad: Passing large data directly
type BadInput struct {
    LargeFile []byte  // Could be megabytes
}

// Good: Pass references
type GoodInput struct {
    FileURL string  // Reference to file location
}
```

### 4. Use Descriptive Names

Node names appear in Temporal UI and logs:

```go
// Good names
"fetch-jira-issues"
"transform-to-embeddings"
"store-in-qdrant"

// Avoid
"step1"
"process"
"doStuff"
```

## Relationship to Temporal

| Resolute Concept | Temporal Concept |
|------------------|------------------|
| Node | Activity |
| Node name | Activity type |
| Activity function | Activity implementation |
| WithRetry | Activity retry policy |
| WithTimeout | StartToCloseTimeout |
| FlowState result | Workflow state |

## See Also

- **[Flows](/docs/concepts/flows/)** - How nodes compose into workflows
- **[State](/docs/concepts/state/)** - How node outputs are stored
- **[Providers](/docs/concepts/providers/)** - Collections of related nodes
- **[Rate Limiting](/docs/guides/advanced-patterns/rate-limiting/)** - Advanced rate limiting patterns
