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

Implement health endpoints for orchestrators:

```go
package main

import (
    "net/http"
    "sync/atomic"

    "github.com/resolute/resolute/core"
)

var healthy int32 = 1

func main() {
    // Health endpoint
    http.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
        if atomic.LoadInt32(&healthy) == 1 {
            w.WriteHeader(http.StatusOK)
            w.Write([]byte("ok"))
        } else {
            w.WriteHeader(http.StatusServiceUnavailable)
        }
    })
    go http.ListenAndServe(":8081", nil)

    // Run worker
    err := core.NewWorker().
        WithConfig(cfg).
        WithFlow(flow).
        Run()

    atomic.StoreInt32(&healthy, 0)
    if err != nil {
        log.Fatal(err)
    }
}
```

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

### Environment-Based Configuration

```go
package main

import (
    "os"
    "strconv"

    "github.com/resolute/resolute/core"
)

func configFromEnv() core.WorkerConfig {
    maxConcurrent := 50
    if v := os.Getenv("WORKER_MAX_CONCURRENT"); v != "" {
        if n, err := strconv.Atoi(v); err == nil {
            maxConcurrent = n
        }
    }

    return core.WorkerConfig{
        TaskQueue:     os.Getenv("TASK_QUEUE"),
        TemporalHost:  os.Getenv("TEMPORAL_HOST"),
        Namespace:     os.Getenv("TEMPORAL_NAMESPACE"),
        MaxConcurrent: maxConcurrent,
    }
}

func main() {
    err := core.NewWorker().
        WithConfig(configFromEnv()).
        WithFlow(flow).
        Run()

    if err != nil {
        log.Fatal(err)
    }
}
```

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

## See Also

- **[Temporal Cloud](/docs/guides/deployment/temporal-cloud/)** - Cloud deployment
- **[Self-Hosted](/docs/guides/deployment/self-hosted/)** - Self-hosted deployment
- **[Workers](/docs/concepts/workers/)** - Worker concepts
- **[Provider Registration](/docs/guides/providers/registering-activities/)** - Activity registration
