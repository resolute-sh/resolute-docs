---
title: "Sequential Steps"
description: "Sequential Steps - Resolute documentation"
weight: 10
toc: true
---


# Sequential Steps

Sequential steps are the foundation of Resolute flows. Each step executes after the previous one completes, with outputs automatically available to subsequent steps.

## Basic Pattern

Use `Then()` to add sequential steps:

```go
flow := core.NewFlow("data-pipeline").
    TriggeredBy(core.Manual("api")).
    Then(fetchNode).
    Then(processNode).
    Then(storeNode).
    Build()
```

Execution order:
1. `fetchNode` runs
2. When complete, `processNode` runs
3. When complete, `storeNode` runs

## Passing Data Between Steps

Each node's output is automatically stored in `FlowState` under its name (or a custom key via `.As()`).

### Using WithInputFunc

The most common pattern uses `WithInputFunc` to read previous outputs:

```go
// First node: fetch data
type FetchOutput struct {
    Items []Item
    Total int
}

fetchNode := core.NewNode("fetch", fetchData, FetchInput{
    Source: "api",
})

// Second node: process data from first node
type ProcessInput struct {
    Items []Item
    Count int
}

processNode := core.NewNode("process", processData, ProcessInput{}).
    WithInputFunc(func(state *core.FlowState) ProcessInput {
        // Type-safe retrieval of previous output
        result := core.Get[FetchOutput](state, "fetch")
        return ProcessInput{
            Items: result.Items,
            Count: result.Total,
        }
    })

// Third node: store results
storeNode := core.NewNode("store", storeData, StoreInput{}).
    WithInputFunc(func(state *core.FlowState) StoreInput {
        processed := core.Get[ProcessOutput](state, "process")
        return StoreInput{
            Records: processed.Records,
        }
    })
```

### Using Output Markers

For simpler cases, use `Output()` markers to reference previous outputs directly:

```go
// Reference entire output from a previous node
processNode := core.NewNode("process", processData, ProcessInput{
    Data: core.Output[FetchOutput]("fetch"),
})

// Reference specific field
storeNode := core.NewNode("store", storeData, StoreInput{
    Records: core.OutputRef[[]Record]("process", "Records"),
})
```

### Custom Output Keys

Use `.As()` to name outputs for clarity:

```go
fetchNode := core.NewNode("fetch-jira-issues", fetchIssues, input).
    As("issues")  // Store output as "issues" instead of "fetch-jira-issues"

// Reference by the custom key
processNode := core.NewNode("process", processData, ProcessInput{}).
    WithInputFunc(func(state *core.FlowState) ProcessInput {
        issues := core.Get[FetchOutput](state, "issues")
        return ProcessInput{Items: issues.Items}
    })
```

## Complete Example

A data synchronization flow that fetches, transforms, and stores data:

```go
package main

import (
    "context"
    "time"

    "github.com/resolute/resolute/core"
)

// Input/Output types
type FetchInput struct {
    Since time.Time
}

type FetchOutput struct {
    Records []Record
    Latest  time.Time
}

type TransformInput struct {
    Records []Record
}

type TransformOutput struct {
    Transformed []TransformedRecord
    Skipped     int
}

type StoreInput struct {
    Records []TransformedRecord
}

type StoreOutput struct {
    Stored int
}

// Activity implementations
func fetchRecords(ctx context.Context, input FetchInput) (FetchOutput, error) {
    // Fetch from external API
    records, err := api.FetchSince(ctx, input.Since)
    if err != nil {
        return FetchOutput{}, err
    }

    var latest time.Time
    for _, r := range records {
        if r.UpdatedAt.After(latest) {
            latest = r.UpdatedAt
        }
    }

    return FetchOutput{
        Records: records,
        Latest:  latest,
    }, nil
}

func transformRecords(ctx context.Context, input TransformInput) (TransformOutput, error) {
    var transformed []TransformedRecord
    var skipped int

    for _, r := range input.Records {
        if t, ok := transform(r); ok {
            transformed = append(transformed, t)
        } else {
            skipped++
        }
    }

    return TransformOutput{
        Transformed: transformed,
        Skipped:     skipped,
    }, nil
}

func storeRecords(ctx context.Context, input StoreInput) (StoreOutput, error) {
    count, err := db.BulkInsert(ctx, input.Records)
    if err != nil {
        return StoreOutput{}, err
    }
    return StoreOutput{Stored: count}, nil
}

func main() {
    // Build nodes
    fetchNode := core.NewNode("fetch", fetchRecords, FetchInput{}).
        WithInputFunc(func(state *core.FlowState) FetchInput {
            // Use cursor for incremental sync
            cursor := state.GetCursor("records")
            return FetchInput{
                Since: cursor.TimeOr(time.Now().AddDate(0, -1, 0)),
            }
        }).
        WithTimeout(5 * time.Minute).
        As("fetched")

    transformNode := core.NewNode("transform", transformRecords, TransformInput{}).
        WithInputFunc(func(state *core.FlowState) TransformInput {
            fetched := core.Get[FetchOutput](state, "fetched")
            return TransformInput{Records: fetched.Records}
        }).
        WithTimeout(2 * time.Minute).
        As("transformed")

    storeNode := core.NewNode("store", storeRecords, StoreInput{}).
        WithInputFunc(func(state *core.FlowState) StoreInput {
            transformed := core.Get[TransformOutput](state, "transformed")
            return StoreInput{Records: transformed.Transformed}
        }).
        WithTimeout(3 * time.Minute)

    // Update cursor after successful store
    updateCursorNode := core.NewNode("update-cursor", updateCursor, UpdateCursorInput{}).
        WithInputFunc(func(state *core.FlowState) UpdateCursorInput {
            fetched := core.Get[FetchOutput](state, "fetched")
            return UpdateCursorInput{
                Source:   "records",
                Position: fetched.Latest.Format(time.RFC3339),
            }
        })

    // Build flow
    flow := core.NewFlow("sync-records").
        TriggeredBy(core.Schedule("*/15 * * * *")).  // Every 15 minutes
        Then(fetchNode).
        Then(transformNode).
        Then(storeNode).
        Then(updateCursorNode).
        Build()

    // Run worker
    core.NewWorker().
        WithConfig(core.WorkerConfig{
            TaskQueue: "sync-queue",
        }).
        WithFlow(flow).
        Run()
}
```

## Step Configuration

Each node can be configured independently:

```go
fetchNode := core.NewNode("fetch", fetchData, input).
    WithTimeout(5 * time.Minute).           // Activity timeout
    WithRetry(core.RetryPolicy{             // Retry configuration
        InitialInterval:    time.Second,
        BackoffCoefficient: 2.0,
        MaximumInterval:    time.Minute,
        MaximumAttempts:    5,
    }).
    WithRateLimit(100, time.Minute).        // Rate limiting
    As("fetched")                           // Output key
```

## Error Behavior

When a sequential step fails:

1. The activity retries according to its `RetryPolicy`
2. If all retries exhaust, the error propagates
3. Compensation runs for any completed steps with `.OnError()` handlers
4. The workflow fails with the original error

```go
// Add compensation for rollback on failure
createNode := core.NewNode("create", createRecord, input).
    OnError(deleteNode)  // Runs if subsequent steps fail

flow := core.NewFlow("transactional").
    TriggeredBy(core.Manual("api")).
    Then(createNode).        // If this succeeds...
    Then(notifyNode).        // ...and this fails...
    Build()                  // ...deleteNode runs to compensate
```

## Best Practices

### 1. Keep Steps Focused

Each node should do one thing:

```go
// Good: Separate concerns
flow := core.NewFlow("pipeline").
    Then(fetchNode).      // Fetch data
    Then(validateNode).   // Validate data
    Then(transformNode).  // Transform data
    Then(storeNode).      // Store data
    Build()

// Avoid: Monolithic steps
flow := core.NewFlow("pipeline").
    Then(doEverythingNode).  // Too much in one step
    Build()
```

### 2. Use Meaningful Names

Node names appear in Temporal UI and logs:

```go
// Good: Descriptive names
fetchNode := core.NewNode("fetch-jira-issues", fetch, input)
processNode := core.NewNode("generate-embeddings", process, input)

// Avoid: Generic names
fetchNode := core.NewNode("step1", fetch, input)
processNode := core.NewNode("step2", process, input)
```

### 3. Handle Empty Data

Check for empty results before processing:

```go
processNode := core.NewNode("process", processData, ProcessInput{}).
    WithInputFunc(func(state *core.FlowState) ProcessInput {
        fetched := core.Get[FetchOutput](state, "fetch")
        if len(fetched.Records) == 0 {
            return ProcessInput{Skip: true}  // Signal to skip processing
        }
        return ProcessInput{Records: fetched.Records}
    })
```

### 4. Configure Appropriate Timeouts

Match timeouts to expected operation duration:

```go
// External API: may be slow
fetchNode := core.NewNode("fetch", fetch, input).
    WithTimeout(5 * time.Minute)

// Local processing: should be fast
processNode := core.NewNode("process", process, input).
    WithTimeout(30 * time.Second)

// Database write: moderate
storeNode := core.NewNode("store", store, input).
    WithTimeout(2 * time.Minute)
```

## See Also

- **[Parallel Execution](/docs/guides/building-flows/parallel-execution/)** - Execute nodes concurrently
- **[Conditional Logic](/docs/guides/building-flows/conditional-logic/)** - Branch based on conditions
- **[Error Handling](/docs/guides/building-flows/error-handling/)** - Handle failures gracefully
- **[FlowState](/docs/concepts/state/)** - State management details
