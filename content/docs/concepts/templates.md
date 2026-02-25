---
title: "Templates"
description: "Templates - Resolute documentation"
weight: 90
toc: true
---

# Flow Templates

**Flow Templates** construct flows dynamically at runtime. Unlike `FlowBuilder`'s compile-time fluent chain, `FlowTemplate` accepts step definitions that can vary per execution — useful for data-driven, user-configured, or feature-flagged workflows.

## FlowBuilder vs FlowTemplate

| Aspect | FlowBuilder | FlowTemplate |
|--------|------------|--------------|
| Construction | Compile-time fluent chain | Runtime step-by-step |
| Steps | Fixed at build time | Variable per invocation |
| Use case | Known, static pipelines | Dynamic/configurable pipelines |
| Output | `*Flow` | `*Flow` (identical) |

Both produce the same `*Flow` struct. The difference is only in how you construct it.

## Creating a Template

```go
tmpl := core.NewFlowTemplate("configurable-pipeline").
    TriggeredBy(core.Manual("api")).
    WithHooks(&core.FlowHooks{
        AfterFlow: func(ctx core.HookContext) {
            log.Info("pipeline completed", "duration", ctx.Duration)
        },
    })
```

## Adding Steps

### Sequential

```go
tmpl.AddStep(fetchNode)
tmpl.AddStep(transformNode)
```

### Parallel

```go
tmpl.AddParallel("fetch-sources", jiraFetchNode, confluenceFetchNode, slackFetchNode)
```

### Gate

```go
tmpl.AddGate("approval", core.GateConfig{
    SignalName: "manager-approval",
    Timeout:    24 * time.Hour,
})
```

### Child Flows

```go
tmpl.AddChildren("process-batch", core.ChildFlowConfig{
    Flow:        itemFlow,
    InputMapper: mapper,
})
```

### Conditional

```go
tmpl.AddConditional(
    func(state *core.FlowState) bool {
        return state.GetResult("fetch") != nil
    },
    []core.ExecutableNode{processNode, storeNode},  // then branch
    []core.ExecutableNode{fallbackNode},             // else branch (optional)
)
```

## Building

`.Build()` validates the template and returns a `*Flow`:

```go
flow := tmpl.Build()
```

Build panics if:
- No steps were added
- No trigger was set
- Any step validation failed (nil nodes, missing signal names, etc.)

## Dynamic Pipeline Example

```go
func buildPipeline(config PipelineConfig) *core.Flow {
    tmpl := core.NewFlowTemplate(config.Name).
        TriggeredBy(core.Schedule(config.Cron))

    for _, source := range config.Sources {
        tmpl.AddStep(createFetchNode(source))
    }

    if config.NeedsApproval {
        tmpl.AddGate("review", core.GateConfig{
            SignalName: config.ApprovalSignal,
            Timeout:    config.ApprovalTimeout,
        })
    }

    if len(config.Transforms) > 1 {
        nodes := make([]core.ExecutableNode, len(config.Transforms))
        for i, t := range config.Transforms {
            nodes[i] = createTransformNode(t)
        }
        tmpl.AddParallel("transforms", nodes...)
    } else if len(config.Transforms) == 1 {
        tmpl.AddStep(createTransformNode(config.Transforms[0]))
    }

    tmpl.AddStep(storeNode)

    return tmpl.Build()
}
```

## FlowTemplate Methods

| Method | Description |
|--------|-------------|
| `NewFlowTemplate(name)` | Create a new template |
| `.TriggeredBy(trigger)` | Set the trigger |
| `.WithHooks(hooks)` | Attach lifecycle hooks |
| `.WithState(config)` | Configure state persistence |
| `.AddStep(node)` | Add a sequential step |
| `.AddParallel(name, ...nodes)` | Add a parallel step |
| `.AddGate(name, config)` | Add a gate step |
| `.AddChildren(name, config)` | Add a child flow step |
| `.AddConditional(pred, then, else)` | Add a conditional branch |
| `.Build()` | Validate and return `*Flow` |

## See Also

- **[Flows](/docs/concepts/flows/)** — FlowBuilder for static pipelines
- **[Gates](/docs/concepts/gates/)** — Pause execution for signals
- **[Child Flows](/docs/concepts/child-flows/)** — Spawn child workflows
- **[Hooks](/docs/concepts/hooks/)** — Lifecycle callbacks
