---
title: "Pagination"
description: "Pagination - Resolute documentation"
weight: 20
toc: true
---


# Pagination

Pagination handles fetching data from paginated APIs that return results across multiple pages. Resolute provides built-in support for accumulating all pages into a single result.

## Why Pagination Support?

Many APIs limit response size and require pagination:
- Jira returns max 100 issues per request
- GitHub limits to 100 items per page
- Most REST APIs paginate large collections

Without pagination support, you'd need to write loops and handle cursors manually. Resolute's `Paginate` function handles this automatically.

## Basic Pattern

Use `core.Paginate` to create a node that fetches all pages:

```go
// Define how to fetch a single page
fetcher := func(ctx context.Context, cursor string) (core.PageResult[Issue], error) {
    startAt := 0
    if cursor != "" {
        startAt, _ = strconv.Atoi(cursor)
    }

    result, err := jiraClient.Search(ctx, jql, startAt, 100)
    if err != nil {
        return core.PageResult[Issue]{}, err
    }

    nextCursor := ""
    hasMore := startAt+len(result.Issues) < result.Total
    if hasMore {
        nextCursor = strconv.Itoa(startAt + len(result.Issues))
    }

    return core.PageResult[Issue]{
        Items:      result.Issues,
        NextCursor: nextCursor,
        HasMore:    hasMore,
    }, nil
}

// Create paginated node
fetchAllIssues := core.Paginate("fetch-all-issues", fetcher)
```

## PageResult Structure

The `PageFetcher` function returns a `PageResult`:

```go
type PageResult[T any] struct {
    Items      []T    // Results from this page
    NextCursor string // Cursor for next page (empty = no more pages)
    HasMore    bool   // Whether more pages exist
}
```

Pagination stops when:
- `HasMore` is `false`, OR
- `NextCursor` is empty, OR
- `MaxPages` limit is reached

## Configuration Options

### Limit Pages

```go
// Fetch at most 10 pages
fetchNode := core.Paginate("fetch-issues", fetcher,
    core.WithMaxPages(10),
)
```

### Set Page Size Hint

```go
// Hint for fetcher (not enforced by Resolute)
fetchNode := core.Paginate("fetch-issues", fetcher,
    core.WithPageSize(100),
)
```

### Cursor Persistence

Persist the final cursor for incremental fetching on next run:

```go
fetchNode := core.Paginate("fetch-issues", fetcher,
    core.WithCursorSource("jira-issues"),  // Saves cursor to FlowState
)
```

## Complete Example: Jira Issue Sync

```go
package main

import (
    "context"
    "strconv"
    "time"

    "github.com/resolute/resolute/core"
)

type Issue struct {
    ID          string
    Key         string
    Summary     string
    Description string
    UpdatedAt   time.Time
}

type JiraSearchResult struct {
    Issues     []Issue
    Total      int
    StartAt    int
    MaxResults int
}

func fetchIssuePage(client *JiraClient, jql string) core.PageFetcher[Issue] {
    return func(ctx context.Context, cursor string) (core.PageResult[Issue], error) {
        startAt := 0
        if cursor != "" {
            startAt, _ = strconv.Atoi(cursor)
        }

        result, err := client.Search(ctx, jql, startAt, 100)
        if err != nil {
            return core.PageResult[Issue]{}, err
        }

        nextCursor := ""
        hasMore := startAt+len(result.Issues) < result.Total
        if hasMore {
            nextCursor = strconv.Itoa(startAt + len(result.Issues))
        }

        return core.PageResult[Issue]{
            Items:      result.Issues,
            NextCursor: nextCursor,
            HasMore:    hasMore,
        }, nil
    }
}

func main() {
    jiraClient := NewJiraClient(os.Getenv("JIRA_URL"), os.Getenv("JIRA_TOKEN"))

    // Paginated fetch node
    fetchIssues := core.Paginate(
        "fetch-jira-issues",
        fetchIssuePage(jiraClient, "project = PLATFORM ORDER BY updated DESC"),
        core.WithMaxPages(50),  // Safety limit
    ).WithTimeout(30 * time.Minute)

    // Process all fetched issues
    processIssues := core.NewNode("process-issues", processIssuesFn, ProcessInput{}).
        WithInputFunc(func(s *core.FlowState) ProcessInput {
            result := core.Get[core.PaginateOutput[Issue]](s, "fetch-jira-issues")
            return ProcessInput{
                Issues:     result.Items,
                TotalCount: result.TotalItems,
                PageCount:  result.PageCount,
            }
        })

    flow := core.NewFlow("jira-sync").
        TriggeredBy(core.Schedule("0 */2 * * *")).  // Every 2 hours
        Then(fetchIssues).
        Then(processIssues).
        Build()

    core.NewWorker().
        WithConfig(core.WorkerConfig{TaskQueue: "jira-sync"}).
        WithFlow(flow).
        Run()
}
```

## PaginateOutput

The paginated node produces a `PaginateOutput`:

```go
type PaginateOutput[T any] struct {
    Items       []T    // All collected items across all pages
    FinalCursor string // Cursor after last page
    PageCount   int    // Number of pages fetched
    TotalItems  int    // Total count of items
}
```

Access in subsequent nodes:

```go
processNode := core.NewNode("process", processFn, ProcessInput{}).
    WithInputFunc(func(s *core.FlowState) ProcessInput {
        result := core.Get[core.PaginateOutput[Issue]](s, "fetch-issues")
        return ProcessInput{
            Items:  result.Items,       // All items
            Count:  result.TotalItems,  // Total count
            Pages:  result.PageCount,   // Pages fetched
        }
    })
```

## Pagination with Configuration

When the fetcher needs configuration (API credentials, filters):

```go
type FetchConfig struct {
    APIURL    string
    APIToken  string
    ProjectID string
    JQL       string
}

func fetchConfiguredPage(ctx context.Context, cfg FetchConfig, cursor string) (core.PageResult[Issue], error) {
    client := NewClient(cfg.APIURL, cfg.APIToken)

    startAt := 0
    if cursor != "" {
        startAt, _ = strconv.Atoi(cursor)
    }

    result, err := client.Search(ctx, cfg.JQL, startAt, 100)
    if err != nil {
        return core.PageResult[Issue]{}, err
    }

    // ... build PageResult
    return pageResult, nil
}

// Create node with configuration
fetchNode := core.PaginateWithConfig[Issue, FetchConfig](
    "fetch-issues",
    fetchConfiguredPage,
    core.WithMaxPages(100),
)

// Use in flow
flow := core.NewFlow("sync").
    TriggeredBy(core.Manual("api")).
    Then(fetchNode.WithInputFunc(func(s *core.FlowState) core.PaginateWithInputParams[FetchConfig] {
        return core.PaginateWithInputParams[FetchConfig]{
            Config: FetchConfig{
                APIURL:    os.Getenv("JIRA_URL"),
                APIToken:  os.Getenv("JIRA_TOKEN"),
                ProjectID: "PLATFORM",
                JQL:       "project = PLATFORM",
            },
            StartCursor: "",  // Start from beginning
        }
    })).
    Then(processNode).
    Build()
```

## Incremental Pagination

Resume from where the last run stopped using cursors:

```go
fetchNode := core.Paginate("fetch-issues", fetcher).
    WithInputFunc(func(s *core.FlowState) core.PaginateInput {
        // Get cursor from previous run
        cursor := s.GetCursor("jira-issues")
        return core.PaginateInput{
            StartCursor: cursor.Position,
        }
    })

// After pagination, update cursor
updateCursor := core.NewNode("update-cursor", updateCursorFn, UpdateCursorInput{}).
    WithInputFunc(func(s *core.FlowState) UpdateCursorInput {
        result := core.Get[core.PaginateOutput[Issue]](s, "fetch-issues")
        return UpdateCursorInput{
            Source:   "jira-issues",
            Position: result.FinalCursor,
        }
    })

flow := core.NewFlow("incremental-sync").
    Then(fetchNode).
    Then(processNode).
    Then(updateCursor).  // Save cursor for next run
    Build()
```

## Cursor Types

Different APIs use different cursor types:

### Offset-Based (Jira, many REST APIs)

```go
fetcher := func(ctx context.Context, cursor string) (core.PageResult[Item], error) {
    offset := 0
    if cursor != "" {
        offset, _ = strconv.Atoi(cursor)
    }

    result, _ := api.List(ctx, offset, 100)

    nextCursor := ""
    if offset+len(result.Items) < result.Total {
        nextCursor = strconv.Itoa(offset + len(result.Items))
    }

    return core.PageResult[Item]{
        Items:      result.Items,
        NextCursor: nextCursor,
        HasMore:    nextCursor != "",
    }, nil
}
```

### Token-Based (GitHub, many modern APIs)

```go
fetcher := func(ctx context.Context, cursor string) (core.PageResult[Item], error) {
    result, _ := api.List(ctx, cursor, 100)

    return core.PageResult[Item]{
        Items:      result.Items,
        NextCursor: result.NextPageToken,  // Opaque token from API
        HasMore:    result.HasNextPage,
    }, nil
}
```

### Timestamp-Based

```go
fetcher := func(ctx context.Context, cursor string) (core.PageResult[Item], error) {
    since := time.Time{}
    if cursor != "" {
        since, _ = time.Parse(time.RFC3339, cursor)
    }

    result, _ := api.ListSince(ctx, since, 100)

    nextCursor := ""
    if len(result.Items) > 0 {
        // Use last item's timestamp as cursor
        lastItem := result.Items[len(result.Items)-1]
        nextCursor = lastItem.UpdatedAt.Format(time.RFC3339)
    }

    return core.PageResult[Item]{
        Items:      result.Items,
        NextCursor: nextCursor,
        HasMore:    len(result.Items) == 100,  // Full page = probably more
    }, nil
}
```

## Error Handling

Pagination handles errors gracefully:

```go
fetcher := func(ctx context.Context, cursor string) (core.PageResult[Item], error) {
    result, err := api.List(ctx, cursor)
    if err != nil {
        // Error stops pagination and triggers retry policy
        return core.PageResult[Item]{}, fmt.Errorf("fetch page (cursor=%s): %w", cursor, err)
    }
    return result, nil
}

// Configure retries for the paginated node
fetchNode := core.Paginate("fetch", fetcher).
    WithRetry(core.RetryPolicy{
        InitialInterval:    time.Second,
        BackoffCoefficient: 2.0,
        MaximumAttempts:    5,
    })
```

If a page fetch fails:
1. Retry according to retry policy
2. If all retries fail, node fails (partial results lost)
3. On next flow run, pagination restarts (use cursor persistence to resume)

## Rate Limiting with Pagination

Combine pagination with rate limiting:

```go
fetchNode := core.Paginate("fetch-issues", fetcher).
    WithRateLimit(50, time.Minute)  // Max 50 pages per minute
```

For API rate limits (vs page rate limits):

```go
// Rate limit in the fetcher
limiter := rate.NewLimiter(rate.Every(time.Minute/100), 10)  // 100/min with burst of 10

fetcher := func(ctx context.Context, cursor string) (core.PageResult[Item], error) {
    if err := limiter.Wait(ctx); err != nil {
        return core.PageResult[Item]{}, err
    }
    return api.List(ctx, cursor)
}
```

## Memory Considerations

All items are collected in memory. For very large datasets:

### Option 1: Limit Pages

```go
fetchNode := core.Paginate("fetch", fetcher,
    core.WithMaxPages(100),  // Cap at 100 pages
)
```

### Option 2: Process in Batches

Instead of fetching everything, process page by page:

```go
// Custom activity that processes each page
func processAllPages(ctx context.Context, input ProcessInput) (ProcessOutput, error) {
    cursor := input.StartCursor
    var processedCount int

    for {
        page, err := api.List(ctx, cursor, 100)
        if err != nil {
            return ProcessOutput{}, err
        }

        // Process this page immediately (don't accumulate)
        for _, item := range page.Items {
            if err := processItem(ctx, item); err != nil {
                return ProcessOutput{}, err
            }
            processedCount++
        }

        if !page.HasMore {
            break
        }
        cursor = page.NextCursor
    }

    return ProcessOutput{Processed: processedCount}, nil
}
```

### Option 3: Use Data References

Store large datasets externally:

```go
func fetchAndStore(ctx context.Context, input FetchInput) (FetchOutput, error) {
    var allItems []Item
    cursor := ""

    for {
        page, _ := api.List(ctx, cursor, 100)
        allItems = append(allItems, page.Items...)
        if !page.HasMore {
            break
        }
        cursor = page.NextCursor
    }

    // Store to S3 instead of returning
    ref, err := storage.Store(ctx, allItems)
    if err != nil {
        return FetchOutput{}, err
    }

    return FetchOutput{
        Ref:   ref,    // Reference to S3 object
        Count: len(allItems),
    }, nil
}
```

## Best Practices

### 1. Set Reasonable Page Limits

```go
// Prevent runaway pagination
fetchNode := core.Paginate("fetch", fetcher,
    core.WithMaxPages(100),
)
```

### 2. Configure Appropriate Timeouts

Pagination can take a long time:

```go
fetchNode := core.Paginate("fetch", fetcher).
    WithTimeout(30 * time.Minute)  // Allow time for many pages
```

### 3. Log Progress for Debugging

```go
fetcher := func(ctx context.Context, cursor string) (core.PageResult[Item], error) {
    result, _ := api.List(ctx, cursor, 100)

    log.Printf("Fetched page: cursor=%s, items=%d, hasMore=%v",
        cursor, len(result.Items), result.HasMore)

    return result, nil
}
```

### 4. Handle Empty Pages

```go
fetcher := func(ctx context.Context, cursor string) (core.PageResult[Item], error) {
    result, _ := api.List(ctx, cursor, 100)

    // Empty page might not mean "done" for some APIs
    if len(result.Items) == 0 && result.HasMore {
        log.Printf("Warning: empty page with hasMore=true at cursor=%s", cursor)
    }

    return result, nil
}
```

## See Also

- **[Sequential Steps](/docs/guides/building-flows/sequential-steps/)** - Using pagination in flows
- **[Rate Limiting](/docs/guides/advanced-patterns/rate-limiting/)** - Combining with rate limits
- **[Data References](/docs/guides/advanced-patterns/data-references/)** - Handling large datasets
- **[FlowState](/docs/concepts/state/)** - Cursor persistence
