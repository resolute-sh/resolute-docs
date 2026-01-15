---
title: "FlowTester"
description: "FlowTester - Resolute documentation"
weight: 10
toc: true
---


# FlowTester

FlowTester provides a test harness for running flows without Temporal. It enables fast, deterministic unit tests with mocked activities.

## Why FlowTester?

Testing flows directly with Temporal requires:
- Running a Temporal server
- Managing workers
- Handling async execution
- Slower test execution

FlowTester eliminates this by:
- Running flows synchronously
- Mocking activities in-process
- Providing assertion helpers
- Enabling fast unit tests

## Basic Usage

```go
func TestDataSyncFlow(t *testing.T) {
    // Create tester
    tester := core.NewFlowTester()

    // Register mocks
    tester.MockValue("fetch-issues", FetchOutput{
        Issues: []Issue{{Key: "TEST-1"}, {Key: "TEST-2"}},
        Count:  2,
    })
    tester.MockValue("process-issues", ProcessOutput{
        Processed: 2,
    })
    tester.MockValue("store-results", StoreOutput{
        Stored: 2,
    })

    // Run the flow
    state, err := tester.Run(dataSyncFlow, core.FlowInput{})

    // Assert success
    require.NoError(t, err)

    // Assert all nodes were called
    tester.AssertCalled(t, "fetch-issues")
    tester.AssertCalled(t, "process-issues")
    tester.AssertCalled(t, "store-results")

    // Assert final state
    result := core.Get[StoreOutput](state, "store-results")
    assert.Equal(t, 2, result.Stored)
}
```

## Creating a FlowTester

```go
tester := core.NewFlowTester()
```

Options:

```go
// Enable rate limiting (disabled by default for speed)
tester := core.NewFlowTester().WithRateLimiting()
```

## Running Flows

### Basic Run

```go
state, err := tester.Run(flow, core.FlowInput{})
```

### With Context

For cancellation or timeout:

```go
ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
defer cancel()

state, err := tester.RunWithContext(ctx, flow, core.FlowInput{})
```

### With Input

Pass initial data to the flow:

```go
state, err := tester.Run(flow, core.FlowInput{
    "project": "PLATFORM",
    "since":   time.Now().Add(-24 * time.Hour),
})
```

## FlowState Access

After running, access flow state:

```go
// Get typed result
fetchResult := core.Get[FetchOutput](state, "fetch")
assert.Equal(t, 5, fetchResult.Count)

// Get with default
processResult := core.GetOr(state, "process", ProcessOutput{})

// Check result exists
result := state.GetResult("some-node")
assert.NotNil(t, result)
```

## Call Tracking

### Check if Called

```go
// Was the node called?
assert.True(t, tester.WasCalled("fetch"))

// Assertion helper
tester.AssertCalled(t, "fetch")
tester.AssertNotCalled(t, "skip-node")
```

### Call Count

```go
// Get call count
count := tester.CallCount("fetch")
assert.Equal(t, 1, count)

// Assertion helper
tester.AssertCallCount(t, "fetch", 1)
```

### Call Arguments

```go
// Get all arguments from all calls
args := tester.CallArgs("fetch")
firstInput := args[0].(FetchInput)
assert.Equal(t, "PLATFORM", firstInput.Project)

// Get last call's argument
lastArg := tester.LastCallArg("fetch")
input := lastArg.(FetchInput)
assert.Equal(t, "PLATFORM", input.Project)
```

## Resetting State

```go
// Reset call tracking only (keep mocks)
tester.Reset()

// Reset everything (mocks and call tracking)
tester.ResetAll()
```

## Complete Example

```go
func TestIssueEnrichmentFlow(t *testing.T) {
    // Build the flow
    flow := buildEnrichmentFlow()

    // Create tester
    tester := core.NewFlowTester()

    // Mock all activities
    tester.Mock("fetch-issues", func(input FetchInput) (FetchOutput, error) {
        return FetchOutput{
            Issues: []Issue{
                {Key: "TEST-1", Summary: "First issue"},
                {Key: "TEST-2", Summary: "Second issue"},
            },
            Count: 2,
        }, nil
    })

    tester.Mock("generate-embeddings", func(input EmbedInput) (EmbedOutput, error) {
        embeddings := make([][]float32, len(input.Texts))
        for i := range embeddings {
            embeddings[i] = make([]float32, 384)
        }
        return EmbedOutput{Embeddings: embeddings}, nil
    })

    tester.Mock("store-vectors", func(input StoreInput) (StoreOutput, error) {
        return StoreOutput{Stored: len(input.Vectors)}, nil
    })

    // Run flow
    state, err := tester.Run(flow, core.FlowInput{
        "project": "TEST",
    })

    // Assertions
    require.NoError(t, err)

    // Verify execution order
    tester.AssertCalled(t, "fetch-issues")
    tester.AssertCalled(t, "generate-embeddings")
    tester.AssertCalled(t, "store-vectors")

    // Verify input passed correctly
    fetchInput := tester.LastCallArg("fetch-issues").(FetchInput)
    assert.Equal(t, "TEST", fetchInput.Project)

    // Verify output
    storeResult := core.Get[StoreOutput](state, "store-vectors")
    assert.Equal(t, 2, storeResult.Stored)
}
```

## Testing Conditionals

```go
func TestConditionalFlow(t *testing.T) {
    // Build flow with conditional
    flow := core.NewFlow("conditional-test").
        Then(checkNode).
        When(func(s *core.FlowState) bool {
            result := core.Get[CheckOutput](s, "check")
            return result.NeedsProcessing
        }).
            Then(processNode).
        Otherwise().
            Then(skipNode).
        EndWhen().
        Build()

    t.Run("takes then branch when condition true", func(t *testing.T) {
        tester := core.NewFlowTester()
        tester.MockValue("check", CheckOutput{NeedsProcessing: true})
        tester.MockValue("process", ProcessOutput{})
        tester.MockValue("skip", SkipOutput{})

        _, err := tester.Run(flow, core.FlowInput{})
        require.NoError(t, err)

        tester.AssertCalled(t, "check")
        tester.AssertCalled(t, "process")
        tester.AssertNotCalled(t, "skip")
    })

    t.Run("takes else branch when condition false", func(t *testing.T) {
        tester := core.NewFlowTester()
        tester.MockValue("check", CheckOutput{NeedsProcessing: false})
        tester.MockValue("process", ProcessOutput{})
        tester.MockValue("skip", SkipOutput{})

        _, err := tester.Run(flow, core.FlowInput{})
        require.NoError(t, err)

        tester.AssertCalled(t, "check")
        tester.AssertNotCalled(t, "process")
        tester.AssertCalled(t, "skip")
    })
}
```

## Testing Parallel Steps

FlowTester executes parallel steps sequentially for determinism:

```go
func TestParallelFlow(t *testing.T) {
    flow := core.NewFlow("parallel-test").
        Then(fetchNode).
        ThenParallel("enrich",
            enrichANode,
            enrichBNode,
            enrichCNode,
        ).
        Then(aggregateNode).
        Build()

    tester := core.NewFlowTester()
    tester.MockValue("fetch", FetchOutput{Data: "test"})
    tester.MockValue("enrich-a", EnrichAOutput{Value: 1})
    tester.MockValue("enrich-b", EnrichBOutput{Value: 2})
    tester.MockValue("enrich-c", EnrichCOutput{Value: 3})
    tester.MockValue("aggregate", AggregateOutput{Total: 6})

    state, err := tester.Run(flow, core.FlowInput{})
    require.NoError(t, err)

    // All parallel nodes called
    tester.AssertCalled(t, "enrich-a")
    tester.AssertCalled(t, "enrich-b")
    tester.AssertCalled(t, "enrich-c")

    // Final aggregation
    result := core.Get[AggregateOutput](state, "aggregate")
    assert.Equal(t, 6, result.Total)
}
```

## Testing Error Handling

```go
func TestFlowErrorHandling(t *testing.T) {
    t.Run("propagates activity error", func(t *testing.T) {
        tester := core.NewFlowTester()
        tester.MockValue("fetch", FetchOutput{Count: 5})
        tester.MockError("process", errors.New("processing failed"))
        tester.MockValue("store", StoreOutput{})

        _, err := tester.Run(flow, core.FlowInput{})

        require.Error(t, err)
        assert.Contains(t, err.Error(), "processing failed")

        // Verify execution stopped at error
        tester.AssertCalled(t, "fetch")
        tester.AssertCalled(t, "process")
        tester.AssertNotCalled(t, "store")
    })
}
```

## Testing Data Flow

Verify data passes correctly between nodes:

```go
func TestDataFlowBetweenNodes(t *testing.T) {
    flow := core.NewFlow("data-flow").
        Then(fetchNode.As("fetch")).
        Then(processNode).
        Build()

    tester := core.NewFlowTester()

    // Track what process receives
    var receivedInput ProcessInput
    tester.MockValue("fetch", FetchOutput{
        Items: []Item{{ID: "1"}, {ID: "2"}},
    })
    tester.Mock("process", func(input ProcessInput) (ProcessOutput, error) {
        receivedInput = input
        return ProcessOutput{Processed: len(input.Items)}, nil
    })

    _, err := tester.Run(flow, core.FlowInput{})
    require.NoError(t, err)

    // Verify data passed correctly
    assert.Equal(t, 2, len(receivedInput.Items))
    assert.Equal(t, "1", receivedInput.Items[0].ID)
}
```

## Best Practices

### 1. Test One Thing Per Test

```go
// Good: Focused test
func TestFlow_FetchesAllPages(t *testing.T) {
    // ...
}

func TestFlow_StopsOnError(t *testing.T) {
    // ...
}

// Bad: Testing too much
func TestFlow_EverythingWorks(t *testing.T) {
    // ...
}
```

### 2. Use Table-Driven Tests

```go
func TestConditionalRouting(t *testing.T) {
    tests := []struct {
        name          string
        condition     bool
        expectProcess bool
        expectSkip    bool
    }{
        {
            name:          "processes when condition true",
            condition:     true,
            expectProcess: true,
            expectSkip:    false,
        },
        {
            name:          "skips when condition false",
            condition:     false,
            expectProcess: false,
            expectSkip:    true,
        },
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            tester := core.NewFlowTester()
            tester.MockValue("check", CheckOutput{NeedsWork: tt.condition})
            tester.MockValue("process", ProcessOutput{})
            tester.MockValue("skip", SkipOutput{})

            tester.Run(flow, core.FlowInput{})

            if tt.expectProcess {
                tester.AssertCalled(t, "process")
            } else {
                tester.AssertNotCalled(t, "process")
            }

            if tt.expectSkip {
                tester.AssertCalled(t, "skip")
            } else {
                tester.AssertNotCalled(t, "skip")
            }
        })
    }
}
```

### 3. Reset Between Tests

```go
func TestMultipleRuns(t *testing.T) {
    tester := core.NewFlowTester()
    tester.MockValue("fetch", FetchOutput{Count: 5})

    // First run
    tester.Run(flow, core.FlowInput{})
    assert.Equal(t, 1, tester.CallCount("fetch"))

    // Reset before second run
    tester.Reset()

    // Second run
    tester.Run(flow, core.FlowInput{})
    assert.Equal(t, 1, tester.CallCount("fetch")) // Reset count
}
```

### 4. Test Edge Cases

```go
func TestFlow_HandlesEmptyResults(t *testing.T) {
    tester := core.NewFlowTester()
    tester.MockValue("fetch", FetchOutput{Items: []Item{}})
    tester.MockValue("process", ProcessOutput{})

    state, err := tester.Run(flow, core.FlowInput{})
    require.NoError(t, err)

    result := core.Get[ProcessOutput](state, "process")
    assert.Equal(t, 0, result.Processed)
}
```

## See Also

- **[Mocking Activities](/docs/guides/testing/mocking-activities/)** - Detailed mocking patterns
- **[Integration Tests](/docs/guides/testing/integration-tests/)** - Testing with real Temporal
- **[Error Handling](/docs/guides/building-flows/error-handling/)** - Error scenarios to test
- **[Conditional Logic](/docs/guides/building-flows/conditional-logic/)** - Testing conditionals
