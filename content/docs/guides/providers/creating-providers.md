---
title: "Creating Providers"
description: "Creating Providers - Resolute documentation"
weight: 10
toc: true
---


# Creating Providers

Providers are collections of related activities that integrate with external systems. This guide walks through creating a provider from scratch.

## Provider Structure

A provider typically consists of:
- Provider definition (implements `core.Provider`)
- Activity functions
- Input/output types
- Configuration handling

```
my-provider/
├── provider.go      # Provider definition and registration
├── activities.go    # Activity implementations
├── types.go         # Input/output types
├── client.go        # External API client
└── config.go        # Configuration
```

## Basic Provider

### Using BaseProvider

The simplest way to create a provider is with `core.NewProvider`:

```go
package slack

import (
    "github.com/resolute/resolute/core"
    "go.temporal.io/sdk/worker"
)

const (
    ProviderName    = "resolute-slack"
    ProviderVersion = "1.0.0"
)

// Provider returns the Slack provider for registration.
func Provider() core.Provider {
    return core.NewProvider(ProviderName, ProviderVersion).
        AddActivity("slack.PostMessage", PostMessageActivity).
        AddActivity("slack.GetChannel", GetChannelActivity).
        AddActivity("slack.ListChannels", ListChannelsActivity)
}

// RegisterActivities registers all Slack activities with a Temporal worker.
func RegisterActivities(w worker.Worker) {
    core.RegisterProviderActivities(w, Provider())
}
```

### Activity Functions

Activities follow a consistent signature:

```go
func ActivityName(ctx context.Context, input InputType) (OutputType, error)
```

Example activities:

```go
package slack

import (
    "context"
    "fmt"
)

type PostMessageInput struct {
    Channel string
    Text    string
    Blocks  []Block
}

type PostMessageOutput struct {
    Timestamp string
    Channel   string
}

func PostMessageActivity(ctx context.Context, input PostMessageInput) (PostMessageOutput, error) {
    client := getClient(ctx)

    resp, err := client.PostMessage(ctx, input.Channel, input.Text, input.Blocks)
    if err != nil {
        return PostMessageOutput{}, fmt.Errorf("post message: %w", err)
    }

    return PostMessageOutput{
        Timestamp: resp.Timestamp,
        Channel:   resp.Channel,
    }, nil
}

type GetChannelInput struct {
    ChannelID string
}

type GetChannelOutput struct {
    ID       string
    Name     string
    Topic    string
    Purpose  string
    IsPublic bool
}

func GetChannelActivity(ctx context.Context, input GetChannelInput) (GetChannelOutput, error) {
    client := getClient(ctx)

    channel, err := client.GetChannel(ctx, input.ChannelID)
    if err != nil {
        return GetChannelOutput{}, fmt.Errorf("get channel: %w", err)
    }

    return GetChannelOutput{
        ID:       channel.ID,
        Name:     channel.Name,
        Topic:    channel.Topic.Value,
        Purpose:  channel.Purpose.Value,
        IsPublic: channel.IsChannel,
    }, nil
}
```

## Provider with Configuration

Most providers need configuration (API keys, URLs, etc.):

```go
package jira

import (
    "context"
    "net/http"
    "time"

    "github.com/resolute/resolute/core"
    "go.temporal.io/sdk/worker"
)

type Config struct {
    BaseURL     string
    Email       string
    APIToken    string
    Timeout     time.Duration
}

type Provider struct {
    *core.BaseProvider
    config Config
    client *Client
}

func NewProvider(cfg Config) *Provider {
    p := &Provider{
        BaseProvider: core.NewProvider("resolute-jira", "1.0.0"),
        config:       cfg,
        client:       NewClient(cfg),
    }

    p.AddActivity("jira.FetchIssues", p.fetchIssues).
      AddActivity("jira.FetchIssue", p.fetchIssue).
      AddActivity("jira.CreateIssue", p.createIssue).
      AddActivity("jira.UpdateIssue", p.updateIssue).
      AddActivity("jira.SearchJQL", p.searchJQL)

    return p
}

// Activities are methods on the provider struct
func (p *Provider) fetchIssues(ctx context.Context, input FetchIssuesInput) (FetchIssuesOutput, error) {
    issues, err := p.client.Search(ctx, input.JQL, input.StartAt, input.MaxResults)
    if err != nil {
        return FetchIssuesOutput{}, fmt.Errorf("fetch issues: %w", err)
    }

    return FetchIssuesOutput{
        Issues:     issues,
        Total:      len(issues),
        StartAt:    input.StartAt,
        MaxResults: input.MaxResults,
    }, nil
}

func (p *Provider) RegisterActivities(w worker.Worker) {
    core.RegisterProviderActivities(w, p)
}
```

### Configuration from Environment

Load configuration from environment variables:

```go
package jira

import (
    "fmt"
    "os"
    "time"
)

func ConfigFromEnv() (Config, error) {
    baseURL := os.Getenv("JIRA_BASE_URL")
    if baseURL == "" {
        return Config{}, fmt.Errorf("JIRA_BASE_URL required")
    }

    email := os.Getenv("JIRA_EMAIL")
    if email == "" {
        return Config{}, fmt.Errorf("JIRA_EMAIL required")
    }

    token := os.Getenv("JIRA_API_TOKEN")
    if token == "" {
        return Config{}, fmt.Errorf("JIRA_API_TOKEN required")
    }

    timeout := 30 * time.Second
    if t := os.Getenv("JIRA_TIMEOUT"); t != "" {
        d, err := time.ParseDuration(t)
        if err != nil {
            return Config{}, fmt.Errorf("invalid JIRA_TIMEOUT: %w", err)
        }
        timeout = d
    }

    return Config{
        BaseURL:  baseURL,
        Email:    email,
        APIToken: token,
        Timeout:  timeout,
    }, nil
}
```

## Provider with Rate Limiting

Add rate limiting to respect API limits:

```go
package jira

import "time"

func NewProvider(cfg Config) *Provider {
    p := &Provider{
        BaseProvider: core.NewProvider("resolute-jira", "1.0.0"),
        config:       cfg,
        client:       NewClient(cfg),
    }

    // Jira Cloud: ~100 requests per minute
    p.WithRateLimit(80, time.Minute)  // Conservative limit

    p.AddActivity("jira.FetchIssues", p.fetchIssues).
      AddActivity("jira.CreateIssue", p.createIssue)

    return p
}
```

## Implementing the Client

Providers typically wrap an API client:

```go
package jira

import (
    "bytes"
    "context"
    "encoding/json"
    "fmt"
    "io"
    "net/http"
)

type Client struct {
    baseURL    string
    httpClient *http.Client
    auth       string
}

func NewClient(cfg Config) *Client {
    return &Client{
        baseURL: cfg.BaseURL,
        httpClient: &http.Client{
            Timeout: cfg.Timeout,
        },
        auth: basicAuth(cfg.Email, cfg.APIToken),
    }
}

func (c *Client) Search(ctx context.Context, jql string, startAt, maxResults int) ([]Issue, error) {
    body := map[string]interface{}{
        "jql":        jql,
        "startAt":    startAt,
        "maxResults": maxResults,
    }

    resp, err := c.do(ctx, "POST", "/rest/api/3/search", body)
    if err != nil {
        return nil, err
    }

    var result SearchResponse
    if err := json.Unmarshal(resp, &result); err != nil {
        return nil, fmt.Errorf("unmarshal response: %w", err)
    }

    return result.Issues, nil
}

func (c *Client) do(ctx context.Context, method, path string, body interface{}) ([]byte, error) {
    var bodyReader io.Reader
    if body != nil {
        b, err := json.Marshal(body)
        if err != nil {
            return nil, fmt.Errorf("marshal body: %w", err)
        }
        bodyReader = bytes.NewReader(b)
    }

    req, err := http.NewRequestWithContext(ctx, method, c.baseURL+path, bodyReader)
    if err != nil {
        return nil, fmt.Errorf("create request: %w", err)
    }

    req.Header.Set("Authorization", c.auth)
    req.Header.Set("Content-Type", "application/json")

    resp, err := c.httpClient.Do(req)
    if err != nil {
        return nil, fmt.Errorf("do request: %w", err)
    }
    defer resp.Body.Close()

    if resp.StatusCode >= 400 {
        body, _ := io.ReadAll(resp.Body)
        return nil, fmt.Errorf("api error %d: %s", resp.StatusCode, string(body))
    }

    return io.ReadAll(resp.Body)
}
```

## Custom Provider Interface

For advanced cases, implement the full `Provider` interface:

```go
package custom

import "github.com/resolute/resolute/core"

type CustomProvider struct {
    name       string
    version    string
    activities []core.ActivityMeta
    // Custom fields
    pool       *ConnectionPool
    metrics    *Metrics
}

func (p *CustomProvider) Name() string {
    return p.name
}

func (p *CustomProvider) Version() string {
    return p.version
}

func (p *CustomProvider) Activities() []core.ActivityMeta {
    return p.activities
}

// Additional custom methods
func (p *CustomProvider) Close() error {
    return p.pool.Close()
}

func (p *CustomProvider) Health() error {
    return p.pool.Ping()
}
```

## Complete Example: GitHub Provider

A full provider implementation:

```go
package github

import (
    "context"
    "fmt"
    "time"

    "github.com/google/go-github/v60/github"
    "github.com/resolute/resolute/core"
    "go.temporal.io/sdk/worker"
    "golang.org/x/oauth2"
)

const (
    ProviderName    = "resolute-github"
    ProviderVersion = "1.0.0"
)

type Config struct {
    Token string
}

type Provider struct {
    *core.BaseProvider
    client *github.Client
}

func NewProvider(cfg Config) *Provider {
    ts := oauth2.StaticTokenSource(
        &oauth2.Token{AccessToken: cfg.Token},
    )
    tc := oauth2.NewClient(context.Background(), ts)
    client := github.NewClient(tc)

    p := &Provider{
        BaseProvider: core.NewProvider(ProviderName, ProviderVersion),
        client:       client,
    }

    // GitHub API: 5000 requests per hour
    p.WithRateLimit(5000, time.Hour)

    p.AddActivity("github.ListPullRequests", p.listPullRequests).
      AddActivity("github.GetPullRequest", p.getPullRequest).
      AddActivity("github.CreateIssue", p.createIssue).
      AddActivity("github.ListIssues", p.listIssues)

    return p
}

// Input/Output types
type ListPullRequestsInput struct {
    Owner string
    Repo  string
    State string // open, closed, all
}

type PullRequest struct {
    Number    int
    Title     string
    State     string
    Author    string
    CreatedAt time.Time
    UpdatedAt time.Time
    URL       string
}

type ListPullRequestsOutput struct {
    PullRequests []PullRequest
    Total        int
}

func (p *Provider) listPullRequests(ctx context.Context, input ListPullRequestsInput) (ListPullRequestsOutput, error) {
    opts := &github.PullRequestListOptions{
        State: input.State,
        ListOptions: github.ListOptions{
            PerPage: 100,
        },
    }

    prs, _, err := p.client.PullRequests.List(ctx, input.Owner, input.Repo, opts)
    if err != nil {
        return ListPullRequestsOutput{}, fmt.Errorf("list pull requests: %w", err)
    }

    result := make([]PullRequest, 0, len(prs))
    for _, pr := range prs {
        result = append(result, PullRequest{
            Number:    pr.GetNumber(),
            Title:     pr.GetTitle(),
            State:     pr.GetState(),
            Author:    pr.GetUser().GetLogin(),
            CreatedAt: pr.GetCreatedAt().Time,
            UpdatedAt: pr.GetUpdatedAt().Time,
            URL:       pr.GetHTMLURL(),
        })
    }

    return ListPullRequestsOutput{
        PullRequests: result,
        Total:        len(result),
    }, nil
}

type CreateIssueInput struct {
    Owner  string
    Repo   string
    Title  string
    Body   string
    Labels []string
}

type CreateIssueOutput struct {
    Number int
    URL    string
}

func (p *Provider) createIssue(ctx context.Context, input CreateIssueInput) (CreateIssueOutput, error) {
    issue := &github.IssueRequest{
        Title:  github.String(input.Title),
        Body:   github.String(input.Body),
        Labels: &input.Labels,
    }

    created, _, err := p.client.Issues.Create(ctx, input.Owner, input.Repo, issue)
    if err != nil {
        return CreateIssueOutput{}, fmt.Errorf("create issue: %w", err)
    }

    return CreateIssueOutput{
        Number: created.GetNumber(),
        URL:    created.GetHTMLURL(),
    }, nil
}

func (p *Provider) RegisterActivities(w worker.Worker) {
    core.RegisterProviderActivities(w, p)
}
```

## See Also

- **[Registering Activities](/docs/guides/providers/registering-activities/)** - Worker registration
- **[Provider Best Practices](/docs/guides/providers/best-practices/)** - Design patterns
- **[Rate Limiting](/docs/guides/advanced-patterns/rate-limiting/)** - Provider rate limits
- **[Provider Reference](/docs/reference/providers/jira/)** - Built-in providers
