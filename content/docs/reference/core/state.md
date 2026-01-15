---
title: "FlowState"
description: "FlowState - Resolute documentation"
weight: 40
toc: true
---


# FlowState

FlowState carries data through workflow execution, holding input data, activity outputs, and cursor state for incremental processing.

## Types

### FlowState

```go
type FlowState struct {
    // unexported fields (thread-safe)
}
```

Thread-safe state container for workflow execution.

### Cursor

```go
type Cursor struct {
    Source    string    `json:"source"`
    Position  string    `json:"position"`
    UpdatedAt time.Time `json:"updated_at"`
}
```

Tracks incremental processing position for a data source.

### StateConfig

```go
type StateConfig struct {
    Backend   StateBackend
    Namespace string
}
```

Defines state persistence behavior.

### StateBackend

```go
type StateBackend interface {
    Load(workflowID, flowName string) (*PersistedState, error)
    Save(workflowID, flowName string, state *PersistedState) error
}
```

Interface for pluggable state persistence.

### PersistedState

```go
type PersistedState struct {
    Cursors   map[string]Cursor `json:"cursors"`
    Metadata  map[string]string `json:"metadata,omitempty"`
    Version   int64             `json:"version"`
    UpdatedAt time.Time         `json:"updated_at"`
}
```

Data structure saved between workflow runs.

## Constructor

### NewFlowState

```go
func NewFlowState(input FlowInput) *FlowState
```

Creates a new flow state with the given input.

**Parameters:**
- `input` - Initial flow input

**Returns:** `*FlowState` initialized with input data

## Generic Accessor Functions

### Get

```go
func Get[T any](s *FlowState, key string) T
```

Retrieves a typed value from results.

**Type Parameters:**
- `T` - Expected result type

**Parameters:**
- `s` - FlowState instance
- `key` - Result key (node name or output key)

**Returns:** Typed value

**Panics if:**
- Key doesn't exist
- Type doesn't match

**Example:**
```go
// In a predicate or input function
issues := core.Get[jira.FetchOutput](state, "issues")
count := issues.Count
```

### GetOr

```go
func GetOr[T any](s *FlowState, key string, defaultVal T) T
```

Retrieves a typed value with a default fallback.

**Type Parameters:**
- `T` - Expected result type

**Parameters:**
- `s` - FlowState instance
- `key` - Result key
- `defaultVal` - Value to return if key missing or type mismatch

**Returns:** Typed value or default

**Example:**
```go
// Safely get with default
config := core.GetOr(state, "config", DefaultConfig{
    BatchSize: 100,
})
```

### Set

```go
func Set[T any](s *FlowState, key string, value T)
```

Stores a typed value in results.

**Type Parameters:**
- `T` - Value type

**Parameters:**
- `s` - FlowState instance
- `key` - Storage key
- `value` - Value to store

**Example:**
```go
core.Set(state, "processed-count", 42)
```

## FlowState Methods

### GetResult

```go
func (s *FlowState) GetResult(key string) any
```

Retrieves a raw result by key. Returns `any` because activity result types vary. Prefer `Get[T]()` for type safety.

**Parameters:**
- `key` - Result key

**Returns:** Raw value or nil if not found

### SetResult

```go
func (s *FlowState) SetResult(key string, value any)
```

Stores a result by key. Called automatically by node execution.

**Parameters:**
- `key` - Storage key
- `value` - Value to store

### GetCursor

```go
func (s *FlowState) GetCursor(source string) Cursor
```

Returns the cursor for a data source.

**Parameters:**
- `source` - Cursor source identifier

**Returns:** Cursor (empty cursor if not found)

**Example:**
```go
cursor := state.GetCursor("jira")
lastSync := cursor.TimeOr(time.Now().Add(-24 * time.Hour))
```

### SetCursor

```go
func (s *FlowState) SetCursor(source, position string)
```

Updates the cursor for a data source.

**Parameters:**
- `source` - Cursor source identifier
- `position` - New position value

**Example:**
```go
state.SetCursor("jira", time.Now().Format(time.RFC3339))
```

### Snapshot

```go
func (s *FlowState) Snapshot() *FlowState
```

Creates a copy of the current state for compensation.

**Returns:** Deep copy of FlowState

### LoadPersisted

```go
func (s *FlowState) LoadPersisted(ctx workflow.Context, flowName string, cfg *StateConfig) error
```

Loads persisted state (cursors) from the configured backend.

**Parameters:**
- `ctx` - Temporal workflow context
- `flowName` - Flow identifier
- `cfg` - State configuration (nil for default)

**Returns:** Error if loading fails

### SavePersisted

```go
func (s *FlowState) SavePersisted(ctx workflow.Context, flowName string, cfg *StateConfig) error
```

Saves persisted state (cursors) to the configured backend.

**Parameters:**
- `ctx` - Temporal workflow context
- `flowName` - Flow identifier
- `cfg` - State configuration (nil for default)

**Returns:** Error if saving fails

## Cursor Methods

### Time

```go
func (c Cursor) Time() (time.Time, error)
```

Parses the cursor position as a `time.Time` value.

**Returns:** Parsed time and error if parsing fails

### TimeOr

```go
func (c Cursor) TimeOr(def time.Time) time.Time
```

Parses the cursor position as `time.Time`, returning default on error.

**Parameters:**
- `def` - Default time if parsing fails or cursor is empty

**Returns:** Parsed time or default

**Example:**
```go
cursor := state.GetCursor("jira")
since := cursor.TimeOr(time.Now().Add(-7 * 24 * time.Hour))  // Default: 7 days ago
```

## State Backend

### Default Backend

By default, state is persisted to the `.resolute/` directory.

### Custom Backend

Implement `StateBackend` for custom persistence:

```go
type S3Backend struct {
    bucket string
    client *s3.Client
}

func (b *S3Backend) Load(workflowID, flowName string) (*core.PersistedState, error) {
    key := fmt.Sprintf("%s/%s.json", flowName, workflowID)
    // Load from S3...
}

func (b *S3Backend) Save(workflowID, flowName string, state *core.PersistedState) error {
    key := fmt.Sprintf("%s/%s.json", flowName, workflowID)
    // Save to S3...
}
```

Use in flow:

```go
flow := core.NewFlow("production-sync").
    TriggeredBy(core.Schedule("0 * * * *")).
    WithState(core.StateConfig{
        Backend: &S3Backend{bucket: "my-state-bucket"},
    }).
    Then(syncNode).
    Build()
```

### SetDefaultBackend

```go
func SetDefaultBackend(b StateBackend)
```

Allows overriding the default backend globally (useful for testing).

## Usage Patterns

### Accessing Previous Node Output

```go
flow := core.NewFlow("pipeline").
    TriggeredBy(core.Manual("api")).
    Then(fetchNode.As("data")).
    When(func(s *core.FlowState) bool {
        data := core.Get[FetchOutput](s, "data")
        return len(data.Items) > 0
    }).
        Then(processNode).
    EndWhen().
    Build()
```

### Incremental Processing with Cursors

```go
// Activity updates cursor after processing
func SyncActivity(ctx context.Context, input SyncInput) (SyncOutput, error) {
    // Fetch data since cursor position
    data, err := fetchSince(input.Since)
    if err != nil {
        return SyncOutput{}, err
    }

    // Return new cursor position
    return SyncOutput{
        Items:     data,
        NewCursor: time.Now().Format(time.RFC3339),
    }, nil
}

// Flow uses cursor for incremental sync
flow := core.NewFlow("incremental-sync").
    TriggeredBy(core.Schedule("0 * * * *")).
    Then(core.NewNode("sync", SyncActivity, SyncInput{
        Since: core.CursorFor("sync-cursor"),
    })).
    Build()
```

### Input Resolution with Magic Markers

```go
// Node input references previous output
processInput := ProcessInput{
    Items: core.Output("fetch.Items"),  // Resolved at runtime
    Count: core.Output("fetch.Count"),
}

flow := core.NewFlow("pipeline").
    TriggeredBy(core.Manual("api")).
    Then(fetchNode.As("fetch")).
    Then(core.NewNode("process", ProcessActivity, processInput)).
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
    // Custom S3 backend for production
    s3Backend := NewS3Backend("my-state-bucket")

    // Flow with state management
    flow := core.NewFlow("data-pipeline").
        TriggeredBy(core.Schedule("0 * * * *")).
        WithState(core.StateConfig{
            Backend: s3Backend,
        }).
        Then(jira.FetchIssues(jira.FetchInput{
            JQL:    "project = PLATFORM",
            Cursor: core.CursorFor("jira"),
        }).As("issues")).
        When(func(s *core.FlowState) bool {
            issues := core.Get[jira.FetchOutput](s, "issues")
            return issues.Count > 0
        }).
            Then(processNode).
            Then(storeNode).
        EndWhen().
        Build()

    // Run worker
    core.NewWorker().
        WithConfig(core.WorkerConfig{TaskQueue: "pipeline"}).
        WithFlow(flow).
        Run()
}
```

## See Also

- **[Flow](/docs/reference/core/flow/)** - Flow builder
- **[Node](/docs/reference/core/node/)** - Activity wrapper
- **[Magic Markers](/docs/guides/advanced-patterns/magic-markers/)** - Output and cursor references
- **[Pagination](/docs/guides/advanced-patterns/pagination/)** - Cursor-based pagination
