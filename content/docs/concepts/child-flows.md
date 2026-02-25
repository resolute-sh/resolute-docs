---
title: "Child Flows"
description: "Child Flows - Resolute documentation"
weight: 80
toc: true
---

# Child Flows

**Child Flows** spawn child workflows from a parent flow for fan-out processing, batch operations, and nested workflow composition.

## What is a Child Flow Node?

A `ChildFlowNode` uses Temporal's child workflow mechanism to spawn one or more instances of a flow. The parent flow waits for all children to complete before proceeding.

```
┌─────────────────────────────────────────────────────────────────────┐
│                     Child Flow Execution                             │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  Parent Flow                                                         │
│  ├── fetchItems                                                      │
│  ├── ThenChildren("process-items")                                   │
│  │   ├── InputMapper(state) → [input₀, input₁, input₂]             │
│  │   │                                                               │
│  │   │   ┌─────────────────────────┐                                │
│  │   │   │  Parallel by default    │                                │
│  │   │   ├─────────────────────────┤                                │
│  │   │   │ child-0 ──▶ childFlow   │                                │
│  │   │   │ child-1 ──▶ childFlow   │                                │
│  │   │   │ child-2 ──▶ childFlow   │                                │
│  │   │   └─────────────────────────┘                                │
│  │   │                                                               │
│  │   └── ChildFlowResults{Count: 3, Errors: [...]}                  │
│  │                                                                   │
│  └── aggregateResults                                                │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

## Creating Child Flow Steps

### Define the child flow

```go
itemFlow := core.NewFlow("process-item").
    TriggeredBy(core.Manual("internal")).
    Then(validateNode).
    Then(transformNode).
    Then(storeNode).
    Build()
```

### Add to parent via FlowBuilder

```go
parentFlow := core.NewFlow("batch-processor").
    TriggeredBy(core.Schedule("0 * * * *")).
    Then(fetchItemsNode).
    ThenChildren("process-items", core.ChildFlowConfig{
        Flow: itemFlow,
        InputMapper: func(state *core.FlowState) []core.FlowInput {
            items := core.Get[FetchOutput](state, "fetch-items")
            inputs := make([]core.FlowInput, len(items.Items))
            for i, item := range items.Items {
                data, _ := json.Marshal(item)
                inputs[i] = core.FlowInput{
                    Data: map[string][]byte{"item": data},
                }
            }
            return inputs
        },
    }).
    Then(aggregateNode).
    Build()
```

## ChildFlowConfig

```go
type ChildFlowConfig struct {
    Flow        *Flow
    InputMapper func(*FlowState) []FlowInput
    Sequential  bool
}
```

| Field | Required | Description |
|-------|----------|-------------|
| `Flow` | Yes | The child flow to spawn |
| `InputMapper` | Yes | Function that derives child inputs from parent state |
| `Sequential` | No | Execute children one at a time (default: parallel) |

## Execution Modes

### Parallel (default)

All child workflows launch simultaneously. The parent waits for all to complete. If any child fails, the first error is returned.

```go
core.ChildFlowConfig{
    Flow:        childFlow,
    InputMapper: mapper,
    // Sequential defaults to false
}
```

### Sequential

Children execute one at a time in order. Stops on first error.

```go
core.ChildFlowConfig{
    Flow:        childFlow,
    InputMapper: mapper,
    Sequential:  true,
}
```

## ChildFlowResults

After execution, the results are stored in FlowState:

```go
type ChildFlowResults struct {
    States []*FlowState
    Errors []error
    Count  int
}
```

Access in downstream nodes:

```go
results := core.Get[core.ChildFlowResults](state, "process-items")
fmt.Printf("Processed %d items\n", results.Count)
for i, err := range results.Errors {
    if err != nil {
        log.Error("child failed", "index", i, "error", err)
    }
}
```

## Child Workflow IDs

Each child gets a unique workflow ID derived from the node name and index:

```
process-items-child-0
process-items-child-1
process-items-child-2
```

## Empty Input

If `InputMapper` returns an empty slice, no children are spawned and `ChildFlowResults{Count: 0}` is stored immediately.

## ChildFlowNode Methods

| Method | Description |
|--------|-------------|
| `NewChildFlowNode(name, config)` | Create a child flow node |
| `.As(key)` | Override output key in FlowState |
| `.Name()` | Get node name |
| `.OutputKey()` | Get output storage key |

## See Also

- **[Flows](/docs/concepts/flows/)** — How child flows compose into parent workflows
- **[Nodes](/docs/concepts/nodes/)** — Other executable node types
- **[Templates](/docs/concepts/templates/)** — Dynamic flow construction with child flows
