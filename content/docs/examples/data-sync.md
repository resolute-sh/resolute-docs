---
title: "Data Sync"
description: "Data Sync - Resolute documentation"
weight: 30
toc: true
---


# Data Sync Example

This example demonstrates incremental data synchronization between systems using Resolute's cursor management and pagination patterns.

## Overview

The sync workflow:
1. Tracks last sync position with cursors
2. Fetches only changed records since last run
3. Transforms data for the target system
4. Upserts to destination with conflict handling
5. Persists cursor state for next run

## Use Case

Sync Jira issues to an internal data warehouse, running hourly to capture updates.

## Complete Code

```go
package main

import (
    "context"
    "os"
    "time"

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

    // Build incremental sync flow
    flow := core.NewFlow("jira-warehouse-sync").
        TriggeredBy(core.Schedule("0 * * * *")). // Every hour

        // Fetch issues updated since last sync
        Then(jira.FetchIssues(jira.FetchInput{
            JQL:    "project = PLATFORM AND updated >= ${cursor}",
            Cursor: core.CursorFor("jira-sync"),
            Limit:  100,
        }).As("issues")).

        // Process if there are updates
        When(hasUpdates).
            // Transform to warehouse schema
            Then(transform.Map(transform.MapInput{
                Items:    core.Output("issues.Items"),
                Template: warehouseTemplate,
            }).As("transformed")).

            // Deduplicate by issue key
            Then(transform.Unique(transform.UniqueInput{
                Items: core.Output("transformed.Results"),
                Key:   "issue_key",
            }).As("unique")).

            // Upsert to warehouse in batches
            Then(upsertToWarehouseNode.As("upserted")).

            // Log sync stats
            Then(logSyncStatsNode).
        EndWhen().
        Build()

    // Run worker
    err := core.NewWorker().
        WithConfig(core.WorkerConfig{
            TaskQueue: "data-sync",
        }).
        WithFlow(flow).
        WithProviders(jiraProvider, transformProvider).
        Run()

    if err != nil {
        panic(err)
    }
}

func hasUpdates(s *core.FlowState) bool {
    issues := core.Get[jira.FetchOutput](s, "issues")
    return len(issues.Items) > 0
}

const warehouseTemplate = `{
    "issue_key": "{{.Key}}",
    "project": "{{.Project}}",
    "summary": "{{.Summary}}",
    "status": "{{.Status}}",
    "assignee": "{{.Assignee}}",
    "priority": "{{.Priority}}",
    "created_at": "{{.Created}}",
    "updated_at": "{{.Updated}}",
    "story_points": {{.StoryPoints}},
    "labels": {{json .Labels}},
    "sync_timestamp": "{{now}}"
}`

// Custom node for warehouse upsert
type UpsertInput struct {
    Records []map[string]any `json:"records"`
}

type UpsertOutput struct {
    Inserted int `json:"inserted"`
    Updated  int `json:"updated"`
    Failed   int `json:"failed"`
}

var upsertToWarehouseNode = core.NewNode("upsert-warehouse", upsertToWarehouse)

func upsertToWarehouse(ctx context.Context, input UpsertInput) (UpsertOutput, error) {
    // Implementation: batch upsert to your warehouse
    // (Postgres, BigQuery, Snowflake, etc.)
    return UpsertOutput{
        Inserted: len(input.Records),
    }, nil
}

var logSyncStatsNode = core.NewNode("log-stats", logSyncStats)

func logSyncStats(ctx context.Context, input UpsertOutput) (struct{}, error) {
    log.Printf("Sync complete: %d inserted, %d updated, %d failed",
        input.Inserted, input.Updated, input.Failed)
    return struct{}{}, nil
}
```

## Key Patterns

### 1. Cursor-Based Incremental Sync

```go
jira.FetchIssues(jira.FetchInput{
    JQL:    "project = PLATFORM AND updated >= ${cursor}",
    Cursor: core.CursorFor("jira-sync"),
})
```

The cursor automatically:
- Stores the last processed timestamp
- Substitutes `${cursor}` in queries
- Updates after successful processing

### 2. Cursor Storage

Cursors are persisted to Temporal's workflow state:

```go
// First run: cursor is empty, fetches all
// Subsequent runs: cursor = last updated timestamp
```

You can also use custom cursor storage:

```go
core.CursorFor("jira-sync").
    WithStorage(redisStorage).
    WithFormat("2006-01-02T15:04:05Z")
```

### 3. Pagination Handling

For APIs with pagination:

```go
flow := core.NewFlow("paginated-sync").
    TriggeredBy(core.Schedule("0 * * * *")).
    Then(fetchFirstPageNode.As("page")).
    While(hasMorePages).
        Then(processPageNode).
        Then(fetchNextPageNode.As("page")).
    EndWhile().
    Build()

func hasMorePages(s *core.FlowState) bool {
    page := core.Get[PageOutput](s, "page")
    return page.HasMore
}
```

## Multi-Source Sync

Sync from multiple sources in parallel:

```go
flow := core.NewFlow("multi-source-sync").
    TriggeredBy(core.Schedule("0 * * * *")).

    // Parallel fetch from multiple sources
    Parallel().
        Then(fetchJiraNode.As("jira")).
        Then(fetchConfluenceNode.As("confluence")).
        Then(fetchGitHubNode.As("github")).
    EndParallel().

    // Merge all sources
    Then(transform.Merge(transform.MergeInput{
        Collections: [][]any{
            core.Output("jira.Items"),
            core.Output("confluence.Items"),
            core.Output("github.Items"),
        },
    }).As("merged")).

    // Deduplicate across sources
    Then(transform.Unique(transform.UniqueInput{
        Items: core.Output("merged.Results"),
        Key:   "canonical_id",
    }).As("unique")).

    Then(upsertToWarehouseNode).
    Build()
```

## Error Handling and Recovery

### Partial Failure Handling

```go
Then(upsertToWarehouseNode.
    OnError(func(err error, state *core.FlowState) *core.Node {
        // Log failed records for retry
        return logFailedRecordsNode
    }).
    WithRetry(3, time.Minute))
```

### Dead Letter Queue

```go
flow := core.NewFlow("sync-with-dlq").
    TriggeredBy(core.Schedule("0 * * * *")).
    Then(fetchDataNode.As("data")).
    Then(processDataNode.
        OnError(sendToDLQNode)).
    Build()
```

### Cursor Rollback on Failure

```go
flow := core.NewFlow("safe-sync").
    TriggeredBy(core.Schedule("0 * * * *")).
    Then(fetchWithCursor.As("data")).
    Then(processData.
        OnError(core.RollbackCursor("jira-sync"))).
    Build()
```

## Monitoring and Observability

### Sync Metrics

```go
type SyncMetrics struct {
    SourceRecords  int       `json:"source_records"`
    Processed      int       `json:"processed"`
    Inserted       int       `json:"inserted"`
    Updated        int       `json:"updated"`
    Failed         int       `json:"failed"`
    Duration       float64   `json:"duration_seconds"`
    CursorPosition string    `json:"cursor_position"`
}

var emitMetricsNode = core.NewNode("emit-metrics", emitMetrics)

func emitMetrics(ctx context.Context, input SyncMetrics) (struct{}, error) {
    // Push to Prometheus, Datadog, etc.
    return struct{}{}, nil
}
```

### Adding Metrics to Flow

```go
flow := core.NewFlow("monitored-sync").
    TriggeredBy(core.Schedule("0 * * * *")).
    Then(recordStartTimeNode.As("start")).
    Then(fetchDataNode.As("data")).
    Then(processDataNode.As("processed")).
    Then(upsertDataNode.As("upserted")).
    Then(emitMetricsNode).
    Build()
```

## Full Reindex Flow

For occasional full reindex (e.g., schema changes):

```go
reindexFlow := core.NewFlow("full-reindex").
    TriggeredBy(core.Manual("reindex")).

    // Reset cursor to beginning
    Then(core.ResetCursor("jira-sync")).

    // Clear destination table
    Then(truncateWarehouseTableNode).

    // Fetch all with pagination
    Then(fetchAllIssuesNode.As("page")).
    While(hasMorePages).
        Then(transformPageNode).
        Then(upsertPageNode).
        Then(fetchNextPageNode.As("page")).
    EndWhile().

    // Rebuild indexes
    Then(rebuildIndexesNode).
    Build()
```

## Environment Variables

```bash
# Jira
export JIRA_BASE_URL="https://your-org.atlassian.net"
export JIRA_EMAIL="your-email@company.com"
export JIRA_API_TOKEN="your-api-token"

# Warehouse (example: Postgres)
export WAREHOUSE_HOST="localhost"
export WAREHOUSE_PORT="5432"
export WAREHOUSE_DB="analytics"
export WAREHOUSE_USER="sync_user"
export WAREHOUSE_PASSWORD="..."
```

## Best Practices

| Practice | Rationale |
|----------|-----------|
| Use cursors, not timestamps in code | Cursors survive restarts and handle edge cases |
| Batch upserts | Reduce database round trips |
| Deduplicate before insert | APIs may return duplicates across pages |
| Log sync stats | Enable debugging and monitoring |
| Test with small batches | Verify transforms before full sync |

## See Also

- **[Pagination](/docs/guides/advanced-patterns/pagination/)** - Handling paginated APIs
- **[Magic Markers](/docs/guides/advanced-patterns/magic-markers/)** - CursorFor and Output
- **[Error Handling](/docs/guides/building-flows/error-handling/)** - Recovery patterns
- **[Jira Provider](/docs/reference/providers/jira/)** - Full API reference
