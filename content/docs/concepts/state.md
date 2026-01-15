---
title: "State"
description: "State - Resolute documentation"
weight: 50
toc: true
---


# FlowState

**FlowState** carries data through workflow execution, storing node outputs, cursors for incremental processing, and input data.

## What is FlowState?

FlowState is the runtime state container that:
- Stores results from each node execution
- Tracks cursors for incremental data processing
- Provides type-safe access to stored values
- Supports snapshots for compensation

```go
type FlowState struct {
    input   map[string][]byte  // Initial workflow input
    results map[string]any     // Node outputs (keyed by node name)
    cursors map[string]Cursor  // Position tracking for data sources
}
```

## Accessing Node Outputs

### Type-Safe Retrieval

Use generic functions for compile-time type safety:

```go
// Get a value (panics if key missing or type mismatch)
result := core.Get[FetchOutput](state, "fetch-node")

// Get with default fallback (returns default on missing/mismatch)
result := core.GetOr(state, "fetch-node", FetchOutput{})
```

### Storing Values

Nodes automatically store their outputs, but you can also store manually:

```go
// Set a typed value
core.Set(state, "custom-key", MyData{Value: 42})

// Raw access (less safe)
state.SetResult("key", value)
raw := state.GetResult("key")  // Returns any
```

### Example: Data Flow Between Nodes

```go
// First node produces output
fetchNode := core.NewNode("fetch", fetchData, FetchInput{})

// Second node consumes it via WithInputFunc
processNode := core.NewNode("process", processData, ProcessInput{}).
    WithInputFunc(func(state *core.FlowState) ProcessInput {
        // Type-safe retrieval of previous node's output
        fetchResult := core.Get[FetchOutput](state, "fetch")
        return ProcessInput{
            Items: fetchResult.Items,
            Count: len(fetchResult.Items),
        }
    })
```

## Cursors

Cursors track processing position for incremental data synchronization.

### What is a Cursor?

```go
type Cursor struct {
    Source    string    // Data source identifier
    Position  string    // Current position (timestamp, ID, offset)
    UpdatedAt time.Time // When cursor was last updated
}
```

Cursors enable:
- Resume from last position after restarts
- Incremental sync (only process new/changed data)
- Checkpoint progress within long-running syncs

### Reading Cursors

```go
// Get cursor for a data source
cursor := state.GetCursor("jira-issues")

// Parse as timestamp
since, err := cursor.Time()

// Parse with default fallback
since := cursor.TimeOr(time.Now().AddDate(0, 0, -7))  // Default: 7 days ago
```

### Updating Cursors

```go
// Update cursor position
state.SetCursor("jira-issues", latestIssue.UpdatedAt.Format(time.RFC3339))
```

### Cursor-Based Incremental Sync

```go
fetchNode := core.NewNode("fetch", fetchIssues, FetchInput{}).
    WithInputFunc(func(state *core.FlowState) FetchInput {
        cursor := state.GetCursor("jira-issues")
        return FetchInput{
            Since: cursor.TimeOr(time.Now().AddDate(0, -1, 0)),  // Default: 1 month
        }
    })

// After successful sync, update cursor
updateCursorNode := core.NewNode("update-cursor", updateCursor, UpdateInput{}).
    WithInputFunc(func(state *core.FlowState) UpdateInput {
        result := core.Get[FetchOutput](state, "fetch")
        if len(result.Issues) == 0 {
            return UpdateInput{}  // No update needed
        }
        latest := result.Issues[len(result.Issues)-1]
        return UpdateInput{
            Source:   "jira-issues",
            Position: latest.UpdatedAt.Format(time.RFC3339),
        }
    })
```

### Cursor Persistence

Cursors are automatically persisted:
1. **Load**: At flow start, cursors are loaded from the configured backend
2. **Save**: On successful completion, cursors are saved

```go
// Default: Local .resolute/ directory
// Production: Configure a cloud backend
flow := core.NewFlow("sync").
    WithState(core.StateConfig{
        Backend: myS3Backend,
    }).
    ...
```

## State Snapshots

Snapshots capture FlowState at a point in time for compensation:

```go
// Create a snapshot (deep copy)
snapshot := state.Snapshot()

// Snapshot is used in Saga pattern for rollback
// When compensation runs, it receives the snapshot from when the original node ran
```

### Compensation with Snapshots

```go
// During execution:
// 1. fetchNode executes, snapshot captured
// 2. processNode fails
// 3. Compensation for fetchNode runs with the captured snapshot
//    (can see what fetchNode produced, undo accordingly)
```

## Thread Safety

FlowState is thread-safe:

```go
type FlowState struct {
    mu sync.RWMutex  // Protects all fields
    // ...
}
```

All read/write operations acquire appropriate locks. This is important for parallel node execution where multiple goroutines access state concurrently.

## State Backend

The `StateBackend` interface allows pluggable storage:

```go
type StateBackend interface {
    Load(workflowID, flowName string) (*PersistedState, error)
    Save(workflowID, flowName string, state *PersistedState) error
}

type PersistedState struct {
    Cursors   map[string]Cursor
    Metadata  map[string]string
    Version   int64
    UpdatedAt time.Time
}
```

### Default Backend

The default backend stores state in `.resolute/` directory:

```
.resolute/
├── workflow-123/
│   └── my-flow.json
├── workflow-456/
│   └── my-flow.json
```

### Custom Backend

Implement `StateBackend` for production storage:

```go
type S3Backend struct {
    bucket string
    client *s3.Client
}

func (b *S3Backend) Load(workflowID, flowName string) (*core.PersistedState, error) {
    key := fmt.Sprintf("%s/%s.json", workflowID, flowName)
    // Load from S3...
}

func (b *S3Backend) Save(workflowID, flowName string, state *core.PersistedState) error {
    key := fmt.Sprintf("%s/%s.json", workflowID, flowName)
    // Save to S3...
}

// Use in flow
flow := core.NewFlow("sync").
    WithState(core.StateConfig{
        Backend:   &S3Backend{bucket: "my-bucket", client: s3Client},
        Namespace: "production",
    }).
    Then(syncNode).
    Build()
```

## FlowState Lifecycle

```
┌─────────────────────────────────────────────────────────────────────┐
│                     FlowState Lifecycle                              │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  1. CREATION                                                         │
│     └─▶ NewFlowState(input) creates empty state with input data     │
│                                                                      │
│  2. LOAD PERSISTED                                                   │
│     └─▶ LoadPersisted() loads cursors from backend                  │
│                                                                      │
│  3. NODE EXECUTION (repeated for each node)                          │
│     ├─▶ WithInputFunc reads from state                              │
│     ├─▶ Node executes activity                                      │
│     └─▶ SetResult() stores output                                   │
│                                                                      │
│  4. SAVE PERSISTED                                                   │
│     └─▶ SavePersisted() saves updated cursors                       │
│                                                                      │
│  5. COMPLETION                                                       │
│     └─▶ State discarded (in-memory results not persisted)           │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

## API Reference

### FlowState Methods

| Method | Description |
|--------|-------------|
| `GetResult(key)` | Get raw result by key (returns `any`) |
| `SetResult(key, value)` | Store raw result by key |
| `GetCursor(source)` | Get cursor for data source |
| `SetCursor(source, position)` | Update cursor position |
| `Snapshot()` | Create deep copy of current state |
| `LoadPersisted(ctx, flow, cfg)` | Load cursors from backend |
| `SavePersisted(ctx, flow, cfg)` | Save cursors to backend |

### Generic Functions

| Function | Description |
|----------|-------------|
| `Get[T](state, key)` | Get typed value (panics on error) |
| `GetOr[T](state, key, default)` | Get typed value with default |
| `Set[T](state, key, value)` | Store typed value |

### Cursor Methods

| Method | Description |
|--------|-------------|
| `Time()` | Parse position as `time.Time` |
| `TimeOr(default)` | Parse position with fallback |

## Best Practices

### 1. Use Typed Access

Always prefer generic functions for type safety:

```go
// Good
result := core.Get[FetchOutput](state, "fetch")

// Avoid
raw := state.GetResult("fetch")
result := raw.(FetchOutput)  // Runtime panic risk
```

### 2. Name Output Keys Consistently

Use the node name or a descriptive key:

```go
// Output stored as "fetch-issues" by default
fetchNode := core.NewNode("fetch-issues", fetch, input)

// Or explicitly name it
fetchNode := core.NewNode("fetch-issues", fetch, input).As("issues")
```

### 3. Always Handle Missing Cursors

New flows have no cursors. Use `TimeOr` for defaults:

```go
// Good: Handles missing cursor
since := cursor.TimeOr(time.Now().AddDate(0, 0, -30))

// Risky: May panic or return zero time
since, _ := cursor.Time()
```

### 4. Keep Results Small

FlowState is in-memory. For large data, store references:

```go
// Bad: Large data in state
type BadOutput struct {
    AllRecords []Record  // Could be millions
}

// Good: Store reference
type GoodOutput struct {
    S3Key     string  // Reference to data
    Count     int
    Summary   string
}
```

## See Also

- **[Nodes](/docs/concepts/nodes/)** - How nodes store outputs
- **[Flows](/docs/concepts/flows/)** - State configuration in flows
- **[Data References](/docs/guides/advanced-patterns/data-references/)** - Claim check pattern for large data
