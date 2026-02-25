---
title: "Gates"
description: "Gates - Resolute documentation"
weight: 70
toc: true
---

# Gates

A **Gate** pauses flow execution until an external signal is received. Use gates for approval workflows, manual review steps, and wait-for-event patterns.

## What is a Gate?

A Gate is a special step that blocks execution until a Temporal signal carrying a `GateResult` is received. Unlike regular nodes that execute activities, gates wait passively for external input.

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Gate Lifecycle                                │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  1. Flow reaches gate step                                           │
│     └─▶ Execution pauses                                            │
│                                                                      │
│  2. External system sends Temporal signal                            │
│     └─▶ Signal carries GateResult payload                           │
│                                                                      │
│  3. Gate receives signal                                             │
│     ├─▶ Stores GateResult in FlowState                              │
│     └─▶ Execution resumes                                           │
│                                                                      │
│  OR                                                                  │
│                                                                      │
│  3. Timeout expires                                                  │
│     └─▶ GateTimeoutError returned, compensation runs                │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

## Creating Gates

### Via FlowBuilder

```go
flow := core.NewFlow("deploy-pipeline").
    TriggeredBy(core.Manual("api")).
    Then(runTestsNode).
    Then(buildArtifactNode).
    ThenGate("deploy-approval", core.GateConfig{
        SignalName: "approve-deploy",
        Timeout:    24 * time.Hour,
    }).
    Then(deployNode).
    Build()
```

### Via FlowTemplate

```go
tmpl := core.NewFlowTemplate("deploy-pipeline").
    TriggeredBy(core.Manual("api"))

tmpl.AddStep(runTestsNode)
tmpl.AddGate("deploy-approval", core.GateConfig{
    SignalName: "approve-deploy",
    Timeout:    24 * time.Hour,
})
tmpl.AddStep(deployNode)

flow := tmpl.Build()
```

### Standalone GateNode

```go
gate := core.NewGateNode("review", core.GateConfig{
    SignalName: "code-review",
    Timeout:    48 * time.Hour,
}).As("review-result")
```

## GateConfig

```go
type GateConfig struct {
    SignalName string         // Temporal signal name to wait for
    Timeout    time.Duration  // Optional timeout (0 = wait indefinitely)
}
```

| Field | Required | Description |
|-------|----------|-------------|
| `SignalName` | Yes | Temporal signal name the gate listens for |
| `Timeout` | No | Maximum wait duration. Zero means wait forever. |

## GateResult

The signal payload must be a `GateResult`:

```go
type GateResult struct {
    Approved   bool
    Decision   string
    DecidedBy  string
    DecidedAt  time.Time
    Reason     string
    Metadata   map[string]string
}
```

After the gate resolves, the result is stored in FlowState under the gate's output key:

```go
// In a downstream node's InputFunc
result := core.Get[core.GateResult](state, "deploy-approval")
if result.Approved {
    // proceed with deployment
}
```

## Sending Signals

Use the Temporal client to signal a running workflow:

```go
client.SignalWorkflow(ctx, workflowID, runID, "approve-deploy", core.GateResult{
    Approved:  true,
    DecidedBy: "alice@company.com",
    Reason:    "All tests passed, deploy approved",
    Metadata: map[string]string{
        "ticket": "DEPLOY-456",
    },
})
```

## Timeout Handling

If a timeout is configured and expires before a signal arrives, the gate returns a `GateTimeoutError`:

```go
type GateTimeoutError struct {
    GateName string
    Timeout  time.Duration
}
```

The error message follows the format: `gate "deploy-approval" timed out after 24h0m0s`

When a gate times out, the flow's compensation chain runs (if configured).

## GateNode Methods

| Method | Description |
|--------|-------------|
| `NewGateNode(name, config)` | Create a gate node |
| `.As(key)` | Override output key in FlowState |
| `.Name()` | Get gate name |
| `.OutputKey()` | Get output storage key |
| `.Execute(ctx, state)` | Wait for signal (called by flow engine) |

## Use Cases

| Pattern | SignalName | Timeout | Description |
|---------|-----------|---------|-------------|
| Deploy approval | `"approve-deploy"` | 24h | Human approves production deploy |
| Code review | `"review-complete"` | 48h | Wait for PR review |
| External system | `"payment-confirmed"` | 1h | Wait for payment webhook |
| Manual data entry | `"data-provided"` | 0 (forever) | Wait for operator input |

## See Also

- **[Flows](/docs/concepts/flows/)** — How gates compose into workflows
- **[Nodes](/docs/concepts/nodes/)** — Other executable node types
- **[Triggers](/docs/concepts/triggers/)** — How flows start
