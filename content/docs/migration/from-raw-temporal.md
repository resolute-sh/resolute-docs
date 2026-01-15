---
title: "From Raw Temporal"
description: "From Raw Temporal - Resolute documentation"
weight: 10
toc: true
---


# Migrating from Raw Temporal SDK

This guide helps teams transition from direct Temporal SDK usage to Resolute's higher-level abstractions.

## Why Migrate?

| Raw Temporal | Resolute |
|--------------|----------|
| Imperative workflow definitions | Declarative flow builder |
| Manual activity registration | Auto-registered via providers |
| Custom retry/compensation logic | Built-in patterns (Saga, etc.) |
| Boilerplate for common patterns | Ready-to-use abstractions |
| Testing requires mocks | FlowTester with simplified API |

## Key Concept Mapping

### Workflows → Flows

**Raw Temporal:**
```go
func MyWorkflow(ctx workflow.Context, input MyInput) (MyOutput, error) {
    var result Step1Output
    err := workflow.ExecuteActivity(ctx, Step1Activity, input).Get(ctx, &result)
    if err != nil {
        return MyOutput{}, err
    }

    var step2Result Step2Output
    err = workflow.ExecuteActivity(ctx, Step2Activity, result).Get(ctx, &step2Result)
    if err != nil {
        return MyOutput{}, err
    }

    return MyOutput{Data: step2Result.Data}, nil
}
```

**Resolute:**
```go
flow := core.NewFlow("my-workflow").
    TriggeredBy(core.Manual("api")).
    Then(step1Node.As("step1")).
    Then(step2Node.As("step2")).
    Build()
```

### Activities → Nodes

**Raw Temporal:**
```go
func FetchDataActivity(ctx context.Context, input FetchInput) (FetchOutput, error) {
    // Implementation
    return FetchOutput{}, nil
}

// Registration in worker
w.RegisterActivity(FetchDataActivity)
```

**Resolute:**
```go
var fetchDataNode = core.NewNode("fetch-data", fetchData)

func fetchData(ctx context.Context, input FetchInput) (FetchOutput, error) {
    // Same implementation
    return FetchOutput{}, nil
}

// Auto-registered via provider or flow
```

### Activity Options → Node Configuration

**Raw Temporal:**
```go
ao := workflow.ActivityOptions{
    StartToCloseTimeout: 10 * time.Minute,
    RetryPolicy: &temporal.RetryPolicy{
        InitialInterval:    time.Second,
        BackoffCoefficient: 2.0,
        MaximumInterval:    time.Minute,
        MaximumAttempts:    3,
    },
}
ctx = workflow.WithActivityOptions(ctx, ao)
err := workflow.ExecuteActivity(ctx, MyActivity, input).Get(ctx, &result)
```

**Resolute:**
```go
Then(myNode.
    WithTimeout(10 * time.Minute).
    WithRetry(3, time.Second))
```

### Signals → Signal Triggers

**Raw Temporal:**
```go
func MyWorkflow(ctx workflow.Context) error {
    var signal MySignal
    signalChan := workflow.GetSignalChannel(ctx, "my-signal")

    selector := workflow.NewSelector(ctx)
    selector.AddReceive(signalChan, func(c workflow.ReceiveChannel, more bool) {
        c.Receive(ctx, &signal)
    })
    selector.Select(ctx)

    // Handle signal
    return nil
}
```

**Resolute:**
```go
flow := core.NewFlow("signal-handler").
    TriggeredBy(core.Signal("my-signal")).
    Then(handleSignalNode).
    Build()
```

### Queries → Not Directly Mapped

Temporal queries are handled at the worker level. Resolute focuses on workflow definition, so queries remain as standard Temporal queries on the underlying workflow.

## Migration Patterns

### Sequential Workflows

**Before (Raw Temporal):**
```go
func OrderWorkflow(ctx workflow.Context, order Order) error {
    var validated Order
    err := workflow.ExecuteActivity(ctx, ValidateOrder, order).Get(ctx, &validated)
    if err != nil {
        return err
    }

    var charged ChargeResult
    err = workflow.ExecuteActivity(ctx, ChargePayment, validated).Get(ctx, &charged)
    if err != nil {
        return err
    }

    var fulfilled FulfillResult
    err = workflow.ExecuteActivity(ctx, FulfillOrder, charged).Get(ctx, &fulfilled)
    if err != nil {
        return err
    }

    return workflow.ExecuteActivity(ctx, SendConfirmation, fulfilled).Get(ctx, nil)
}
```

**After (Resolute):**
```go
flow := core.NewFlow("order-workflow").
    TriggeredBy(core.Manual("api")).
    Then(validateOrderNode.As("validated")).
    Then(chargePaymentNode.As("charged")).
    Then(fulfillOrderNode.As("fulfilled")).
    Then(sendConfirmationNode).
    Build()
```

### Parallel Execution

**Before (Raw Temporal):**
```go
func ParallelWorkflow(ctx workflow.Context, input Input) error {
    var futures []workflow.Future

    futures = append(futures, workflow.ExecuteActivity(ctx, Task1, input))
    futures = append(futures, workflow.ExecuteActivity(ctx, Task2, input))
    futures = append(futures, workflow.ExecuteActivity(ctx, Task3, input))

    for _, f := range futures {
        var result TaskResult
        if err := f.Get(ctx, &result); err != nil {
            return err
        }
    }

    return nil
}
```

**After (Resolute):**
```go
flow := core.NewFlow("parallel-workflow").
    TriggeredBy(core.Manual("api")).
    Parallel().
        Then(task1Node.As("result1")).
        Then(task2Node.As("result2")).
        Then(task3Node.As("result3")).
    EndParallel().
    Build()
```

### Conditional Logic

**Before (Raw Temporal):**
```go
func ConditionalWorkflow(ctx workflow.Context, input Input) error {
    var checkResult CheckOutput
    err := workflow.ExecuteActivity(ctx, CheckCondition, input).Get(ctx, &checkResult)
    if err != nil {
        return err
    }

    if checkResult.ShouldProcess {
        err = workflow.ExecuteActivity(ctx, ProcessData, input).Get(ctx, nil)
        if err != nil {
            return err
        }
    } else {
        err = workflow.ExecuteActivity(ctx, SkipProcessing, input).Get(ctx, nil)
        if err != nil {
            return err
        }
    }

    return nil
}
```

**After (Resolute):**
```go
flow := core.NewFlow("conditional-workflow").
    TriggeredBy(core.Manual("api")).
    Then(checkConditionNode.As("check")).
    When(func(s *core.FlowState) bool {
        check := core.Get[CheckOutput](s, "check")
        return check.ShouldProcess
    }).
        Then(processDataNode).
    EndWhen().
    When(func(s *core.FlowState) bool {
        check := core.Get[CheckOutput](s, "check")
        return !check.ShouldProcess
    }).
        Then(skipProcessingNode).
    EndWhen().
    Build()
```

### Saga Pattern (Compensation)

**Before (Raw Temporal):**
```go
func SagaWorkflow(ctx workflow.Context, input Input) error {
    var compensations []func()

    // Step 1
    err := workflow.ExecuteActivity(ctx, Step1, input).Get(ctx, nil)
    if err != nil {
        return err
    }
    compensations = append(compensations, func() {
        workflow.ExecuteActivity(ctx, CompensateStep1, input)
    })

    // Step 2
    err = workflow.ExecuteActivity(ctx, Step2, input).Get(ctx, nil)
    if err != nil {
        // Compensate in reverse order
        for i := len(compensations) - 1; i >= 0; i-- {
            compensations[i]()
        }
        return err
    }
    compensations = append(compensations, func() {
        workflow.ExecuteActivity(ctx, CompensateStep2, input)
    })

    // Step 3
    err = workflow.ExecuteActivity(ctx, Step3, input).Get(ctx, nil)
    if err != nil {
        for i := len(compensations) - 1; i >= 0; i-- {
            compensations[i]()
        }
        return err
    }

    return nil
}
```

**After (Resolute):**
```go
flow := core.NewFlow("saga-workflow").
    TriggeredBy(core.Manual("api")).
    Then(step1Node.OnError(compensateStep1Node)).
    Then(step2Node.OnError(compensateStep2Node)).
    Then(step3Node.OnError(compensateStep3Node)).
    Build()
```

### Timer/Sleep

**Before (Raw Temporal):**
```go
func TimerWorkflow(ctx workflow.Context) error {
    err := workflow.ExecuteActivity(ctx, DoSomething).Get(ctx, nil)
    if err != nil {
        return err
    }

    // Wait 1 hour
    workflow.Sleep(ctx, time.Hour)

    return workflow.ExecuteActivity(ctx, DoSomethingElse).Get(ctx, nil)
}
```

**After (Resolute):**
```go
flow := core.NewFlow("timer-workflow").
    TriggeredBy(core.Manual("api")).
    Then(doSomethingNode).
    Then(core.Sleep(time.Hour)).
    Then(doSomethingElseNode).
    Build()
```

## Worker Migration

### Raw Temporal Worker

```go
func main() {
    c, _ := client.Dial(client.Options{})
    defer c.Close()

    w := worker.New(c, "my-task-queue", worker.Options{})

    w.RegisterWorkflow(MyWorkflow)
    w.RegisterActivity(Activity1)
    w.RegisterActivity(Activity2)
    w.RegisterActivity(Activity3)

    err := w.Run(worker.InterruptCh())
    if err != nil {
        log.Fatalln("unable to start worker", err)
    }
}
```

### Resolute Worker

```go
func main() {
    // Provider handles activity registration
    myProvider := NewMyProvider()

    flow := core.NewFlow("my-workflow").
        TriggeredBy(core.Manual("api")).
        Then(activity1Node).
        Then(activity2Node).
        Then(activity3Node).
        Build()

    err := core.NewWorker().
        WithConfig(core.WorkerConfig{
            TaskQueue: "my-task-queue",
        }).
        WithFlow(flow).
        WithProviders(myProvider).
        Run()

    if err != nil {
        panic(err)
    }
}
```

## Testing Migration

### Raw Temporal Testing

```go
func TestMyWorkflow(t *testing.T) {
    testSuite := &testsuite.WorkflowTestSuite{}
    env := testSuite.NewTestWorkflowEnvironment()

    env.OnActivity(Activity1, mock.Anything).Return(Activity1Output{}, nil)
    env.OnActivity(Activity2, mock.Anything).Return(Activity2Output{}, nil)

    env.ExecuteWorkflow(MyWorkflow, MyInput{})

    require.True(t, env.IsWorkflowCompleted())
    require.NoError(t, env.GetWorkflowError())
}
```

### Resolute Testing

```go
func TestMyFlow(t *testing.T) {
    tester := core.NewFlowTester(myFlow)

    tester.MockNode("activity1", Activity1Output{Data: "mocked"})
    tester.MockNode("activity2", Activity2Output{Result: 42})

    result := tester.Run(MyInput{})

    assert.NoError(t, result.Error)
    assert.Equal(t, expected, result.Get("activity2"))
}
```

## Incremental Migration Strategy

1. **Start with new workflows**: Build new workflows in Resolute while maintaining existing Temporal workflows.

2. **Create provider wrappers**: Wrap existing activities in Resolute nodes.
   ```go
   var legacyActivityNode = core.NewNode("legacy-activity", legacyActivityWrapper)

   func legacyActivityWrapper(ctx context.Context, input LegacyInput) (LegacyOutput, error) {
       return LegacyActivity(ctx, input) // Call existing activity
   }
   ```

3. **Migrate workflow-by-workflow**: Convert one workflow at a time, testing thoroughly.

4. **Consolidate providers**: Group related activities into providers as you migrate.

## What Stays the Same

- **Temporal Server**: Resolute uses the same Temporal server
- **Activity implementation**: Core activity logic remains identical
- **Durability guarantees**: Same execution guarantees from Temporal
- **Observability**: Same Temporal UI and metrics

## What Changes

| Aspect | Change |
|--------|--------|
| Workflow definition | Imperative → Declarative |
| Activity registration | Manual → Provider-based |
| Error handling | try/catch → OnError chains |
| Testing | Mocks → FlowTester |
| Boilerplate | Significant reduction |

## Common Pitfalls

### 1. Forgetting to Register Providers

```go
// Wrong: Node won't be registered
core.NewWorker().
    WithFlow(flow).
    Run()

// Correct: Provider registers its activities
core.NewWorker().
    WithFlow(flow).
    WithProviders(myProvider). // Don't forget!
    Run()
```

### 2. Mixing Imperative and Declarative

```go
// Wrong: Don't mix styles
flow := core.NewFlow("mixed").
    TriggeredBy(core.Manual("api")).
    Then(core.NewNode("inline", func(ctx context.Context, input Input) (Output, error) {
        // Avoid complex logic here
        if condition {
            // Don't branch inside node
        }
        return Output{}, nil
    })).
    Build()

// Correct: Use flow-level conditionals
flow := core.NewFlow("declarative").
    TriggeredBy(core.Manual("api")).
    Then(checkNode.As("check")).
    When(conditionA).
        Then(branchANode).
    EndWhen().
    When(conditionB).
        Then(branchBNode).
    EndWhen().
    Build()
```

### 3. Over-relying on FlowState

```go
// Avoid: Mutating state directly
func myActivity(ctx context.Context, state *core.FlowState) error {
    state.Set("key", "value") // Don't do this
    return nil
}

// Correct: Return data from nodes
func myActivity(ctx context.Context, input Input) (Output, error) {
    return Output{Key: "value"}, nil // Data flows through outputs
}
```

## See Also

- **[Concepts Overview](/docs/concepts/overview/)** - Understanding Resolute's model
- **[Flows](/docs/concepts/flows/)** - Flow builder API
- **[Nodes](/docs/concepts/nodes/)** - Activity wrappers
- **[Testing](/docs/reference/core/testing/)** - FlowTester documentation
