---
title: "Workers"
description: "Workers - Resolute documentation"
weight: 70
toc: true
---


# Workers

A **Worker** executes flows by connecting to Temporal and processing tasks from a queue. Workers are the runtime component that brings flows to life.

## What is a Worker?

A Worker:
- Connects to a Temporal server via gRPC
- Registers flows as Temporal workflows
- Registers provider activities
- Polls a task queue for work
- Executes activities when tasks arrive

```go
core.NewWorker().
    WithConfig(core.WorkerConfig{
        TaskQueue:    "my-queue",
        TemporalHost: "localhost:7233",
    }).
    WithFlow(myFlow).
    WithProviders(jiraProvider).
    Run()
```

## Worker Configuration

### WorkerConfig Options

```go
type WorkerConfig struct {
    TemporalHost  string // Temporal server address
    TaskQueue     string // Task queue name (required)
    Namespace     string // Temporal namespace
    MaxConcurrent int    // Max concurrent activities
}
```

| Option | Description | Default |
|--------|-------------|---------|
| `TemporalHost` | Temporal server address | `TEMPORAL_HOST` env or `localhost:7233` |
| `TaskQueue` | Task queue name | **Required** |
| `Namespace` | Temporal namespace | `TEMPORAL_NAMESPACE` env or `default` |
| `MaxConcurrent` | Maximum concurrent activity executions | 0 (unlimited) |

### Environment Variables

Workers automatically read these environment variables:

```bash
export TEMPORAL_HOST="temporal.example.com:7233"
export TEMPORAL_NAMESPACE="production"
```

```go
// Config will use env vars if fields are empty
worker := core.NewWorker().
    WithConfig(core.WorkerConfig{
        TaskQueue: "my-queue",
        // TemporalHost and Namespace read from env
    })
```

## WorkerBuilder API

The `WorkerBuilder` provides a fluent API for configuration:

```go
worker := core.NewWorker().
    WithConfig(config).           // Set configuration
    WithFlow(flow1).              // Register a flow
    WithFlow(flow2).              // Register another flow
    WithProviders(provider1, provider2). // Register providers
    WithWebhookServer(":8080").   // Enable webhook server
    Run()                         // Start (blocking)
```

### Methods

| Method | Description |
|--------|-------------|
| `NewWorker()` | Create a new worker builder |
| `.WithConfig(cfg)` | Set worker configuration |
| `.WithFlow(flow)` | Register a flow |
| `.WithProviders(...providers)` | Register providers |
| `.WithWebhookServer(addr)` | Enable webhook HTTP server |
| `.Build()` | Build without starting (for testing) |
| `.Run()` | Build and run (blocking) |
| `.RunAsync()` | Build and run (non-blocking) |
| `.Client()` | Get Temporal client (after Build) |
| `.Worker()` | Get Temporal worker (after Build) |

## Running Workers

### Blocking Mode

`Run()` starts the worker and blocks until interrupted:

```go
func main() {
    worker := core.NewWorker().
        WithConfig(config).
        WithFlow(myFlow).
        Run()  // Blocks here

    // Never reached unless worker stops
}
```

Stop with `Ctrl+C` or `SIGINT`.

### Non-Blocking Mode

`RunAsync()` starts the worker in the background:

```go
shutdown, err := core.NewWorker().
    WithConfig(config).
    WithFlow(myFlow).
    RunAsync()

if err != nil {
    log.Fatal(err)
}

// Do other work...

// When done, shutdown gracefully
shutdown()
```

### Build Without Running

Use `Build()` for testing or custom lifecycle:

```go
builder := core.NewWorker().
    WithConfig(config).
    WithFlow(myFlow)

if err := builder.Build(); err != nil {
    log.Fatal(err)
}

// Access internals
client := builder.Client()
worker := builder.Worker()

// Manual control
worker.Start()
// ...
worker.Stop()
client.Close()
```

## Registering Flows

Register one or more flows with a worker:

```go
syncFlow := core.NewFlow("sync").
    TriggeredBy(core.Schedule("*/15 * * * *")).
    Then(syncNode).
    Build()

processFlow := core.NewFlow("process").
    TriggeredBy(core.Manual("api")).
    Then(processNode).
    Build()

core.NewWorker().
    WithConfig(config).
    WithFlow(syncFlow).
    WithFlow(processFlow).
    Run()
```

Each flow becomes a registered Temporal workflow type.

## Registering Providers

Providers register their activities with the worker:

```go
core.NewWorker().
    WithConfig(config).
    WithFlow(myFlow).
    WithProviders(
        jira.NewProvider(jiraConfig),
        ollama.NewProvider(ollamaConfig),
        qdrant.NewProvider(qdrantConfig),
    ).
    Run()
```

Activities from all providers are registered before the worker starts polling.

## Webhook Server

Enable HTTP webhooks to trigger flows:

```go
webhookFlow := core.NewFlow("webhook-handler").
    TriggeredBy(core.Webhook("/events", "POST")).
    Then(handleEventNode).
    Build()

core.NewWorker().
    WithConfig(config).
    WithFlow(webhookFlow).
    WithWebhookServer(":8080").  // Listen on port 8080
    Run()
```

The webhook server:
- Starts alongside the Temporal worker
- Routes requests to matching flows
- Validates signatures (if configured)
- Returns workflow IDs in responses

## Worker Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                           Worker Process                             │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │                     Temporal Worker                          │    │
│  │                                                              │    │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐       │    │
│  │  │   Flow 1     │  │   Flow 2     │  │   Flow 3     │       │    │
│  │  │  (workflow)  │  │  (workflow)  │  │  (workflow)  │       │    │
│  │  └──────────────┘  └──────────────┘  └──────────────┘       │    │
│  │                                                              │    │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐       │    │
│  │  │  Provider 1  │  │  Provider 2  │  │  Provider 3  │       │    │
│  │  │ (activities) │  │ (activities) │  │ (activities) │       │    │
│  │  └──────────────┘  └──────────────┘  └──────────────┘       │    │
│  │                                                              │    │
│  └───────────────────────────────┬──────────────────────────────┘    │
│                                  │                                   │
│  ┌───────────────────────────────┼───────────────────────────────┐  │
│  │              Webhook Server (optional)                         │  │
│  │                      :8080                                     │  │
│  └───────────────────────────────┼───────────────────────────────┘  │
│                                  │                                   │
└──────────────────────────────────┼───────────────────────────────────┘
                                   │ gRPC
                                   ▼
┌─────────────────────────────────────────────────────────────────────┐
│                        Temporal Server                               │
│                                                                      │
│   Task Queue: "my-queue"                                            │
│   ┌─────────┐  ┌─────────┐  ┌─────────┐                            │
│   │ Task 1  │  │ Task 2  │  │ Task 3  │  ...                       │
│   └─────────┘  └─────────┘  └─────────┘                            │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

## Multiple Workers

Run multiple workers for scalability:

```go
// Worker 1 (process A)
core.NewWorker().
    WithConfig(core.WorkerConfig{
        TaskQueue: "my-queue",
    }).
    WithFlow(myFlow).
    Run()

// Worker 2 (process B, same queue)
core.NewWorker().
    WithConfig(core.WorkerConfig{
        TaskQueue: "my-queue",
    }).
    WithFlow(myFlow).
    Run()
```

Temporal distributes tasks across workers on the same queue.

### Horizontal Scaling

```
┌─────────────┐  ┌─────────────┐  ┌─────────────┐
│  Worker 1   │  │  Worker 2   │  │  Worker 3   │
│  (Pod A)    │  │  (Pod B)    │  │  (Pod C)    │
└──────┬──────┘  └──────┬──────┘  └──────┬──────┘
       │                │                │
       └────────────────┼────────────────┘
                        │
                        ▼
              ┌──────────────────┐
              │  Temporal Server │
              │                  │
              │  Task Queue:     │
              │  "my-queue"      │
              └──────────────────┘
```

## Concurrency Control

Limit concurrent activity executions:

```go
core.NewWorker().
    WithConfig(core.WorkerConfig{
        TaskQueue:     "my-queue",
        MaxConcurrent: 10,  // Max 10 concurrent activities
    }).
    WithFlow(myFlow).
    Run()
```

Use this to:
- Prevent overwhelming external APIs
- Control resource usage
- Match rate limits

## Graceful Shutdown

Workers handle shutdown gracefully:

1. Stop accepting new tasks
2. Wait for in-flight activities to complete
3. Close Temporal connection

```go
// Run() responds to SIGINT/SIGTERM
core.NewWorker().
    WithConfig(config).
    WithFlow(myFlow).
    Run()  // Ctrl+C triggers graceful shutdown

// RunAsync() provides shutdown function
shutdown, _ := core.NewWorker().
    WithConfig(config).
    WithFlow(myFlow).
    RunAsync()

// Later...
shutdown()  // Triggers graceful shutdown
```

## Error Handling

### Configuration Errors

```go
err := core.NewWorker().
    WithConfig(core.WorkerConfig{
        // Missing TaskQueue
    }).
    Run()

// err: "invalid config: TaskQueue is required"
```

### Connection Errors

```go
err := core.NewWorker().
    WithConfig(core.WorkerConfig{
        TaskQueue:    "my-queue",
        TemporalHost: "invalid-host:7233",
    }).
    Run()

// err: "dial temporal: ..."
```

## Best Practices

### 1. Use Dedicated Task Queues

Separate queues for different workloads:

```go
// High-priority queue
core.NewWorker().
    WithConfig(core.WorkerConfig{TaskQueue: "critical-queue"}).
    WithFlow(criticalFlow).
    Run()

// Background queue
core.NewWorker().
    WithConfig(core.WorkerConfig{TaskQueue: "background-queue"}).
    WithFlow(backgroundFlow).
    Run()
```

### 2. Configure for Production

```go
core.NewWorker().
    WithConfig(core.WorkerConfig{
        TemporalHost:  os.Getenv("TEMPORAL_HOST"),
        TaskQueue:     "production-queue",
        Namespace:     "production",
        MaxConcurrent: 20,
    }).
    WithFlow(myFlow).
    Run()
```

### 3. Health Checks

Access the underlying worker for health checks:

```go
builder := core.NewWorker().WithConfig(config).WithFlow(flow)
builder.Build()

// Use in health endpoint
func healthHandler(w http.ResponseWriter, r *http.Request) {
    if builder.Worker() != nil {
        w.WriteHeader(http.StatusOK)
    } else {
        w.WriteHeader(http.StatusServiceUnavailable)
    }
}
```

### 4. Log Configuration

Workers log on startup:

```
Starting worker for task queue: my-queue (host: localhost:7233, namespace: default)
```

Ensure your logging captures this for debugging.

## Relationship to Temporal

| Resolute | Temporal |
|----------|----------|
| `WorkerBuilder` | `worker.New()` + configuration |
| `WithFlow()` | `RegisterWorkflow()` |
| `WithProviders()` | `RegisterActivity()` for each activity |
| `Run()` | `worker.Run(worker.InterruptCh())` |
| `TaskQueue` | Temporal task queue |

## See Also

- **[Flows](/docs/concepts/flows/)** - What workers execute
- **[Providers](/docs/concepts/providers/)** - Activities workers register
- **[Deployment](/docs/guides/deployment/worker-configuration/)** - Production setup
- **[Temporal Cloud](/docs/guides/deployment/temporal-cloud/)** - Cloud deployment
