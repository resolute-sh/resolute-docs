---
title: "Testing"
description: "Testing - Resolute documentation"
weight: 60
toc: true
---


# Testing

FlowTester provides a test harness for running flows without Temporal, enabling fast, deterministic unit tests with mocked activities.

## Types

### FlowTester

```go
type FlowTester struct {
    // unexported fields
}
```

Test harness for running flows synchronously with mocked activities.

## Constructor

### NewFlowTester

```go
func NewFlowTester() *FlowTester
```

Creates a new flow tester.

**Returns:** `*FlowTester` configured for testing

**Example:**
```go
tester := core.NewFlowTester()
```

## Mock Methods

### Mock

```go
func (t *FlowTester) Mock(name string, fn interface{}) *FlowTester
```

Registers a mock function for an activity. Use when the mock needs logic or input inspection.

**Parameters:**
- `name` - Activity name to mock
- `fn` - Mock function with signature matching the activity

**Returns:** `*FlowTester` for method chaining

**Example:**
```go
tester.Mock("jira.FetchIssues", func(input jira.FetchInput) (jira.FetchOutput, error) {
    if input.JQL == "project = EMPTY" {
        return jira.FetchOutput{Issues: []jira.Issue{}, Count: 0}, nil
    }
    return jira.FetchOutput{
        Issues: []jira.Issue{{Key: "TEST-1"}},
        Count:  1,
    }, nil
})
```

### MockValue

```go
func (t *FlowTester) MockValue(name string, value interface{}) *FlowTester
```

Registers a fixed return value for an activity. Use for simple fixed returns.

**Parameters:**
- `name` - Activity name to mock
- `value` - Value to return from the mock

**Returns:** `*FlowTester` for method chaining

**Example:**
```go
tester.MockValue("fetch-issues", jira.FetchOutput{
    Issues: []jira.Issue{{Key: "TEST-1"}, {Key: "TEST-2"}},
    Count:  2,
})
```

### MockError

```go
func (t *FlowTester) MockError(name string, err error) *FlowTester
```

Registers an error return for an activity. Use to simulate failures.

**Parameters:**
- `name` - Activity name to mock
- `err` - Error to return

**Returns:** `*FlowTester` for method chaining

**Example:**
```go
tester.MockError("fetch-issues", errors.New("connection timeout"))
```

## Execution Methods

### Run

```go
func (t *FlowTester) Run(flow *Flow, input FlowInput) (*FlowState, error)
```

Executes the flow synchronously with mocked activities.

**Parameters:**
- `flow` - Flow to execute
- `input` - Initial flow input

**Returns:**
- `*FlowState` - Final state after execution
- `error` - Error if execution fails

**Example:**
```go
state, err := tester.Run(myFlow, core.FlowInput{})
require.NoError(t, err)
```

### RunWithContext

```go
func (t *FlowTester) RunWithContext(ctx context.Context, flow *Flow, input FlowInput) (*FlowState, error)
```

Executes the flow with a context for cancellation or timeout.

**Parameters:**
- `ctx` - Context for cancellation/timeout
- `flow` - Flow to execute
- `input` - Initial flow input

**Returns:**
- `*FlowState` - Final state after execution
- `error` - Error if execution fails or context cancelled

**Example:**
```go
ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
defer cancel()

state, err := tester.RunWithContext(ctx, myFlow, core.FlowInput{})
```

## Call Tracking Methods

### WasCalled

```go
func (t *FlowTester) WasCalled(name string) bool
```

Returns true if the activity was called at least once.

**Parameters:**
- `name` - Activity name

**Returns:** `bool`

**Example:**
```go
assert.True(t, tester.WasCalled("fetch-issues"))
```

### CallCount

```go
func (t *FlowTester) CallCount(name string) int
```

Returns the number of times the activity was called.

**Parameters:**
- `name` - Activity name

**Returns:** Call count

**Example:**
```go
assert.Equal(t, 3, tester.CallCount("process-batch"))
```

### CallArgs

```go
func (t *FlowTester) CallArgs(name string) []interface{}
```

Returns all arguments from all calls to the activity.

**Parameters:**
- `name` - Activity name

**Returns:** Slice of arguments from each call

**Example:**
```go
args := tester.CallArgs("fetch-issues")
firstInput := args[0].(jira.FetchInput)
assert.Equal(t, "PLATFORM", firstInput.Project)
```

### LastCallArg

```go
func (t *FlowTester) LastCallArg(name string) interface{}
```

Returns the argument from the last call to the activity.

**Parameters:**
- `name` - Activity name

**Returns:** Last call's argument

**Example:**
```go
lastArg := tester.LastCallArg("fetch-issues")
input := lastArg.(jira.FetchInput)
assert.Equal(t, "PLATFORM", input.Project)
```

## Assertion Methods

### AssertCalled

```go
func (t *FlowTester) AssertCalled(t *testing.T, name string)
```

Asserts that the activity was called at least once.

**Parameters:**
- `t` - Test instance
- `name` - Activity name

**Example:**
```go
tester.AssertCalled(t, "fetch-issues")
tester.AssertCalled(t, "process-data")
```

### AssertNotCalled

```go
func (t *FlowTester) AssertNotCalled(t *testing.T, name string)
```

Asserts that the activity was not called.

**Parameters:**
- `t` - Test instance
- `name` - Activity name

**Example:**
```go
tester.AssertNotCalled(t, "skip-node")
```

### AssertCallCount

```go
func (t *FlowTester) AssertCallCount(t *testing.T, name string, expected int)
```

Asserts the activity was called exactly N times.

**Parameters:**
- `t` - Test instance
- `name` - Activity name
- `expected` - Expected call count

**Example:**
```go
tester.AssertCallCount(t, "fetch-page", 3)
```

## Reset Methods

### Reset

```go
func (t *FlowTester) Reset()
```

Resets call tracking only (keeps mocks).

**Example:**
```go
// Run first test
tester.Run(flow, input1)
assert.Equal(t, 1, tester.CallCount("fetch"))

// Reset and run second test
tester.Reset()
tester.Run(flow, input2)
assert.Equal(t, 1, tester.CallCount("fetch"))  // Count reset
```

### ResetAll

```go
func (t *FlowTester) ResetAll()
```

Resets everything (mocks and call tracking).

**Example:**
```go
tester.ResetAll()
// Must re-register mocks
tester.MockValue("fetch", output)
```

## Configuration Methods

### WithRateLimiting

```go
func (t *FlowTester) WithRateLimiting() *FlowTester
```

Enables rate limiting (disabled by default for speed).

**Returns:** `*FlowTester` for method chaining

**Example:**
```go
tester := core.NewFlowTester().WithRateLimiting()
```

## Usage Patterns

### Basic Test

```go
func TestDataSyncFlow(t *testing.T) {
    tester := core.NewFlowTester()

    // Register mocks
    tester.MockValue("fetch-issues", jira.FetchOutput{
        Issues: []jira.Issue{{Key: "TEST-1"}, {Key: "TEST-2"}},
        Count:  2,
    })
    tester.MockValue("process-issues", ProcessOutput{Processed: 2})
    tester.MockValue("store-results", StoreOutput{Stored: 2})

    // Run flow
    state, err := tester.Run(dataSyncFlow, core.FlowInput{})

    // Assert success
    require.NoError(t, err)

    // Assert all nodes called
    tester.AssertCalled(t, "fetch-issues")
    tester.AssertCalled(t, "process-issues")
    tester.AssertCalled(t, "store-results")

    // Assert final state
    result := core.Get[StoreOutput](state, "store-results")
    assert.Equal(t, 2, result.Stored)
}
```

### Testing Conditionals

```go
func TestConditionalFlow(t *testing.T) {
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

### Testing Error Handling

```go
func TestFlowErrorHandling(t *testing.T) {
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
}
```

### Testing Input Transformation

```go
func TestInputTransformation(t *testing.T) {
    tester := core.NewFlowTester()

    var processInput ProcessInput
    tester.MockValue("fetch", FetchOutput{RawData: "data", Count: 100})
    tester.Mock("process", func(input ProcessInput) (ProcessOutput, error) {
        processInput = input
        return ProcessOutput{}, nil
    })

    tester.Run(flow, core.FlowInput{})

    // Verify transformation happened
    assert.Equal(t, "DATA", processInput.NormalizedData)
    assert.Equal(t, 100, processInput.ItemCount)
}
```

### Table-Driven Tests

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

## Complete Example

```go
package flows_test

import (
    "testing"

    "github.com/stretchr/testify/assert"
    "github.com/stretchr/testify/require"

    "github.com/resolute/resolute/core"
    "myapp/flows"
    "myapp/providers/jira"
)

func TestIssueEnrichmentFlow(t *testing.T) {
    // Build the flow
    flow := flows.BuildEnrichmentFlow()

    // Create tester
    tester := core.NewFlowTester()

    // Mock all activities
    tester.Mock("fetch-issues", func(input jira.FetchInput) (jira.FetchOutput, error) {
        return jira.FetchOutput{
            Issues: []jira.Issue{
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
        Data: map[string][]byte{
            "project": []byte("TEST"),
        },
    })

    // Assertions
    require.NoError(t, err)

    // Verify execution order
    tester.AssertCalled(t, "fetch-issues")
    tester.AssertCalled(t, "generate-embeddings")
    tester.AssertCalled(t, "store-vectors")

    // Verify input passed correctly
    fetchInput := tester.LastCallArg("fetch-issues").(jira.FetchInput)
    assert.Equal(t, "TEST", fetchInput.Project)

    // Verify output
    storeResult := core.Get[StoreOutput](state, "store-vectors")
    assert.Equal(t, 2, storeResult.Stored)
}
```

## See Also

- **[FlowTester Guide](/docs/guides/testing/flow-tester/)** - Complete testing guide
- **[Mocking Activities](/docs/guides/testing/mocking-activities/)** - Mock patterns
- **[Integration Tests](/docs/guides/testing/integration-tests/)** - Testing with Temporal
