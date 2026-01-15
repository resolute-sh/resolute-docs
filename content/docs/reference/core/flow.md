---
title: "Flow"
description: "Flow - Resolute documentation"
weight: 10
toc: true
---


# Flow

The `Flow` type represents a complete workflow definition, composed of triggers, steps, and state configuration.

## Types

### Flow

```go
type Flow struct {
    // unexported fields
}
```

A completed workflow definition. Created via `FlowBuilder.Build()`.

#### Methods

| Method | Signature | Description |
|--------|-----------|-------------|
| `Name` | `() string` | Returns the flow's identifier |
| `Trigger` | `() Trigger` | Returns the flow's trigger configuration |
| `Steps` | `() []Step` | Returns the flow's execution steps |
| `StateConfig` | `() *StateConfig` | Returns state configuration, or nil for default |
| `Execute` | `(ctx workflow.Context, input FlowInput) error` | Runs the flow as a Temporal workflow |

### FlowBuilder

```go
type FlowBuilder struct {
    // unexported fields
}
```

Provides a fluent API for constructing flows.

### Step

```go
type Step struct {
    // unexported fields
}
```

Represents one execution unit within a flow. A step can contain:
- One node (sequential execution)
- Multiple nodes (parallel execution)
- A conditional branch

### FlowInput

```go
type FlowInput struct {
    Data map[string][]byte
}
```

Contains the initial input to a flow execution.

## Constructor

### NewFlow

```go
func NewFlow(name string) *FlowBuilder
```

Creates a new flow builder with the given name.

**Parameters:**
- `name` - Unique identifier for the flow

**Returns:** `*FlowBuilder` for method chaining

**Example:**
```go
builder := core.NewFlow("data-sync")
```

## FlowBuilder Methods

### TriggeredBy

```go
func (b *FlowBuilder) TriggeredBy(t Trigger) *FlowBuilder
```

Sets the trigger that initiates this flow.

**Parameters:**
- `t` - Trigger configuration (Manual, Schedule, Signal, or Webhook)

**Returns:** `*FlowBuilder` for method chaining

**Example:**
```go
flow := core.NewFlow("my-flow").
    TriggeredBy(core.Manual("api")).
    // ...
```

### Then

```go
func (b *FlowBuilder) Then(node ExecutableNode) *FlowBuilder
```

Adds a sequential step with a single node.

**Parameters:**
- `node` - The node to execute (cannot be nil)

**Returns:** `*FlowBuilder` for method chaining

**Example:**
```go
flow := core.NewFlow("pipeline").
    TriggeredBy(core.Manual("api")).
    Then(fetchNode).
    Then(processNode).
    Then(storeNode).
    Build()
```

### ThenParallel

```go
func (b *FlowBuilder) ThenParallel(name string, nodes ...ExecutableNode) *FlowBuilder
```

Adds a parallel step with multiple nodes executed concurrently.

**Parameters:**
- `name` - Identifier for the parallel step
- `nodes` - One or more nodes to execute in parallel

**Returns:** `*FlowBuilder` for method chaining

**Example:**
```go
flow := core.NewFlow("enrichment").
    TriggeredBy(core.Manual("api")).
    Then(fetchNode).
    ThenParallel("enrich",
        enrichANode,
        enrichBNode,
        enrichCNode,
    ).
    Then(aggregateNode).
    Build()
```

### When

```go
func (b *FlowBuilder) When(pred Predicate) *ConditionalBuilder
```

Starts a conditional branch based on a predicate.

**Parameters:**
- `pred` - Function that evaluates FlowState and returns bool

**Returns:** `*ConditionalBuilder` for building conditional logic

**Example:**
```go
flow := core.NewFlow("order-flow").
    TriggeredBy(core.Manual("api")).
    Then(fetchOrder).
    When(func(s *core.FlowState) bool {
        return core.Get[Order](s, "order").Total > 1000
    }).
        Then(requireApproval).
    Otherwise(autoApprove).
    Then(fulfillOrder).
    Build()
```

### WithState

```go
func (b *FlowBuilder) WithState(cfg StateConfig) *FlowBuilder
```

Overrides the default state backend (`.resolute/` directory).

**Parameters:**
- `cfg` - State configuration with custom backend

**Returns:** `*FlowBuilder` for method chaining

**Example:**
```go
flow := core.NewFlow("production-flow").
    TriggeredBy(core.Schedule("0 * * * *")).
    WithState(core.StateConfig{
        Backend: s3Backend,
    }).
    Then(syncNode).
    Build()
```

### Build

```go
func (b *FlowBuilder) Build() *Flow
```

Validates and returns the constructed flow.

**Returns:** `*Flow` - The completed flow definition

**Panics if:**
- Flow has no steps
- Flow has no trigger
- Any builder errors accumulated

**Example:**
```go
flow := core.NewFlow("my-flow").
    TriggeredBy(core.Manual("api")).
    Then(myNode).
    Build()
```

## ConditionalBuilder Methods

### Then (ConditionalBuilder)

```go
func (cb *ConditionalBuilder) Then(node ExecutableNode) *ConditionalBuilder
```

Adds a sequential step to the current branch.

### ThenParallel (ConditionalBuilder)

```go
func (cb *ConditionalBuilder) ThenParallel(name string, nodes ...ExecutableNode) *ConditionalBuilder
```

Adds a parallel step to the current branch.

### Else

```go
func (cb *ConditionalBuilder) Else() *ConditionalBuilder
```

Switches to building the "else" branch. Subsequent `Then`/`ThenParallel` calls add to the else branch.

### Otherwise

```go
func (cb *ConditionalBuilder) Otherwise(node ExecutableNode) *FlowBuilder
```

Adds a single node to the "else" branch and returns to the main flow builder.

### OtherwiseParallel

```go
func (cb *ConditionalBuilder) OtherwiseParallel(name string, nodes ...ExecutableNode) *FlowBuilder
```

Adds parallel nodes to the "else" branch and returns to the main flow builder.

### EndWhen

```go
func (cb *ConditionalBuilder) EndWhen() *FlowBuilder
```

Completes the conditional block without an else branch and returns to the main flow builder.

## Flow Methods

### Name

```go
func (f *Flow) Name() string
```

Returns the flow's identifier.

### Trigger

```go
func (f *Flow) Trigger() Trigger
```

Returns the flow's trigger configuration.

### Steps

```go
func (f *Flow) Steps() []Step
```

Returns the flow's execution steps.

### StateConfig

```go
func (f *Flow) StateConfig() *StateConfig
```

Returns the flow's state configuration, or nil for default.

### Execute

```go
func (f *Flow) Execute(ctx workflow.Context, input FlowInput) error
```

Runs the flow as a Temporal workflow. This method:
1. Initializes flow state from input
2. Loads persisted state (cursors) from backend
3. Executes steps in order
4. Runs compensations on failure (Saga pattern)
5. Persists state on successful completion

**Parameters:**
- `ctx` - Temporal workflow context
- `input` - Initial flow input

**Returns:** Error if execution fails

## Complete Example

```go
package main

import (
    "github.com/resolute/resolute/core"
    "myapp/providers/jira"
)

func main() {
    // Define the flow
    flow := core.NewFlow("issue-sync").
        TriggeredBy(core.Schedule("0 */6 * * *")).  // Every 6 hours
        WithState(core.StateConfig{
            Backend: s3Backend,
        }).
        Then(jira.FetchIssues(jira.FetchInput{
            JQL:    "project = PLATFORM AND updated > {{cursor:jira}}",
            Cursor: core.CursorFor("jira"),
        }).As("issues")).
        When(func(s *core.FlowState) bool {
            issues := core.Get[jira.FetchOutput](s, "issues")
            return issues.Count > 0
        }).
            ThenParallel("process",
                processNode,
                enrichNode,
            ).
            Then(storeNode).
        EndWhen().
        Build()

    // Run with worker
    err := core.NewWorker().
        WithConfig(core.WorkerConfig{TaskQueue: "sync"}).
        WithFlow(flow).
        WithProviders(jira.Provider()).
        Run()
}
```

## See Also

- **[Node](/docs/reference/core/node/)** - Activity wrapper
- **[Trigger](/docs/reference/core/trigger/)** - Trigger types
- **[State](/docs/reference/core/state/)** - FlowState management
- **[Building Flows](/docs/guides/building-flows/sequential-steps/)** - Flow construction guide
