---
title: "Quickstart"
description: "Quickstart - Resolute documentation"
weight: 30
toc: true
---


# Quickstart

Build and run your first Resolute workflow in 5 minutes.

## Prerequisites

- Go 1.22+ installed
- Temporal server running locally

Start Temporal if you haven't already:
```bash
temporal server start-dev
```

## Step 1: Create a New Project

```bash
mkdir hello-resolute && cd hello-resolute
go mod init hello-resolute
go get github.com/resolute/resolute/core
```

## Step 2: Define Your Workflow

Create `main.go` with a simple 3-step data processing flow:

```go title="main.go"
package main

import (
    "context"
    "fmt"
    "log"
    "time"

    "github.com/resolute/resolute/core"
)

// Step 1: Fetch data from a source
type FetchInput struct{}
type FetchOutput struct {
    Records []string
}

func fetchData(ctx context.Context, input FetchInput) (FetchOutput, error) {
    log.Println("📥 Fetching records...")
    // Simulate fetching from an external API
    time.Sleep(500 * time.Millisecond)
    return FetchOutput{
        Records: []string{"record-1", "record-2", "record-3"},
    }, nil
}

// Step 2: Process the data
type ProcessInput struct {
    Records []string
}
type ProcessOutput struct {
    Processed int
    Summary   string
}

func processData(ctx context.Context, input ProcessInput) (ProcessOutput, error) {
    log.Printf("⚙️  Processing %d records...\n", len(input.Records))
    time.Sleep(300 * time.Millisecond)
    return ProcessOutput{
        Processed: len(input.Records),
        Summary:   fmt.Sprintf("Processed %d records successfully", len(input.Records)),
    }, nil
}

// Step 3: Store the results
type StoreInput struct {
    Summary string
}
type StoreOutput struct {
    StorageKey string
}

func storeResults(ctx context.Context, input StoreInput) (StoreOutput, error) {
    log.Printf("💾 Storing: %s\n", input.Summary)
    time.Sleep(200 * time.Millisecond)
    return StoreOutput{
        StorageKey: fmt.Sprintf("results-%d", time.Now().Unix()),
    }, nil
}

func main() {
    // Define nodes for each step
    fetchNode := core.NewNode("fetch", fetchData, FetchInput{}).
        WithTimeout(1 * time.Minute)

    processNode := core.NewNode("process", processData, ProcessInput{}).
        WithTimeout(2 * time.Minute)

    storeNode := core.NewNode("store", storeResults, StoreInput{}).
        WithTimeout(30 * time.Second)

    // Build the flow
    flow := core.NewFlow("hello-flow").
        TriggeredBy(core.Manual("api")).
        Then(fetchNode).
        Then(processNode).
        Then(storeNode).
        Build()

    log.Printf("🚀 Starting worker for flow: %s\n", flow.Name())

    // Run the worker
    core.NewWorker().
        WithConfig(core.WorkerConfig{
            TaskQueue:    "hello-queue",
            TemporalHost: "localhost:7233",
        }).
        WithFlow(flow).
        Run()
}
```

## Step 3: Run the Worker

```bash
go run main.go
```

You should see:
```
🚀 Starting worker for flow: hello-flow
```

The worker is now listening for workflow executions.

## Step 4: Start a Workflow

Open a **new terminal** and trigger the workflow:

```bash
temporal workflow start \
    --task-queue hello-queue \
    --type hello-flow \
    --workflow-id my-first-workflow
```

Back in your worker terminal, you'll see:
```
📥 Fetching records...
⚙️  Processing 3 records...
💾 Storing: Processed 3 records successfully
```

## Step 5: View in Temporal UI

Open [http://localhost:8233](http://localhost:8233) in your browser.

You'll see your workflow execution with:
- Workflow status (Completed)
- Each activity execution
- Input/output for each step
- Execution timeline

## What You Built

```
┌──────────────────────────────────────────────┐
│               hello-flow                      │
│  Trigger: Manual (API)                        │
├──────────────────────────────────────────────┤
│                                              │
│   ┌─────────┐   ┌─────────┐   ┌─────────┐   │
│   │  fetch  │ → │ process │ → │  store  │   │
│   └─────────┘   └─────────┘   └─────────┘   │
│                                              │
└──────────────────────────────────────────────┘
```

**Key concepts demonstrated:**

| Concept | What You Used |
|---------|---------------|
| **Flow** | `NewFlow("hello-flow")` - defines the workflow |
| **Trigger** | `Manual("api")` - starts via API/CLI |
| **Nodes** | `NewNode(...)` - wraps activities with typed I/O |
| **Worker** | `NewWorker()` - executes the flow |
| **Configuration** | `WithTimeout()`, `WorkerConfig` |

## Add Error Handling

Resolute provides automatic retries. Enhance your fetch node:

```go
fetchNode := core.NewNode("fetch", fetchData, FetchInput{}).
    WithTimeout(1 * time.Minute).
    WithRetry(core.RetryPolicy{
        InitialInterval:    time.Second,
        BackoffCoefficient: 2.0,
        MaximumInterval:    30 * time.Second,
        MaximumAttempts:    5,
    })
```

If `fetchData` fails, Temporal will automatically retry up to 5 times with exponential backoff.

## Next Steps

You've built your first Resolute workflow! Continue learning:

- **[Your First Flow](/docs/getting-started/your-first-flow/)** - A more complete tutorial with real integrations
- **[Core Concepts](/docs/concepts/overview/)** - Understand flows, nodes, state, and more
- **[Testing](/docs/guides/testing/flow-tester/)** - Test flows without running Temporal
