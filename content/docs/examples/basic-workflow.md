---
title: "Basic Workflow"
description: "Basic Workflow - Resolute documentation"
weight: 10
toc: true
---


# Basic Workflow Example

This example demonstrates a simple workflow that fetches Jira issues, processes them, and posts a summary to Slack.

## Overview

The workflow:
1. Fetches open issues from a Jira project
2. Filters high-priority items
3. Generates a summary
4. Posts to Slack

## Prerequisites

- Running Temporal server
- Jira API credentials
- Slack webhook URL

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

    // Define the workflow
    flow := core.NewFlow("daily-issue-summary").
        TriggeredBy(core.Schedule("0 9 * * *")). // 9 AM daily

        // Fetch open issues
        Then(jira.FetchIssues(jira.FetchInput{
            JQL:   "project = PLATFORM AND status = Open",
            Limit: 100,
        }).As("issues")).

        // Filter high priority
        Then(transform.Filter(transform.FilterInput{
            Items:      core.Output("issues.Items"),
            Expression: ".Priority == 'High' || .Priority == 'Critical'",
        }).As("high-priority")).

        // Generate report
        Then(transform.Template(transform.TemplateInput{
            Data: map[string]any{
                "total":    core.Output("issues.Count"),
                "critical": core.Output("high-priority.Results"),
            },
            Template: dailySummaryTemplate,
        }).As("report")).

        // Send to Slack
        Then(sendSlackMessageNode).
        Build()

    // Create and run worker
    err := core.NewWorker().
        WithConfig(core.WorkerConfig{
            TaskQueue: "issue-summary",
        }).
        WithFlow(flow).
        WithProviders(jiraProvider, transformProvider).
        Run()

    if err != nil {
        panic(err)
    }
}

const dailySummaryTemplate = `
*Daily Issue Summary*

Total Open Issues: {{.total}}

{{if .critical}}
:rotating_light: *High Priority Items:*
{{range .critical}}
- [{{.Key}}] {{.Summary}} - {{.Assignee}}
{{end}}
{{else}}
No high priority items today.
{{end}}
`

type SlackInput struct {
    Message string `json:"message"`
}

type SlackOutput struct {
    Sent bool `json:"sent"`
}

// sendSlackMessageNode posts to Slack webhook
var sendSlackMessageNode = core.NewNode("send-slack", sendToSlack)

func sendToSlack(ctx context.Context, input SlackInput) (SlackOutput, error) {
    // Implementation to post to Slack webhook
    return SlackOutput{Sent: true}, nil
}
```

## Step-by-Step Breakdown

### 1. Provider Configuration

```go
jiraProvider := jira.NewProvider(jira.JiraConfig{
    BaseURL:  os.Getenv("JIRA_BASE_URL"),
    Email:    os.Getenv("JIRA_EMAIL"),
    APIToken: os.Getenv("JIRA_API_TOKEN"),
})
```

Providers encapsulate external service connections. Configure once, use throughout your flows.

### 2. Flow Definition

```go
flow := core.NewFlow("daily-issue-summary").
    TriggeredBy(core.Schedule("0 9 * * *")).
    // ... steps
    Build()
```

The fluent builder API creates readable workflow definitions. `TriggeredBy` sets when the workflow executes.

### 3. Data Flow with `As()` and `core.Output()`

```go
Then(jira.FetchIssues(...).As("issues")).
Then(transform.Filter(transform.FilterInput{
    Items: core.Output("issues.Items"),
    // ...
}))
```

- `As("issues")` names the step's output
- `core.Output("issues.Items")` references that output in subsequent steps

### 4. Worker Execution

```go
core.NewWorker().
    WithConfig(core.WorkerConfig{TaskQueue: "issue-summary"}).
    WithFlow(flow).
    WithProviders(jiraProvider, transformProvider).
    Run()
```

The worker registers the flow with Temporal and starts processing.

## Running the Example

1. Set environment variables:
```bash
export JIRA_BASE_URL="https://your-org.atlassian.net"
export JIRA_EMAIL="your-email@company.com"
export JIRA_API_TOKEN="your-api-token"
export SLACK_WEBHOOK_URL="https://hooks.slack.com/..."
```

2. Start Temporal server:
```bash
temporal server start-dev
```

3. Run the worker:
```bash
go run main.go
```

4. Trigger manually (for testing):
```bash
temporal workflow start \
    --task-queue issue-summary \
    --type daily-issue-summary
```

## Variations

### Manual Trigger with Input

```go
flow := core.NewFlow("on-demand-summary").
    TriggeredBy(core.Manual("api")).
    Then(jira.FetchIssues(jira.FetchInput{
        Project: core.Input("project"), // From trigger payload
    })).
    // ...
    Build()
```

### Adding Error Handling

```go
flow := core.NewFlow("resilient-summary").
    TriggeredBy(core.Schedule("0 9 * * *")).
    Then(jira.FetchIssues(...).
        OnError(notifyOpsNode). // Alert on failure
        WithRetry(3, time.Minute)). // Retry up to 3 times
    // ...
    Build()
```

### Conditional Paths

```go
flow := core.NewFlow("conditional-summary").
    TriggeredBy(core.Schedule("0 9 * * *")).
    Then(fetchIssuesNode.As("issues")).
    When(func(s *core.FlowState) bool {
        issues := core.Get[jira.FetchOutput](s, "issues")
        return issues.Count > 0
    }).
        Then(generateReportNode).
        Then(sendSlackNode).
    EndWhen().
    Build()
```

## See Also

- **[Flows](/docs/concepts/flows/)** - Understanding flow structure
- **[Triggers](/docs/concepts/triggers/)** - Trigger types and configuration
- **[Jira Provider](/docs/reference/providers/jira/)** - Full Jira API reference
