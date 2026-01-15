---
title: "Magic Markers"
description: "Magic Markers - Resolute documentation"
weight: 50
toc: true
---


# Magic Markers

Magic markers are placeholder values that the framework resolves at execution time. They enable declarative data wiring between nodes without explicit `WithInputFunc` callbacks.

## Why Magic Markers?

Traditional approach requires explicit callbacks:

```go
// Verbose: Manual wiring with WithInputFunc
enrichNode := core.NewNode("enrich", enrichFn, EnrichInput{}).
    WithInputFunc(func(s *core.FlowState) EnrichInput {
        fetchResult := core.Get[FetchOutput](s, "fetch")
        cursor := s.GetCursor("jira")
        return EnrichInput{
            DocumentsRef: fetchResult.Ref,
            Since:        cursor.TimeOr(time.Time{}),
        }
    })
```

Magic markers make this declarative:

```go
// Concise: Declarative with markers
enrichNode := core.NewNode("enrich", enrichFn, EnrichInput{
    DocumentsRef: core.OutputRef("fetch"),
    Since:        core.CursorFor("jira"),
})
```

The framework automatically resolves markers before activity execution.

## Available Markers

| Marker | Returns | Resolves To |
|--------|---------|-------------|
| `CursorFor(source)` | `*time.Time` | Persisted cursor timestamp |
| `CursorString(source)` | `string` | Persisted cursor position |
| `Output(path)` | `string` | Previous node's output field |
| `OutputRef(nodeKey)` | `DataRef` | Previous node's DataRef |

## CursorFor

Returns a `*time.Time` marker that resolves to a persisted cursor timestamp.

### Basic Usage

```go
type FetchInput struct {
    Project string
    Since   *time.Time  // Will receive cursor value
}

fetchNode := core.NewNode("fetch", fetchIssues, FetchInput{
    Project: "PLATFORM",
    Since:   core.CursorFor("jira"),  // Resolves to persisted cursor
})
```

### How It Works

```
At Definition Time                At Execution Time
─────────────────────            ─────────────────────
FetchInput{                      FetchInput{
    Since: CursorFor("jira")         Since: 2024-01-15T10:30:00Z
}                                }
     │                                    ▲
     │                                    │
     └─── marker stored ──────────────────┘
          in registry                     │
                                    resolve() reads
                                    from FlowState
```

### Nil Handling

If no cursor exists, the field becomes `nil`:

```go
func fetchIssues(ctx context.Context, input FetchInput) (FetchOutput, error) {
    if input.Since == nil {
        // First run: fetch all issues
        return fetchAll(ctx, input.Project)
    }
    // Incremental: fetch since cursor
    return fetchSince(ctx, input.Project, *input.Since)
}
```

## CursorString

Returns a `string` marker for cursor position (for APIs that use string cursors).

### Basic Usage

```go
type PaginateInput struct {
    Query      string
    StartAfter string  // String cursor field
}

paginateNode := core.NewNode("paginate", paginate, PaginateInput{
    Query:      "status = open",
    StartAfter: core.CursorString("pagination"),
})
```

### When to Use

| Use `CursorFor` | Use `CursorString` |
|-----------------|---------------------|
| Field is `*time.Time` | Field is `string` |
| Timestamp-based cursors | Token/offset cursors |
| "Fetch since X" patterns | "Start after Y" patterns |

## Output

Returns a `string` marker that resolves to a previous node's output field.

### Basic Usage

```go
type CreateSubnetInput struct {
    VPCName string
    CIDR    string
}

createSubnet := core.NewNode("create-subnet", createSubnetFn, CreateSubnetInput{
    VPCName: core.Output("vpc.Name"),  // Resolves to VPCOutput.Name
    CIDR:    "10.0.1.0/24",
})
```

### Path Syntax

```go
// Reference entire output (calls String() or fmt.Sprintf)
core.Output("nodename")

// Reference specific field
core.Output("nodename.FieldName")

// Field names are case-insensitive
core.Output("vpc.name")   // Matches vpc.Name
core.Output("vpc.Name")   // Also works
```

### Complete Example

```go
type VPCOutput struct {
    ID     string
    Name   string
    Region string
}

type SubnetOutput struct {
    ID    string
    VPC   string
    CIDR  string
}

createVPC := core.NewNode("vpc", createVPCFn, VPCInput{
    Name:   "production",
    Region: "us-west-2",
}).As("vpc")

createSubnet := core.NewNode("subnet", createSubnetFn, SubnetInput{
    VPCName: core.Output("vpc.Name"),    // "production"
    VPCID:   core.Output("vpc.ID"),      // "vpc-abc123"
    Region:  core.Output("vpc.Region"),  // "us-west-2"
    CIDR:    "10.0.1.0/24",
})

flow := core.NewFlow("infra").
    Then(createVPC).
    Then(createSubnet).
    Build()
```

## OutputRef

Returns a `DataRef` marker that resolves to a previous node's DataRef output.

### Basic Usage

```go
type EnrichInput struct {
    DocumentsRef core.DataRef  // Reference to large dataset
    Model        string
}

enrichNode := core.NewNode("enrich", enrichFn, EnrichInput{
    DocumentsRef: core.OutputRef("fetch"),  // Resolves to FetchOutput.Ref
    Model:        "text-embedding-3-small",
})
```

### How It Works

OutputRef looks for a `Ref` field in the referenced node's output:

```go
type FetchOutput struct {
    Ref   core.DataRef  // OutputRef extracts this field
    Count int
    Size  int64
}

// OutputRef("fetch") resolves to FetchOutput.Ref
```

If the output is directly a `DataRef`, it uses that value.

### Complete Pipeline

```go
// Fetch stores large data externally, returns reference
fetchNode := core.NewNode("fetch", fetchDocuments, FetchInput{
    Query: "project = PLATFORM",
}).As("docs")

// Enrich uses OutputRef to receive the reference
enrichNode := core.NewNode("enrich", enrichDocuments, EnrichInput{
    DocumentsRef: core.OutputRef("docs"),
    Model:        "text-embedding-3-small",
})

// Store also uses OutputRef
storeNode := core.NewNode("store", storeEmbeddings, StoreInput{
    EmbeddingsRef: core.OutputRef("enrich"),
    Collection:    "documents",
})

flow := core.NewFlow("embedding-pipeline").
    Then(fetchNode).
    Then(enrichNode).
    Then(storeNode).
    Build()
```

## Resolution Mechanism

The framework resolves markers automatically before activity execution:

```
┌─────────────────┐
│  Node Input     │
│  with Markers   │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│   resolve()     │
│                 │
│  1. Traverse    │
│     struct      │
│                 │
│  2. Find        │
│     markers     │
│                 │
│  3. Replace     │
│     with values │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Node Input     │
│  with Values    │
└─────────────────┘
```

### Resolution Order

1. **CursorFor/CursorString**: Read from FlowState cursor store
2. **Output**: Read from FlowState results, access field by path
3. **OutputRef**: Read from FlowState results, extract `Ref` field

### Supported Field Types

Resolution works on:
- Direct fields (`*time.Time`, `string`, `DataRef`)
- Nested structs
- Slices
- Map values (string values only)

```go
type ComplexInput struct {
    // Direct fields
    Since       *time.Time
    Name        string
    DataRef     core.DataRef

    // Nested struct
    Config      struct {
        Source  string
    }

    // Slice
    Tags        []string

    // Map (values resolved, not keys)
    Metadata    map[string]string
}
```

## Markers vs WithInputFunc

Choose based on complexity:

### Use Markers When

- Simple 1:1 field mapping
- No transformation needed
- Cleaner, more declarative code

```go
// Good: Direct mapping
enrichNode := core.NewNode("enrich", enrichFn, EnrichInput{
    DataRef: core.OutputRef("fetch"),
    Since:   core.CursorFor("source"),
})
```

### Use WithInputFunc When

- Transformation required
- Conditional logic needed
- Multiple sources combined
- Computed values

```go
// Good: Complex transformation
enrichNode := core.NewNode("enrich", enrichFn, EnrichInput{}).
    WithInputFunc(func(s *core.FlowState) EnrichInput {
        fetch := core.Get[FetchOutput](s, "fetch")
        config := core.Get[ConfigOutput](s, "config")

        return EnrichInput{
            DataRef:   fetch.Ref,
            BatchSize: calculateBatchSize(fetch.Count, config.MaxMemory),
            Tags:      mergeTags(fetch.Tags, config.DefaultTags),
        }
    })
```

### Combine Both

Markers and `WithInputFunc` can coexist:

```go
// Markers set defaults, WithInputFunc can override
enrichNode := core.NewNode("enrich", enrichFn, EnrichInput{
    Since: core.CursorFor("source"),  // Default from cursor
}).WithInputFunc(func(s *core.FlowState) EnrichInput {
    // Override if needed
    input := EnrichInput{
        Since: core.CursorFor("source"),
    }

    if config := core.GetOr(s, "config", ConfigOutput{}); config.ForceFullSync {
        input.Since = nil  // Override: ignore cursor
    }

    return input
})
```

## Error Handling

### Missing Node Output

```go
// If "fetch" node didn't run or failed
enrichNode := core.NewNode("enrich", enrichFn, EnrichInput{
    DataRef: core.OutputRef("fetch"),  // Error: no result for node "fetch"
})
```

Resolution fails if referenced node has no output.

### Missing Ref Field

```go
type BadOutput struct {
    Data  []Item  // No Ref field!
    Count int
}

// OutputRef fails: struct BadOutput has no Ref field
```

### Invalid Field Path

```go
// Output path references non-existent field
CreateSubnetInput{
    VPCName: core.Output("vpc.NonExistent"),  // Error: field not found
}
```

## Best Practices

### 1. Use Consistent Node Keys

```go
// Good: Clear, consistent naming
fetchNode := core.NewNode("fetch-docs", fetchFn, input).As("docs")
enrichNode := core.NewNode("enrich", enrichFn, EnrichInput{
    DocsRef: core.OutputRef("docs"),
})

// Bad: Inconsistent or unclear
fetchNode := core.NewNode("step1", fetchFn, input).As("x")
enrichNode := core.NewNode("step2", enrichFn, EnrichInput{
    DocsRef: core.OutputRef("x"),  // What is "x"?
})
```

### 2. Document Marker Dependencies

```go
// EnrichInput requires:
// - "fetch" node to produce FetchOutput with Ref field
// - "jira" cursor to be persisted
type EnrichInput struct {
    DocumentsRef core.DataRef   `marker:"OutputRef(fetch)"`
    Since        *time.Time     `marker:"CursorFor(jira)"`
}
```

### 3. Prefer Explicit Field Paths

```go
// Good: Explicit field path
VPCName: core.Output("vpc.Name")

// Less clear: Relies on String() implementation
VPCName: core.Output("vpc")
```

### 4. Handle Missing Cursors Gracefully

```go
func fetchIssues(ctx context.Context, input FetchInput) (FetchOutput, error) {
    // CursorFor returns nil if no cursor exists
    if input.Since == nil {
        log.Info("No cursor found, fetching all")
        return fetchAll(ctx, input)
    }

    log.Info("Fetching since cursor", "since", input.Since)
    return fetchIncremental(ctx, input)
}
```

## See Also

- **[FlowState](/docs/concepts/state/)** - Cursor and result storage
- **[Data References](/docs/guides/advanced-patterns/data-references/)** - Using DataRef with OutputRef
- **[Pagination](/docs/guides/advanced-patterns/pagination/)** - Cursor patterns for pagination
- **[Sequential Steps](/docs/guides/building-flows/sequential-steps/)** - Data passing between nodes
