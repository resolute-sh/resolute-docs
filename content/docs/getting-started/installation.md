---
title: "Installation"
description: "Installation - Resolute documentation"
weight: 20
toc: true
---


# Installation

Install Resolute and its providers using Go modules.

## Core Package

```bash
go get github.com/resolute/resolute/core
```

This provides the fundamental primitives:
- `Flow` and `FlowBuilder` for workflow definition
- `Node` for typed activity wrappers
- `Trigger` types (Manual, Schedule, Signal)
- `FlowState` for runtime state management
- `Worker` for execution

## Providers

Providers add integrations with external systems. Install based on your needs:

```bash
# Jira - Issue tracking integration
go get github.com/resolute/resolute-jira

# Ollama - Local LLM embeddings
go get github.com/resolute/resolute-ollama

# Qdrant - Vector database
go get github.com/resolute/resolute-qdrant

# Confluence - Wiki integration
go get github.com/resolute/resolute-confluence

# PagerDuty - Incident management
go get github.com/resolute/resolute-pagerduty

# Transform - Document processing utilities
go get github.com/resolute/resolute-transform
```

## Verify Installation

Create a test file to verify everything is working:

```go title="main.go"
package main

import (
    "fmt"

    "github.com/resolute/resolute/core"
)

func main() {
    // Create a minimal flow
    flow := core.NewFlow("test-flow").
        TriggeredBy(core.Manual("test")).
        Then(core.NewNode("noop", noopActivity, struct{}{})).
        Build()

    fmt.Printf("Flow created: %s\n", flow.Name())
    fmt.Printf("Trigger type: %s\n", flow.Trigger().Type())
    fmt.Printf("Steps: %d\n", len(flow.Steps()))
}

func noopActivity(ctx context.Context, input struct{}) (struct{}, error) {
    return struct{}{}, nil
}
```

Run it:

```bash
go run main.go
```

Expected output:
```
Flow created: test-flow
Trigger type: manual
Steps: 1
```

## Project Structure

Recommended project layout:

```
myproject/
├── main.go              # Worker entry point
├── flows/
│   ├── sync.go          # Flow definitions
│   └── process.go
├── activities/
│   └── custom.go        # Custom activity functions
├── go.mod
└── go.sum
```

### Example `go.mod`

```go title="go.mod"
module myproject

go 1.22

require (
    github.com/resolute/resolute/core v0.1.0
    github.com/resolute/resolute-jira v0.1.0
)
```

## Environment Variables

Resolute reads these environment variables for configuration:

| Variable | Description | Default |
|----------|-------------|---------|
| `TEMPORAL_HOST` | Temporal server address | `localhost:7233` |
| `TEMPORAL_NAMESPACE` | Temporal namespace | `default` |

You can also set these programmatically via `WorkerConfig`.

## Next Steps

Continue to [Quickstart](/docs/getting-started/quickstart/) to build your first workflow in 5 minutes.
