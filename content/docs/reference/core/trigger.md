---
title: "Trigger"
description: "Trigger - Resolute documentation"
weight: 30
toc: true
---


# Trigger

Triggers define how flows are initiated. Resolute supports manual (API), scheduled (cron), signal, and webhook triggers.

## Types

### Trigger

```go
type Trigger interface {
    Type() TriggerType
    Config() TriggerConfig
}
```

Interface implemented by all trigger types.

### TriggerType

```go
type TriggerType string

const (
    TriggerManual   TriggerType = "manual"
    TriggerSchedule TriggerType = "schedule"
    TriggerSignal   TriggerType = "signal"
    TriggerWebhook  TriggerType = "webhook"
)
```

Identifies the type of trigger.

### TriggerConfig

```go
type TriggerConfig struct {
    ID            string  // Identifier for manual triggers
    CronSchedule  string  // Cron expression for scheduled triggers
    SignalName    string  // Temporal signal name for signal triggers
    WebhookPath   string  // HTTP path for webhook triggers
    WebhookMethod string  // HTTP method for webhook triggers (default: POST)
    WebhookSecret string  // HMAC secret for webhook signature verification
}
```

Holds trigger-specific configuration.

## Trigger Constructors

### Manual

```go
func Manual(id string) Trigger
```

Creates a trigger for API-initiated flow execution.

**Parameters:**
- `id` - Unique identifier for the trigger (used as API endpoint path)

**Returns:** `Trigger` for use with `TriggeredBy()`

**Example:**
```go
flow := core.NewFlow("my-flow").
    TriggeredBy(core.Manual("start-sync")).
    Then(myNode).
    Build()

// Start via Temporal client:
// client.ExecuteWorkflow(ctx, opts, flow.Execute, input)
```

### Schedule

```go
func Schedule(cron string) Trigger
```

Creates a trigger for cron-scheduled flow execution.

**Parameters:**
- `cron` - Cron expression (minute hour day month weekday)

**Returns:** `Trigger` for use with `TriggeredBy()`

**Cron Format:**
```
┌───────────── minute (0-59)
│ ┌───────────── hour (0-23)
│ │ ┌───────────── day of month (1-31)
│ │ │ ┌───────────── month (1-12)
│ │ │ │ ┌───────────── day of week (0-6, Sunday=0)
│ │ │ │ │
* * * * *
```

**Common Patterns:**

| Expression | Description |
|------------|-------------|
| `0 * * * *` | Every hour |
| `0 0 * * *` | Daily at midnight |
| `0 2 * * *` | Daily at 2 AM |
| `*/15 * * * *` | Every 15 minutes |
| `0 9 * * 1-5` | Weekdays at 9 AM |
| `0 0 1 * *` | First day of month |

**Example:**
```go
// Daily sync at 2 AM
flow := core.NewFlow("daily-sync").
    TriggeredBy(core.Schedule("0 2 * * *")).
    Then(syncNode).
    Build()

// Hourly check
flow := core.NewFlow("hourly-check").
    TriggeredBy(core.Schedule("0 * * * *")).
    Then(checkNode).
    Build()
```

### Signal

```go
func Signal(name string) Trigger
```

Creates a trigger that starts the flow from a Temporal signal.

**Parameters:**
- `name` - Temporal signal name to listen for

**Returns:** `Trigger` for use with `TriggeredBy()`

**Example:**
```go
flow := core.NewFlow("event-handler").
    TriggeredBy(core.Signal("new-event")).
    Then(handleEventNode).
    Build()

// Send signal from another workflow or client:
// client.SignalWorkflow(ctx, workflowID, runID, "new-event", payload)
```

### Webhook

```go
func Webhook(path string) *WebhookTrigger
```

Creates a trigger for HTTP webhook-initiated flow execution.

**Parameters:**
- `path` - HTTP path for the webhook endpoint

**Returns:** `*WebhookTrigger` for additional configuration

**Example:**
```go
flow := core.NewFlow("github-webhook").
    TriggeredBy(core.Webhook("/github/push").
        WithMethod("POST").
        WithSecret(os.Getenv("WEBHOOK_SECRET"))).
    Then(handlePushNode).
    Build()
```

## WebhookTrigger Methods

### WithMethod

```go
func (w *WebhookTrigger) WithMethod(method string) *WebhookTrigger
```

Sets the HTTP method for the webhook (default: POST).

**Parameters:**
- `method` - HTTP method (GET, POST, PUT, etc.)

**Returns:** `*WebhookTrigger` for method chaining

### WithSecret

```go
func (w *WebhookTrigger) WithSecret(secret string) *WebhookTrigger
```

Sets the HMAC secret for webhook signature verification.

**Parameters:**
- `secret` - Secret key for HMAC-SHA256 signature

**Returns:** `*WebhookTrigger` for method chaining

## Trigger Interface Methods

### Type

```go
func (t Trigger) Type() TriggerType
```

Returns the trigger type identifier.

### Config

```go
func (t Trigger) Config() TriggerConfig
```

Returns the trigger-specific configuration.

## Usage Patterns

### Manual with Temporal Client

```go
// Define flow
flow := core.NewFlow("process-order").
    TriggeredBy(core.Manual("process")).
    Then(processNode).
    Build()

// Start workflow
c, _ := client.Dial(client.Options{})
we, err := c.ExecuteWorkflow(ctx, client.StartWorkflowOptions{
    ID:        "order-123",
    TaskQueue: "orders",
}, flow.Execute, core.FlowInput{})
```

### Scheduled with Worker

```go
// Define scheduled flow
flow := core.NewFlow("nightly-sync").
    TriggeredBy(core.Schedule("0 2 * * *")).
    Then(syncNode).
    Build()

// Run worker (handles scheduling)
err := core.NewWorker().
    WithConfig(core.WorkerConfig{TaskQueue: "sync"}).
    WithFlow(flow).
    Run()
```

### Webhook with Server

```go
// Define webhook flow
flow := core.NewFlow("github-events").
    TriggeredBy(core.Webhook("/webhooks/github").
        WithSecret(os.Getenv("GITHUB_SECRET"))).
    Then(handleEventNode).
    Build()

// Run worker with webhook server
err := core.NewWorker().
    WithConfig(core.WorkerConfig{TaskQueue: "webhooks"}).
    WithFlow(flow).
    WithWebhookServer(":8080").
    Run()

// Webhook available at: POST http://localhost:8080/webhooks/github
```

### Signal for Inter-Workflow Communication

```go
// Parent workflow signals child
parentFlow := core.NewFlow("parent").
    TriggeredBy(core.Manual("start")).
    Then(prepareNode).
    Then(signalChildNode).  // Sends signal to child workflow
    Then(waitForChildNode).
    Build()

// Child workflow triggered by signal
childFlow := core.NewFlow("child").
    TriggeredBy(core.Signal("start-processing")).
    Then(processNode).
    Build()
```

## Complete Example

```go
package main

import (
    "os"
    "github.com/resolute/resolute/core"
)

func main() {
    // Manual trigger for on-demand execution
    manualFlow := core.NewFlow("manual-sync").
        TriggeredBy(core.Manual("sync")).
        Then(syncNode).
        Build()

    // Scheduled trigger for periodic execution
    scheduledFlow := core.NewFlow("hourly-check").
        TriggeredBy(core.Schedule("0 * * * *")).
        Then(checkNode).
        Build()

    // Webhook trigger for external events
    webhookFlow := core.NewFlow("github-events").
        TriggeredBy(core.Webhook("/github").
            WithMethod("POST").
            WithSecret(os.Getenv("GITHUB_SECRET"))).
        Then(handleGithubNode).
        Build()

    // Signal trigger for inter-workflow communication
    signalFlow := core.NewFlow("event-processor").
        TriggeredBy(core.Signal("process-event")).
        Then(processEventNode).
        Build()
}
```

## See Also

- **[Flow](/docs/reference/core/flow/)** - Flow builder
- **[Worker](/docs/reference/core/worker/)** - Worker configuration
- **[Deployment](/docs/guides/deployment/worker-configuration/)** - Production setup
