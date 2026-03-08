---
title: "Slack Provider"
description: "Slack Provider - Resolute documentation"
weight: 80
toc: true
---

# Slack Provider

The Slack provider sends messages to Slack channels via incoming webhooks with Block Kit support.

## Installation

```bash
go get github.com/resolute-sh/resolute-slack@v0.2.1-alpha
```

## Configuration

### Slack Webhook

Slack messages are sent via [Incoming Webhooks](https://api.slack.com/messaging/webhooks). Create a webhook in your Slack workspace and pass the URL per-activity.

| Parameter | Description | Required |
|-----------|-------------|----------|
| `WebhookURL` | Slack Incoming Webhook URL | Yes |

### Provider Registration

```go
import (
    "github.com/resolute-sh/resolute-slack"
)

// Register with worker
slack.RegisterActivities(w)

// Or use Provider() for introspection
provider := slack.Provider()
```

## Types

### Block Kit Types

```go
type BlockType string

const (
    BlockTypeSection BlockType = "section"
    BlockTypeHeader  BlockType = "header"
    BlockTypeDivider BlockType = "divider"
)

type TextType string

const (
    TextTypeMrkdwn    TextType = "mrkdwn"
    TextTypePlainText TextType = "plain_text"
)

type Text struct {
    Type TextType `json:"type"`
    Text string   `json:"text"`
}

type Block struct {
    Type BlockType `json:"type"`
    Text *Text     `json:"text,omitempty"`
}
```

## Activities

### SendMessage

Sends a message to a Slack channel via incoming webhook.

**Input:**
```go
type SendMessageInput struct {
    WebhookURL string   // Slack Incoming Webhook URL
    Channel    string   // Channel override (optional)
    Text       string   // Plain text fallback
    Blocks     []Block  // Block Kit blocks (optional)
}
```

**Output:**
```go
type SendMessageOutput struct {
    Sent bool
}
```

**Node Factory:**
```go
func SendMessage(input SendMessageInput) *core.Node[SendMessageInput, SendMessageOutput]
```

**Example — Plain text:**
```go
notifyNode := slack.SendMessage(slack.SendMessageInput{
    WebhookURL: os.Getenv("SLACK_WEBHOOK_URL"),
    Text:       "Deployment completed successfully",
})
```

**Example — Block Kit:**
```go
notifyNode := slack.SendMessage(slack.SendMessageInput{
    WebhookURL: os.Getenv("SLACK_WEBHOOK_URL"),
    Text:       "Deployment update",
    Blocks: []slack.Block{
        {
            Type: slack.BlockTypeHeader,
            Text: &slack.Text{
                Type: slack.TextTypePlainText,
                Text: "Deployment Complete",
            },
        },
        {Type: slack.BlockTypeDivider},
        {
            Type: slack.BlockTypeSection,
            Text: &slack.Text{
                Type: slack.TextTypeMrkdwn,
                Text: "*Service:* api-gateway\n*Version:* v2.1.0\n*Status:* Healthy",
            },
        },
    },
})
```

If both `Text` and `Blocks` are empty, the message is not sent and `Sent` returns `false`.

### NotifyReport

Sends a structured Block Kit report notification with metadata (cost, duration, LLM info) and automatic markdown-to-Slack-mrkdwn conversion. Handles both success and failure states.

**Input:**
```go
type NotifyReportInput struct {
    WebhookURL  string // Slack Incoming Webhook URL
    Header      string // Success header text
    Label1      string // First metadata label (e.g., "Incident")
    Value1      string // First metadata value
    Label2      string // Second metadata label (e.g., "Service")
    Value2      string // Second metadata value
    Body        string // Report body (Markdown — auto-converted to Slack mrkdwn)
    CostUSD     string // Cost in USD
    Duration    string // Execution duration
    TurnsUsed   string // Number of LLM turns
    Succeeded   string // "true" for success layout, anything else for failure
    LLMProvider string // Provider name (e.g., "anthropic")
    LLMModel    string // Model name (e.g., "claude-sonnet-4-6")
    FailHeader  string // Header shown on failure
    FailMessage string // Message shown on failure
}
```

**Output:**
```go
type NotifyReportOutput struct {
    Notified bool
}
```

**Node Factory:**
```go
func NotifyReport(input NotifyReportInput) *core.Node[NotifyReportInput, NotifyReportOutput]
```

**Example:**
```go
reportNode := slack.NotifyReport(slack.NotifyReportInput{
    WebhookURL:  os.Getenv("SLACK_WEBHOOK_URL"),
    Header:      "Incident Review Complete",
    Label1:      "Incident",
    Value1:      core.Output("webhook.IncidentID"),
    Label2:      "Service",
    Value2:      core.Output("webhook.ServiceName"),
    Body:        core.Output("review.Response"),
    CostUSD:     core.Output("review.CostUSD"),
    Duration:    core.Output("review.Duration"),
    TurnsUsed:   core.Output("review.TurnsUsed"),
    Succeeded:   core.Output("review.Succeeded"),
    LLMProvider: "anthropic",
    LLMModel:    "claude-sonnet-4-6",
    FailHeader:  "Review Failed",
    FailMessage: "The automated review failed. Check Temporal UI for details.",
})
```

The activity automatically:
- Converts Markdown headings, bold, and links to Slack mrkdwn format
- Splits long bodies into multiple section blocks (3000 char limit per block)
- Uses `---` horizontal rules as block dividers
- Caps output at 50 Slack blocks
- Returns `Notified: false` (no error) if `WebhookURL` is empty

## Usage Patterns

### Notification at End of Pipeline

```go
flow := core.NewFlow("data-sync").
    TriggeredBy(core.Schedule("0 * * * *")).
    Then(fetchNode).
    Then(transformNode).
    Then(storeNode).
    Then(slack.SendMessage(slack.SendMessageInput{
        WebhookURL: os.Getenv("SLACK_WEBHOOK_URL"),
        Text:       "Data sync completed",
    })).
    Build()
```

### Dynamic Message from Flow State

```go
notifyNode := core.NewNode("notify", slack.SendMessageActivity, slack.SendMessageInput{}).
    WithInputFunc(func(state *core.FlowState) slack.SendMessageInput {
        results := core.Get[ProcessOutput](state, "process")
        return slack.SendMessageInput{
            WebhookURL: os.Getenv("SLACK_WEBHOOK_URL"),
            Blocks: []slack.Block{
                {
                    Type: slack.BlockTypeSection,
                    Text: &slack.Text{
                        Type: slack.TextTypeMrkdwn,
                        Text: fmt.Sprintf("Processed *%d* items with *%d* errors",
                            results.Total, results.ErrorCount),
                    },
                },
            },
        }
    })
```

### Combined with Bitbucket for PR Notifications

```go
flow := core.NewFlow("pr-notify").
    TriggeredBy(core.Webhook("/bitbucket")).
    Then(bitbucket.ParseWebhook(bitbucket.ParseWebhookInput{
        RawPayload: core.InputData("webhook_payload"),
    }).As("pr")).
    Then(core.NewNode("notify", slack.SendMessageActivity, slack.SendMessageInput{}).
        WithInputFunc(func(state *core.FlowState) slack.SendMessageInput {
            pr := core.Get[bitbucket.ParseWebhookOutput](state, "pr")
            return slack.SendMessageInput{
                WebhookURL: os.Getenv("SLACK_WEBHOOK_URL"),
                Text: fmt.Sprintf("New PR: %s by %s — %s",
                    pr.PR.Title, pr.PR.Author, pr.PR.PRURL),
            }
        }),
    ).
    Build()
```

## See Also

- **[Bitbucket Provider](/docs/reference/providers/bitbucket/)** — Webhook parsing and PR comments
- **[Triggers](/docs/concepts/triggers/)** — Webhook and schedule triggers
