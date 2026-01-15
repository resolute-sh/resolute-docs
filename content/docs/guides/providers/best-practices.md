---
title: "Provider Best Practices"
description: "Provider Best Practices - Resolute documentation"
weight: 30
toc: true
---


# Provider Best Practices

Design patterns and recommendations for building robust, maintainable providers.

## API Design

### Consistent Naming

Use a clear naming convention for activities:

```go
// Pattern: {provider}.{Action}{Resource}
provider.AddActivity("jira.FetchIssues", FetchIssuesActivity)
provider.AddActivity("jira.CreateIssue", CreateIssueActivity)
provider.AddActivity("jira.UpdateIssue", UpdateIssueActivity)
provider.AddActivity("jira.DeleteIssue", DeleteIssueActivity)

// Or: {provider}.{Resource}{Action}
provider.AddActivity("slack.ChannelCreate", CreateChannelActivity)
provider.AddActivity("slack.ChannelArchive", ArchiveChannelActivity)
provider.AddActivity("slack.MessagePost", PostMessageActivity)
```

### Clear Input/Output Types

Define explicit types for every activity:

```go
// Good: Explicit types with all fields documented
type FetchIssuesInput struct {
    JQL        string  // JQL query to filter issues
    MaxResults int     // Maximum issues to return (default: 50)
    StartAt    int     // Offset for pagination
    Fields     []string // Specific fields to include
}

type FetchIssuesOutput struct {
    Issues     []Issue  // Fetched issues
    Total      int      // Total matching issues
    StartAt    int      // Current offset
    MaxResults int      // Page size used
}

// Bad: Generic or unclear types
type FetchInput struct {
    Query string
    Opts  map[string]interface{}
}
```

### Sensible Defaults

Provide defaults for optional parameters:

```go
func FetchIssuesActivity(ctx context.Context, input FetchIssuesInput) (FetchIssuesOutput, error) {
    // Apply defaults
    maxResults := input.MaxResults
    if maxResults == 0 {
        maxResults = 50
    }

    fields := input.Fields
    if len(fields) == 0 {
        fields = []string{"summary", "status", "assignee", "created", "updated"}
    }

    // ...
}
```

## Error Handling

### Wrap All Errors

Provide context for debugging:

```go
func FetchIssuesActivity(ctx context.Context, input FetchIssuesInput) (FetchIssuesOutput, error) {
    issues, err := client.Search(ctx, input.JQL, input.StartAt, input.MaxResults)
    if err != nil {
        // Include context: what operation, what parameters
        return FetchIssuesOutput{}, fmt.Errorf(
            "search jira (jql=%q, startAt=%d): %w",
            input.JQL, input.StartAt, err,
        )
    }
    return FetchIssuesOutput{Issues: issues}, nil
}
```

### Distinguish Error Types

Help workflows make retry decisions:

```go
import "go.temporal.io/sdk/temporal"

func CreateIssueActivity(ctx context.Context, input CreateIssueInput) (CreateIssueOutput, error) {
    issue, err := client.CreateIssue(ctx, input)
    if err != nil {
        // Validation errors: don't retry
        if isValidationError(err) {
            return CreateIssueOutput{}, temporal.NewNonRetryableApplicationError(
                fmt.Sprintf("validation error: %v", err),
                "VALIDATION_ERROR",
                err,
            )
        }

        // Rate limit: retry with backoff
        if isRateLimitError(err) {
            return CreateIssueOutput{}, fmt.Errorf("rate limited: %w", err)
        }

        // Unknown errors: retry
        return CreateIssueOutput{}, fmt.Errorf("create issue: %w", err)
    }

    return CreateIssueOutput{IssueKey: issue.Key}, nil
}

func isValidationError(err error) bool {
    var httpErr *HTTPError
    if errors.As(err, &httpErr) {
        return httpErr.StatusCode == 400
    }
    return false
}

func isRateLimitError(err error) bool {
    var httpErr *HTTPError
    if errors.As(err, &httpErr) {
        return httpErr.StatusCode == 429
    }
    return false
}
```

### Handle Partial Failures

For batch operations, report what succeeded:

```go
type BatchUpdateInput struct {
    Issues []IssueUpdate
}

type BatchUpdateOutput struct {
    Succeeded []string  // Keys of successfully updated issues
    Failed    []FailedUpdate
}

type FailedUpdate struct {
    IssueKey string
    Error    string
}

func BatchUpdateActivity(ctx context.Context, input BatchUpdateInput) (BatchUpdateOutput, error) {
    output := BatchUpdateOutput{
        Succeeded: make([]string, 0),
        Failed:    make([]FailedUpdate, 0),
    }

    for _, update := range input.Issues {
        err := client.UpdateIssue(ctx, update)
        if err != nil {
            output.Failed = append(output.Failed, FailedUpdate{
                IssueKey: update.Key,
                Error:    err.Error(),
            })
        } else {
            output.Succeeded = append(output.Succeeded, update.Key)
        }
    }

    // Return success with partial results
    // Let the workflow decide how to handle failures
    return output, nil
}
```

## Rate Limiting

### Provider-Level Limits

Set rate limits at the provider level:

```go
func NewProvider(cfg Config) *Provider {
    p := &Provider{
        BaseProvider: core.NewProvider("resolute-jira", "1.0.0"),
        client:       NewClient(cfg),
    }

    // Jira Cloud: 100 requests/minute
    // Use 80% of limit for safety margin
    p.WithRateLimit(80, time.Minute)

    // Add activities...
    return p
}
```

### Respect API Headers

Adapt to rate limit headers:

```go
func (c *Client) do(ctx context.Context, req *http.Request) (*http.Response, error) {
    resp, err := c.httpClient.Do(req)
    if err != nil {
        return nil, err
    }

    // Check rate limit headers
    if remaining := resp.Header.Get("X-RateLimit-Remaining"); remaining != "" {
        if n, _ := strconv.Atoi(remaining); n < 10 {
            log.Printf("Rate limit warning: %d requests remaining", n)
        }
    }

    // Handle rate limit response
    if resp.StatusCode == 429 {
        retryAfter := resp.Header.Get("Retry-After")
        return nil, &RateLimitError{
            RetryAfter: retryAfter,
        }
    }

    return resp, nil
}
```

## Configuration

### Validate Early

Validate configuration at construction:

```go
type Config struct {
    BaseURL  string
    APIToken string
    Timeout  time.Duration
}

func (c Config) Validate() error {
    if c.BaseURL == "" {
        return fmt.Errorf("BaseURL is required")
    }
    if c.APIToken == "" {
        return fmt.Errorf("APIToken is required")
    }
    if c.Timeout <= 0 {
        return fmt.Errorf("Timeout must be positive")
    }
    return nil
}

func NewProvider(cfg Config) (*Provider, error) {
    if err := cfg.Validate(); err != nil {
        return nil, fmt.Errorf("invalid config: %w", err)
    }

    return &Provider{
        BaseProvider: core.NewProvider("resolute-jira", "1.0.0"),
        client:       NewClient(cfg),
    }, nil
}
```

### Provide ConfigFromEnv

Make environment-based configuration easy:

```go
func ConfigFromEnv() (Config, error) {
    cfg := Config{
        BaseURL:  os.Getenv("JIRA_BASE_URL"),
        APIToken: os.Getenv("JIRA_API_TOKEN"),
        Timeout:  30 * time.Second,
    }

    if t := os.Getenv("JIRA_TIMEOUT"); t != "" {
        d, err := time.ParseDuration(t)
        if err != nil {
            return Config{}, fmt.Errorf("invalid JIRA_TIMEOUT: %w", err)
        }
        cfg.Timeout = d
    }

    if err := cfg.Validate(); err != nil {
        return Config{}, err
    }

    return cfg, nil
}
```

## Testing

### Make Activities Testable

Inject dependencies for testing:

```go
type Provider struct {
    *core.BaseProvider
    client JiraClient  // Interface, not concrete type
}

type JiraClient interface {
    Search(ctx context.Context, jql string, startAt, max int) ([]Issue, error)
    CreateIssue(ctx context.Context, input CreateIssueInput) (*Issue, error)
}

func (p *Provider) fetchIssues(ctx context.Context, input FetchIssuesInput) (FetchIssuesOutput, error) {
    issues, err := p.client.Search(ctx, input.JQL, input.StartAt, input.MaxResults)
    // ...
}
```

### Unit Test Activities

```go
func TestFetchIssuesActivity(t *testing.T) {
    tests := []struct {
        name       string
        input      FetchIssuesInput
        mockIssues []Issue
        mockErr    error
        want       FetchIssuesOutput
        wantErr    bool
    }{
        {
            name: "returns issues on success",
            input: FetchIssuesInput{
                JQL:        "project = TEST",
                MaxResults: 10,
            },
            mockIssues: []Issue{
                {Key: "TEST-1", Summary: "Issue 1"},
                {Key: "TEST-2", Summary: "Issue 2"},
            },
            want: FetchIssuesOutput{
                Issues: []Issue{
                    {Key: "TEST-1", Summary: "Issue 1"},
                    {Key: "TEST-2", Summary: "Issue 2"},
                },
                Total: 2,
            },
        },
        {
            name: "returns error on failure",
            input: FetchIssuesInput{
                JQL: "invalid jql",
            },
            mockErr: errors.New("invalid JQL"),
            wantErr: true,
        },
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            // given
            mockClient := &MockJiraClient{
                SearchResult: tt.mockIssues,
                SearchErr:    tt.mockErr,
            }
            provider := &Provider{client: mockClient}

            // when
            got, err := provider.fetchIssues(context.Background(), tt.input)

            // then
            if tt.wantErr {
                require.Error(t, err)
                return
            }
            require.NoError(t, err)
            assert.Equal(t, tt.want.Issues, got.Issues)
        })
    }
}
```

## Idempotency

### Design for Retries

Activities may run multiple times. Design for idempotency:

```go
func CreateIssueActivity(ctx context.Context, input CreateIssueInput) (CreateIssueOutput, error) {
    // Check if issue already exists (idempotency key in custom field)
    if input.IdempotencyKey != "" {
        existing, err := client.FindByIdempotencyKey(ctx, input.IdempotencyKey)
        if err == nil && existing != nil {
            // Already created, return existing
            return CreateIssueOutput{
                IssueKey: existing.Key,
                Created:  false,
            }, nil
        }
    }

    // Create new issue
    issue, err := client.CreateIssue(ctx, input)
    if err != nil {
        return CreateIssueOutput{}, err
    }

    return CreateIssueOutput{
        IssueKey: issue.Key,
        Created:  true,
    }, nil
}
```

### Use External IDs

Leverage external system IDs for deduplication:

```go
type SyncIssueInput struct {
    ExternalID string  // ID from source system
    // ...
}

func SyncIssueActivity(ctx context.Context, input SyncIssueInput) (SyncIssueOutput, error) {
    // Check if already synced
    existing, err := client.FindByExternalID(ctx, input.ExternalID)
    if err == nil && existing != nil {
        // Update existing
        return updateIssue(ctx, existing, input)
    }

    // Create new
    return createIssue(ctx, input)
}
```

## Documentation

### Document Each Activity

```go
// AddActivity adds an activity with description for discovery
provider.AddActivityWithDescription(
    "jira.FetchIssues",
    "Fetches issues from Jira using JQL. Supports pagination.",
    FetchIssuesActivity,
)

provider.AddActivityWithDescription(
    "jira.CreateIssue",
    "Creates a new issue in Jira. Returns the created issue key.",
    CreateIssueActivity,
)
```

### Document Input/Output Types

```go
// FetchIssuesInput configures the Jira issue search.
//
// Example:
//
//	input := FetchIssuesInput{
//	    JQL:        "project = PLATFORM AND status = Open",
//	    MaxResults: 100,
//	    Fields:     []string{"summary", "status", "assignee"},
//	}
type FetchIssuesInput struct {
    // JQL is the Jira Query Language query to filter issues.
    // See: https://support.atlassian.com/jira-service-management-cloud/docs/use-advanced-search-with-jql/
    JQL string

    // MaxResults limits the number of issues returned.
    // Default: 50. Maximum: 1000.
    MaxResults int

    // StartAt is the index of the first issue to return (0-based).
    // Used for pagination.
    StartAt int

    // Fields specifies which issue fields to include.
    // Empty means use default fields.
    Fields []string
}
```

## Logging

### Structured Logging

Use structured logging for observability:

```go
import "log/slog"

func (p *Provider) fetchIssues(ctx context.Context, input FetchIssuesInput) (FetchIssuesOutput, error) {
    logger := slog.With(
        "provider", p.Name(),
        "activity", "FetchIssues",
        "jql", input.JQL,
    )

    logger.Info("fetching issues")

    issues, err := p.client.Search(ctx, input.JQL, input.StartAt, input.MaxResults)
    if err != nil {
        logger.Error("fetch failed", "error", err)
        return FetchIssuesOutput{}, fmt.Errorf("search: %w", err)
    }

    logger.Info("fetch complete", "count", len(issues))

    return FetchIssuesOutput{Issues: issues, Total: len(issues)}, nil
}
```

### Avoid Logging Sensitive Data

```go
func (p *Provider) createIssue(ctx context.Context, input CreateIssueInput) (CreateIssueOutput, error) {
    // Good: Log project and type, not content
    slog.Info("creating issue",
        "project", input.Project,
        "issueType", input.Type,
    )

    // Bad: Don't log potentially sensitive data
    // slog.Info("creating issue", "input", input)
}
```

## Checklist

Before publishing a provider:

- [ ] All activities have clear names with provider prefix
- [ ] Input/output types are explicit (no `map[string]interface{}`)
- [ ] Errors are wrapped with context
- [ ] Non-retryable errors are marked appropriately
- [ ] Rate limits are configured
- [ ] Configuration is validated at construction
- [ ] `ConfigFromEnv()` is provided
- [ ] Activities are designed for idempotency
- [ ] Unit tests cover success and error cases
- [ ] Activities and types are documented

## See Also

- **[Creating Providers](/docs/guides/providers/creating-providers/)** - Build from scratch
- **[Registering Activities](/docs/guides/providers/registering-activities/)** - Worker registration
- **[Rate Limiting](/docs/guides/advanced-patterns/rate-limiting/)** - Detailed rate limiting
- **[Error Handling](/docs/guides/building-flows/error-handling/)** - Flow-level error handling
