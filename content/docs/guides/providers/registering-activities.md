---
title: "Registering Activities"
description: "Registering Activities - Resolute documentation"
weight: 20
toc: true
---


# Registering Activities

Activities must be registered with Temporal workers before they can be used in workflows. This guide covers the different approaches to activity registration.

## Registration Overview

```
┌─────────────┐     ┌──────────────┐     ┌────────────────┐
│  Provider   │────▶│   Registry   │────▶│ Temporal Worker│
│ (Activities)│     │ (Organizes)  │     │ (Executes)     │
└─────────────┘     └──────────────┘     └────────────────┘
```

## Direct Registration

The simplest approach—register activities directly with the worker:

```go
package main

import (
    "log"

    "github.com/resolute/resolute/core"
    "go.temporal.io/sdk/client"
    "go.temporal.io/sdk/worker"

    "myapp/providers/jira"
    "myapp/providers/slack"
)

func main() {
    c, err := client.Dial(client.Options{})
    if err != nil {
        log.Fatal(err)
    }
    defer c.Close()

    w := worker.New(c, "my-task-queue", worker.Options{})

    // Register activities from each provider
    jira.RegisterActivities(w)
    slack.RegisterActivities(w)

    // Register the workflow
    w.RegisterWorkflow(MyWorkflow)

    if err := w.Run(worker.InterruptCh()); err != nil {
        log.Fatal(err)
    }
}
```

### Provider's RegisterActivities

Each provider exposes a `RegisterActivities` function:

```go
package jira

import (
    "github.com/resolute/resolute/core"
    "go.temporal.io/sdk/worker"
)

// RegisterActivities registers all Jira activities with a Temporal worker.
func RegisterActivities(w worker.Worker) {
    core.RegisterProviderActivities(w, Provider())
}
```

## Using Provider Registry

For more control, use `ProviderRegistry`:

```go
package main

import (
    "log"

    "github.com/resolute/resolute/core"
    "go.temporal.io/sdk/client"
    "go.temporal.io/sdk/worker"

    "myapp/providers/jira"
    "myapp/providers/slack"
    "myapp/providers/github"
)

func main() {
    // Create registry
    registry := core.NewProviderRegistry()

    // Register providers
    if err := registry.Register(jira.Provider()); err != nil {
        log.Fatal(err)
    }
    if err := registry.Register(slack.Provider()); err != nil {
        log.Fatal(err)
    }
    if err := registry.Register(github.NewProvider(github.Config{
        Token: os.Getenv("GITHUB_TOKEN"),
    })); err != nil {
        log.Fatal(err)
    }

    // Create Temporal client and worker
    c, _ := client.Dial(client.Options{})
    defer c.Close()

    w := worker.New(c, "my-task-queue", worker.Options{})

    // Register all activities from all providers
    registry.RegisterAllActivities(w)

    w.RegisterWorkflow(MyWorkflow)
    w.Run(worker.InterruptCh())
}
```

### Selective Registration

Register activities from specific providers only:

```go
// Register only Jira activities
if err := registry.RegisterActivities(w, "resolute-jira"); err != nil {
    log.Fatal(err)
}

// Register only Slack activities
if err := registry.RegisterActivities(w, "resolute-slack"); err != nil {
    log.Fatal(err)
}
```

### List Registered Providers

```go
providers := registry.List()
for _, p := range providers {
    fmt.Printf("Provider: %s v%s\n", p.Name(), p.Version())
    for _, act := range p.Activities() {
        fmt.Printf("  - %s\n", act.Name)
    }
}
```

## Activity Naming

Activity names identify the function during workflow execution.

### Naming Convention

Use a namespace prefix for clarity:

```go
// Good: Namespaced names
provider.AddActivity("jira.FetchIssues", FetchIssuesActivity)
provider.AddActivity("jira.CreateIssue", CreateIssueActivity)
provider.AddActivity("slack.PostMessage", PostMessageActivity)

// Bad: Generic names (may conflict)
provider.AddActivity("FetchIssues", FetchIssuesActivity)
provider.AddActivity("PostMessage", PostMessageActivity)
```

### Activity Name in Workflows

The activity name is used when calling from workflows:

```go
// In workflow code
var result FetchOutput
err := workflow.ExecuteActivity(ctx, "jira.FetchIssues", input).Get(ctx, &result)
```

With Resolute nodes, the framework handles this:

```go
// Node automatically uses the registered activity name
fetchNode := core.NewNode("fetch", jira.FetchIssuesActivity, input)
```

## Worker Configuration

### Single Task Queue

```go
w := worker.New(c, "default", worker.Options{})

// All activities on one queue
jira.RegisterActivities(w)
slack.RegisterActivities(w)
github.RegisterActivities(w)
```

### Multiple Task Queues

Separate activities by queue for isolation or scaling:

```go
// Queue for Jira activities
jiraWorker := worker.New(c, "jira-tasks", worker.Options{
    MaxConcurrentActivityExecutionSize: 10,
})
jira.RegisterActivities(jiraWorker)

// Queue for Slack activities
slackWorker := worker.New(c, "slack-tasks", worker.Options{
    MaxConcurrentActivityExecutionSize: 50,
})
slack.RegisterActivities(slackWorker)

// Run both workers
go jiraWorker.Run(worker.InterruptCh())
slackWorker.Run(worker.InterruptCh())
```

### Worker Options

Configure worker behavior:

```go
w := worker.New(c, "my-tasks", worker.Options{
    // Max concurrent activity executions
    MaxConcurrentActivityExecutionSize: 100,

    // Max concurrent workflow executions
    MaxConcurrentWorkflowTaskExecutionSize: 50,

    // Activities per second
    WorkerActivitiesPerSecond: 100,

    // Enable sessions for sticky execution
    EnableSessionWorker: true,
})
```

## Stateful Providers

For providers that need configuration or state:

```go
package main

func main() {
    // Create configured providers
    jiraProvider := jira.NewProvider(jira.Config{
        BaseURL:  os.Getenv("JIRA_BASE_URL"),
        Email:    os.Getenv("JIRA_EMAIL"),
        APIToken: os.Getenv("JIRA_API_TOKEN"),
    })

    slackProvider := slack.NewProvider(slack.Config{
        Token: os.Getenv("SLACK_TOKEN"),
    })

    // Register activities
    c, _ := client.Dial(client.Options{})
    w := worker.New(c, "my-tasks", worker.Options{})

    jiraProvider.RegisterActivities(w)
    slackProvider.RegisterActivities(w)

    w.Run(worker.InterruptCh())
}
```

## Registration Patterns

### Factory Pattern

Create providers through a factory:

```go
package providers

import (
    "github.com/resolute/resolute/core"

    "myapp/providers/jira"
    "myapp/providers/slack"
    "myapp/providers/github"
)

type Config struct {
    Jira   jira.Config
    Slack  slack.Config
    GitHub github.Config
}

func NewRegistry(cfg Config) (*core.ProviderRegistry, error) {
    registry := core.NewProviderRegistry()

    // Register Jira if configured
    if cfg.Jira.BaseURL != "" {
        if err := registry.Register(jira.NewProvider(cfg.Jira)); err != nil {
            return nil, err
        }
    }

    // Register Slack if configured
    if cfg.Slack.Token != "" {
        if err := registry.Register(slack.NewProvider(cfg.Slack)); err != nil {
            return nil, err
        }
    }

    // Register GitHub if configured
    if cfg.GitHub.Token != "" {
        if err := registry.Register(github.NewProvider(cfg.GitHub)); err != nil {
            return nil, err
        }
    }

    return registry, nil
}
```

### Environment-Based Registration

```go
func RegisterFromEnv(w worker.Worker) error {
    // Jira
    if os.Getenv("JIRA_BASE_URL") != "" {
        cfg, err := jira.ConfigFromEnv()
        if err != nil {
            return fmt.Errorf("jira config: %w", err)
        }
        jira.NewProvider(cfg).RegisterActivities(w)
    }

    // Slack
    if os.Getenv("SLACK_TOKEN") != "" {
        cfg, err := slack.ConfigFromEnv()
        if err != nil {
            return fmt.Errorf("slack config: %w", err)
        }
        slack.NewProvider(cfg).RegisterActivities(w)
    }

    return nil
}
```

### Plugin-Style Registration

Dynamic provider loading:

```go
type ProviderFactory func(config map[string]string) (core.Provider, error)

var providerFactories = map[string]ProviderFactory{
    "jira":   jira.NewFromConfig,
    "slack":  slack.NewFromConfig,
    "github": github.NewFromConfig,
}

func RegisterProviders(w worker.Worker, configs map[string]map[string]string) error {
    for name, cfg := range configs {
        factory, ok := providerFactories[name]
        if !ok {
            return fmt.Errorf("unknown provider: %s", name)
        }

        provider, err := factory(cfg)
        if err != nil {
            return fmt.Errorf("create %s provider: %w", name, err)
        }

        core.RegisterProviderActivities(w, provider)
    }
    return nil
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
    "go.temporal.io/sdk/client"
    "go.temporal.io/sdk/worker"

    "myapp/providers/jira"
    "myapp/providers/slack"
    "myapp/workflows"
)

func main() {
    // Load configuration
    jiraCfg := jira.Config{
        BaseURL:  os.Getenv("JIRA_BASE_URL"),
        Email:    os.Getenv("JIRA_EMAIL"),
        APIToken: os.Getenv("JIRA_API_TOKEN"),
    }

    slackCfg := slack.Config{
        Token: os.Getenv("SLACK_TOKEN"),
    }

    // Create Temporal client
    c, err := client.Dial(client.Options{
        HostPort: os.Getenv("TEMPORAL_HOST"),
    })
    if err != nil {
        log.Fatalf("Failed to create client: %v", err)
    }
    defer c.Close()

    // Create worker
    w := worker.New(c, "data-sync", worker.Options{
        MaxConcurrentActivityExecutionSize: 50,
    })

    // Register providers
    jiraProvider := jira.NewProvider(jiraCfg)
    jiraProvider.RegisterActivities(w)

    slackProvider := slack.NewProvider(slackCfg)
    slackProvider.RegisterActivities(w)

    // Register workflows
    w.RegisterWorkflow(workflows.DataSyncWorkflow)
    w.RegisterWorkflow(workflows.NotificationWorkflow)

    // Handle shutdown
    sigCh := make(chan os.Signal, 1)
    signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)

    go func() {
        <-sigCh
        log.Println("Shutting down...")
        w.Stop()
    }()

    // Run worker
    log.Println("Starting worker...")
    if err := w.Run(worker.InterruptCh()); err != nil {
        log.Fatalf("Worker failed: %v", err)
    }
}
```

## Debugging Registration

### Verify Activities

```go
// List all registered activities
provider := jira.Provider()
for _, act := range provider.Activities() {
    log.Printf("Registered: %s", act.Name)
    if act.Description != "" {
        log.Printf("  Description: %s", act.Description)
    }
}
```

### Check Registration Errors

```go
registry := core.NewProviderRegistry()

// First registration succeeds
err := registry.Register(jira.Provider())
if err != nil {
    log.Printf("Failed to register jira: %v", err)
}

// Duplicate registration fails
err = registry.Register(jira.Provider())
if err != nil {
    log.Printf("Expected error: %v", err)
    // Output: provider "resolute-jira" already registered
}
```

## See Also

- **[Creating Providers](/docs/guides/providers/creating-providers/)** - Build custom providers
- **[Provider Best Practices](/docs/guides/providers/best-practices/)** - Design patterns
- **[Workers](/docs/concepts/workers/)** - Worker configuration
- **[Deployment](/docs/guides/deployment/worker-configuration/)** - Production setup
