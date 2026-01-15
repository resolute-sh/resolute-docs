---
title: "Transform Provider"
description: "Transform Provider - Resolute documentation"
weight: 60
toc: true
---


# Transform Provider

The Transform provider offers data transformation utilities for converting, mapping, filtering, and aggregating data within flows.

## Installation

```bash
go get github.com/resolute/resolute/providers/transform
```

## Configuration

The Transform provider requires no configuration as all operations are performed locally.

## Provider Constructor

### NewProvider

```go
func NewProvider() *TransformProvider
```

Creates a new Transform provider.

**Returns:** `*TransformProvider` implementing `core.Provider`

**Example:**
```go
provider := transform.NewProvider()
```

## Activities

### Map

Applies a transformation function to each element in a collection.

**Input:**
```go
type MapInput struct {
    Items      []any  `json:"items"`
    Expression string `json:"expression"` // JSONPath or expression
    Template   string `json:"template"`   // Go template for transformation
}
```

**Output:**
```go
type MapOutput struct {
    Results []any `json:"results"`
    Count   int   `json:"count"`
}
```

**Node Factory:**
```go
func Map(input MapInput) *core.Node[MapInput, MapOutput]
```

**Example:**
```go
mapNode := transform.Map(transform.MapInput{
    Items:    core.Output("issues.Items"),
    Template: `{"key": "{{.Key}}", "title": "{{.Summary}}"}`,
})
```

### Filter

Filters a collection based on a condition.

**Input:**
```go
type FilterInput struct {
    Items      []any  `json:"items"`
    Expression string `json:"expression"` // Filter expression
}
```

**Output:**
```go
type FilterOutput struct {
    Results []any `json:"results"`
    Count   int   `json:"count"`
    Removed int   `json:"removed"`
}
```

**Node Factory:**
```go
func Filter(input FilterInput) *core.Node[FilterInput, FilterOutput]
```

**Example:**
```go
filterNode := transform.Filter(transform.FilterInput{
    Items:      core.Output("issues.Items"),
    Expression: ".Status == 'Open' && .Priority == 'High'",
})
```

### Reduce

Reduces a collection to a single value.

**Input:**
```go
type ReduceInput struct {
    Items       []any  `json:"items"`
    Expression  string `json:"expression"`
    InitialValue any   `json:"initial_value"`
}
```

**Output:**
```go
type ReduceOutput struct {
    Result any `json:"result"`
}
```

**Node Factory:**
```go
func Reduce(input ReduceInput) *core.Node[ReduceInput, ReduceOutput]
```

**Example:**
```go
reduceNode := transform.Reduce(transform.ReduceInput{
    Items:        core.Output("orders.Items"),
    Expression:   "acc + item.Total",
    InitialValue: 0,
})
```

### GroupBy

Groups items by a key.

**Input:**
```go
type GroupByInput struct {
    Items []any  `json:"items"`
    Key   string `json:"key"` // Field to group by
}
```

**Output:**
```go
type GroupByOutput struct {
    Groups map[string][]any `json:"groups"`
    Keys   []string         `json:"keys"`
}
```

**Node Factory:**
```go
func GroupBy(input GroupByInput) *core.Node[GroupByInput, GroupByOutput]
```

**Example:**
```go
groupNode := transform.GroupBy(transform.GroupByInput{
    Items: core.Output("issues.Items"),
    Key:   "Status",
})
```

### Sort

Sorts a collection by a field.

**Input:**
```go
type SortInput struct {
    Items      []any  `json:"items"`
    Key        string `json:"key"`
    Descending bool   `json:"descending"`
}
```

**Output:**
```go
type SortOutput struct {
    Results []any `json:"results"`
}
```

**Node Factory:**
```go
func Sort(input SortInput) *core.Node[SortInput, SortOutput]
```

**Example:**
```go
sortNode := transform.Sort(transform.SortInput{
    Items:      core.Output("issues.Items"),
    Key:        "Priority",
    Descending: true,
})
```

### Flatten

Flattens nested arrays.

**Input:**
```go
type FlattenInput struct {
    Items []any `json:"items"`
    Depth int   `json:"depth"` // Flatten depth (default: 1, -1 for unlimited)
}
```

**Output:**
```go
type FlattenOutput struct {
    Results []any `json:"results"`
    Count   int   `json:"count"`
}
```

**Node Factory:**
```go
func Flatten(input FlattenInput) *core.Node[FlattenInput, FlattenOutput]
```

### Unique

Removes duplicate items.

**Input:**
```go
type UniqueInput struct {
    Items []any  `json:"items"`
    Key   string `json:"key"` // Optional: field to use for uniqueness
}
```

**Output:**
```go
type UniqueOutput struct {
    Results    []any `json:"results"`
    Duplicates int   `json:"duplicates"`
}
```

**Node Factory:**
```go
func Unique(input UniqueInput) *core.Node[UniqueInput, UniqueOutput]
```

### Chunk

Splits a collection into chunks.

**Input:**
```go
type ChunkInput struct {
    Items []any `json:"items"`
    Size  int   `json:"size"` // Chunk size
}
```

**Output:**
```go
type ChunkOutput struct {
    Chunks [][]any `json:"chunks"`
    Count  int     `json:"count"`
}
```

**Node Factory:**
```go
func Chunk(input ChunkInput) *core.Node[ChunkInput, ChunkOutput]
```

**Example:**
```go
chunkNode := transform.Chunk(transform.ChunkInput{
    Items: core.Output("documents.Items"),
    Size:  100,
})
```

### Merge

Merges multiple collections.

**Input:**
```go
type MergeInput struct {
    Collections [][]any `json:"collections"`
    Unique      bool    `json:"unique"`
}
```

**Output:**
```go
type MergeOutput struct {
    Results []any `json:"results"`
    Count   int   `json:"count"`
}
```

**Node Factory:**
```go
func Merge(input MergeInput) *core.Node[MergeInput, MergeOutput]
```

### Pick

Extracts specific fields from objects.

**Input:**
```go
type PickInput struct {
    Items  []any    `json:"items"`
    Fields []string `json:"fields"`
}
```

**Output:**
```go
type PickOutput struct {
    Results []map[string]any `json:"results"`
}
```

**Node Factory:**
```go
func Pick(input PickInput) *core.Node[PickInput, PickOutput]
```

**Example:**
```go
pickNode := transform.Pick(transform.PickInput{
    Items:  core.Output("issues.Items"),
    Fields: []string{"Key", "Summary", "Status"},
})
```

### Omit

Removes specific fields from objects.

**Input:**
```go
type OmitInput struct {
    Items  []any    `json:"items"`
    Fields []string `json:"fields"`
}
```

**Output:**
```go
type OmitOutput struct {
    Results []map[string]any `json:"results"`
}
```

**Node Factory:**
```go
func Omit(input OmitInput) *core.Node[OmitInput, OmitOutput]
```

### JSONPath

Extracts data using JSONPath expressions.

**Input:**
```go
type JSONPathInput struct {
    Data       any    `json:"data"`
    Expression string `json:"expression"`
}
```

**Output:**
```go
type JSONPathOutput struct {
    Results []any `json:"results"`
    Count   int   `json:"count"`
}
```

**Node Factory:**
```go
func JSONPath(input JSONPathInput) *core.Node[JSONPathInput, JSONPathOutput]
```

**Example:**
```go
jsonPathNode := transform.JSONPath(transform.JSONPathInput{
    Data:       core.Output("response"),
    Expression: "$.items[*].metadata.name",
})
```

### Template

Applies a Go template to data.

**Input:**
```go
type TemplateInput struct {
    Data     any    `json:"data"`
    Template string `json:"template"`
}
```

**Output:**
```go
type TemplateOutput struct {
    Result string `json:"result"`
}
```

**Node Factory:**
```go
func Template(input TemplateInput) *core.Node[TemplateInput, TemplateOutput]
```

**Example:**
```go
templateNode := transform.Template(transform.TemplateInput{
    Data: core.Output("issues"),
    Template: `
# Issue Report

Total Issues: {{len .Items}}

{{range .Items}}
- [{{.Key}}] {{.Summary}} ({{.Status}})
{{end}}
`,
})
```

### Aggregate

Performs aggregation operations on numeric data.

**Input:**
```go
type AggregateInput struct {
    Items     []any    `json:"items"`
    Field     string   `json:"field"`
    Operation string   `json:"operation"` // "sum", "avg", "min", "max", "count"
}
```

**Output:**
```go
type AggregateOutput struct {
    Result float64 `json:"result"`
}
```

**Node Factory:**
```go
func Aggregate(input AggregateInput) *core.Node[AggregateInput, AggregateOutput]
```

**Example:**
```go
avgNode := transform.Aggregate(transform.AggregateInput{
    Items:     core.Output("orders.Items"),
    Field:     "Total",
    Operation: "avg",
})
```

## Usage Patterns

### Data Processing Pipeline

```go
flow := core.NewFlow("data-pipeline").
    TriggeredBy(core.Schedule("0 * * * *")).
    Then(fetchDataNode.As("raw")).
    Then(transform.Filter(transform.FilterInput{
        Items:      core.Output("raw.Items"),
        Expression: ".Status == 'active'",
    }).As("filtered")).
    Then(transform.Map(transform.MapInput{
        Items:    core.Output("filtered.Results"),
        Template: `{"id": "{{.ID}}", "value": "{{.Value}}"}`,
    }).As("mapped")).
    Then(transform.GroupBy(transform.GroupByInput{
        Items: core.Output("mapped.Results"),
        Key:   "category",
    }).As("grouped")).
    Then(storeResultsNode).
    Build()
```

### Batch Processing with Chunking

```go
flow := core.NewFlow("batch-processor").
    TriggeredBy(core.Manual("api")).
    Then(fetchAllRecordsNode.As("records")).
    Then(transform.Chunk(transform.ChunkInput{
        Items: core.Output("records.Items"),
        Size:  100,
    }).As("batches")).
    ForEach(core.Output("batches.Chunks")).
        Then(processBatchNode).
    EndForEach().
    Build()
```

### Report Generation

```go
flow := core.NewFlow("report-generator").
    TriggeredBy(core.Schedule("0 9 * * 1")).
    Then(jira.FetchIssues(jira.FetchInput{
        Project: "PLATFORM",
    }).As("issues")).
    Then(transform.GroupBy(transform.GroupByInput{
        Items: core.Output("issues.Items"),
        Key:   "Status",
    }).As("by-status")).
    Then(transform.Aggregate(transform.AggregateInput{
        Items:     core.Output("issues.Items"),
        Field:     "StoryPoints",
        Operation: "sum",
    }).As("total-points")).
    Then(transform.Template(transform.TemplateInput{
        Data: map[string]any{
            "groups": core.Output("by-status.Groups"),
            "total":  core.Output("total-points.Result"),
        },
        Template: weeklyReportTemplate,
    }).As("report")).
    Then(sendReportNode).
    Build()
```

### Data Deduplication

```go
flow := core.NewFlow("deduplicate").
    TriggeredBy(core.Manual("api")).
    Then(fetchFromSourceANode.As("source-a")).
    Then(fetchFromSourceBNode.As("source-b")).
    Then(transform.Merge(transform.MergeInput{
        Collections: [][]any{
            core.Output("source-a.Items"),
            core.Output("source-b.Items"),
        },
    }).As("merged")).
    Then(transform.Unique(transform.UniqueInput{
        Items: core.Output("merged.Results"),
        Key:   "id",
    }).As("unique")).
    Then(storeUniqueItemsNode).
    Build()
```

### Field Projection

```go
flow := core.NewFlow("field-projection").
    TriggeredBy(core.Manual("api")).
    Then(fetchUserDataNode.As("users")).
    Then(transform.Pick(transform.PickInput{
        Items:  core.Output("users.Items"),
        Fields: []string{"id", "email", "name"},
    }).As("public")).
    Then(transform.Omit(transform.OmitInput{
        Items:  core.Output("users.Items"),
        Fields: []string{"password", "ssn", "creditCard"},
    }).As("safe")).
    Build()
```

## Complete Example

```go
package main

import (
    "github.com/resolute/resolute/core"
    "github.com/resolute/resolute/providers/jira"
    "github.com/resolute/resolute/providers/transform"
)

func main() {
    // Configure providers
    jiraProvider := jira.NewProvider(jira.JiraConfig{
        BaseURL:  os.Getenv("JIRA_BASE_URL"),
        Email:    os.Getenv("JIRA_EMAIL"),
        APIToken: os.Getenv("JIRA_API_TOKEN"),
    })

    transformProvider := transform.NewProvider()

    // Build analytics flow
    flow := core.NewFlow("sprint-analytics").
        TriggeredBy(core.Schedule("0 18 * * 5")).
        // Fetch sprint issues
        Then(jira.FetchIssues(jira.FetchInput{
            JQL: "project = PLATFORM AND sprint in openSprints()",
        }).As("issues")).
        // Group by assignee
        Then(transform.GroupBy(transform.GroupByInput{
            Items: core.Output("issues.Items"),
            Key:   "Assignee",
        }).As("by-assignee")).
        // Group by status
        Then(transform.GroupBy(transform.GroupByInput{
            Items: core.Output("issues.Items"),
            Key:   "Status",
        }).As("by-status")).
        // Calculate total story points
        Then(transform.Aggregate(transform.AggregateInput{
            Items:     core.Output("issues.Items"),
            Field:     "StoryPoints",
            Operation: "sum",
        }).As("total-points")).
        // Filter completed issues
        Then(transform.Filter(transform.FilterInput{
            Items:      core.Output("issues.Items"),
            Expression: ".Status == 'Done'",
        }).As("completed")).
        // Calculate completed points
        Then(transform.Aggregate(transform.AggregateInput{
            Items:     core.Output("completed.Results"),
            Field:     "StoryPoints",
            Operation: "sum",
        }).As("completed-points")).
        // Generate report
        Then(transform.Template(transform.TemplateInput{
            Data: map[string]any{
                "total":     core.Output("issues.Count"),
                "byStatus":  core.Output("by-status.Groups"),
                "byAssignee": core.Output("by-assignee.Groups"),
                "totalPoints": core.Output("total-points.Result"),
                "completedPoints": core.Output("completed-points.Result"),
            },
            Template: sprintReportTemplate,
        }).As("report")).
        // Send report
        Then(sendSlackReportNode).
        Build()

    // Run worker
    err := core.NewWorker().
        WithConfig(core.WorkerConfig{
            TaskQueue: "analytics",
        }).
        WithFlow(flow).
        WithProviders(jiraProvider, transformProvider).
        Run()

    if err != nil {
        panic(err)
    }
}

const sprintReportTemplate = `
# Sprint Report

## Summary
- Total Issues: {{.total}}
- Total Story Points: {{.totalPoints}}
- Completed Story Points: {{.completedPoints}}
- Velocity: {{printf "%.1f" (div .completedPoints .totalPoints | mul 100)}}%

## By Status
{{range $status, $issues := .byStatus}}
### {{$status}}: {{len $issues}} issues
{{end}}

## By Assignee
{{range $assignee, $issues := .byAssignee}}
- {{$assignee}}: {{len $issues}} issues
{{end}}
`
```

## See Also

- **[Magic Markers](/docs/guides/advanced-patterns/magic-markers/)** - Data references
- **[Pagination](/docs/guides/advanced-patterns/pagination/)** - Processing large datasets
- **[Parallel Execution](/docs/guides/building-flows/parallel-execution/)** - Concurrent processing
