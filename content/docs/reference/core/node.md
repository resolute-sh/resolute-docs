---
title: "Node"
description: "Node - Resolute documentation"
weight: 20
toc: true
---


# Node

The `Node[I, O]` type wraps a Temporal Activity with typed input and output. Nodes are the building blocks of flows.

## Types

### Node[I, O]

```go
type Node[I, O any] struct {
    // unexported fields
}
```

A generic node wrapping an activity function with input type `I` and output type `O`.

### ExecutableNode

```go
type ExecutableNode interface {
    Name() string
    OutputKey() string
    Execute(ctx workflow.Context, state *FlowState) error
    Compensate(ctx workflow.Context, state *FlowState) error
    HasCompensation() bool
    Compensation() ExecutableNode
    Input() any
    RateLimiterID() string
}
```

Interface implemented by all nodes. Allows type-erased storage in flow steps.

### ActivityOptions

```go
type ActivityOptions struct {
    RetryPolicy         *RetryPolicy
    StartToCloseTimeout time.Duration
    HeartbeatTimeout    time.Duration
    TaskQueue           string
}
```

Configures retry and timeout behavior for a node.

### RetryPolicy

```go
type RetryPolicy struct {
    InitialInterval    time.Duration
    BackoffCoefficient float64
    MaximumInterval    time.Duration
    MaximumAttempts    int32
}
```

Defines retry behavior for failed activities.

## Constructor

### NewNode

```go
func NewNode[I, O any](name string, activity func(context.Context, I) (O, error), input I) *Node[I, O]
```

Creates a node wrapping an activity function.

**Type Parameters:**
- `I` - Input type
- `O` - Output type

**Parameters:**
- `name` - Activity name (used for registration and debugging)
- `activity` - The activity function to execute
- `input` - Initial input value (may contain magic markers)

**Returns:** `*Node[I, O]` configured with default options

**Example:**
```go
node := core.NewNode("fetch-issues", jira.FetchIssuesActivity, jira.FetchInput{
    JQL: "project = PLATFORM",
})
```

### DefaultActivityOptions

```go
func DefaultActivityOptions() ActivityOptions
```

Returns sensible defaults for activity execution:
- `StartToCloseTimeout`: 5 minutes
- `RetryPolicy.InitialInterval`: 1 second
- `RetryPolicy.BackoffCoefficient`: 2.0
- `RetryPolicy.MaximumInterval`: 1 minute
- `RetryPolicy.MaximumAttempts`: 3

## Node Methods

### WithRetry

```go
func (n *Node[I, O]) WithRetry(policy RetryPolicy) *Node[I, O]
```

Configures the retry policy for this node.

**Parameters:**
- `policy` - Custom retry configuration

**Returns:** `*Node[I, O]` for method chaining

**Example:**
```go
node := jira.FetchIssues(input).WithRetry(core.RetryPolicy{
    InitialInterval:    2 * time.Second,
    BackoffCoefficient: 1.5,
    MaximumInterval:    30 * time.Second,
    MaximumAttempts:    5,
})
```

### WithTimeout

```go
func (n *Node[I, O]) WithTimeout(d time.Duration) *Node[I, O]
```

Sets the start-to-close timeout for this node.

**Parameters:**
- `d` - Maximum duration for activity execution

**Returns:** `*Node[I, O]` for method chaining

**Example:**
```go
node := longRunningActivity(input).WithTimeout(30 * time.Minute)
```

### OnError

```go
func (n *Node[I, O]) OnError(compensation ExecutableNode) *Node[I, O]
```

Attaches a compensation node to run if subsequent steps fail (Saga pattern).

**Parameters:**
- `compensation` - Node to execute for rollback

**Returns:** `*Node[I, O]` for method chaining

**Example:**
```go
createOrder := orders.Create(input).OnError(orders.Cancel(cancelInput))
chargePayment := payments.Charge(paymentInput).OnError(payments.Refund(refundInput))

flow := core.NewFlow("order").
    TriggeredBy(core.Manual("api")).
    Then(createOrder).    // If charge fails, order is cancelled
    Then(chargePayment).  // If ship fails, payment is refunded
    Then(shipOrder).
    Build()
```

### WithRateLimit

```go
func (n *Node[I, O]) WithRateLimit(requests int, per time.Duration) *Node[I, O]
```

Configures rate limiting for this node. Creates a rate limiter unique to this node instance.

**Parameters:**
- `requests` - Maximum number of requests allowed
- `per` - Time window for the rate limit

**Returns:** `*Node[I, O]` for method chaining

**Example:**
```go
// Limit to 100 requests per minute
node := jira.FetchIssues(input).WithRateLimit(100, time.Minute)
```

### WithSharedRateLimit

```go
func (n *Node[I, O]) WithSharedRateLimit(limiter *SharedRateLimiter) *Node[I, O]
```

Configures this node to use a shared rate limiter. Multiple nodes can share the same rate limiter to coordinate request rates.

**Parameters:**
- `limiter` - Pre-created shared rate limiter

**Returns:** `*Node[I, O]` for method chaining

**Example:**
```go
// Multiple nodes share one rate limit
limiter := core.NewSharedRateLimiter("jira-api", 100, time.Minute)

fetchNode := jira.FetchIssues(fetchInput).WithSharedRateLimit(limiter)
searchNode := jira.SearchJQL(searchInput).WithSharedRateLimit(limiter)
```

### As

```go
func (n *Node[I, O]) As(outputKey string) *Node[I, O]
```

Names the output of this node for reference by downstream nodes.

**Parameters:**
- `outputKey` - Key to store output in FlowState

**Returns:** `*Node[I, O]` for method chaining

**Example:**
```go
flow := core.NewFlow("pipeline").
    TriggeredBy(core.Manual("api")).
    Then(jira.FetchIssues(input).As("issues")).  // Output stored as "issues"
    Then(processNode).  // Can reference "issues" via magic markers
    Build()
```

### Name

```go
func (n *Node[I, O]) Name() string
```

Returns the node's identifier.

### OutputKey

```go
func (n *Node[I, O]) OutputKey() string
```

Returns the key used to store this node's output. Returns the custom key set via `As()`, or the node's name if not set.

### HasCompensation

```go
func (n *Node[I, O]) HasCompensation() bool
```

Returns true if this node has a compensation handler.

### Compensation

```go
func (n *Node[I, O]) Compensation() ExecutableNode
```

Returns the compensation node, if any.

### Input

```go
func (n *Node[I, O]) Input() any
```

Returns the node's input value (used for testing).

### RateLimiterID

```go
func (n *Node[I, O]) RateLimiterID() string
```

Returns the rate limiter ID for this node, or empty string if not configured.

### Execute

```go
func (n *Node[I, O]) Execute(ctx workflow.Context, state *FlowState) error
```

Runs the activity within a Temporal workflow context.

**Execution steps:**
1. Apply rate limiting if configured
2. Resolve magic markers in input
3. Configure activity options (timeout, retry)
4. Execute activity via Temporal
5. Store result in FlowState

**Parameters:**
- `ctx` - Temporal workflow context
- `state` - Current flow state

**Returns:** Error if execution fails

### Compensate

```go
func (n *Node[I, O]) Compensate(ctx workflow.Context, state *FlowState) error
```

Runs the compensation activity if one is configured.

**Parameters:**
- `ctx` - Temporal workflow context
- `state` - Flow state snapshot from when the node executed

**Returns:** Error if compensation fails

## Provider Pattern

Providers typically expose factory functions that return configured nodes:

```go
package jira

// Provider function returns a ready-to-use node
func FetchIssues(input FetchInput) *core.Node[FetchInput, FetchOutput] {
    return core.NewNode("jira.FetchIssues", FetchIssuesActivity, input)
}

// Activity function (registered with worker)
func FetchIssuesActivity(ctx context.Context, input FetchInput) (FetchOutput, error) {
    // Implementation
}
```

Usage in flows:

```go
flow := core.NewFlow("sync").
    TriggeredBy(core.Manual("api")).
    Then(jira.FetchIssues(jira.FetchInput{
        JQL: "project = PLATFORM",
    })).
    Build()
```

## Complete Example

```go
package main

import (
    "time"
    "github.com/resolute/resolute/core"
)

func main() {
    // Shared rate limiter for Jira API
    jiraLimiter := core.NewSharedRateLimiter("jira", 100, time.Minute)

    // Configure nodes with various options
    fetchNode := jira.FetchIssues(jira.FetchInput{
        JQL:    "project = PLATFORM",
        Cursor: core.CursorFor("jira"),
    }).
        As("issues").
        WithSharedRateLimit(jiraLimiter).
        WithTimeout(10 * time.Minute).
        WithRetry(core.RetryPolicy{
            MaximumAttempts: 5,
        })

    // Node with compensation
    createNode := orders.Create(orderInput).
        OnError(orders.Cancel(cancelInput))

    // Build flow with configured nodes
    flow := core.NewFlow("order-pipeline").
        TriggeredBy(core.Manual("api")).
        Then(fetchNode).
        Then(createNode).
        Build()
}
```

## See Also

- **[Flow](/docs/reference/core/flow/)** - Flow builder
- **[State](/docs/reference/core/state/)** - FlowState and result access
- **[Rate Limiting](/docs/guides/advanced-patterns/rate-limiting/)** - Rate limit patterns
- **[Compensation](/docs/guides/advanced-patterns/compensation-saga/)** - Saga pattern
