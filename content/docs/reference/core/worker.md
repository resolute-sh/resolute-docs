---
title: "Worker"
description: "Worker - Resolute documentation"
weight: 50
toc: true
---


# Worker

The Worker API provides a fluent builder for constructing and running Temporal workers with Resolute flows.

## Types

### WorkerConfig

```go
type WorkerConfig struct {
    TemporalHost  string  // Default: TEMPORAL_HOST env or "localhost:7233"
    TaskQueue     string  // Required - no default
    Namespace     string  // Default: TEMPORAL_NAMESPACE env or "default"
    MaxConcurrent int     // Default: 0 (unlimited)
}
```

Configuration for connecting to Temporal and running the worker.

### WorkerBuilder

```go
type WorkerBuilder struct {
    // unexported fields
}
```

Fluent API for constructing and running workers.

## Constructor

### NewWorker

```go
func NewWorker() *WorkerBuilder
```

Creates a new worker builder with environment defaults loaded.

**Returns:** `*WorkerBuilder` for method chaining

**Example:**
```go
worker := core.NewWorker()
```

## WorkerConfig Methods

### Validate

```go
func (c *WorkerConfig) Validate() error
```

Checks that required fields are set.

**Returns:** Error if TaskQueue is empty

## WorkerBuilder Methods

### WithConfig

```go
func (b *WorkerBuilder) WithConfig(cfg WorkerConfig) *WorkerBuilder
```

Sets the worker configuration. Empty fields are populated from environment variables or defaults.

**Parameters:**
- `cfg` - Worker configuration

**Returns:** `*WorkerBuilder` for method chaining

**Example:**
```go
worker := core.NewWorker().
    WithConfig(core.WorkerConfig{
        TaskQueue:     "my-queue",
        TemporalHost:  "localhost:7233",
        Namespace:     "production",
        MaxConcurrent: 50,
    })
```

### WithFlow

```go
func (b *WorkerBuilder) WithFlow(f *Flow) *WorkerBuilder
```

Sets the flow to be executed by this worker.

**Parameters:**
- `f` - Flow to register

**Returns:** `*WorkerBuilder` for method chaining

**Example:**
```go
worker := core.NewWorker().
    WithConfig(cfg).
    WithFlow(myFlow)
```

### WithProviders

```go
func (b *WorkerBuilder) WithProviders(providers ...Provider) *WorkerBuilder
```

Adds providers whose activities will be registered with the worker.

**Parameters:**
- `providers` - One or more providers

**Returns:** `*WorkerBuilder` for method chaining

**Example:**
```go
worker := core.NewWorker().
    WithConfig(cfg).
    WithFlow(myFlow).
    WithProviders(
        jira.Provider(),
        slack.Provider(),
        github.Provider(),
    )
```

### WithWebhookServer

```go
func (b *WorkerBuilder) WithWebhookServer(addr string) *WorkerBuilder
```

Enables the webhook server on the specified address. If the flow has a webhook trigger, incoming webhooks will start workflow executions.

**Parameters:**
- `addr` - Server address (e.g., ":8080")

**Returns:** `*WorkerBuilder` for method chaining

**Example:**
```go
worker := core.NewWorker().
    WithConfig(cfg).
    WithFlow(webhookFlow).
    WithWebhookServer(":8080")
```

### WithHealthServer

```go
func (b *WorkerBuilder) WithHealthServer(addr string) *WorkerBuilder
```

Enables Kubernetes-compatible health endpoints on the specified address. Provides `/health/live`, `/health/ready`, and `/health/startup` endpoints.

**Parameters:**
- `addr` - Server address (e.g., ":8081")

**Returns:** `*WorkerBuilder` for method chaining

**Example:**
```go
worker := core.NewWorker().
    WithConfig(cfg).
    WithFlow(flow).
    WithHealthServer(":8081")
```

### WithMetrics

```go
func (b *WorkerBuilder) WithMetrics(exporter MetricsExporter) *WorkerBuilder
```

Enables metrics collection with the provided exporter. Metrics are recorded for flow executions, activity durations, errors, and rate limiting.

**Parameters:**
- `exporter` - Metrics exporter implementation (e.g., `core.NewPrometheusExporter()`)

**Returns:** `*WorkerBuilder` for method chaining

**Example:**
```go
worker := core.NewWorker().
    WithConfig(cfg).
    WithFlow(flow).
    WithMetrics(core.NewPrometheusExporter())
```

### Build

```go
func (b *WorkerBuilder) Build() error
```

Creates the Temporal client and worker without starting them. Useful for testing or custom lifecycle management.

**Returns:** Error if configuration invalid or connection fails

**Example:**
```go
worker := core.NewWorker().
    WithConfig(cfg).
    WithFlow(flow)

if err := worker.Build(); err != nil {
    log.Fatal(err)
}

// Access underlying objects
client := worker.Client()
temporalWorker := worker.Worker()
```

### Run

```go
func (b *WorkerBuilder) Run() error
```

Builds and runs the worker, blocking until interrupted. This is the typical entry point for a worker process.

**Returns:** Error if startup or execution fails

**Example:**
```go
err := core.NewWorker().
    WithConfig(core.WorkerConfig{
        TaskQueue: "my-queue",
    }).
    WithFlow(myFlow).
    WithProviders(jira.Provider()).
    Run()

if err != nil {
    log.Fatal(err)
}
```

### RunAsync

```go
func (b *WorkerBuilder) RunAsync() (shutdown func(), err error)
```

Builds and starts the worker in the background. Returns a shutdown function for graceful termination.

**Returns:**
- `shutdown` - Function to call for graceful shutdown
- `err` - Error if startup fails

**Example:**
```go
worker := core.NewWorker().
    WithConfig(cfg).
    WithFlow(flow)

shutdown, err := worker.RunAsync()
if err != nil {
    log.Fatal(err)
}
defer shutdown()

// Do other work...

// Wait for signal
<-make(chan os.Signal, 1)
```

### Client

```go
func (b *WorkerBuilder) Client() client.Client
```

Returns the underlying Temporal client after `Build()` has been called.

**Returns:** `client.Client` or nil if `Build()` not called

### Worker

```go
func (b *WorkerBuilder) Worker() worker.Worker
```

Returns the underlying Temporal worker after `Build()` has been called.

**Returns:** `worker.Worker` or nil if `Build()` not called

### WebhookServer

```go
func (b *WorkerBuilder) WebhookServer() *WebhookServer
```

Returns the webhook server if configured.

**Returns:** `*WebhookServer` or nil if not enabled or `Build()` not called

### HealthServer

```go
func (b *WorkerBuilder) HealthServer() *HealthServer
```

Returns the health server if configured.

**Returns:** `*HealthServer` or nil if not enabled or `Build()` not called

## Schedule Auto-Creation

When a flow has a `core.Schedule(...)` trigger, the worker automatically creates or updates a Temporal Schedule on startup. If the schedule already exists, it updates the cron expression and action. The schedule ID is derived from the flow name (`<flow-name>-schedule`). Overlap policy is set to Skip (concurrent runs are not started if one is already in progress).

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `TEMPORAL_HOST` | Temporal server address | `localhost:7233` |
| `TEMPORAL_NAMESPACE` | Temporal namespace | `default` |

## Usage Patterns

### Basic Worker

```go
func main() {
    err := core.NewWorker().
        WithConfig(core.WorkerConfig{
            TaskQueue: "my-queue",
        }).
        WithFlow(myFlow).
        WithProviders(myProvider).
        Run()

    if err != nil {
        log.Fatal(err)
    }
}
```

### Worker with Webhook Server

```go
func main() {
    err := core.NewWorker().
        WithConfig(core.WorkerConfig{
            TaskQueue: "webhooks",
        }).
        WithFlow(webhookFlow).
        WithWebhookServer(":8080").
        Run()

    if err != nil {
        log.Fatal(err)
    }
}
```

### Worker with Health and Metrics

```go
func main() {
    err := core.NewWorker().
        WithConfig(core.WorkerConfig{
            TaskQueue: "my-queue",
        }).
        WithFlow(myFlow).
        WithProviders(myProvider).
        WithHealthServer(":8081").
        WithMetrics(core.NewPrometheusExporter()).
        Run()

    if err != nil {
        log.Fatal(err)
    }
}
```

### Multiple Providers

```go
func main() {
    // Configure providers
    jiraProvider := jira.NewProvider(jira.Config{
        BaseURL:  os.Getenv("JIRA_BASE_URL"),
        APIToken: os.Getenv("JIRA_API_TOKEN"),
    })

    slackProvider := slack.NewProvider(slack.Config{
        Token: os.Getenv("SLACK_TOKEN"),
    })

    // Run worker
    err := core.NewWorker().
        WithConfig(core.WorkerConfig{
            TaskQueue: "notifications",
        }).
        WithFlow(notificationFlow).
        WithProviders(jiraProvider, slackProvider).
        Run()

    if err != nil {
        log.Fatal(err)
    }
}
```

### Custom Lifecycle

```go
func main() {
    worker := core.NewWorker().
        WithConfig(cfg).
        WithFlow(flow)

    if err := worker.Build(); err != nil {
        log.Fatal(err)
    }

    // Access Temporal primitives
    c := worker.Client()
    w := worker.Worker()

    // Register additional workflows
    w.RegisterWorkflow(anotherWorkflow)

    // Custom startup logic
    log.Println("Starting worker...")

    // Run with custom interrupt handling
    if err := w.Run(worker.InterruptCh()); err != nil {
        log.Fatal(err)
    }

    c.Close()
}
```

### Background Worker with Shutdown

```go
func main() {
    worker := core.NewWorker().
        WithConfig(cfg).
        WithFlow(flow)

    shutdown, err := worker.RunAsync()
    if err != nil {
        log.Fatal(err)
    }

    // Handle shutdown signal
    sigCh := make(chan os.Signal, 1)
    signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)

    <-sigCh
    log.Println("Shutting down...")
    shutdown()
}
```

## Complete Example

```go
package main

import (
    "log"
    "os"
    "os/signal"
    "syscall"

    "github.com/resolute/resolute/core"
    "myapp/flows"
    "myapp/providers/jira"
    "myapp/providers/slack"
)

func main() {
    // Load configuration
    cfg := core.WorkerConfig{
        TemporalHost:  os.Getenv("TEMPORAL_HOST"),
        Namespace:     os.Getenv("TEMPORAL_NAMESPACE"),
        TaskQueue:     os.Getenv("TASK_QUEUE"),
        MaxConcurrent: 50,
    }

    // Configure providers
    jiraProvider := jira.NewProvider(jira.Config{
        BaseURL:  os.Getenv("JIRA_BASE_URL"),
        Email:    os.Getenv("JIRA_EMAIL"),
        APIToken: os.Getenv("JIRA_API_TOKEN"),
    })

    slackProvider := slack.NewProvider(slack.Config{
        Token: os.Getenv("SLACK_TOKEN"),
    })

    // Build and run worker
    err := core.NewWorker().
        WithConfig(cfg).
        WithFlow(flows.DataSyncFlow).
        WithProviders(jiraProvider, slackProvider).
        WithWebhookServer(":8080").
        WithHealthServer(":8081").
        WithMetrics(core.NewPrometheusExporter()).
        Run()

    if err != nil {
        log.Fatal(err)
    }
}
```

## See Also

- **[Flow](/docs/reference/core/flow/)** - Flow builder
- **[Providers](/docs/reference/providers/jira/)** - Provider reference
- **[Worker Configuration](/docs/guides/deployment/worker-configuration/)** - Deployment guide
- **[Temporal Cloud](/docs/guides/deployment/temporal-cloud/)** - Cloud deployment
