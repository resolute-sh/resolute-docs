---
title: "Worker Configuration"
description: "Worker Configuration - Resolute documentation"
weight: 10
toc: true
---


# Worker Configuration

Workers execute workflows and activities. This guide covers configuration options for production deployments.

## WorkerBuilder

Resolute provides a fluent builder for worker configuration:

```go
package main

import (
    "log"

    "github.com/resolute/resolute/core"

    "myapp/flows"
    "myapp/providers/jira"
    "myapp/providers/slack"
)

func main() {
    err := core.NewWorker().
        WithConfig(core.WorkerConfig{
            TaskQueue:     "data-sync",
            TemporalHost:  "localhost:7233",
            Namespace:     "production",
            MaxConcurrent: 50,
        }).
        WithFlow(flows.DataSyncFlow).
        WithProviders(
            jira.Provider(),
            slack.Provider(),
        ).
        Run()

    if err != nil {
        log.Fatal(err)
    }
}
```

## Configuration Options

### WorkerConfig

```go
type WorkerConfig struct {
    // TemporalHost is the Temporal server address.
    // Default: TEMPORAL_HOST env or "localhost:7233"
    TemporalHost string

    // TaskQueue identifies the work this worker handles.
    // Required - no default.
    TaskQueue string

    // Namespace partitions workflows in Temporal.
    // Default: TEMPORAL_NAMESPACE env or "default"
    Namespace string

    // MaxConcurrent limits concurrent activity executions.
    // Default: 0 (unlimited)
    MaxConcurrent int
}
```

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `TEMPORAL_HOST` | Temporal server address | `localhost:7233` |
| `TEMPORAL_NAMESPACE` | Temporal namespace | `default` |

```go
// Config loads from environment automatically
err := core.NewWorker().
    WithConfig(core.WorkerConfig{
        TaskQueue: "my-queue",
        // TemporalHost and Namespace loaded from env
    }).
    Run()
```

## Builder Methods

### WithConfig

Sets worker configuration:

```go
worker := core.NewWorker().
    WithConfig(core.WorkerConfig{
        TaskQueue:     "my-queue",
        TemporalHost:  "temporal.example.com:7233",
        Namespace:     "production",
        MaxConcurrent: 100,
    })
```

### WithFlow

Registers a flow (workflow) with the worker:

```go
worker := core.NewWorker().
    WithConfig(cfg).
    WithFlow(myFlow)
```

### WithProviders

Registers provider activities:

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

Enables HTTP server for webhook triggers:

```go
worker := core.NewWorker().
    WithConfig(cfg).
    WithFlow(webhookTriggeredFlow).
    WithWebhookServer(":8080")
```

## Lifecycle Methods

### Run (Blocking)

Starts the worker and blocks until interrupted:

```go
func main() {
    err := core.NewWorker().
        WithConfig(cfg).
        WithFlow(flow).
        Run()

    if err != nil {
        log.Fatal(err)
    }
}
```

### RunAsync (Non-Blocking)

Starts the worker in the background:

```go
func main() {
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
}
```

### Build (Manual Lifecycle)

Creates client and worker without starting:

```go
func main() {
    worker := core.NewWorker().
        WithConfig(cfg).
        WithFlow(flow)

    if err := worker.Build(); err != nil {
        log.Fatal(err)
    }

    // Access underlying Temporal objects
    client := worker.Client()
    temporalWorker := worker.Worker()

    // Custom startup logic...
    temporalWorker.Run(worker.InterruptCh())
}
```

## Production Configuration

### Concurrency Tuning

```go
cfg := core.WorkerConfig{
    TaskQueue:     "high-throughput",
    MaxConcurrent: 100, // Tune based on activity characteristics
}
```

Consider:
- **CPU-bound activities**: Lower concurrency (matches cores)
- **I/O-bound activities**: Higher concurrency (10x-100x cores)
- **Memory-intensive**: Limit based on available RAM
- **External rate limits**: Match provider API limits

### Multiple Task Queues

Run specialized workers for different workloads:

```go
// High-priority worker
go func() {
    core.NewWorker().
        WithConfig(core.WorkerConfig{
            TaskQueue:     "priority-high",
            MaxConcurrent: 10,
        }).
        WithFlow(criticalFlow).
        Run()
}()

// Bulk processing worker
go func() {
    core.NewWorker().
        WithConfig(core.WorkerConfig{
            TaskQueue:     "bulk-processing",
            MaxConcurrent: 100,
        }).
        WithFlow(bulkFlow).
        Run()
}()
```

### Graceful Shutdown

Workers handle SIGINT/SIGTERM automatically:

```go
// Run() blocks until interrupt signal
err := core.NewWorker().
    WithConfig(cfg).
    WithFlow(flow).
    Run()
// Worker drains in-flight work before exiting
```

For custom shutdown handling:

```go
shutdown, err := worker.RunAsync()
if err != nil {
    log.Fatal(err)
}

// Custom signal handling
sigCh := make(chan os.Signal, 1)
signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)
<-sigCh

log.Println("Shutting down gracefully...")
shutdown() // Drains in-flight work
```

## Accessing Underlying Objects

After `Build()` or `Run()`, access Temporal primitives:

```go
worker := core.NewWorker().
    WithConfig(cfg).
    WithFlow(flow)

if err := worker.Build(); err != nil {
    log.Fatal(err)
}

// Temporal client for starting workflows programmatically
client := worker.Client()

// Temporal worker for advanced configuration
temporalWorker := worker.Worker()

// Webhook server if enabled
webhookServer := worker.WebhookServer()
```

## Health Checks

Use `WithHealthServer` to enable Kubernetes-compatible health endpoints:

```go
err := core.NewWorker().
    WithConfig(cfg).
    WithFlow(flow).
    WithHealthServer(":8081").
    Run()
```

This starts three endpoints:

| Endpoint | Purpose | K8s Probe |
|----------|---------|-----------|
| `/health/live` | Process is alive | `livenessProbe` |
| `/health/ready` | Worker is accepting work | `readinessProbe` |
| `/health/startup` | Worker has started | `startupProbe` |

All endpoints return JSON with `status` and `timestamp` fields. The ready and startup probes return `503 Service Unavailable` until the worker has fully initialized.

## Metrics

Enable Prometheus metrics with `WithMetrics`:

```go
err := core.NewWorker().
    WithConfig(cfg).
    WithFlow(flow).
    WithMetrics(core.NewPrometheusExporter()).
    Run()
```

Exported metrics:

| Metric | Type | Labels | Description |
|--------|------|--------|-------------|
| `resolute_flow_executions_total` | Counter | `flow`, `status` | Total flow executions |
| `resolute_flow_duration_seconds` | Histogram | `flow` | Flow execution duration |
| `resolute_activity_duration_seconds` | Histogram | `node` | Activity execution duration |
| `resolute_activity_errors_total` | Counter | `node`, `error_type` | Activity errors by type |
| `resolute_rate_limiter_wait_seconds` | Histogram | `limiter` | Rate limiter wait time |
| `resolute_state_operations_total` | Counter | `operation` | State backend operations |

## Logging

Workers log key events automatically:

```
Starting worker for task queue: data-sync (host: localhost:7233, namespace: default)
Starting webhook server on :8080
```

For structured logging, configure Temporal SDK:

```go
import (
    "go.temporal.io/sdk/client"
    "log/slog"
)

// Custom logger adapter
type slogAdapter struct {
    logger *slog.Logger
}

func (a *slogAdapter) Debug(msg string, keyvals ...interface{}) {
    a.logger.Debug(msg, keyvals...)
}
// ... implement other methods

// Use with Temporal client
c, err := client.Dial(client.Options{
    Logger: &slogAdapter{logger: slog.Default()},
})
```

## Common Patterns

### Typed Configuration with LoadConfig

Use `core.LoadConfig[T]` to load configuration from environment variables with validation:

```go
type JiraConfig struct {
    BaseURL  string `env:"BASE_URL" required:"true"`
    Email    string `env:"EMAIL" required:"true"`
    APIToken string `env:"API_TOKEN" required:"true"`
    Project  string `env:"PROJECT" required:"true"`
    PageSize int    `env:"PAGE_SIZE" default:"100"`
}

cfg, err := core.LoadConfig[JiraConfig]("JIRA")
// Reads: JIRA_BASE_URL, JIRA_EMAIL, JIRA_API_TOKEN, JIRA_PROJECT, JIRA_PAGE_SIZE
```

Supported struct tags:
- `env:"VAR_NAME"` — environment variable suffix (PREFIX_VAR_NAME)
- `required:"true"` — fail if the variable is not set
- `default:"value"` — fallback when the variable is not set

Supported field types: `string`, `int`, `int64`, `bool`, `float64`, `time.Duration`

### Multiple Flows Per Worker

```go
// Register multiple workflows with underlying worker
worker := core.NewWorker().
    WithConfig(cfg)

if err := worker.Build(); err != nil {
    log.Fatal(err)
}

// Register additional workflows
worker.Worker().RegisterWorkflow(flow1.Execute)
worker.Worker().RegisterWorkflow(flow2.Execute)
worker.Worker().RegisterWorkflow(flow3.Execute)

worker.Worker().Run(worker.InterruptCh())
```

### Provider Configuration

```go
// Configure providers with credentials
jiraProvider := jira.NewProvider(jira.Config{
    BaseURL:  os.Getenv("JIRA_BASE_URL"),
    Email:    os.Getenv("JIRA_EMAIL"),
    APIToken: os.Getenv("JIRA_API_TOKEN"),
})

slackProvider := slack.NewProvider(slack.Config{
    Token: os.Getenv("SLACK_TOKEN"),
})

err := core.NewWorker().
    WithConfig(cfg).
    WithFlow(flow).
    WithProviders(jiraProvider, slackProvider).
    Run()
```

## Kubernetes Deployment

A Helm chart is available for deploying workers to Kubernetes. See the `flows/knowledge-ingestion/deploy` directory for a reference implementation.

### Deployment with Helm

```bash
# Default values
helm upgrade --install my-worker ./deploy

# Production overrides
helm upgrade --install my-worker ./deploy -f ./deploy/values-production.yaml
```

The Helm chart supports:
- Configurable image, resources, and replica count
- ConfigMap for non-sensitive configuration
- Secret management (inline or external `existingSecret`)
- PersistentVolumeClaim for state storage
- Health probe configuration pointing to the health server

### Production Worker Example

```go
func main() {
    cfg, err := LoadFlowConfig()
    if err != nil {
        log.Fatalf("config: %v", err)
    }

    err = core.NewWorker().
        WithConfig(core.WorkerConfig{TaskQueue: "my-queue"}).
        WithFlow(BuildFlow(cfg)).
        WithProviders(myProviders...).
        WithHealthServer(":8081").
        WithMetrics(core.NewPrometheusExporter()).
        Run()

    if err != nil {
        log.Fatalf("worker: %v", err)
    }
}
```

## See Also

- **[Temporal Cloud](/docs/guides/deployment/temporal-cloud/)** - Cloud deployment
- **[Self-Hosted](/docs/guides/deployment/self-hosted/)** - Self-hosted deployment
- **[Workers](/docs/concepts/workers/)** - Worker concepts
- **[Provider Registration](/docs/guides/providers/registering-activities/)** - Activity registration
