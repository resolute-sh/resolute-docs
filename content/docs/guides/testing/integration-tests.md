---
title: "Integration Tests"
description: "Integration Tests - Resolute documentation"
weight: 30
toc: true
---


# Integration Tests

Integration tests run flows against a real Temporal server, testing actual behavior including retries, timeouts, and signals. Use them for end-to-end validation.

## When to Use Integration Tests

| Use Unit Tests (FlowTester) | Use Integration Tests |
|-----------------------------|----------------------|
| Fast feedback loop | Full end-to-end validation |
| Testing flow logic | Testing Temporal behavior |
| Mocking external dependencies | Testing with real activities |
| CI/CD quick checks | Release validation |
| Testing conditionals/branching | Testing retry/timeout behavior |

## Test Environment Setup

### Local Temporal Server

Use the Temporal test server or run Temporal locally:

```go
package integration

import (
    "testing"

    "go.temporal.io/sdk/testsuite"
)

func TestMain(m *testing.M) {
    // Start test server
    ts := testsuite.NewTestServer()
    defer ts.Stop()

    // Run tests
    os.Exit(m.Run())
}
```

### Using Temporal CLI Dev Server

```bash
# Start development server
temporal server start-dev

# Run tests
go test -tags=integration ./...
```

## Basic Integration Test

```go
//go:build integration

package integration

import (
    "context"
    "testing"
    "time"

    "github.com/stretchr/testify/require"
    "go.temporal.io/sdk/client"
    "go.temporal.io/sdk/worker"

    "myapp/flows"
    "myapp/providers/jira"
)

func TestDataSyncFlow_Integration(t *testing.T) {
    // Create Temporal client
    c, err := client.Dial(client.Options{
        HostPort: "localhost:7233",
    })
    require.NoError(t, err)
    defer c.Close()

    // Create and start worker
    taskQueue := "test-data-sync"
    w := worker.New(c, taskQueue, worker.Options{})

    // Register activities
    jira.RegisterActivities(w)
    w.RegisterWorkflow(flows.DataSyncWorkflow)

    // Start worker in background
    go w.Run(worker.InterruptCh())
    defer w.Stop()

    // Execute workflow
    workflowOptions := client.StartWorkflowOptions{
        ID:        "test-sync-" + time.Now().Format("20060102150405"),
        TaskQueue: taskQueue,
    }

    we, err := c.ExecuteWorkflow(
        context.Background(),
        workflowOptions,
        flows.DataSyncWorkflow,
        flows.DataSyncInput{Project: "TEST"},
    )
    require.NoError(t, err)

    // Wait for completion
    var result flows.DataSyncOutput
    err = we.Get(context.Background(), &result)
    require.NoError(t, err)

    // Assert results
    require.Greater(t, result.SyncedCount, 0)
}
```

## Test Fixtures

### Activity Stubs for Integration Tests

Create test implementations that don't hit real APIs:

```go
package testfixtures

import (
    "context"

    "myapp/providers/jira"
)

type TestJiraActivities struct{}

func (t *TestJiraActivities) FetchIssues(ctx context.Context, input jira.FetchInput) (jira.FetchOutput, error) {
    return jira.FetchOutput{
        Issues: []jira.Issue{
            {Key: "TEST-1", Summary: "Test issue 1"},
            {Key: "TEST-2", Summary: "Test issue 2"},
        },
        Count: 2,
    }, nil
}

func (t *TestJiraActivities) CreateIssue(ctx context.Context, input jira.CreateInput) (jira.CreateOutput, error) {
    return jira.CreateOutput{
        Key: "TEST-" + input.Summary[:3],
    }, nil
}
```

### Using Test Activities

```go
func TestWorkflow_WithTestActivities(t *testing.T) {
    c, _ := client.Dial(client.Options{})
    defer c.Close()

    taskQueue := "test-" + t.Name()
    w := worker.New(c, taskQueue, worker.Options{})

    // Register test activities instead of real ones
    testActivities := &testfixtures.TestJiraActivities{}
    w.RegisterActivityWithOptions(
        testActivities.FetchIssues,
        activity.RegisterOptions{Name: "jira.FetchIssues"},
    )

    w.RegisterWorkflow(flows.DataSyncWorkflow)
    go w.Run(worker.InterruptCh())
    defer w.Stop()

    // Run test...
}
```

## Testing Temporal Behaviors

### Test Retry Behavior

```go
func TestActivity_Retries(t *testing.T) {
    ts := testsuite.NewTestServer()
    defer ts.Stop()

    c := ts.Client()
    taskQueue := "retry-test"

    // Track call count
    callCount := 0
    activities := &RetryTestActivities{
        callCount: &callCount,
    }

    w := worker.New(c, taskQueue, worker.Options{})
    w.RegisterActivityWithOptions(
        activities.FlakyActivity,
        activity.RegisterOptions{Name: "flaky"},
    )
    w.RegisterWorkflow(RetryTestWorkflow)
    go w.Run(worker.InterruptCh())
    defer w.Stop()

    we, _ := c.ExecuteWorkflow(
        context.Background(),
        client.StartWorkflowOptions{
            ID:        "retry-test",
            TaskQueue: taskQueue,
        },
        RetryTestWorkflow,
        nil,
    )

    var result string
    err := we.Get(context.Background(), &result)

    require.NoError(t, err)
    assert.Equal(t, "success", result)
    assert.Equal(t, 3, callCount) // Failed twice, succeeded third time
}

type RetryTestActivities struct {
    callCount *int
}

func (a *RetryTestActivities) FlakyActivity(ctx context.Context) (string, error) {
    *a.callCount++
    if *a.callCount < 3 {
        return "", errors.New("temporary failure")
    }
    return "success", nil
}
```

### Test Timeouts

```go
func TestActivity_Timeout(t *testing.T) {
    ts := testsuite.NewTestServer()
    defer ts.Stop()

    c := ts.Client()
    taskQueue := "timeout-test"

    w := worker.New(c, taskQueue, worker.Options{})
    w.RegisterActivity(SlowActivity)
    w.RegisterWorkflow(TimeoutTestWorkflow)
    go w.Run(worker.InterruptCh())
    defer w.Stop()

    ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
    defer cancel()

    we, _ := c.ExecuteWorkflow(
        ctx,
        client.StartWorkflowOptions{
            ID:                    "timeout-test",
            TaskQueue:             taskQueue,
            WorkflowRunTimeout:    5 * time.Second,
        },
        TimeoutTestWorkflow,
        nil,
    )

    var result string
    err := we.Get(ctx, &result)

    // Should fail due to timeout
    require.Error(t, err)
    assert.Contains(t, err.Error(), "timeout")
}

func SlowActivity(ctx context.Context) (string, error) {
    time.Sleep(10 * time.Second) // Exceeds workflow timeout
    return "done", nil
}
```

### Test Signals

```go
func TestWorkflow_Signal(t *testing.T) {
    ts := testsuite.NewTestServer()
    defer ts.Stop()

    c := ts.Client()
    taskQueue := "signal-test"

    w := worker.New(c, taskQueue, worker.Options{})
    w.RegisterWorkflow(SignalWorkflow)
    go w.Run(worker.InterruptCh())
    defer w.Stop()

    we, err := c.ExecuteWorkflow(
        context.Background(),
        client.StartWorkflowOptions{
            ID:        "signal-test",
            TaskQueue: taskQueue,
        },
        SignalWorkflow,
        nil,
    )
    require.NoError(t, err)

    // Wait for workflow to start and reach wait state
    time.Sleep(100 * time.Millisecond)

    // Send signal
    err = c.SignalWorkflow(
        context.Background(),
        we.GetID(),
        we.GetRunID(),
        "approval",
        ApprovalSignal{Approved: true, Approver: "test"},
    )
    require.NoError(t, err)

    // Wait for completion
    var result SignalOutput
    err = we.Get(context.Background(), &result)
    require.NoError(t, err)
    assert.True(t, result.Approved)
}
```

## Test Isolation

### Unique Task Queues

Use unique task queues to prevent test interference:

```go
func TestFlow_Isolated(t *testing.T) {
    // Each test gets its own queue
    taskQueue := fmt.Sprintf("test-%s-%d", t.Name(), time.Now().UnixNano())

    w := worker.New(c, taskQueue, worker.Options{})
    // ...
}
```

### Cleanup

Ensure proper cleanup:

```go
func TestFlow_WithCleanup(t *testing.T) {
    c, _ := client.Dial(client.Options{})
    defer c.Close()

    taskQueue := "test-" + t.Name()
    w := worker.New(c, taskQueue, worker.Options{})

    // Cleanup running workflows after test
    t.Cleanup(func() {
        // Terminate any hanging workflows
        c.TerminateWorkflow(
            context.Background(),
            "test-workflow-id",
            "",
            "test cleanup",
        )
        w.Stop()
    })

    // ... run test
}
```

## Testing with Real Services

### Environment Setup

```go
func skipIfNoEnv(t *testing.T) {
    if os.Getenv("JIRA_API_TOKEN") == "" {
        t.Skip("JIRA_API_TOKEN not set, skipping integration test")
    }
}

func TestRealJiraIntegration(t *testing.T) {
    skipIfNoEnv(t)

    cfg := jira.Config{
        BaseURL:  os.Getenv("JIRA_BASE_URL"),
        Email:    os.Getenv("JIRA_EMAIL"),
        APIToken: os.Getenv("JIRA_API_TOKEN"),
    }

    provider := jira.NewProvider(cfg)
    // ... test with real provider
}
```

### Test Data Management

```go
func TestCreateAndDeleteIssue(t *testing.T) {
    skipIfNoEnv(t)

    // Setup
    c, w := setupTestEnvironment(t)
    defer w.Stop()

    // Create test issue
    createResult := runWorkflow(t, c, CreateIssueWorkflow, CreateInput{
        Project: "TEST",
        Summary: "Integration Test Issue " + time.Now().Format(time.RFC3339),
    })

    // Cleanup: delete the created issue
    t.Cleanup(func() {
        runWorkflow(t, c, DeleteIssueWorkflow, DeleteInput{
            Key: createResult.Key,
        })
    })

    // Test assertions
    assert.NotEmpty(t, createResult.Key)
}
```

## Test Organization

### Build Tags

Separate integration tests with build tags:

```go
//go:build integration

package integration

// Integration tests only run with: go test -tags=integration
```

### Test Suites

Group related tests:

```go
type DataSyncIntegrationSuite struct {
    suite.Suite
    client    client.Client
    worker    worker.Worker
    taskQueue string
}

func (s *DataSyncIntegrationSuite) SetupSuite() {
    c, _ := client.Dial(client.Options{})
    s.client = c
    s.taskQueue = "data-sync-suite"
    s.worker = worker.New(c, s.taskQueue, worker.Options{})
    // Register activities/workflows
    go s.worker.Run(worker.InterruptCh())
}

func (s *DataSyncIntegrationSuite) TearDownSuite() {
    s.worker.Stop()
    s.client.Close()
}

func (s *DataSyncIntegrationSuite) TestFetchIssues() {
    // Test implementation
}

func (s *DataSyncIntegrationSuite) TestProcessData() {
    // Test implementation
}

func TestDataSyncIntegration(t *testing.T) {
    suite.Run(t, new(DataSyncIntegrationSuite))
}
```

## CI/CD Integration

### GitHub Actions Example

```yaml
name: Integration Tests

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  integration:
    runs-on: ubuntu-latest

    services:
      temporal:
        image: temporalio/auto-setup:latest
        ports:
          - 7233:7233

    steps:
      - uses: actions/checkout@v4

      - name: Set up Go
        uses: actions/setup-go@v5
        with:
          go-version: '1.22'

      - name: Wait for Temporal
        run: |
          timeout 60 bash -c 'until nc -z localhost 7233; do sleep 1; done'

      - name: Run integration tests
        run: go test -tags=integration -v ./tests/integration/...
        env:
          TEMPORAL_HOST: localhost:7233
```

## Best Practices

### 1. Keep Tests Independent

```go
// Good: Self-contained test
func TestWorkflow_Independent(t *testing.T) {
    taskQueue := uniqueTaskQueue(t)
    w := createWorker(t, taskQueue)
    defer w.Stop()
    // ...
}

// Bad: Shared state between tests
var sharedWorker worker.Worker

func TestWorkflow_A(t *testing.T) {
    // Uses sharedWorker - can cause flaky tests
}
```

### 2. Use Timeouts

```go
func TestWorkflow_WithTimeout(t *testing.T) {
    ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
    defer cancel()

    we, _ := c.ExecuteWorkflow(ctx, opts, workflow, input)

    var result Output
    err := we.Get(ctx, &result)
    if ctx.Err() == context.DeadlineExceeded {
        t.Fatal("test timed out waiting for workflow")
    }
}
```

### 3. Test Error Scenarios

```go
func TestWorkflow_HandlesFailure(t *testing.T) {
    // Register activity that fails
    w.RegisterActivityWithOptions(
        func(ctx context.Context) error {
            return errors.New("simulated failure")
        },
        activity.RegisterOptions{Name: "failing-activity"},
    )

    we, _ := c.ExecuteWorkflow(ctx, opts, workflow, input)

    var result Output
    err := we.Get(ctx, &result)

    require.Error(t, err)
    assert.Contains(t, err.Error(), "simulated failure")
}
```

### 4. Log for Debugging

```go
func TestWorkflow_WithLogging(t *testing.T) {
    we, err := c.ExecuteWorkflow(ctx, opts, workflow, input)
    require.NoError(t, err)

    t.Logf("Started workflow: ID=%s RunID=%s", we.GetID(), we.GetRunID())

    var result Output
    err = we.Get(ctx, &result)
    if err != nil {
        t.Logf("Workflow failed: %v", err)
    }
    require.NoError(t, err)
}
```

## See Also

- **[FlowTester](/docs/guides/testing/flow-tester/)** - Unit testing without Temporal
- **[Mocking Activities](/docs/guides/testing/mocking-activities/)** - Mock patterns
- **[Worker Configuration](/docs/guides/deployment/worker-configuration/)** - Production setup
- **[Temporal Foundation](/docs/concepts/temporal-foundation/)** - Understanding Temporal
