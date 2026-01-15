---
title: "Conditional Logic"
description: "Conditional Logic - Resolute documentation"
weight: 30
toc: true
---


# Conditional Logic

Conditional logic allows flows to branch based on runtime data. Use predicates to evaluate FlowState and execute different paths.

## Basic Pattern

Use `When()` to start a conditional block:

```go
flow := core.NewFlow("conditional-flow").
    TriggeredBy(core.Manual("api")).
    Then(fetchOrderNode).
    When(func(s *core.FlowState) bool {
        order := core.Get[Order](s, "fetch-order")
        return order.Total > 1000
    }).
    Then(requireApprovalNode).
    Otherwise(autoApproveNode).
    Then(fulfillOrderNode).
    Build()
```

Execution:
1. `fetchOrderNode` runs
2. Predicate evaluates order total
3. If `> 1000`: `requireApprovalNode` runs
4. Otherwise: `autoApproveNode` runs
5. `fulfillOrderNode` runs (always)

## Predicate Functions

A predicate is a function that takes `*FlowState` and returns `bool`:

```go
type Predicate func(*FlowState) bool
```

### Simple Predicates

```go
// Check a boolean field
When(func(s *core.FlowState) bool {
    result := core.Get[CheckOutput](s, "check")
    return result.IsValid
})

// Compare values
When(func(s *core.FlowState) bool {
    order := core.Get[Order](s, "order")
    return order.Total > 1000
})

// Check string equality
When(func(s *core.FlowState) bool {
    user := core.Get[User](s, "user")
    return user.Role == "admin"
})
```

### Complex Predicates

```go
// Multiple conditions
When(func(s *core.FlowState) bool {
    order := core.Get[Order](s, "order")
    user := core.Get[User](s, "user")
    return order.Total > 1000 && user.VIPStatus
})

// Check array length
When(func(s *core.FlowState) bool {
    result := core.Get[FetchOutput](s, "fetch")
    return len(result.Items) > 0
})

// Check for errors in previous step
When(func(s *core.FlowState) bool {
    validation := core.Get[ValidationOutput](s, "validate")
    return len(validation.Errors) == 0
})
```

## Conditional API

### Then / Otherwise (Simple Branch)

For simple if/else logic:

```go
flow := core.NewFlow("simple-branch").
    TriggeredBy(core.Manual("api")).
    Then(checkNode).
    When(predicate).
    Then(doIfTrue).
    Otherwise(doIfFalse).
    Then(continueNode).
    Build()
```

- `Then()` adds to the "if true" branch
- `Otherwise()` adds to the "if false" branch and returns to main flow

### Then / Else / EndWhen (Complex Branches)

For multi-step branches:

```go
flow := core.NewFlow("complex-branch").
    TriggeredBy(core.Manual("api")).
    Then(checkNode).
    When(predicate).
    Then(step1IfTrue).
    Then(step2IfTrue).
    ThenParallel("parallel-if-true", nodeA, nodeB).
    Else().
    Then(step1IfFalse).
    Then(step2IfFalse).
    EndWhen().
    Then(continueNode).
    Build()
```

- `Else()` switches to building the "if false" branch
- `EndWhen()` ends the conditional block without an else action
- After `EndWhen()` or `Otherwise()`, you're back on the main flow

### No Else Branch

Use `EndWhen()` when no else branch is needed:

```go
flow := core.NewFlow("optional-step").
    TriggeredBy(core.Manual("api")).
    Then(fetchNode).
    When(func(s *core.FlowState) bool {
        result := core.Get[FetchOutput](s, "fetch")
        return result.NeedsEnrichment
    }).
    Then(enrichNode).
    EndWhen().
    Then(storeNode).
    Build()
```

If predicate is false, flow skips directly to `storeNode`.

## Parallel in Conditionals

Both branches support parallel execution:

```go
flow := core.NewFlow("parallel-branches").
    TriggeredBy(core.Manual("api")).
    Then(checkPriorityNode).
    When(func(s *core.FlowState) bool {
        return core.Get[PriorityCheck](s, "check").IsHighPriority
    }).
    ThenParallel("high-priority-actions",
        notifyManagerNode,
        escalateNode,
        logAuditNode,
    ).
    Otherwise(standardProcessingNode).
    Then(completeNode).
    Build()
```

Using `OtherwiseParallel()`:

```go
flow := core.NewFlow("parallel-else").
    TriggeredBy(core.Manual("api")).
    When(predicate).
    Then(singleActionNode).
    OtherwiseParallel("fallback-actions",
        fallbackA,
        fallbackB,
        fallbackC,
    ).
    Build()
```

## Nested Conditionals

Conditionals can be nested within branches:

```go
flow := core.NewFlow("nested-conditions").
    TriggeredBy(core.Manual("api")).
    Then(fetchOrderNode).
    When(func(s *core.FlowState) bool {
        order := core.Get[Order](s, "order")
        return order.Total > 100
    }).
    // First level: order > $100
    Then(checkInventoryNode).
    When(func(s *core.FlowState) bool {
        inv := core.Get[InventoryCheck](s, "inventory")
        return inv.InStock
    }).
    // Nested: in stock
    Then(reserveStockNode).
    Otherwise(backorderNode).
    // Back to first level
    Else().
    // First level else: order <= $100
    Then(expressCheckoutNode).
    EndWhen().
    Then(confirmOrderNode).
    Build()
```

## Complete Example

Order processing with conditional approval flow:

```go
package main

import (
    "context"
    "time"

    "github.com/resolute/resolute/core"
)

type Order struct {
    ID       string
    Total    float64
    Customer Customer
    Items    []Item
}

type Customer struct {
    ID        string
    VIP       bool
    CreditScore int
}

type ValidationResult struct {
    Valid  bool
    Errors []string
}

type ApprovalResult struct {
    Approved   bool
    ApproverID string
    Notes      string
}

func main() {
    // Fetch and validate order
    fetchOrder := core.NewNode("fetch-order", fetchOrderFn, FetchInput{}).
        As("order")

    validateOrder := core.NewNode("validate-order", validateOrderFn, ValidateInput{}).
        WithInputFunc(func(s *core.FlowState) ValidateInput {
            order := core.Get[Order](s, "order")
            return ValidateInput{OrderID: order.ID}
        }).
        As("validation")

    // Approval nodes
    autoApprove := core.NewNode("auto-approve", autoApproveFn, ApproveInput{}).
        WithInputFunc(func(s *core.FlowState) ApproveInput {
            order := core.Get[Order](s, "order")
            return ApproveInput{OrderID: order.ID, Auto: true}
        })

    managerApproval := core.NewNode("manager-approval", requestApprovalFn, ApprovalRequest{}).
        WithInputFunc(func(s *core.FlowState) ApprovalRequest {
            order := core.Get[Order](s, "order")
            return ApprovalRequest{
                OrderID: order.ID,
                Amount:  order.Total,
                Level:   "manager",
            }
        }).
        WithTimeout(24 * time.Hour)

    vpApproval := core.NewNode("vp-approval", requestApprovalFn, ApprovalRequest{}).
        WithInputFunc(func(s *core.FlowState) ApprovalRequest {
            order := core.Get[Order](s, "order")
            return ApprovalRequest{
                OrderID: order.ID,
                Amount:  order.Total,
                Level:   "vp",
            }
        }).
        WithTimeout(48 * time.Hour)

    // Processing nodes
    processPayment := core.NewNode("process-payment", processPaymentFn, PaymentInput{}).
        WithInputFunc(func(s *core.FlowState) PaymentInput {
            order := core.Get[Order](s, "order")
            return PaymentInput{OrderID: order.ID, Amount: order.Total}
        })

    rejectOrder := core.NewNode("reject-order", rejectOrderFn, RejectInput{}).
        WithInputFunc(func(s *core.FlowState) RejectInput {
            order := core.Get[Order](s, "order")
            validation := core.Get[ValidationResult](s, "validation")
            return RejectInput{
                OrderID: order.ID,
                Reasons: validation.Errors,
            }
        })

    fulfillOrder := core.NewNode("fulfill-order", fulfillOrderFn, FulfillInput{}).
        WithInputFunc(func(s *core.FlowState) FulfillInput {
            order := core.Get[Order](s, "order")
            return FulfillInput{OrderID: order.ID}
        })

    // Build flow with conditionals
    flow := core.NewFlow("order-processing").
        TriggeredBy(core.Manual("order-api")).
        Then(fetchOrder).
        Then(validateOrder).
        // First check: Is order valid?
        When(func(s *core.FlowState) bool {
            validation := core.Get[ValidationResult](s, "validation")
            return validation.Valid
        }).
        // Valid order path
        When(func(s *core.FlowState) bool {
            order := core.Get[Order](s, "order")
            // VIP customers or small orders auto-approve
            return order.Customer.VIP || order.Total < 500
        }).
        Then(autoApprove).
        Else().
        // Large orders need approval
        When(func(s *core.FlowState) bool {
            order := core.Get[Order](s, "order")
            return order.Total >= 10000
        }).
        Then(managerApproval).
        Then(vpApproval).  // VP also reviews very large orders
        Otherwise(managerApproval).  // Just manager for medium orders
        EndWhen().
        // After approval, process payment
        Then(processPayment).
        Then(fulfillOrder).
        Otherwise(rejectOrder).  // Invalid order path
        Build()

    core.NewWorker().
        WithConfig(core.WorkerConfig{
            TaskQueue: "orders-queue",
        }).
        WithFlow(flow).
        Run()
}
```

## Conditional Decision Diagram

```
                    ┌──────────────┐
                    │ fetchOrder   │
                    └──────┬───────┘
                           │
                    ┌──────▼───────┐
                    │validateOrder │
                    └──────┬───────┘
                           │
              ┌────────────▼────────────┐
              │   validation.Valid?     │
              └────────────┬────────────┘
                     yes   │   no
              ┌────────────┴────────────┐
              │                         │
     ┌────────▼────────┐       ┌────────▼────────┐
     │VIP || total<500?│       │  rejectOrder    │
     └────────┬────────┘       └─────────────────┘
        yes   │   no
     ┌────────┴────────┐
     │                 │
┌────▼────┐    ┌───────▼───────┐
│autoApprove│   │ total>=10000? │
└────┬────┘    └───────┬───────┘
     │           yes   │   no
     │    ┌────────────┴────────────┐
     │    │                         │
     │  ┌─▼──────────┐    ┌─────────▼─┐
     │  │mgr+vp      │    │mgr only   │
     │  │approval    │    │approval   │
     │  └────────────┘    └───────────┘
     │           │                │
     │           └────────┬───────┘
     │                    │
     └────────────────────┤
                          │
                   ┌──────▼───────┐
                   │processPayment│
                   └──────┬───────┘
                          │
                   ┌──────▼───────┐
                   │ fulfillOrder │
                   └──────────────┘
```

## Best Practices

### 1. Keep Predicates Simple

Extract complex logic into helper functions:

```go
// Good: Clear, named predicate
func needsApproval(s *core.FlowState) bool {
    order := core.Get[Order](s, "order")
    return order.Total > 1000 && !order.Customer.VIP
}

flow := core.NewFlow("orders").
    When(needsApproval).
    ...

// Avoid: Complex inline logic
When(func(s *core.FlowState) bool {
    o := core.Get[Order](s, "order")
    c := core.Get[Customer](s, "customer")
    h := core.Get[History](s, "history")
    return o.Total > 1000 && !c.VIP &&
           h.Disputes < 3 &&
           time.Since(c.CreatedAt) > 30*24*time.Hour
})
```

### 2. Handle All Cases

Ensure all paths are handled:

```go
// Good: Explicit handling
When(predicate).
Then(handleTrue).
Otherwise(handleFalse)

// Or explicit no-action else
When(predicate).
Then(handleTrue).
EndWhen()  // Explicit: do nothing if false

// Risky: Forgetting else
When(predicate).
Then(handleTrue)
// What happens if predicate is false?
```

### 3. Use Descriptive Node Names

Make conditional paths clear in logs:

```go
// Good: Clear what each path does
When(isHighValue).
Then(core.NewNode("approve-high-value", ...)).
Otherwise(core.NewNode("auto-approve-standard", ...))

// Avoid: Generic names
When(isHighValue).
Then(core.NewNode("step1", ...)).
Otherwise(core.NewNode("step2", ...))
```

### 4. Avoid Deep Nesting

Flatten complex conditionals when possible:

```go
// Consider: Multiple simple conditionals
flow := core.NewFlow("flat").
    Then(checkA).
    When(conditionA).Then(handleA).EndWhen().
    Then(checkB).
    When(conditionB).Then(handleB).EndWhen().
    Then(checkC).
    When(conditionC).Then(handleC).EndWhen().
    Build()

// Instead of: Deeply nested
flow := core.NewFlow("nested").
    When(conditionA).
        When(conditionB).
            When(conditionC).
                Then(handleABC).
            ...
```

### 5. Test All Branches

Ensure test coverage for each conditional path:

```go
func TestOrderFlow_VIPAutoApproves(t *testing.T) {
    tester := core.NewFlowTester(flow)
    tester.SetResult("order", Order{Total: 5000, Customer: Customer{VIP: true}})
    tester.SetResult("validation", ValidationResult{Valid: true})

    err := tester.Run()
    require.NoError(t, err)

    // Verify auto-approve was called, not manual approval
    assert.True(t, tester.WasExecuted("auto-approve"))
    assert.False(t, tester.WasExecuted("manager-approval"))
}

func TestOrderFlow_LargeOrderNeedsVPApproval(t *testing.T) {
    tester := core.NewFlowTester(flow)
    tester.SetResult("order", Order{Total: 15000, Customer: Customer{VIP: false}})
    tester.SetResult("validation", ValidationResult{Valid: true})

    err := tester.Run()
    require.NoError(t, err)

    // Both manager and VP should approve
    assert.True(t, tester.WasExecuted("manager-approval"))
    assert.True(t, tester.WasExecuted("vp-approval"))
}
```

## See Also

- **[Sequential Steps](/docs/guides/building-flows/sequential-steps/)** - Basic sequential execution
- **[Parallel Execution](/docs/guides/building-flows/parallel-execution/)** - Concurrent execution
- **[Error Handling](/docs/guides/building-flows/error-handling/)** - Handling failures
- **[FlowState](/docs/concepts/state/)** - Accessing state in predicates
- **[Testing](/docs/guides/testing/flow-tester/)** - Testing conditional flows
