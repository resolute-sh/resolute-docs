---
title: "Compensation (Saga)"
description: "Compensation (Saga) - Resolute documentation"
weight: 10
toc: true
---


# Compensation (Saga Pattern)

The Saga pattern ensures data consistency across distributed operations by defining compensation actions for each step. When a later step fails, compensation actions run in reverse order to undo completed work.

## Why Saga?

In distributed systems, you can't use traditional transactions. If a multi-step operation fails partway through:

```
Step 1: Reserve Flight     ✓ (committed)
Step 2: Reserve Hotel      ✓ (committed)
Step 3: Charge Payment     ✗ (failed)
```

Without compensation, you have an inconsistent state: reserved flight and hotel with no payment. The Saga pattern solves this by defining how to undo each step.

## Basic Pattern

Use `.OnError()` to attach compensation handlers:

```go
// Define compensation
cancelFlight := core.NewNode("cancel-flight", cancelFlightFn, CancelInput{}).
    WithInputFunc(func(s *core.FlowState) CancelInput {
        flight := core.Get[FlightReservation](s, "flight")
        return CancelInput{ReservationID: flight.ID}
    })

// Attach to main operation
reserveFlight := core.NewNode("reserve-flight", reserveFlightFn, input).
    As("flight").
    OnError(cancelFlight)
```

## How Compensation Works

When a step fails after retries:

1. Compensation runs for each **completed** step with an `.OnError()` handler
2. Compensation runs in **reverse order** of completion
3. Each compensation receives a **snapshot** of state from when its step completed
4. After all compensations complete, the workflow fails with the original error

```
Forward Execution          Compensation (on failure)
──────────────────         ────────────────────────
Step A → completed
Step B → completed         ← compensate B
Step C → FAILED            ← compensate A
                           Return original error
```

## State Snapshots

Compensation nodes receive a **snapshot** of FlowState from when the original node completed, not the current state:

```go
// During execution:
// 1. reserveFlight completes (state has flight info)
// 2. reserveHotel completes (state has flight + hotel)
// 3. chargePayment fails
//
// During compensation:
// - cancelHotel receives snapshot from step 2 (sees hotel)
// - cancelFlight receives snapshot from step 1 (sees flight)

cancelHotel := core.NewNode("cancel-hotel", cancelHotelFn, CancelInput{}).
    WithInputFunc(func(s *core.FlowState) CancelInput {
        // 's' is the snapshot from when reserveHotel completed
        // It contains the hotel data from that point in time
        hotel := core.Get[HotelReservation](s, "hotel")
        return CancelInput{ReservationID: hotel.ID}
    })
```

## Complete Example: Travel Booking

```go
package main

import (
    "context"
    "fmt"
    "time"

    "github.com/resolute/resolute/core"
)

// Domain types
type FlightReservation struct {
    ID         string
    FlightNo   string
    Passenger  string
    SeatNumber string
}

type HotelReservation struct {
    ID       string
    HotelID  string
    RoomType string
    CheckIn  time.Time
    CheckOut time.Time
}

type CarReservation struct {
    ID       string
    VehicleID string
    PickupAt  time.Time
    ReturnAt  time.Time
}

type PaymentResult struct {
    TransactionID string
    Amount        float64
    Currency      string
}

// Forward operations
func reserveFlight(ctx context.Context, input FlightInput) (FlightReservation, error) {
    reservation, err := flightAPI.Reserve(ctx, input)
    if err != nil {
        return FlightReservation{}, fmt.Errorf("reserve flight: %w", err)
    }
    return reservation, nil
}

func reserveHotel(ctx context.Context, input HotelInput) (HotelReservation, error) {
    reservation, err := hotelAPI.Reserve(ctx, input)
    if err != nil {
        return HotelReservation{}, fmt.Errorf("reserve hotel: %w", err)
    }
    return reservation, nil
}

func reserveCar(ctx context.Context, input CarInput) (CarReservation, error) {
    reservation, err := carAPI.Reserve(ctx, input)
    if err != nil {
        return CarReservation{}, fmt.Errorf("reserve car: %w", err)
    }
    return reservation, nil
}

func chargePayment(ctx context.Context, input PaymentInput) (PaymentResult, error) {
    result, err := paymentAPI.Charge(ctx, input)
    if err != nil {
        return PaymentResult{}, fmt.Errorf("charge payment: %w", err)
    }
    return result, nil
}

// Compensation operations (idempotent!)
func cancelFlight(ctx context.Context, input CancelFlightInput) (CancelResult, error) {
    // Check if already cancelled (idempotent)
    status, _ := flightAPI.GetStatus(ctx, input.ReservationID)
    if status == "CANCELLED" {
        return CancelResult{AlreadyCancelled: true}, nil
    }

    err := flightAPI.Cancel(ctx, input.ReservationID)
    if err != nil {
        return CancelResult{}, fmt.Errorf("cancel flight: %w", err)
    }
    return CancelResult{Cancelled: true}, nil
}

func cancelHotel(ctx context.Context, input CancelHotelInput) (CancelResult, error) {
    status, _ := hotelAPI.GetStatus(ctx, input.ReservationID)
    if status == "CANCELLED" {
        return CancelResult{AlreadyCancelled: true}, nil
    }

    err := hotelAPI.Cancel(ctx, input.ReservationID)
    if err != nil {
        return CancelResult{}, fmt.Errorf("cancel hotel: %w", err)
    }
    return CancelResult{Cancelled: true}, nil
}

func cancelCar(ctx context.Context, input CancelCarInput) (CancelResult, error) {
    status, _ := carAPI.GetStatus(ctx, input.ReservationID)
    if status == "CANCELLED" {
        return CancelResult{AlreadyCancelled: true}, nil
    }

    err := carAPI.Cancel(ctx, input.ReservationID)
    if err != nil {
        return CancelResult{}, fmt.Errorf("cancel car: %w", err)
    }
    return CancelResult{Cancelled: true}, nil
}

func refundPayment(ctx context.Context, input RefundInput) (RefundResult, error) {
    // Check if transaction exists and wasn't already refunded
    tx, _ := paymentAPI.GetTransaction(ctx, input.TransactionID)
    if tx == nil || tx.Status == "REFUNDED" {
        return RefundResult{AlreadyRefunded: true}, nil
    }

    result, err := paymentAPI.Refund(ctx, input.TransactionID)
    if err != nil {
        return RefundResult{}, fmt.Errorf("refund payment: %w", err)
    }
    return result, nil
}

func main() {
    // Build compensation nodes
    cancelFlightNode := core.NewNode("cancel-flight", cancelFlight, CancelFlightInput{}).
        WithInputFunc(func(s *core.FlowState) CancelFlightInput {
            flight := core.Get[FlightReservation](s, "flight")
            return CancelFlightInput{ReservationID: flight.ID}
        })

    cancelHotelNode := core.NewNode("cancel-hotel", cancelHotel, CancelHotelInput{}).
        WithInputFunc(func(s *core.FlowState) CancelHotelInput {
            hotel := core.Get[HotelReservation](s, "hotel")
            return CancelHotelInput{ReservationID: hotel.ID}
        })

    cancelCarNode := core.NewNode("cancel-car", cancelCar, CancelCarInput{}).
        WithInputFunc(func(s *core.FlowState) CancelCarInput {
            car := core.Get[CarReservation](s, "car")
            return CancelCarInput{ReservationID: car.ID}
        })

    refundPaymentNode := core.NewNode("refund-payment", refundPayment, RefundInput{}).
        WithInputFunc(func(s *core.FlowState) RefundInput {
            payment := core.Get[PaymentResult](s, "payment")
            return RefundInput{TransactionID: payment.TransactionID}
        })

    // Build forward nodes with compensation
    flightNode := core.NewNode("reserve-flight", reserveFlight, FlightInput{}).
        WithTimeout(5 * time.Minute).
        As("flight").
        OnError(cancelFlightNode)

    hotelNode := core.NewNode("reserve-hotel", reserveHotel, HotelInput{}).
        WithInputFunc(func(s *core.FlowState) HotelInput {
            flight := core.Get[FlightReservation](s, "flight")
            return HotelInput{
                GuestName: flight.Passenger,
                // Other hotel details...
            }
        }).
        WithTimeout(5 * time.Minute).
        As("hotel").
        OnError(cancelHotelNode)

    carNode := core.NewNode("reserve-car", reserveCar, CarInput{}).
        WithInputFunc(func(s *core.FlowState) CarInput {
            flight := core.Get[FlightReservation](s, "flight")
            return CarInput{
                DriverName: flight.Passenger,
                // Other car details...
            }
        }).
        WithTimeout(5 * time.Minute).
        As("car").
        OnError(cancelCarNode)

    paymentNode := core.NewNode("charge-payment", chargePayment, PaymentInput{}).
        WithInputFunc(func(s *core.FlowState) PaymentInput {
            flight := core.Get[FlightReservation](s, "flight")
            hotel := core.Get[HotelReservation](s, "hotel")
            car := core.Get[CarReservation](s, "car")
            return PaymentInput{
                Amount: calculateTotal(flight, hotel, car),
            }
        }).
        WithTimeout(2 * time.Minute).
        As("payment").
        OnError(refundPaymentNode)

    confirmationNode := core.NewNode("send-confirmation", sendConfirmation, ConfirmInput{}).
        WithInputFunc(func(s *core.FlowState) ConfirmInput {
            return ConfirmInput{
                Flight:  core.Get[FlightReservation](s, "flight"),
                Hotel:   core.Get[HotelReservation](s, "hotel"),
                Car:     core.Get[CarReservation](s, "car"),
                Payment: core.Get[PaymentResult](s, "payment"),
            }
        })

    // Build the saga flow
    flow := core.NewFlow("travel-booking").
        TriggeredBy(core.Manual("booking-api")).
        Then(flightNode).
        Then(hotelNode).
        Then(carNode).
        Then(paymentNode).
        Then(confirmationNode).
        Build()

    core.NewWorker().
        WithConfig(core.WorkerConfig{TaskQueue: "bookings"}).
        WithFlow(flow).
        Run()
}
```

## Failure Scenarios

### Scenario 1: Early Failure

```
reserve-flight    → FAILED (after retries)
```

Result:
- No compensation needed (no completed steps with OnError)
- Workflow fails with flight error

### Scenario 2: Middle Failure

```
reserve-flight    → SUCCESS (flight reserved)
reserve-hotel     → SUCCESS (hotel reserved)
reserve-car       → FAILED (after retries)
```

Compensation sequence:
1. `cancel-hotel` runs (reverses hotel)
2. `cancel-flight` runs (reverses flight)
3. Workflow fails with car error

### Scenario 3: Late Failure (Payment)

```
reserve-flight    → SUCCESS
reserve-hotel     → SUCCESS
reserve-car       → SUCCESS
charge-payment    → FAILED
```

Compensation sequence:
1. `cancel-car` runs
2. `cancel-hotel` runs
3. `cancel-flight` runs
4. Workflow fails with payment error

### Scenario 4: Confirmation Failure

```
reserve-flight    → SUCCESS
reserve-hotel     → SUCCESS
reserve-car       → SUCCESS
charge-payment    → SUCCESS
send-confirmation → FAILED
```

Compensation sequence:
1. `refund-payment` runs (refunds charge)
2. `cancel-car` runs
3. `cancel-hotel` runs
4. `cancel-flight` runs
5. Workflow fails with confirmation error

## Parallel Steps with Compensation

Each parallel node can have its own compensation:

```go
flow := core.NewFlow("parallel-booking").
    TriggeredBy(core.Manual("api")).
    ThenParallel("reserve-all",
        flightNode.OnError(cancelFlightNode),
        hotelNode.OnError(cancelHotelNode),
        carNode.OnError(cancelCarNode),
    ).
    Then(paymentNode.OnError(refundNode)).
    Build()
```

If any parallel node fails, compensation runs for all completed nodes in the parallel step.

## Compensation Best Practices

### 1. Make Compensation Idempotent

Compensation may run multiple times (worker restarts, retries):

```go
func cancelReservation(ctx context.Context, input CancelInput) (CancelResult, error) {
    // Always check current state first
    status, err := api.GetStatus(ctx, input.ID)
    if err != nil {
        return CancelResult{}, err
    }

    // Already in desired state - success
    if status == "CANCELLED" {
        return CancelResult{AlreadyCancelled: true}, nil
    }

    // Proceed with cancellation
    return api.Cancel(ctx, input.ID)
}
```

### 2. Handle Partial Compensation Failure

Compensation itself might fail. Log failures but continue with other compensations:

```go
// Resolute handles this internally:
// - Logs compensation failures
// - Continues with remaining compensations
// - Returns original error (not compensation errors)
```

### 3. Design for Forward Recovery When Possible

Sometimes it's better to retry forward than compensate backward:

```go
// If payment validation fails, don't cancel reservations yet
paymentNode := core.NewNode("charge-payment", chargePayment, input).
    WithRetry(core.RetryPolicy{
        InitialInterval: time.Second,
        MaximumAttempts: 10,  // Try harder before giving up
    }).
    OnError(refundNode)
```

### 4. Consider Compensation Timeouts

Compensation has its own timeout:

```go
cancelFlightNode := core.NewNode("cancel-flight", cancelFlight, CancelInput{}).
    WithTimeout(2 * time.Minute).  // Generous timeout for compensation
    WithRetry(core.RetryPolicy{
        MaximumAttempts: 5,  // Retry compensation too
    })
```

### 5. Not Everything Needs Compensation

Only add compensation for operations with side effects:

```go
// Needs compensation: external state change
createUser := core.NewNode("create-user", createUserFn, input).
    OnError(deleteUser)

// No compensation needed: read-only operation
fetchUser := core.NewNode("fetch-user", fetchUserFn, input)

// No compensation needed: idempotent notification
sendEmail := core.NewNode("send-email", sendEmailFn, input)
```

## Testing Compensation

```go
func TestBookingFlow_CancelsOnPaymentFailure(t *testing.T) {
    tester := core.NewFlowTester(bookingFlow)

    // Set up successful reservations
    tester.SetResult("flight", FlightReservation{ID: "FL123"})
    tester.SetResult("hotel", HotelReservation{ID: "HT456"})
    tester.SetResult("car", CarReservation{ID: "CR789"})

    // Make payment fail
    tester.SetError("charge-payment", errors.New("insufficient funds"))

    // Run flow
    err := tester.Run()

    // Verify error
    require.Error(t, err)
    assert.Contains(t, err.Error(), "insufficient funds")

    // Verify all compensations ran
    assert.True(t, tester.WasExecuted("cancel-car"))
    assert.True(t, tester.WasExecuted("cancel-hotel"))
    assert.True(t, tester.WasExecuted("cancel-flight"))

    // Verify compensation received correct data
    cancelCarInput := tester.GetInput("cancel-car").(CancelCarInput)
    assert.Equal(t, "CR789", cancelCarInput.ReservationID)
}
```

## See Also

- **[Error Handling](/docs/guides/building-flows/error-handling/)** - Error handling basics
- **[Parallel Execution](/docs/guides/building-flows/parallel-execution/)** - Parallel compensation
- **[Sequential Steps](/docs/guides/building-flows/sequential-steps/)** - Building saga steps
- **[Testing](/docs/guides/testing/flow-tester/)** - Testing saga flows
