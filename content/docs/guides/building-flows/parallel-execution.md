---
title: "Parallel Execution"
description: "Parallel Execution - Resolute documentation"
weight: 20
toc: true
---


# Parallel Execution

Parallel execution allows multiple nodes to run concurrently, reducing total flow duration when operations are independent.

## Basic Pattern

Use `ThenParallel()` to execute multiple nodes concurrently:

```go
flow := core.NewFlow("parallel-pipeline").
    TriggeredBy(core.Manual("api")).
    Then(fetchNode).
    ThenParallel("process-all",
        processTypeA,
        processTypeB,
        processTypeC,
    ).
    Then(aggregateNode).
    Build()
```

Execution order:
1. `fetchNode` runs (sequential)
2. `processTypeA`, `processTypeB`, `processTypeC` run concurrently
3. All three must complete before `aggregateNode` runs

## When to Use Parallel Execution

Use parallel execution when:
- Operations are independent (no data dependencies between them)
- Each operation calls a different external service
- Processing multiple items that don't affect each other
- You want to reduce total execution time

```
Sequential:      |--A--|--B--|--C--|  Total: 9s
                   3s    3s    3s

Parallel:        |--A--|
                 |--B--|               Total: 3s
                 |--C--|
```

## Fan-Out Pattern

Process multiple items concurrently:

```go
// Fetch items first
fetchNode := core.NewNode("fetch", fetchItems, FetchInput{}).
    As("items")

// Process each type in parallel
processOrders := core.NewNode("process-orders", processOrders, ProcessInput{}).
    WithInputFunc(func(state *core.FlowState) ProcessInput {
        items := core.Get[FetchOutput](state, "items")
        return ProcessInput{Items: filterOrders(items.Items)}
    })

processReturns := core.NewNode("process-returns", processReturns, ProcessInput{}).
    WithInputFunc(func(state *core.FlowState) ProcessInput {
        items := core.Get[FetchOutput](state, "items")
        return ProcessInput{Items: filterReturns(items.Items)}
    })

processRefunds := core.NewNode("process-refunds", processRefunds, ProcessInput{}).
    WithInputFunc(func(state *core.FlowState) ProcessInput {
        items := core.Get[FetchOutput](state, "items")
        return ProcessInput{Items: filterRefunds(items.Items)}
    })

// Build flow
flow := core.NewFlow("process-transactions").
    TriggeredBy(core.Schedule("0 * * * *")).
    Then(fetchNode).
    ThenParallel("process-types",
        processOrders,
        processReturns,
        processRefunds,
    ).
    Then(reportNode).
    Build()
```

## Collecting Results

All parallel node outputs are stored in FlowState. Access them in subsequent steps:

```go
// Parallel nodes store their outputs
enrichFromJira := core.NewNode("enrich-jira", enrichJira, input).As("jira")
enrichFromSlack := core.NewNode("enrich-slack", enrichSlack, input).As("slack")
enrichFromGithub := core.NewNode("enrich-github", enrichGithub, input).As("github")

// Aggregate node collects all results
aggregateNode := core.NewNode("aggregate", aggregate, AggregateInput{}).
    WithInputFunc(func(state *core.FlowState) AggregateInput {
        return AggregateInput{
            JiraData:   core.Get[JiraOutput](state, "jira"),
            SlackData:  core.Get[SlackOutput](state, "slack"),
            GithubData: core.Get[GithubOutput](state, "github"),
        }
    })

flow := core.NewFlow("enrich-data").
    TriggeredBy(core.Manual("api")).
    Then(fetchNode).
    ThenParallel("enrich",
        enrichFromJira,
        enrichFromSlack,
        enrichFromGithub,
    ).
    Then(aggregateNode).
    Build()
```

## Error Handling in Parallel Steps

When any node in a parallel step fails:

1. **Immediate propagation**: The first error stops the parallel step
2. **Other nodes continue**: Already-running nodes complete (their results may be lost)
3. **Compensation runs**: For completed nodes with `.OnError()` handlers
4. **Workflow fails**: With the original error

```go
// Each parallel node can have its own compensation
createOrder := core.NewNode("create-order", createOrder, input).
    OnError(cancelOrderNode)

createInvoice := core.NewNode("create-invoice", createInvoice, input).
    OnError(voidInvoiceNode)

createShipment := core.NewNode("create-shipment", createShipment, input).
    OnError(cancelShipmentNode)

flow := core.NewFlow("fulfill-order").
    TriggeredBy(core.Manual("api")).
    ThenParallel("create-all",
        createOrder,
        createInvoice,
        createShipment,
    ).
    Then(notifyCustomerNode).
    Build()
```

If `createShipment` fails:
1. Error captured
2. `cancelOrderNode` runs (if `createOrder` succeeded)
3. `voidInvoiceNode` runs (if `createInvoice` succeeded)
4. Workflow fails with shipment error

## Complete Example

Multi-source data enrichment pipeline:

```go
package main

import (
    "context"
    "time"

    "github.com/resolute/resolute/core"
)

type Issue struct {
    ID          string
    Title       string
    Description string
    JiraData    *JiraData
    SlackData   *SlackData
    PRData      *PRData
}

type FetchOutput struct {
    Issues []Issue
}

type EnrichInput struct {
    IssueIDs []string
}

type JiraEnrichOutput struct {
    Data map[string]JiraData
}

type SlackEnrichOutput struct {
    Data map[string]SlackData
}

type PREnrichOutput struct {
    Data map[string]PRData
}

type MergeInput struct {
    Issues  []Issue
    Jira    map[string]JiraData
    Slack   map[string]SlackData
    PRs     map[string]PRData
}

type MergeOutput struct {
    EnrichedIssues []Issue
}

func main() {
    // Fetch issues to enrich
    fetchNode := core.NewNode("fetch-issues", fetchIssues, FetchInput{}).
        As("issues")

    // Enrich from multiple sources in parallel
    enrichJira := core.NewNode("enrich-jira", enrichFromJira, EnrichInput{}).
        WithInputFunc(func(state *core.FlowState) EnrichInput {
            issues := core.Get[FetchOutput](state, "issues")
            return EnrichInput{IssueIDs: extractIDs(issues.Issues)}
        }).
        WithTimeout(2 * time.Minute).
        WithRateLimit(50, time.Minute).  // Jira rate limit
        As("jira-data")

    enrichSlack := core.NewNode("enrich-slack", enrichFromSlack, EnrichInput{}).
        WithInputFunc(func(state *core.FlowState) EnrichInput {
            issues := core.Get[FetchOutput](state, "issues")
            return EnrichInput{IssueIDs: extractIDs(issues.Issues)}
        }).
        WithTimeout(2 * time.Minute).
        As("slack-data")

    enrichPRs := core.NewNode("enrich-prs", enrichFromGithub, EnrichInput{}).
        WithInputFunc(func(state *core.FlowState) EnrichInput {
            issues := core.Get[FetchOutput](state, "issues")
            return EnrichInput{IssueIDs: extractIDs(issues.Issues)}
        }).
        WithTimeout(3 * time.Minute).
        WithRateLimit(1000, time.Hour).  // GitHub rate limit
        As("pr-data")

    // Merge all enrichment data
    mergeNode := core.NewNode("merge-data", mergeEnrichments, MergeInput{}).
        WithInputFunc(func(state *core.FlowState) MergeInput {
            return MergeInput{
                Issues: core.Get[FetchOutput](state, "issues").Issues,
                Jira:   core.Get[JiraEnrichOutput](state, "jira-data").Data,
                Slack:  core.Get[SlackEnrichOutput](state, "slack-data").Data,
                PRs:    core.Get[PREnrichOutput](state, "pr-data").Data,
            }
        })

    // Store enriched data
    storeNode := core.NewNode("store-enriched", storeIssues, StoreInput{}).
        WithInputFunc(func(state *core.FlowState) StoreInput {
            merged := core.Get[MergeOutput](state, "merge-data")
            return StoreInput{Issues: merged.EnrichedIssues}
        })

    // Build flow
    flow := core.NewFlow("enrich-issues").
        TriggeredBy(core.Schedule("0 */4 * * *")).  // Every 4 hours
        Then(fetchNode).
        ThenParallel("enrich-sources",
            enrichJira,
            enrichSlack,
            enrichPRs,
        ).
        Then(mergeNode).
        Then(storeNode).
        Build()

    core.NewWorker().
        WithConfig(core.WorkerConfig{
            TaskQueue: "enrichment-queue",
        }).
        WithFlow(flow).
        Run()
}
```

## Parallel Within Conditionals

Parallel execution works inside conditional branches:

```go
flow := core.NewFlow("conditional-parallel").
    TriggeredBy(core.Manual("api")).
    Then(checkOrderType).
    When(func(s *core.FlowState) bool {
        return core.Get[CheckOutput](s, "check").IsRush
    }).
    ThenParallel("rush-processing",
        expediteShipping,
        notifyWarehouse,
        alertCustomerService,
    ).
    Else().
    Then(standardProcessing).
    EndWhen().
    Then(completeOrder).
    Build()
```

## Configuration Options

Each parallel node can have independent configuration:

```go
ThenParallel("multi-api-calls",
    // Each node has its own timeout and retry policy
    core.NewNode("fast-api", fastAPI, input).
        WithTimeout(30 * time.Second).
        WithRetry(core.RetryPolicy{MaximumAttempts: 5}),

    core.NewNode("slow-api", slowAPI, input).
        WithTimeout(5 * time.Minute).
        WithRetry(core.RetryPolicy{MaximumAttempts: 3}),

    core.NewNode("flaky-api", flakyAPI, input).
        WithTimeout(1 * time.Minute).
        WithRetry(core.RetryPolicy{
            InitialInterval:    time.Second,
            BackoffCoefficient: 2.0,
            MaximumAttempts:    10,
        }),
)
```

## Best Practices

### 1. Ensure Independence

Parallel nodes should not depend on each other:

```go
// Good: Independent operations
ThenParallel("independent-calls",
    callServiceA,  // No dependency on B or C
    callServiceB,  // No dependency on A or C
    callServiceC,  // No dependency on A or B
)

// Bad: Hidden dependencies
ThenParallel("coupled-calls",
    createUser,      // Creates user
    createProfile,   // Needs user ID - RACE CONDITION!
)
```

### 2. Use Shared Rate Limiters

When parallel nodes call the same API:

```go
// Create shared limiter for API
apiLimiter := core.NewSharedRateLimiter("external-api", 100, time.Minute)

node1 := core.NewNode("call-1", callAPI, input1).WithSharedRateLimit(apiLimiter)
node2 := core.NewNode("call-2", callAPI, input2).WithSharedRateLimit(apiLimiter)
node3 := core.NewNode("call-3", callAPI, input3).WithSharedRateLimit(apiLimiter)

ThenParallel("api-calls", node1, node2, node3)
```

### 3. Name Parallel Steps

Give meaningful names to parallel groups:

```go
// Good: Descriptive group name
ThenParallel("enrich-from-external-sources", ...)
ThenParallel("notify-stakeholders", ...)

// Avoid: Generic names
ThenParallel("parallel-1", ...)
```

### 4. Consider Failure Impact

Think about what happens when one node fails:

```go
// Option A: All-or-nothing (default)
// If any fails, compensate all and fail workflow
ThenParallel("critical-operations",
    opA.OnError(compensateA),
    opB.OnError(compensateB),
    opC.OnError(compensateC),
)

// Option B: Partial success acceptable
// Handle failures in aggregation
ThenParallel("best-effort",
    enrichA,  // May fail
    enrichB,  // May fail
    enrichC,  // May fail
)
// Aggregation handles missing data gracefully
Then(aggregateWithDefaults)
```

### 5. Balance Parallelism

Don't create too many parallel nodes:

```go
// Good: Reasonable parallelism
ThenParallel("process-batch",
    processBatch1,
    processBatch2,
    processBatch3,
)

// Avoid: Excessive parallelism (use pagination instead)
ThenParallel("process-all",
    item1, item2, item3, // ... 100 items
)
```

For large item counts, use the [Pagination](/docs/guides/advanced-patterns/pagination/) pattern instead.

## See Also

- **[Sequential Steps](/docs/guides/building-flows/sequential-steps/)** - Basic sequential execution
- **[Conditional Logic](/docs/guides/building-flows/conditional-logic/)** - Branching based on conditions
- **[Error Handling](/docs/guides/building-flows/error-handling/)** - Handling failures
- **[Rate Limiting](/docs/guides/advanced-patterns/rate-limiting/)** - Coordinating API calls
- **[Pagination](/docs/guides/advanced-patterns/pagination/)** - Processing large datasets
