---
title: "Triggers"
description: "Triggers - Resolute documentation"
weight: 40
toc: true
---


# Triggers

A **Trigger** defines how a flow is initiated. Resolute supports three trigger types: manual (API-initiated), scheduled (cron-based), and signal (Temporal signal).

## What is a Trigger?

Every flow must have exactly one trigger that determines:
- **When** the flow starts
- **How** input data is provided
- **What** initiates execution

```go
flow := core.NewFlow("my-flow").
    TriggeredBy(core.Manual("api")).  // <-- Trigger
    Then(myNode).
    Build()
```

## Trigger Types

### Manual Trigger

Manual triggers start flows via API calls or the Temporal CLI:

```go
flow := core.NewFlow("on-demand-sync").
    TriggeredBy(core.Manual("sync-api")).
    Then(syncNode).
    Build()
```

**Use cases:**
- On-demand operations triggered by users
- API-initiated workflows
- Testing and debugging
- One-time data migrations

**Starting a manual flow:**

```bash
# Using Temporal CLI
temporal workflow start \
    --task-queue my-queue \
    --type on-demand-sync \
    --workflow-id sync-123

# With input data
temporal workflow start \
    --task-queue my-queue \
    --type on-demand-sync \
    --workflow-id sync-123 \
    --input '{"key": "value"}'
```

**Programmatically:**

```go
client, _ := client.Dial(client.Options{})

_, err := client.ExecuteWorkflow(
    context.Background(),
    client.StartWorkflowOptions{
        ID:        "sync-123",
        TaskQueue: "my-queue",
    },
    "on-demand-sync",  // Flow name
    core.FlowInput{
        Data: map[string][]byte{
            "key": []byte(`"value"`),
        },
    },
)
```

### Schedule Trigger

Schedule triggers run flows on a cron schedule:

```go
flow := core.NewFlow("hourly-sync").
    TriggeredBy(core.Schedule("0 * * * *")).  // Every hour
    Then(syncNode).
    Build()
```

**Cron expression format:**

```
┌───────────── minute (0-59)
│ ┌───────────── hour (0-23)
│ │ ┌───────────── day of month (1-31)
│ │ │ ┌───────────── month (1-12)
│ │ │ │ ┌───────────── day of week (0-6, Sunday=0)
│ │ │ │ │
* * * * *
```

**Common schedules:**

| Expression | Description |
|------------|-------------|
| `* * * * *` | Every minute |
| `*/15 * * * *` | Every 15 minutes |
| `0 * * * *` | Every hour (at minute 0) |
| `0 */2 * * *` | Every 2 hours |
| `0 0 * * *` | Daily at midnight |
| `0 2 * * *` | Daily at 2 AM |
| `0 0 * * 0` | Weekly on Sunday at midnight |
| `0 0 1 * *` | Monthly on the 1st at midnight |

**Use cases:**
- Periodic data synchronization
- Daily/weekly reports
- Cleanup jobs
- Health checks

### Signal Trigger

Signal triggers start flows when a Temporal signal is received:

```go
flow := core.NewFlow("event-handler").
    TriggeredBy(core.Signal("new-event")).
    Then(handleEventNode).
    Build()
```

**Sending a signal:**

```bash
# Using Temporal CLI
temporal workflow signal \
    --workflow-id my-workflow \
    --name new-event \
    --input '{"event": "data"}'
```

**Programmatically:**

```go
err := client.SignalWorkflow(
    context.Background(),
    "my-workflow",  // Workflow ID
    "",             // Run ID (empty = latest)
    "new-event",    // Signal name
    signalData,
)
```

**Use cases:**
- Event-driven workflows
- Inter-workflow communication
- External system notifications
- Webhook-initiated processing

## Trigger Configuration

Each trigger type has specific configuration:

```go
type TriggerConfig struct {
    ID            string  // Manual trigger identifier
    CronSchedule  string  // Schedule cron expression
    SignalName    string  // Signal trigger name
    WebhookPath   string  // Webhook HTTP path
    WebhookMethod string  // Webhook HTTP method
    WebhookSecret string  // Webhook HMAC secret
}
```

Access configuration from a trigger:

```go
trigger := core.Manual("my-api")
trigger.Type()   // TriggerManual
trigger.Config() // TriggerConfig{ID: "my-api"}

trigger = core.Schedule("0 * * * *")
trigger.Type()   // TriggerSchedule
trigger.Config() // TriggerConfig{CronSchedule: "0 * * * *"}
```

## Trigger Selection Guide

```
┌─────────────────────────────────────────────────────────────────────┐
│                    Which Trigger Should I Use?                       │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  Does the workflow run on a fixed schedule?                          │
│  └─▶ YES: Use Schedule("cron-expression")                           │
│                                                                      │
│  Is it triggered by an external event or signal?                     │
│  └─▶ YES: Use Signal("signal-name")                                 │
│                                                                      │
│  Is it triggered by a user action or API call?                       │
│  └─▶ YES: Use Manual("trigger-id")                                  │
│                                                                      │
│  Is it triggered by an incoming webhook?                             │
│  └─▶ YES: Use Webhook (see Webhook section)                         │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

## Webhook Triggers

For HTTP webhook-initiated flows, Resolute provides a webhook server:

```go
flow := core.NewFlow("github-webhook").
    TriggeredBy(core.Webhook("/github", "POST").
        WithSecret(os.Getenv("WEBHOOK_SECRET"))).
    Then(handleWebhookNode).
    Build()

core.NewWorker().
    WithConfig(config).
    WithFlow(flow).
    WithWebhookServer(":8080").  // Enable webhook server
    Run()
```

The webhook server:
- Listens on the configured address
- Validates HMAC signatures (if secret configured)
- Starts workflow executions on valid requests
- Returns workflow ID in response

## Multiple Triggers

Currently, each flow supports exactly one trigger. For flows that need multiple trigger methods, create separate flows that call shared logic:

```go
// Shared sync logic as a node
syncNode := core.NewNode("sync", syncData, SyncInput{})

// Manual trigger version
manualFlow := core.NewFlow("sync-manual").
    TriggeredBy(core.Manual("api")).
    Then(syncNode).
    Build()

// Scheduled version
scheduledFlow := core.NewFlow("sync-scheduled").
    TriggeredBy(core.Schedule("0 * * * *")).
    Then(syncNode).
    Build()

// Both flows share the same sync logic
worker := core.NewWorker().
    WithConfig(config).
    WithFlow(manualFlow).
    WithFlow(scheduledFlow).
    Run()
```

## Trigger Interface

All triggers implement the `Trigger` interface:

```go
type Trigger interface {
    Type() TriggerType
    Config() TriggerConfig
}
```

This allows flows to work with any trigger type polymorphically.

## Best Practices

### 1. Use Appropriate Schedule Granularity

Don't schedule more frequently than necessary:

```go
// If data changes daily, don't sync every minute
core.Schedule("0 2 * * *")  // Daily at 2 AM

// If near-real-time is needed, consider signals instead
core.Signal("data-updated")
```

### 2. Consider Time Zones

Cron schedules run in the Temporal server's time zone (usually UTC):

```go
// This runs at 2 AM UTC, not local time
core.Schedule("0 2 * * *")

// For local time, adjust accordingly
// 2 AM PST = 10 AM UTC
core.Schedule("0 10 * * *")  // 2 AM PST
```

### 3. Handle Signal Data

When using signals, validate incoming data:

```go
func handleEvent(ctx context.Context, input EventInput) (EventOutput, error) {
    if input.EventType == "" {
        return EventOutput{}, fmt.Errorf("missing event type")
    }
    // Process event...
}
```

### 4. Use Meaningful Trigger IDs

Trigger IDs appear in logs and the Temporal UI:

```go
// Good: Descriptive
core.Manual("sync-jira-issues")
core.Signal("order-created")

// Avoid: Generic
core.Manual("api")
core.Signal("event")
```

## Relationship to Temporal

| Resolute Trigger | Temporal Feature |
|------------------|------------------|
| Manual | Direct workflow execution |
| Schedule | Temporal Schedule |
| Signal | Workflow signal |
| Webhook | External HTTP → Workflow execution |

Resolute triggers map to native Temporal features. Schedule triggers use Temporal's built-in scheduler, ensuring reliability even if workers restart.

## See Also

- **[Flows](/docs/concepts/flows/)** - How triggers are attached to flows
- **[Workers](/docs/concepts/workers/)** - Webhook server configuration
- **[Deployment](/docs/guides/deployment/worker-configuration/)** - Production trigger setup
