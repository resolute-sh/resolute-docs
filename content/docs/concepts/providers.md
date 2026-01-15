---
title: "Providers"
description: "Providers - Resolute documentation"
weight: 60
toc: true
---


# Providers

A **Provider** groups related activities for integration with external systems. Providers encapsulate connection configuration, rate limiting, and activity registration.

## What is a Provider?

Providers serve multiple purposes:
- **Grouping** - Organize related activities (e.g., all Jira operations)
- **Registration** - Handle Temporal activity registration
- **Rate Limiting** - Apply shared rate limits across activities
- **Configuration** - Centralize connection settings

```go
type Provider interface {
    Name() string
    Version() string
    Activities() []ActivityMeta
}
```

## Built-in Providers

Resolute includes providers for common integrations:

| Provider | Package | Description |
|----------|---------|-------------|
| **Jira** | `resolute-jira` | Issue fetching, search, transitions |
| **Ollama** | `resolute-ollama` | Local LLM embedding generation |
| **Qdrant** | `resolute-qdrant` | Vector database operations |
| **Confluence** | `resolute-confluence` | Wiki page operations |
| **PagerDuty** | `resolute-pagerduty` | Incident management |
| **Transform** | `resolute-transform` | Document chunking and transformation |

### Installation

```bash
go get github.com/resolute/resolute-jira
go get github.com/resolute/resolute-ollama
go get github.com/resolute/resolute-qdrant
```

### Usage

```go
import (
    "github.com/resolute/resolute-jira"
    "github.com/resolute/resolute-ollama"
)

// Create provider instances
jiraProvider := jira.NewProvider(jira.Config{
    BaseURL:  "https://your-domain.atlassian.net",
    Username: os.Getenv("JIRA_USERNAME"),
    Token:    os.Getenv("JIRA_TOKEN"),
})

ollamaProvider := ollama.NewProvider(ollama.Config{
    Host:  "http://localhost:11434",
    Model: "nomic-embed-text",
})

// Register with worker
core.NewWorker().
    WithConfig(config).
    WithFlow(myFlow).
    WithProviders(jiraProvider, ollamaProvider).
    Run()
```

## Creating Custom Providers

### Using BaseProvider

The `BaseProvider` struct provides a default implementation:

```go
package myprovider

import (
    "context"
    "time"

    "github.com/resolute/resolute/core"
)

// Config holds provider configuration
type Config struct {
    APIKey  string
    BaseURL string
}

// Provider implements core.Provider
type Provider struct {
    *core.BaseProvider
    config Config
}

// NewProvider creates a configured provider instance
func NewProvider(cfg Config) *Provider {
    p := &Provider{
        BaseProvider: core.NewProvider("my-provider", "1.0.0"),
        config:       cfg,
    }

    // Register activities
    p.AddActivity("fetch-data", p.fetchData)
    p.AddActivity("store-data", p.storeData)

    return p
}

// Activity: Fetch data from external API
type FetchInput struct {
    Query string
}

type FetchOutput struct {
    Items []Item
    Total int
}

func (p *Provider) fetchData(ctx context.Context, input FetchInput) (FetchOutput, error) {
    // Use p.config for API credentials
    client := newClient(p.config.BaseURL, p.config.APIKey)
    items, err := client.Search(ctx, input.Query)
    if err != nil {
        return FetchOutput{}, fmt.Errorf("fetch data: %w", err)
    }
    return FetchOutput{Items: items, Total: len(items)}, nil
}

// Activity: Store data
type StoreInput struct {
    Items []Item
}

type StoreOutput struct {
    Stored int
}

func (p *Provider) storeData(ctx context.Context, input StoreInput) (StoreOutput, error) {
    // Implementation...
    return StoreOutput{Stored: len(input.Items)}, nil
}
```

### Creating Nodes from Provider Activities

Providers typically expose convenience functions to create nodes:

```go
// In myprovider package

// FetchData returns a node configured to fetch data
func (p *Provider) FetchData(input FetchInput) *core.Node[FetchInput, FetchOutput] {
    return core.NewNode("fetch-data", p.fetchData, input)
}

// StoreData returns a node configured to store data
func (p *Provider) StoreData(input StoreInput) *core.Node[StoreInput, StoreOutput] {
    return core.NewNode("store-data", p.storeData, input)
}
```

Usage in flows:

```go
provider := myprovider.NewProvider(config)

fetchNode := provider.FetchData(myprovider.FetchInput{Query: "test"}).
    WithTimeout(2 * time.Minute).
    WithRetry(retryPolicy)

flow := core.NewFlow("my-flow").
    TriggeredBy(core.Manual("api")).
    Then(fetchNode).
    Build()
```

## Provider Rate Limiting

### Provider-Level Rate Limits

Apply a shared rate limit to all activities in a provider:

```go
provider := myprovider.NewProvider(config).
    WithRateLimit(100, time.Minute)  // 100 requests/minute across all activities
```

All nodes created from this provider share the rate limit:

```go
// Both nodes share the 100 req/min limit
fetchNode := provider.FetchData(input1)
storeNode := provider.StoreData(input2)
```

### Activity-Level Rate Limits

Override rate limits per activity:

```go
fetchNode := provider.FetchData(input).
    WithRateLimit(50, time.Minute)  // Override: 50 req/min just for this node
```

### Shared Rate Limiters

Multiple providers can share a rate limiter:

```go
// Create a shared limiter
apiLimiter := core.NewSharedRateLimiter("external-api", 100, time.Minute)

// Apply to nodes from different providers
jiraNode := jiraProvider.FetchIssues(input).WithSharedRateLimit(apiLimiter)
confluenceNode := confluenceProvider.FetchPages(input).WithSharedRateLimit(apiLimiter)
```

## Provider Registry

For large applications, use the `ProviderRegistry`:

```go
registry := core.NewProviderRegistry()

// Register providers
registry.Register(jiraProvider)
registry.Register(ollamaProvider)
registry.Register(qdrantProvider)

// List all providers
for _, p := range registry.List() {
    fmt.Printf("Provider: %s v%s\n", p.Name(), p.Version())
}

// Get a specific provider
jira, ok := registry.Get("jira")

// Register all activities with a worker
registry.RegisterAllActivities(worker)
```

## Activity Metadata

Activities can include metadata for documentation and discovery:

```go
p.AddActivityWithDescription(
    "fetch-issues",
    "Fetches issues from Jira using JQL query",
    p.fetchIssues,
)
```

Access metadata:

```go
for _, activity := range provider.Activities() {
    fmt.Printf("Activity: %s\n", activity.Name)
    fmt.Printf("Description: %s\n", activity.Description)
}
```

## Provider Interface

The full `Provider` interface:

```go
type Provider interface {
    Name() string              // Provider identifier
    Version() string           // Semantic version
    Activities() []ActivityMeta // List of activities
}

type ActivityMeta struct {
    Name        string       // Activity identifier
    Description string       // Human-readable description
    Function    ActivityFunc // The activity function
}
```

## BaseProvider Methods

| Method | Description |
|--------|-------------|
| `NewProvider(name, version)` | Create a new base provider |
| `.AddActivity(name, fn)` | Register an activity |
| `.AddActivityWithDescription(name, desc, fn)` | Register with description |
| `.WithRateLimit(n, duration)` | Set provider-wide rate limit |
| `.Name()` | Get provider name |
| `.Version()` | Get provider version |
| `.Activities()` | Get activity list |
| `.GetRateLimiter()` | Get rate limiter (if configured) |

## Best Practices

### 1. Centralize Configuration

Put credentials and settings in the provider config:

```go
type Config struct {
    BaseURL     string
    APIKey      string
    Timeout     time.Duration
    MaxRetries  int
}

func NewProvider(cfg Config) *Provider {
    if cfg.Timeout == 0 {
        cfg.Timeout = 30 * time.Second  // Default
    }
    // ...
}
```

### 2. Use Environment Variables

Never hardcode credentials:

```go
provider := myprovider.NewProvider(myprovider.Config{
    APIKey:  os.Getenv("MY_API_KEY"),
    BaseURL: os.Getenv("MY_API_URL"),
})
```

### 3. Apply Appropriate Rate Limits

Respect external API limits:

```go
// Jira Cloud: ~100 requests/minute
jiraProvider := jira.NewProvider(config).
    WithRateLimit(100, time.Minute)

// Be conservative with free tier APIs
freeProvider := myapi.NewProvider(config).
    WithRateLimit(10, time.Minute)
```

### 4. Version Your Providers

Use semantic versioning:

```go
core.NewProvider("my-provider", "1.2.3")
```

### 5. Document Activities

Include descriptions for discoverability:

```go
p.AddActivityWithDescription(
    "fetch-issues",
    "Fetches Jira issues matching a JQL query. Supports pagination via StartAt/MaxResults.",
    p.fetchIssues,
)
```

## Example: Complete Custom Provider

```go
package github

import (
    "context"
    "fmt"

    "github.com/resolute/resolute/core"
)

type Config struct {
    Token string
    Owner string
    Repo  string
}

type Provider struct {
    *core.BaseProvider
    config Config
}

func NewProvider(cfg Config) *Provider {
    p := &Provider{
        BaseProvider: core.NewProvider("github", "1.0.0"),
        config:       cfg,
    }

    p.AddActivityWithDescription("list-issues", "List repository issues", p.listIssues)
    p.AddActivityWithDescription("create-issue", "Create a new issue", p.createIssue)
    p.AddActivityWithDescription("close-issue", "Close an issue", p.closeIssue)

    return p
}

// Activities...

// Node factory functions
func (p *Provider) ListIssues(input ListIssuesInput) *core.Node[ListIssuesInput, ListIssuesOutput] {
    return core.NewNode("list-issues", p.listIssues, input)
}

func (p *Provider) CreateIssue(input CreateIssueInput) *core.Node[CreateIssueInput, CreateIssueOutput] {
    return core.NewNode("create-issue", p.createIssue, input)
}

func (p *Provider) CloseIssue(input CloseIssueInput) *core.Node[CloseIssueInput, CloseIssueOutput] {
    return core.NewNode("close-issue", p.closeIssue, input)
}
```

## See Also

- **[Nodes](/docs/concepts/nodes/)** - Using provider nodes in flows
- **[Workers](/docs/concepts/workers/)** - Registering providers with workers
- **[Creating Providers](/docs/guides/providers/creating-providers/)** - Detailed guide
- **[Rate Limiting](/docs/guides/advanced-patterns/rate-limiting/)** - Advanced patterns
