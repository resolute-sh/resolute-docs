---
title: "Mocking Activities"
description: "Mocking Activities - Resolute documentation"
weight: 20
toc: true
---


# Mocking Activities

FlowTester provides three mocking approaches: function mocks, value mocks, and error mocks. Each serves different testing needs.

## Mock Methods

| Method | Use Case |
|--------|----------|
| `Mock(name, fn)` | Dynamic behavior based on input |
| `MockValue(name, value)` | Fixed successful return value |
| `MockError(name, err)` | Simulate activity failure |

## Function Mocks

Use `Mock()` when the mock needs logic or input inspection.

### Basic Function Mock

```go
tester.Mock("jira.FetchIssues", func(input FetchInput) (FetchOutput, error) {
    return FetchOutput{
        Issues: []Issue{{Key: "TEST-1"}, {Key: "TEST-2"}},
        Count:  2,
    }, nil
})
```

### Input-Dependent Mock

```go
tester.Mock("jira.FetchIssues", func(input FetchInput) (FetchOutput, error) {
    // Return different results based on input
    if input.JQL == "project = EMPTY" {
        return FetchOutput{Issues: []Issue{}, Count: 0}, nil
    }

    return FetchOutput{
        Issues: []Issue{{Key: "TEST-1"}},
        Count:  1,
    }, nil
})
```

### Conditional Error Mock

```go
tester.Mock("api.Call", func(input APIInput) (APIOutput, error) {
    if input.ID == "invalid" {
        return APIOutput{}, errors.New("not found")
    }
    return APIOutput{Value: "success"}, nil
})
```

### State-Tracking Mock

```go
var callInputs []FetchInput

tester.Mock("fetch", func(input FetchInput) (FetchOutput, error) {
    callInputs = append(callInputs, input)
    return FetchOutput{Count: 5}, nil
})

// After running flow
assert.Len(t, callInputs, 1)
assert.Equal(t, "PLATFORM", callInputs[0].Project)
```

## Value Mocks

Use `MockValue()` for simple fixed returns.

### Basic Value Mock

```go
tester.MockValue("fetch", FetchOutput{
    Issues: []Issue{{Key: "TEST-1"}, {Key: "TEST-2"}},
    Count:  2,
})
```

### Multiple Value Mocks

```go
tester.
    MockValue("fetch", FetchOutput{Count: 5}).
    MockValue("process", ProcessOutput{Processed: 5}).
    MockValue("store", StoreOutput{Stored: 5})
```

### Complex Output

```go
tester.MockValue("generate-embeddings", EmbedOutput{
    Embeddings: [][]float32{
        {0.1, 0.2, 0.3},
        {0.4, 0.5, 0.6},
    },
    Model: "text-embedding-3-small",
})
```

## Error Mocks

Use `MockError()` to simulate failures.

### Basic Error Mock

```go
tester.MockError("fetch", errors.New("connection timeout"))
```

### Custom Error Types

```go
tester.MockError("fetch", &APIError{
    Code:    429,
    Message: "rate limited",
})
```

### Testing Error Propagation

```go
func TestFlow_PropagatesError(t *testing.T) {
    tester := core.NewFlowTester()
    tester.MockValue("step-1", Step1Output{})
    tester.MockError("step-2", errors.New("step 2 failed"))
    tester.MockValue("step-3", Step3Output{})

    _, err := tester.Run(flow, core.FlowInput{})

    require.Error(t, err)
    assert.Contains(t, err.Error(), "step 2 failed")

    // Step 3 should not be called
    tester.AssertNotCalled(t, "step-3")
}
```

## Mocking Patterns

### Setup Helper

Create a helper for common mock setups:

```go
func setupSuccessfulMocks(tester *core.FlowTester) {
    tester.MockValue("fetch-issues", FetchOutput{
        Issues: testIssues,
        Count:  len(testIssues),
    })
    tester.MockValue("generate-embeddings", EmbedOutput{
        Embeddings: testEmbeddings,
    })
    tester.MockValue("store-vectors", StoreOutput{
        Stored: len(testIssues),
    })
}

func TestFlow_Success(t *testing.T) {
    tester := core.NewFlowTester()
    setupSuccessfulMocks(tester)

    state, err := tester.Run(flow, core.FlowInput{})
    require.NoError(t, err)
}
```

### Override Pattern

Start with defaults, override specific mocks:

```go
func TestFlow_PartialFailure(t *testing.T) {
    tester := core.NewFlowTester()
    setupSuccessfulMocks(tester)  // Set up default success

    // Override one mock for error case
    tester.MockError("generate-embeddings", errors.New("model unavailable"))

    _, err := tester.Run(flow, core.FlowInput{})
    require.Error(t, err)
}
```

### Counter Mock

Track call counts with logic:

```go
func TestFlow_RetryBehavior(t *testing.T) {
    callCount := 0

    tester := core.NewFlowTester()
    tester.Mock("flaky-api", func(input APIInput) (APIOutput, error) {
        callCount++
        if callCount < 3 {
            return APIOutput{}, errors.New("temporary failure")
        }
        return APIOutput{Value: "success"}, nil
    })

    // Note: FlowTester doesn't implement retry logic
    // This pattern is for illustration
}
```

### Sequence Mock

Return different values on successive calls:

```go
func TestPaginatedFetch(t *testing.T) {
    calls := 0
    pages := [][]Issue{
        {{Key: "TEST-1"}, {Key: "TEST-2"}},
        {{Key: "TEST-3"}},
        {}, // Empty page signals end
    }

    tester := core.NewFlowTester()
    tester.Mock("fetch-page", func(input PageInput) (PageOutput, error) {
        page := pages[calls]
        calls++
        return PageOutput{
            Issues:  page,
            HasMore: len(page) > 0,
        }, nil
    })
}
```

## Testing Specific Scenarios

### Testing WithInputFunc Resolution

```go
func TestInputFuncReceivesCorrectState(t *testing.T) {
    flow := core.NewFlow("test").
        Then(fetchNode.As("fetch")).
        Then(processNode).  // Has WithInputFunc that reads "fetch"
        Build()

    tester := core.NewFlowTester()
    tester.MockValue("fetch", FetchOutput{
        Items: []Item{{ID: "1"}},
    })

    var receivedInput ProcessInput
    tester.Mock("process", func(input ProcessInput) (ProcessOutput, error) {
        receivedInput = input
        return ProcessOutput{}, nil
    })

    tester.Run(flow, core.FlowInput{})

    // Verify WithInputFunc resolved correctly
    assert.Len(t, receivedInput.Items, 1)
    assert.Equal(t, "1", receivedInput.Items[0].ID)
}
```

### Testing Magic Markers

```go
func TestMagicMarkerResolution(t *testing.T) {
    // Node uses core.Output("fetch.ID")
    flow := core.NewFlow("test").
        Then(fetchNode.As("fetch")).
        Then(lookupNode).  // Input has: ID: core.Output("fetch.ID")
        Build()

    tester := core.NewFlowTester()
    tester.MockValue("fetch", FetchOutput{ID: "abc123"})

    var receivedInput LookupInput
    tester.Mock("lookup", func(input LookupInput) (LookupOutput, error) {
        receivedInput = input
        return LookupOutput{}, nil
    })

    tester.Run(flow, core.FlowInput{})

    // Verify marker was resolved
    assert.Equal(t, "abc123", receivedInput.ID)
}
```

### Testing Parallel Node Mocks

```go
func TestParallelNodesMocked(t *testing.T) {
    flow := core.NewFlow("test").
        ThenParallel("enrichment",
            enrichANode,
            enrichBNode,
            enrichCNode,
        ).
        Build()

    tester := core.NewFlowTester()
    tester.MockValue("enrich-a", EnrichAOutput{Value: 1})
    tester.MockValue("enrich-b", EnrichBOutput{Value: 2})
    tester.MockValue("enrich-c", EnrichCOutput{Value: 3})

    state, err := tester.Run(flow, core.FlowInput{})
    require.NoError(t, err)

    // All mocks called
    tester.AssertCalled(t, "enrich-a")
    tester.AssertCalled(t, "enrich-b")
    tester.AssertCalled(t, "enrich-c")
}
```

## Error Handling Tests

### Test Error Message Content

```go
func TestErrorMessage(t *testing.T) {
    tester := core.NewFlowTester()
    tester.MockError("fetch", errors.New("API error: rate limited"))

    _, err := tester.Run(flow, core.FlowInput{})

    require.Error(t, err)
    assert.Contains(t, err.Error(), "rate limited")
}
```

### Test Specific Error Type

```go
type ValidationError struct {
    Field   string
    Message string
}

func (e *ValidationError) Error() string {
    return fmt.Sprintf("%s: %s", e.Field, e.Message)
}

func TestValidationError(t *testing.T) {
    tester := core.NewFlowTester()
    tester.MockError("validate", &ValidationError{
        Field:   "email",
        Message: "invalid format",
    })

    _, err := tester.Run(flow, core.FlowInput{})

    var validationErr *ValidationError
    require.ErrorAs(t, err, &validationErr)
    assert.Equal(t, "email", validationErr.Field)
}
```

## Best Practices

### 1. Mock All Required Nodes

```go
// Test fails if mock missing
func TestFlow_MissingMock(t *testing.T) {
    tester := core.NewFlowTester()
    tester.MockValue("fetch", FetchOutput{})
    // Missing: tester.MockValue("process", ...)

    _, err := tester.Run(flow, core.FlowInput{})
    require.Error(t, err)
    assert.Contains(t, err.Error(), "no mock registered")
}
```

### 2. Use Descriptive Mock Data

```go
// Good: Clear test data
tester.MockValue("fetch", FetchOutput{
    Issues: []Issue{
        {Key: "BUG-1", Summary: "Critical bug", Status: "Open"},
        {Key: "BUG-2", Summary: "Minor bug", Status: "Resolved"},
    },
})

// Bad: Opaque test data
tester.MockValue("fetch", FetchOutput{
    Issues: []Issue{{Key: "X"}, {Key: "Y"}},
})
```

### 3. Test Both Success and Failure Paths

```go
func TestFetchFlow(t *testing.T) {
    t.Run("success", func(t *testing.T) {
        tester := core.NewFlowTester()
        tester.MockValue("fetch", FetchOutput{Count: 5})
        _, err := tester.Run(flow, core.FlowInput{})
        require.NoError(t, err)
    })

    t.Run("fetch fails", func(t *testing.T) {
        tester := core.NewFlowTester()
        tester.MockError("fetch", errors.New("connection refused"))
        _, err := tester.Run(flow, core.FlowInput{})
        require.Error(t, err)
    })
}
```

### 4. Verify Input Transformation

```go
func TestInputTransformation(t *testing.T) {
    tester := core.NewFlowTester()

    var processInput ProcessInput
    tester.MockValue("fetch", FetchOutput{
        RawData: "data",
        Count:   100,
    })
    tester.Mock("process", func(input ProcessInput) (ProcessOutput, error) {
        processInput = input
        return ProcessOutput{}, nil
    })

    tester.Run(flow, core.FlowInput{})

    // Verify transformation happened
    assert.Equal(t, "DATA", processInput.NormalizedData)  // Uppercased
    assert.Equal(t, 100, processInput.ItemCount)
}
```

## See Also

- **[FlowTester](/docs/guides/testing/flow-tester/)** - Complete testing guide
- **[Integration Tests](/docs/guides/testing/integration-tests/)** - Testing with Temporal
- **[Error Handling](/docs/guides/building-flows/error-handling/)** - Error scenarios
