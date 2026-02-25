---
title: "Bitbucket Provider"
description: "Bitbucket Provider - Resolute documentation"
weight: 70
toc: true
---

# Bitbucket Provider

The Bitbucket provider integrates with Bitbucket Cloud for webhook-driven workflows, pull request automation, and code review pipelines.

## Installation

```bash
go get github.com/resolute-sh/resolute-bitbucket@v0.4.0-alpha
```

## Configuration

### Authentication

Bitbucket activities use App Password authentication, passed per-activity in the input struct.

| Parameter | Description | Required |
|-----------|-------------|----------|
| `Username` | Bitbucket username | Yes (for write operations) |
| `AppPassword` | Bitbucket App Password | Yes (for write operations) |

### Provider Registration

```go
import (
    "github.com/resolute-sh/resolute-bitbucket"
)

// Register with worker
bitbucket.RegisterActivities(w)

// Or use Provider() for introspection
provider := bitbucket.Provider()
```

## Types

### PRMetadata

Structured output of webhook parsing containing all fields needed to launch a code review or automation job.

```go
type PRMetadata struct {
    Workspace    string
    RepoSlug     string
    Branch       string
    PRID         int
    TargetBranch string
    CommitSHA    string
    Author       string
    Title        string
    PRURL        string
}
```

### PRCreatedEvent

Represents a Bitbucket `pullrequest:created` webhook payload.

```go
type PRCreatedEvent struct {
    PullRequest PullRequest `json:"pullrequest"`
    Repository  Repository  `json:"repository"`
    Actor       Actor       `json:"actor"`
}
```

## Activities

### ParseWebhook

Parses a raw Bitbucket webhook payload into structured PR metadata.

**Input:**
```go
type ParseWebhookInput struct {
    RawPayload string  // Raw JSON webhook payload
}
```

**Output:**
```go
type ParseWebhookOutput struct {
    PR PRMetadata
}
```

**Node Factory:**
```go
func ParseWebhook(input ParseWebhookInput) *core.Node[ParseWebhookInput, ParseWebhookOutput]
```

**Example:**
```go
parseNode := bitbucket.ParseWebhook(bitbucket.ParseWebhookInput{
    RawPayload: core.InputData("webhook_payload"),
})
```

### AddComment

Posts a comment to a Bitbucket pull request via the REST API.

**Input:**
```go
type AddCommentInput struct {
    Username    string  // Bitbucket username
    AppPassword string  // Bitbucket App Password
    Workspace   string  // Workspace slug
    RepoSlug    string  // Repository slug
    PRID        string  // Pull request ID
    Body        string  // Comment body (Markdown supported)
}
```

**Output:**
```go
type AddCommentOutput struct {
    Posted bool
}
```

**Node Factory:**
```go
func AddComment(input AddCommentInput) *core.Node[AddCommentInput, AddCommentOutput]
```

**Example:**
```go
commentNode := bitbucket.AddComment(bitbucket.AddCommentInput{
    Username:    os.Getenv("BITBUCKET_USERNAME"),
    AppPassword: os.Getenv("BITBUCKET_APP_PASSWORD"),
    Workspace:   core.Output("parse-webhook.PR.Workspace"),
    RepoSlug:    core.Output("parse-webhook.PR.RepoSlug"),
    PRID:        core.Output("parse-webhook.PR.PRID"),
    Body:        core.Output("review.Summary"),
})
```

## Utilities

### ExtractTicketID

Extracts a Jira ticket ID from a branch name using the pattern `[A-Z]+-\d+`.

```go
func ExtractTicketID(branch string) string
```

```go
ticket := bitbucket.ExtractTicketID("feature/PLATFORM-123-add-auth")
// ticket = "PLATFORM-123"

ticket := bitbucket.ExtractTicketID("hotfix/no-ticket")
// ticket = ""
```

## Usage Patterns

### Webhook-Triggered Code Review

```go
flow := core.NewFlow("pr-review").
    TriggeredBy(core.Webhook("/bitbucket")).
    Then(bitbucket.ParseWebhook(bitbucket.ParseWebhookInput{
        RawPayload: core.InputData("webhook_payload"),
    }).As("pr")).
    Then(fetchDiffNode).
    Then(analyzeCodeNode).
    Then(bitbucket.AddComment(bitbucket.AddCommentInput{
        Username:    os.Getenv("BITBUCKET_USERNAME"),
        AppPassword: os.Getenv("BITBUCKET_APP_PASSWORD"),
        Workspace:   core.Output("pr.PR.Workspace"),
        RepoSlug:    core.Output("pr.PR.RepoSlug"),
        PRID:        core.Output("pr.PR.PRID"),
        Body:        core.Output("analyze-code.ReviewComment"),
    })).
    Build()
```

### PR Metadata with Jira Integration

```go
// In an InputFunc, extract Jira ticket from branch name
processNode := core.NewNode("process", processActivity, ProcessInput{}).
    WithInputFunc(func(state *core.FlowState) ProcessInput {
        pr := core.Get[bitbucket.ParseWebhookOutput](state, "pr")
        ticket := bitbucket.ExtractTicketID(pr.PR.Branch)
        return ProcessInput{
            PRID:     pr.PR.PRID,
            TicketID: ticket,
        }
    })
```

## See Also

- **[Slack Provider](/docs/reference/providers/slack/)** — Send notifications about PR events
- **[Triggers](/docs/concepts/triggers/)** — Webhook trigger configuration
- **[InputData](/docs/releases/v0.4.0-alpha/#inputdata-magic-marker)** — Accessing webhook payloads
