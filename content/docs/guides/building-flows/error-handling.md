---
title: "Error Handling"
description: "Error Handling - Resolute documentation"
weight: 40
toc: true
---


# Error Handling

Resolute provides multiple layers of error handling: automatic retries, compensation (Saga pattern), and graceful degradation. Understanding these mechanisms helps build resilient workflows.

## Error Propagation

When an activity fails:

1. **Retry** according to `RetryPolicy` (automatic)
2. **Propagate** error if all retries exhausted
3. **Compensate** previously completed nodes (if configured)
4. **Fail** the workflow with the original error

```
Activity Fails
     │
     ▼
┌──────────────┐
│ Retry Policy │──retry──▶ Activity
└──────┬───────┘
       │ exhausted
       ▼
┌──────────────┐
│ Compensation │──runs──▶ Previous nodes' OnError handlers
└──────┬───────┘
       │
       ▼
  Workflow Fails
```

## Retry Policies

### Default Retry Behavior

Every node gets a default retry policy:

```go
RetryPolicy{
    InitialInterval:    time.Second,      // First retry after 1s
    BackoffCoefficient: 2.0,              // Double wait each retry
    MaximumInterval:    time.Minute,      // Cap at 1 minute between retries
    MaximumAttempts:    3,                // Try up to 3 times total
}
```

### Custom Retry Configuration

Override for specific needs:

```go
// External API: more retries, longer intervals
apiNode := core.NewNode("call-api", callAPI, input).
    WithRetry(core.RetryPolicy{
        InitialInterval:    2 * time.Second,
        BackoffCoefficient: 2.0,
        MaximumInterval:    5 * time.Minute,
        MaximumAttempts:    10,
    })

// Idempotent operation: aggressive retries
idempotentNode := core.NewNode("store-data", storeData, input).
    WithRetry(core.RetryPolicy{
        InitialInterval:    100 * time.Millisecond,
        BackoffCoefficient: 1.5,
        MaximumInterval:    10 * time.Second,
        MaximumAttempts:    20,
    })

// Non-retryable: fail immediately
criticalNode := core.NewNode("validate", validate, input).
    WithRetry(core.RetryPolicy{
        MaximumAttempts: 1,  // No retries
    })
```

### Retry Timing Example

With `InitialInterval: 1s`, `BackoffCoefficient: 2.0`, `MaximumAttempts: 5`:

```
Attempt 1: Execute (fails)
Wait 1s
Attempt 2: Execute (fails)
Wait 2s
Attempt 3: Execute (fails)
Wait 4s
Attempt 4: Execute (fails)
Wait 8s
Attempt 5: Execute (fails)
→ Error propagated
```

## Compensation (Saga Pattern)

For operations that need rollback on failure, use `.OnError()`:

```go
// Define compensation node
cancelReservation := core.NewNode("cancel-reservation", cancelReservationFn, CancelInput{}).
    WithInputFunc(func(s *core.FlowState) CancelInput {
        reservation := core.Get[ReservationOutput](s, "reserve")
        return CancelInput{ReservationID: reservation.ID}
    })

// Attach compensation to main node
reserveNode := core.NewNode("reserve", makeReservation, ReserveInput{}).
    OnError(cancelReservation)
```

### How Compensation Works

```go
flow := core.NewFlow("booking").
    TriggeredBy(core.Manual("api")).
    Then(reserveFlight.OnError(cancelFlight)).
    Then(reserveHotel.OnError(cancelHotel)).
    Then(chargePayment.OnError(refundPayment)).
    Then(sendConfirmation).
    Build()
```

If `chargePayment` fails after retries:
1. `refundPayment` runs (for `chargePayment` - nothing to refund, but called)
2. `cancelHotel` runs (reverses hotel reservation)
3. `cancelFlight` runs (reverses flight reservation)
4. Workflow fails with payment error

Compensation runs in **reverse order** of completion.

### Compensation State

Compensation nodes receive a **snapshot** of FlowState from when the original node completed:

```go
cancelReservation := core.NewNode("cancel", cancelFn, CancelInput{}).
    WithInputFunc(func(s *core.FlowState) CancelInput {
        // 's' contains state as it was when 'reserve' completed
        // Even if later nodes modified state, we see the snapshot
        reservation := core.Get[ReservationOutput](s, "reserve")
        return CancelInput{
            ReservationID: reservation.ID,
            Timestamp:     reservation.CreatedAt,
        }
    })
```

### Complete Saga Example

```go
package main

import (
    "context"
    "time"

    "github.com/resolute/resolute/core"
)

type FlightReservation struct {
    ID        string
    FlightNo  string
    Passenger string
}

type HotelReservation struct {
    ID       string
    HotelID  string
    CheckIn  time.Time
    CheckOut time.Time
}

type PaymentResult struct {
    TransactionID string
    Amount        float64
}

func main() {
    // Forward operations
    reserveFlight := core.NewNode("reserve-flight", reserveFlightFn, FlightInput{}).
        WithTimeout(5 * time.Minute).
        As("flight")

    reserveHotel := core.NewNode("reserve-hotel", reserveHotelFn, HotelInput{}).
        WithInputFunc(func(s *core.FlowState) HotelInput {
            flight := core.Get[FlightReservation](s, "flight")
            return HotelInput{PassengerName: flight.Passenger}
        }).
        WithTimeout(5 * time.Minute).
        As("hotel")

    chargePayment := core.NewNode("charge-payment", chargePaymentFn, PaymentInput{}).
        WithInputFunc(func(s *core.FlowState) PaymentInput {
            flight := core.Get[FlightReservation](s, "flight")
            hotel := core.Get[HotelReservation](s, "hotel")
            return PaymentInput{
                FlightCost: calculateFlightCost(flight),
                HotelCost:  calculateHotelCost(hotel),
            }
        }).
        WithTimeout(2 * time.Minute).
        As("payment")

    // Compensation operations
    cancelFlight := core.NewNode("cancel-flight", cancelFlightFn, CancelFlightInput{}).
        WithInputFunc(func(s *core.FlowState) CancelFlightInput {
            flight := core.Get[FlightReservation](s, "flight")
            return CancelFlightInput{ReservationID: flight.ID}
        })

    cancelHotel := core.NewNode("cancel-hotel", cancelHotelFn, CancelHotelInput{}).
        WithInputFunc(func(s *core.FlowState) CancelHotelInput {
            hotel := core.Get[HotelReservation](s, "hotel")
            return CancelHotelInput{ReservationID: hotel.ID}
        })

    refundPayment := core.NewNode("refund-payment", refundPaymentFn, RefundInput{}).
        WithInputFunc(func(s *core.FlowState) RefundInput {
            payment := core.Get[PaymentResult](s, "payment")
            return RefundInput{TransactionID: payment.TransactionID}
        })

    // Attach compensation
    reserveFlight = reserveFlight.OnError(cancelFlight)
    reserveHotel = reserveHotel.OnError(cancelHotel)
    chargePayment = chargePayment.OnError(refundPayment)

    // Build flow
    flow := core.NewFlow("travel-booking").
        TriggeredBy(core.Manual("booking-api")).
        Then(reserveFlight).
        Then(reserveHotel).
        Then(chargePayment).
        Then(sendConfirmationNode).
        Build()

    core.NewWorker().
        WithConfig(core.WorkerConfig{TaskQueue: "bookings"}).
        WithFlow(flow).
        Run()
}
```

## Timeout Configuration

Timeouts prevent activities from running indefinitely:

```go
// Activity-level timeout
node := core.NewNode("slow-operation", slowOp, input).
    WithTimeout(10 * time.Minute)
```

When timeout is reached:
1. Activity is cancelled
2. Treated as failure (triggers retry policy)
3. If retries exhausted, compensation runs

### Timeout Best Practices

```go
// External API: allow for latency
fetchNode := core.NewNode("fetch", fetchFromAPI, input).
    WithTimeout(5 * time.Minute)

// CPU-intensive: should be fast
processNode := core.NewNode("process", processData, input).
    WithTimeout(30 * time.Second)

// Human approval: may take days
approvalNode := core.NewNode("approval", waitForApproval, input).
    WithTimeout(72 * time.Hour)
```

## Graceful Degradation

Sometimes you want to continue despite failures:

### Option 1: Catch in Activity

Handle errors within the activity function:

```go
func enrichWithOptionalData(ctx context.Context, input EnrichInput) (EnrichOutput, error) {
    output := EnrichOutput{
        Primary: input.Primary,
    }

    // Try to enrich, but don't fail if unavailable
    optional, err := fetchOptionalData(ctx, input.ID)
    if err != nil {
        // Log but continue
        log.Printf("optional enrichment failed: %v", err)
        output.OptionalAvailable = false
    } else {
        output.Optional = optional
        output.OptionalAvailable = true
    }

    return output, nil  // Success even if optional failed
}
```

### Option 2: Conditional Error Handling

Use conditionals to handle failure states:

```go
flow := core.NewFlow("resilient-pipeline").
    TriggeredBy(core.Manual("api")).
    Then(fetchPrimaryData).
    Then(tryEnrichment).  // May fail
    When(func(s *core.FlowState) bool {
        result := core.GetOr(s, "enrichment", EnrichOutput{Success: false})
        return result.Success
    }).
    Then(processEnrichedData).
    Otherwise(processBasicData).
    Then(storeResult).
    Build()
```

### Option 3: Default Values

Use `GetOr` for default fallbacks:

```go
processNode := core.NewNode("process", processData, ProcessInput{}).
    WithInputFunc(func(s *core.FlowState) ProcessInput {
        // Primary data (required)
        primary := core.Get[PrimaryOutput](s, "fetch")

        // Optional enrichment (with default)
        enrichment := core.GetOr(s, "enrich", EnrichOutput{
            Score:  0.5,  // Default score
            Tags:   []string{},
        })

        return ProcessInput{
            Data:  primary.Data,
            Score: enrichment.Score,
            Tags:  enrichment.Tags,
        }
    })
```

## Error Types

### Retryable vs Non-Retryable

Activities can signal non-retryable errors:

```go
import "go.temporal.io/sdk/temporal"

func validateInput(ctx context.Context, input ValidateInput) (ValidateOutput, error) {
    if input.Value < 0 {
        // Non-retryable: input will never become valid
        return ValidateOutput{}, temporal.NewNonRetryableApplicationError(
            "negative value not allowed",
            "INVALID_INPUT",
            nil,
        )
    }

    // Retryable errors (e.g., network issues) return normally
    result, err := callValidationService(ctx, input)
    if err != nil {
        return ValidateOutput{}, err  // Will be retried
    }

    return result, nil
}
```

### Wrapping Errors

Provide context in errors:

```go
func fetchIssues(ctx context.Context, input FetchInput) (FetchOutput, error) {
    resp, err := jiraClient.Search(ctx, input.JQL)
    if err != nil {
        return FetchOutput{}, fmt.Errorf("jira search (jql=%s): %w", input.JQL, err)
    }

    return FetchOutput{Issues: resp.Issues}, nil
}
```

## Parallel Error Handling

In parallel steps, the first error stops the step:

```go
flow := core.NewFlow("parallel-with-errors").
    TriggeredBy(core.Manual("api")).
    ThenParallel("risky-parallel",
        nodeA.OnError(compensateA),
        nodeB.OnError(compensateB),
        nodeC.OnError(compensateC),
    ).
    Then(nextStep).
    Build()
```

If nodeB fails:
1. nodeA and nodeC may complete (if they were faster)
2. Compensation runs for completed nodes
3. Workflow fails

### Partial Success Strategy

For best-effort parallel execution:

```go
// Wrapper that catches errors
func bestEffort[I, O any](activity func(context.Context, I) (O, error)) func(context.Context, I) (Result[O], error) {
    return func(ctx context.Context, input I) (Result[O], error) {
        output, err := activity(ctx, input)
        if err != nil {
            return Result[O]{Error: err.Error()}, nil  // Return success with error info
        }
        return Result[O]{Value: output, Success: true}, nil
    }
}

// Use wrapped activities
enrichA := core.NewNode("enrich-a", bestEffort(enrichFromA), input)
enrichB := core.NewNode("enrich-b", bestEffort(enrichFromB), input)
enrichC := core.NewNode("enrich-c", bestEffort(enrichFromC), input)

flow := core.NewFlow("best-effort-enrich").
    ThenParallel("enrich-all", enrichA, enrichB, enrichC).
    Then(aggregateWithPartialResults).
    Build()
```

## Testing Error Scenarios

```go
func TestFlow_CompensationOnFailure(t *testing.T) {
    // Create test flow
    tester := core.NewFlowTester(bookingFlow)

    // Set up successful steps
    tester.SetResult("reserve-flight", FlightReservation{ID: "FL123"})
    tester.SetResult("reserve-hotel", HotelReservation{ID: "HT456"})

    // Make payment fail
    tester.SetError("charge-payment", errors.New("insufficient funds"))

    // Run flow
    err := tester.Run()

    // Verify error
    require.Error(t, err)
    assert.Contains(t, err.Error(), "insufficient funds")

    // Verify compensation ran
    assert.True(t, tester.WasExecuted("cancel-hotel"))
    assert.True(t, tester.WasExecuted("cancel-flight"))
}

func TestFlow_RetryExhaustion(t *testing.T) {
    tester := core.NewFlowTester(flow)

    // Fail consistently
    attempts := 0
    tester.MockActivity("flaky-api", func(ctx context.Context, input FlakyInput) (FlakyOutput, error) {
        attempts++
        return FlakyOutput{}, errors.New("service unavailable")
    })

    err := tester.Run()

    require.Error(t, err)
    assert.Equal(t, 3, attempts)  // Default retry policy
}
```

## Best Practices

### 1. Configure Retries Based on Error Type

```go
// Transient errors: retry aggressively
networkNode := core.NewNode("network-call", networkCall, input).
    WithRetry(core.RetryPolicy{
        InitialInterval:    100 * time.Millisecond,
        MaximumAttempts:    10,
    })

// Validation: no retries needed
validateNode := core.NewNode("validate", validate, input).
    WithRetry(core.RetryPolicy{
        MaximumAttempts: 1,
    })
```

### 2. Always Add Compensation for Side Effects

```go
// Good: Compensation for each side effect
createUser := core.NewNode("create-user", createUserFn, input).OnError(deleteUser)
sendWelcome := core.NewNode("send-welcome", sendWelcomeFn, input)  // Idempotent, no compensation needed
createBilling := core.NewNode("create-billing", createBillingFn, input).OnError(deleteBilling)

// Bad: Missing compensation
createUser := core.NewNode("create-user", createUserFn, input)  // User orphaned if later step fails
```

### 3. Make Compensation Idempotent

Compensation may run multiple times:

```go
func cancelReservation(ctx context.Context, input CancelInput) (CancelOutput, error) {
    // Check if already cancelled (idempotent)
    status, err := getReservationStatus(ctx, input.ID)
    if err != nil {
        return CancelOutput{}, err
    }

    if status == "CANCELLED" {
        return CancelOutput{AlreadyCancelled: true}, nil
    }

    // Proceed with cancellation
    return doCancel(ctx, input.ID)
}
```

### 4. Log Sufficient Context

Include context in error messages:

```go
func processOrder(ctx context.Context, input OrderInput) (OrderOutput, error) {
    order, err := fetchOrder(ctx, input.OrderID)
    if err != nil {
        return OrderOutput{}, fmt.Errorf(
            "fetch order (id=%s, customer=%s): %w",
            input.OrderID, input.CustomerID, err,
        )
    }
    // ...
}
```

## See Also

- **[Sequential Steps](/docs/guides/building-flows/sequential-steps/)** - Basic flow structure
- **[Parallel Execution](/docs/guides/building-flows/parallel-execution/)** - Error handling in parallel
- **[Compensation (Saga)](/docs/guides/advanced-patterns/compensation-saga/)** - Deep dive on Saga pattern
- **[Testing](/docs/guides/testing/flow-tester/)** - Testing error scenarios
- **[Temporal Foundation](/docs/concepts/temporal-foundation/)** - Underlying retry mechanics
