---
title: "Rate Limiting"
description: "Rate Limiting - Resolute documentation"
weight: 30
toc: true
---


# Rate Limiting

Rate limiting controls the pace of operations to respect external API limits and prevent overwhelming downstream systems. Resolute provides token bucket rate limiters at both node and shared levels.

## Why Rate Limiting?

External APIs enforce rate limits:
- Jira Cloud: ~100 requests/minute
- GitHub: 5000 requests/hour
- Slack: Varies by endpoint

Exceeding limits causes:
- 429 Too Many Requests errors
- Temporary bans
- Degraded service

Rate limiting ensures your workflows stay within bounds.

## Per-Node Rate Limiting

Apply rate limits to individual nodes:

```go
// Limit this node to 100 requests per minute
fetchNode := core.NewNode("fetch-issues", fetchIssues, input).
    WithRateLimit(100, time.Minute)
```

Each node instance gets its own rate limiter.

## Shared Rate Limiters

When multiple nodes call the same API, share a rate limiter:

```go
// Create shared limiter for Jira API
jiraLimiter := core.NewSharedRateLimiter("jira-api", 100, time.Minute)

// Both nodes share the limit
fetchIssues := core.NewNode("fetch-issues", fetchIssuesFn, input).
    WithSharedRateLimit(jiraLimiter)

searchIssues := core.NewNode("search-issues", searchIssuesFn, input).
    WithSharedRateLimit(jiraLimiter)

// Total across both nodes: 100/minute (not 200)
```

## Token Bucket Algorithm

Resolute uses a token bucket rate limiter:

```
Bucket Capacity: 100 tokens
Refill Rate: 100 tokens/minute

┌────────────────────────────┐
│ ████████████████████████   │  Tokens: 95/100
│ ████████████████████████   │
└────────────────────────────┘
        ↑               ↓
    Refill          Consume
  (continuous)    (on request)
```

**How it works:**
1. Bucket starts full (allows initial burst)
2. Each request consumes 1 token
3. Tokens refill continuously at configured rate
4. If bucket empty, request waits for next token

**Benefits:**
- Allows short bursts (bucket starts full)
- Smooths out traffic over time
- No thundering herd problems

## Configuration Options

### Basic Rate Limit

```go
// 100 requests per minute
node.WithRateLimit(100, time.Minute)

// 10 requests per second
node.WithRateLimit(10, time.Second)

// 1000 requests per hour
node.WithRateLimit(1000, time.Hour)
```

### Shared Across Nodes

```go
limiter := core.NewSharedRateLimiter("external-api", 50, time.Minute)

node1.WithSharedRateLimit(limiter)
node2.WithSharedRateLimit(limiter)
node3.WithSharedRateLimit(limiter)
```

## Complete Example

Multi-source data sync respecting API limits:

```go
package main

import (
    "context"
    "time"

    "github.com/resolute/resolute/core"
)

func main() {
    // Create shared rate limiters for each API
    jiraLimiter := core.NewSharedRateLimiter("jira", 100, time.Minute)
    slackLimiter := core.NewSharedRateLimiter("slack", 50, time.Minute)
    githubLimiter := core.NewSharedRateLimiter("github", 5000, time.Hour)

    // Jira nodes share jiraLimiter
    fetchJiraIssues := core.NewNode("fetch-jira-issues", fetchJiraIssuesFn, JiraInput{}).
        WithSharedRateLimit(jiraLimiter).
        WithTimeout(10 * time.Minute)

    updateJiraIssue := core.NewNode("update-jira-issue", updateJiraIssueFn, UpdateInput{}).
        WithSharedRateLimit(jiraLimiter).
        WithTimeout(1 * time.Minute)

    // Slack nodes share slackLimiter
    postSlackMessage := core.NewNode("post-slack", postSlackFn, SlackInput{}).
        WithSharedRateLimit(slackLimiter)

    fetchSlackChannels := core.NewNode("fetch-slack-channels", fetchSlackFn, SlackInput{}).
        WithSharedRateLimit(slackLimiter)

    // GitHub nodes share githubLimiter
    fetchPullRequests := core.NewNode("fetch-prs", fetchPRsFn, GitHubInput{}).
        WithSharedRateLimit(githubLimiter).
        WithTimeout(15 * time.Minute)

    // Build flow
    flow := core.NewFlow("multi-source-sync").
        TriggeredBy(core.Schedule("0 * * * *")).  // Hourly
        Then(fetchJiraIssues).
        ThenParallel("enrich",
            updateJiraIssue,      // Uses jiraLimiter
            postSlackMessage,     // Uses slackLimiter
            fetchPullRequests,    // Uses githubLimiter
        ).
        Then(storeResultsNode).
        Build()

    core.NewWorker().
        WithConfig(core.WorkerConfig{TaskQueue: "sync"}).
        WithFlow(flow).
        Run()
}
```

## Rate Limiting in Parallel Execution

Rate limiters coordinate across parallel nodes:

```go
// All three nodes share the same limiter
apiLimiter := core.NewSharedRateLimiter("api", 10, time.Second)

flow := core.NewFlow("parallel-api-calls").
    ThenParallel("calls",
        call1.WithSharedRateLimit(apiLimiter),
        call2.WithSharedRateLimit(apiLimiter),
        call3.WithSharedRateLimit(apiLimiter),
    ).
    Build()

// Even though nodes run in parallel, total rate <= 10/second
```

## Provider-Level Rate Limiting

Providers can apply default rate limits:

```go
// In provider implementation
func NewJiraProvider(cfg Config) *Provider {
    p := &Provider{
        BaseProvider: core.NewProvider("jira", "1.0.0"),
        config:       cfg,
    }

    // All activities from this provider share the limiter
    p.WithRateLimit(100, time.Minute)

    return p
}

// Or per-activity override
func (p *Provider) FetchIssues(input FetchInput) *core.Node[FetchInput, FetchOutput] {
    return core.NewNode("fetch-issues", p.fetchIssues, input).
        WithRateLimit(50, time.Minute)  // Stricter for this activity
}
```

## Handling Rate Limit Errors

When you hit external rate limits despite local limiting:

```go
func fetchWithBackoff(ctx context.Context, input FetchInput) (FetchOutput, error) {
    result, err := api.Fetch(ctx, input)
    if err != nil {
        // Check if rate limited
        if isRateLimitError(err) {
            // Return retriable error - will use retry policy
            return FetchOutput{}, fmt.Errorf("rate limited: %w", err)
        }
        return FetchOutput{}, err
    }
    return result, nil
}

func isRateLimitError(err error) bool {
    var httpErr *HTTPError
    if errors.As(err, &httpErr) {
        return httpErr.StatusCode == 429
    }
    return false
}

// Configure retry policy for rate limit scenarios
fetchNode := core.NewNode("fetch", fetchWithBackoff, input).
    WithRateLimit(100, time.Minute).
    WithRetry(core.RetryPolicy{
        InitialInterval:    30 * time.Second,  // Wait longer for rate limits
        BackoffCoefficient: 2.0,
        MaximumInterval:    5 * time.Minute,
        MaximumAttempts:    10,
    })
```

## Dynamic Rate Limiting

Adjust limits based on API responses:

```go
func createAdaptiveFetcher() func(context.Context, FetchInput) (FetchOutput, error) {
    var mu sync.Mutex
    currentLimit := 100.0

    return func(ctx context.Context, input FetchInput) (FetchOutput, error) {
        result, resp, err := api.FetchWithHeaders(ctx, input)
        if err != nil {
            return FetchOutput{}, err
        }

        // Read rate limit headers
        remaining := resp.Header.Get("X-RateLimit-Remaining")
        resetTime := resp.Header.Get("X-RateLimit-Reset")

        // Adjust local rate if approaching limit
        mu.Lock()
        if remainingInt, _ := strconv.Atoi(remaining); remainingInt < 10 {
            // Slow down
            currentLimit = currentLimit * 0.5
            log.Printf("Reducing rate to %.0f/min, %d remaining", currentLimit, remainingInt)
        }
        mu.Unlock()

        return result, nil
    }
}
```

## Rate Limiting with Pagination

When paginating, rate limit applies to each page fetch:

```go
fetchNode := core.Paginate("fetch-all", fetcher,
    core.WithMaxPages(100),
).WithRateLimit(10, time.Second)  // Max 10 pages/second

// With 100 items per page and 1000 total items:
// - 10 pages needed
// - At 10 pages/second, completes in ~1 second
// - But respects API rate limit
```

## Cleanup

Close shared rate limiters when done:

```go
limiter := core.NewSharedRateLimiter("api", 100, time.Minute)
defer limiter.Close()  // Unregisters from global registry

// Or in worker shutdown
worker.OnShutdown(func() {
    limiter.Close()
})
```

## Best Practices

### 1. Use Shared Limiters for Same API

```go
// Good: Single limiter for all Jira calls
jiraLimiter := core.NewSharedRateLimiter("jira", 100, time.Minute)
node1.WithSharedRateLimit(jiraLimiter)
node2.WithSharedRateLimit(jiraLimiter)

// Bad: Separate limiters (total could be 200/min)
node1.WithRateLimit(100, time.Minute)
node2.WithRateLimit(100, time.Minute)
```

### 2. Be Conservative

```go
// If API allows 100/min, use 80/min for safety margin
limiter := core.NewSharedRateLimiter("api", 80, time.Minute)
```

### 3. Consider Burst vs Sustained

Token bucket allows bursts. If API doesn't:

```go
// For APIs that don't allow bursts, use smaller time windows
// Instead of 100/minute, use ~1.6/second
limiter := core.NewSharedRateLimiter("strict-api", 2, time.Second)
```

### 4. Monitor Rate Limit Usage

```go
func fetchWithMonitoring(ctx context.Context, input FetchInput) (FetchOutput, error) {
    start := time.Now()
    result, err := api.Fetch(ctx, input)
    duration := time.Since(start)

    // Log for monitoring
    metrics.RecordAPICall("jira", duration, err)

    if err != nil && isRateLimitError(err) {
        metrics.IncrCounter("jira.rate_limited")
    }

    return result, err
}
```

### 5. Coordinate Across Workers

Rate limiters are per-worker. For multi-worker deployments:

```go
// Option A: Divide limit across workers
// If 3 workers and 100/min limit:
limiter := core.NewSharedRateLimiter("api", 33, time.Minute)  // Each worker gets ~33

// Option B: Use external rate limiter (Redis, etc.)
// Implement RateLimiter interface with distributed backend
```

## See Also

- **[Providers](/docs/concepts/providers/)** - Provider-level rate limiting
- **[Pagination](/docs/guides/advanced-patterns/pagination/)** - Combining with pagination
- **[Parallel Execution](/docs/guides/building-flows/parallel-execution/)** - Rate limiting parallel nodes
- **[Error Handling](/docs/guides/building-flows/error-handling/)** - Handling 429 errors
