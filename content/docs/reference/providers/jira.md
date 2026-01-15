---
title: "Jira Provider"
description: "Jira Provider - Resolute documentation"
weight: 10
toc: true
---


# Jira Provider

The Jira provider integrates with Atlassian Jira for issue tracking, project management, and workflow automation.

## Installation

```bash
go get github.com/resolute/resolute/providers/jira
```

## Configuration

### JiraConfig

```go
type JiraConfig struct {
    BaseURL   string  // Jira instance URL (e.g., "https://company.atlassian.net")
    Email     string  // User email for authentication
    APIToken  string  // API token for authentication
}
```

### Environment Variables

| Variable | Description | Required |
|----------|-------------|----------|
| `JIRA_BASE_URL` | Jira instance URL | Yes |
| `JIRA_EMAIL` | Authentication email | Yes |
| `JIRA_API_TOKEN` | API token | Yes |

## Provider Constructor

### NewProvider

```go
func NewProvider(cfg JiraConfig) *JiraProvider
```

Creates a new Jira provider with the given configuration.

**Parameters:**
- `cfg` - Jira configuration

**Returns:** `*JiraProvider` implementing `core.Provider`

**Example:**
```go
provider := jira.NewProvider(jira.JiraConfig{
    BaseURL:  os.Getenv("JIRA_BASE_URL"),
    Email:    os.Getenv("JIRA_EMAIL"),
    APIToken: os.Getenv("JIRA_API_TOKEN"),
})

// Use with worker
core.NewWorker().
    WithConfig(cfg).
    WithFlow(flow).
    WithProviders(provider).
    Run()
```

## Types

### Issue

```go
type Issue struct {
    Key         string            `json:"key"`
    ID          string            `json:"id"`
    Summary     string            `json:"summary"`
    Description string            `json:"description"`
    Status      string            `json:"status"`
    Priority    string            `json:"priority"`
    Assignee    string            `json:"assignee"`
    Reporter    string            `json:"reporter"`
    Labels      []string          `json:"labels"`
    Components  []string          `json:"components"`
    Created     time.Time         `json:"created"`
    Updated     time.Time         `json:"updated"`
    Fields      map[string]any    `json:"fields"`
}
```

### Transition

```go
type Transition struct {
    ID   string `json:"id"`
    Name string `json:"name"`
    To   string `json:"to"`
}
```

### Comment

```go
type Comment struct {
    ID      string    `json:"id"`
    Body    string    `json:"body"`
    Author  string    `json:"author"`
    Created time.Time `json:"created"`
}
```

## Activities

### FetchIssues

Fetches issues from Jira using JQL (Jira Query Language).

**Input:**
```go
type FetchInput struct {
    JQL        string    `json:"jql"`         // JQL query string
    Project    string    `json:"project"`     // Project key (alternative to JQL)
    MaxResults int       `json:"max_results"` // Max issues to return (default: 50)
    StartAt    int       `json:"start_at"`    // Pagination offset
    Fields     []string  `json:"fields"`      // Fields to include
    Cursor     string    `json:"cursor"`      // For incremental sync (RFC3339 timestamp)
}
```

**Output:**
```go
type FetchOutput struct {
    Issues     []Issue `json:"issues"`
    Total      int     `json:"total"`
    Count      int     `json:"count"`
    StartAt    int     `json:"start_at"`
    HasMore    bool    `json:"has_more"`
    NextCursor string  `json:"next_cursor"`
}
```

**Node Factory:**
```go
func FetchIssues(input FetchInput) *core.Node[FetchInput, FetchOutput]
```

**Example:**
```go
// Fetch all issues from a project
fetchNode := jira.FetchIssues(jira.FetchInput{
    Project:    "PLATFORM",
    MaxResults: 100,
})

// Fetch with JQL
fetchNode := jira.FetchIssues(jira.FetchInput{
    JQL: "project = PLATFORM AND status = 'In Progress'",
})

// Incremental sync with cursor
fetchNode := jira.FetchIssues(jira.FetchInput{
    JQL:    "project = PLATFORM",
    Cursor: core.CursorFor("jira"),
})
```

### FetchIssue

Fetches a single issue by key.

**Input:**
```go
type FetchIssueInput struct {
    Key    string   `json:"key"`    // Issue key (e.g., "PROJ-123")
    Fields []string `json:"fields"` // Fields to include
}
```

**Output:**
```go
type FetchIssueOutput struct {
    Issue Issue `json:"issue"`
}
```

**Node Factory:**
```go
func FetchIssue(input FetchIssueInput) *core.Node[FetchIssueInput, FetchIssueOutput]
```

**Example:**
```go
fetchNode := jira.FetchIssue(jira.FetchIssueInput{
    Key: "PLATFORM-123",
})
```

### SearchJQL

Executes a JQL search query with full control over parameters.

**Input:**
```go
type SearchInput struct {
    JQL        string   `json:"jql"`
    MaxResults int      `json:"max_results"`
    StartAt    int      `json:"start_at"`
    Fields     []string `json:"fields"`
    Expand     []string `json:"expand"`
}
```

**Output:**
```go
type SearchOutput struct {
    Issues     []Issue `json:"issues"`
    Total      int     `json:"total"`
    MaxResults int     `json:"max_results"`
    StartAt    int     `json:"start_at"`
}
```

**Node Factory:**
```go
func SearchJQL(input SearchInput) *core.Node[SearchInput, SearchOutput]
```

**Example:**
```go
searchNode := jira.SearchJQL(jira.SearchInput{
    JQL:        "project = PLATFORM AND updated >= -7d",
    MaxResults: 50,
    Fields:     []string{"summary", "status", "assignee"},
})
```

### CreateIssue

Creates a new issue in Jira.

**Input:**
```go
type CreateInput struct {
    Project     string         `json:"project"`
    IssueType   string         `json:"issue_type"`
    Summary     string         `json:"summary"`
    Description string         `json:"description"`
    Priority    string         `json:"priority"`
    Assignee    string         `json:"assignee"`
    Labels      []string       `json:"labels"`
    Components  []string       `json:"components"`
    CustomFields map[string]any `json:"custom_fields"`
}
```

**Output:**
```go
type CreateOutput struct {
    Key string `json:"key"`
    ID  string `json:"id"`
}
```

**Node Factory:**
```go
func CreateIssue(input CreateInput) *core.Node[CreateInput, CreateOutput]
```

**Example:**
```go
createNode := jira.CreateIssue(jira.CreateInput{
    Project:     "PLATFORM",
    IssueType:   "Bug",
    Summary:     "Authentication failing on login",
    Description: "Users cannot log in with valid credentials",
    Priority:    "High",
    Labels:      []string{"auth", "urgent"},
})
```

### UpdateIssue

Updates an existing issue.

**Input:**
```go
type UpdateInput struct {
    Key         string         `json:"key"`
    Summary     string         `json:"summary"`
    Description string         `json:"description"`
    Priority    string         `json:"priority"`
    Assignee    string         `json:"assignee"`
    Labels      []string       `json:"labels"`
    CustomFields map[string]any `json:"custom_fields"`
}
```

**Output:**
```go
type UpdateOutput struct {
    Key     string `json:"key"`
    Updated bool   `json:"updated"`
}
```

**Node Factory:**
```go
func UpdateIssue(input UpdateInput) *core.Node[UpdateInput, UpdateOutput]
```

**Example:**
```go
updateNode := jira.UpdateIssue(jira.UpdateInput{
    Key:      "PLATFORM-123",
    Priority: "Critical",
    Labels:   []string{"auth", "urgent", "escalated"},
})
```

### TransitionIssue

Transitions an issue to a new status.

**Input:**
```go
type TransitionInput struct {
    Key          string         `json:"key"`
    TransitionID string         `json:"transition_id"`
    Comment      string         `json:"comment"`
    Fields       map[string]any `json:"fields"`
}
```

**Output:**
```go
type TransitionOutput struct {
    Key       string `json:"key"`
    NewStatus string `json:"new_status"`
}
```

**Node Factory:**
```go
func TransitionIssue(input TransitionInput) *core.Node[TransitionInput, TransitionOutput]
```

**Example:**
```go
transitionNode := jira.TransitionIssue(jira.TransitionInput{
    Key:          "PLATFORM-123",
    TransitionID: "31", // "Done" transition
    Comment:      "Fixed in release v2.1.0",
})
```

### AddComment

Adds a comment to an issue.

**Input:**
```go
type CommentInput struct {
    Key  string `json:"key"`
    Body string `json:"body"`
}
```

**Output:**
```go
type CommentOutput struct {
    CommentID string `json:"comment_id"`
}
```

**Node Factory:**
```go
func AddComment(input CommentInput) *core.Node[CommentInput, CommentOutput]
```

**Example:**
```go
commentNode := jira.AddComment(jira.CommentInput{
    Key:  "PLATFORM-123",
    Body: "Deployment completed successfully",
})
```

### GetTransitions

Gets available transitions for an issue.

**Input:**
```go
type GetTransitionsInput struct {
    Key string `json:"key"`
}
```

**Output:**
```go
type GetTransitionsOutput struct {
    Transitions []Transition `json:"transitions"`
}
```

**Node Factory:**
```go
func GetTransitions(input GetTransitionsInput) *core.Node[GetTransitionsInput, GetTransitionsOutput]
```

## Usage Patterns

### Basic Issue Sync Flow

```go
flow := core.NewFlow("jira-sync").
    TriggeredBy(core.Schedule("0 * * * *")).
    Then(jira.FetchIssues(jira.FetchInput{
        Project:    "PLATFORM",
        Cursor:     core.CursorFor("jira"),
        MaxResults: 100,
    }).As("issues")).
    When(func(s *core.FlowState) bool {
        result := core.Get[jira.FetchOutput](s, "issues")
        return result.Count > 0
    }).
        Then(processIssuesNode).
    EndWhen().
    Build()
```

### Issue Creation with Compensation

```go
createIssue := jira.CreateIssue(jira.CreateInput{
    Project:   "PLATFORM",
    IssueType: "Task",
    Summary:   core.Output("request.title"),
}).OnError(jira.TransitionIssue(jira.TransitionInput{
    Key:          core.Output("create-issue.Key"),
    TransitionID: "cancel",
}))

flow := core.NewFlow("create-with-rollback").
    TriggeredBy(core.Manual("api")).
    Then(createIssue.As("create-issue")).
    Then(assignResourcesNode).
    Build()
```

### Rate-Limited Bulk Operations

```go
// Provider-level rate limiting
provider := jira.NewProvider(cfg).WithRateLimit(100, time.Minute)

// Or per-node rate limiting
fetchNode := jira.FetchIssues(input).WithRateLimit(50, time.Minute)
```

### Pagination Flow

```go
flow := core.NewFlow("paginated-fetch").
    TriggeredBy(core.Manual("api")).
    Then(jira.SearchJQL(jira.SearchInput{
        JQL:        "project = PLATFORM",
        MaxResults: 50,
    }).As("page")).
    While(func(s *core.FlowState) bool {
        result := core.Get[jira.SearchOutput](s, "page")
        return result.StartAt + len(result.Issues) < result.Total
    }).
        Then(processPageNode).
        Then(nextPageNode).
    EndWhile().
    Build()
```

## Complete Example

```go
package main

import (
    "os"
    "time"

    "github.com/resolute/resolute/core"
    "github.com/resolute/resolute/providers/jira"
)

func main() {
    // Configure provider
    jiraProvider := jira.NewProvider(jira.JiraConfig{
        BaseURL:  os.Getenv("JIRA_BASE_URL"),
        Email:    os.Getenv("JIRA_EMAIL"),
        APIToken: os.Getenv("JIRA_API_TOKEN"),
    }).WithRateLimit(100, time.Minute)

    // Build flow
    flow := core.NewFlow("jira-issue-processor").
        TriggeredBy(core.Schedule("0 */2 * * *")).
        Then(jira.FetchIssues(jira.FetchInput{
            JQL:        "project = PLATFORM AND status = 'To Do'",
            Cursor:     core.CursorFor("jira-todo"),
            MaxResults: 50,
        }).As("issues")).
        When(func(s *core.FlowState) bool {
            issues := core.Get[jira.FetchOutput](s, "issues")
            return issues.Count > 0
        }).
            Then(triageIssuesNode).
            Then(notifyTeamNode).
        EndWhen().
        Build()

    // Run worker
    err := core.NewWorker().
        WithConfig(core.WorkerConfig{
            TaskQueue: "jira-processor",
        }).
        WithFlow(flow).
        WithProviders(jiraProvider).
        Run()

    if err != nil {
        panic(err)
    }
}
```

## See Also

- **[Provider Guide](/docs/guides/providers/creating-providers/)** - Creating custom providers
- **[Rate Limiting](/docs/guides/advanced-patterns/rate-limiting/)** - Rate limit patterns
- **[Pagination](/docs/guides/advanced-patterns/pagination/)** - Handling paginated APIs
