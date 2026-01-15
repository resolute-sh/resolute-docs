---
title: "Your First Flow"
description: "Your First Flow - Resolute documentation"
weight: 40
toc: true
---


# Your First Flow

Build a complete data synchronization workflow that fetches issues from Jira, transforms them, and tracks progress with cursors.

**Time**: ~20 minutes

## What You'll Build

A workflow that:
1. Fetches updated Jira issues since the last sync
2. Transforms issues into a standardized format
3. Stores them in your data layer
4. Tracks progress using cursors for incremental syncing

```
┌─────────────────────────────────────────────────────────────┐
│                    jira-sync-flow                            │
│  Trigger: Schedule (every 15 minutes)                        │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│   ┌─────────┐   ┌───────────┐   ┌─────────┐   ┌─────────┐  │
│   │  fetch  │ → │ transform │ → │  store  │ → │ update  │  │
│   │ issues  │   │  issues   │   │  data   │   │ cursor  │  │
│   └─────────┘   └───────────┘   └─────────┘   └─────────┘  │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## Prerequisites

- Completed [Quickstart](/docs/getting-started/quickstart/)
- Temporal server running (`temporal server start-dev`)
- Basic Go knowledge

## Project Setup

Create a new project:

```bash
mkdir jira-sync && cd jira-sync
go mod init jira-sync
go get github.com/resolute/resolute/core
go get github.com/resolute/resolute-jira
```

## Step 1: Define Your Data Types

Create `types.go` with your domain models:

```go title="types.go"
package main

import "time"

// Issue represents a normalized issue from any source
type Issue struct {
    ID          string
    Key         string
    Title       string
    Description string
    Status      string
    Priority    string
    Assignee    string
    UpdatedAt   time.Time
    Source      string
}

// SyncResult tracks what was synced
type SyncResult struct {
    Synced    int
    Skipped   int
    LastKey   string
    Timestamp time.Time
}
```

## Step 2: Create the Fetch Activity

Create `activities.go` with your workflow activities:

```go title="activities.go"
package main

import (
    "context"
    "fmt"
    "log"
    "time"

    jira "github.com/resolute/resolute-jira"
)

// FetchInput configures what issues to fetch
type FetchInput struct {
    Project   string
    Since     time.Time
    MaxResults int
}

// FetchOutput contains the fetched issues
type FetchOutput struct {
    Issues    []jira.Issue
    Total     int
    HasMore   bool
}

func fetchIssues(ctx context.Context, input FetchInput) (FetchOutput, error) {
    client := jira.NewClient(jira.Config{
        BaseURL: "https://your-domain.atlassian.net",
        // Credentials from environment
    })

    // Build JQL query for updated issues
    jql := fmt.Sprintf(
        "project = %s AND updated >= '%s' ORDER BY updated ASC",
        input.Project,
        input.Since.Format("2006-01-02 15:04"),
    )

    log.Printf("Fetching issues: %s", jql)

    result, err := client.FetchIssues(ctx, jira.FetchIssuesInput{
        JQL:        jql,
        MaxResults: input.MaxResults,
        Fields:     []string{"summary", "description", "status", "priority", "assignee", "updated"},
    })
    if err != nil {
        return FetchOutput{}, fmt.Errorf("fetch issues: %w", err)
    }

    log.Printf("Fetched %d issues (total: %d)", len(result.Issues), result.Total)

    return FetchOutput{
        Issues:  result.Issues,
        Total:   result.Total,
        HasMore: result.Total > len(result.Issues),
    }, nil
}
```

## Step 3: Create the Transform Activity

Add the transformation logic to `activities.go`:

```go title="activities.go (continued)"
// TransformInput takes raw Jira issues
type TransformInput struct {
    Issues []jira.Issue
}

// TransformOutput contains normalized issues
type TransformOutput struct {
    Issues []Issue
}

func transformIssues(ctx context.Context, input TransformInput) (TransformOutput, error) {
    log.Printf("Transforming %d issues", len(input.Issues))

    issues := make([]Issue, 0, len(input.Issues))
    for _, ji := range input.Issues {
        issue := Issue{
            ID:          ji.ID,
            Key:         ji.Key,
            Title:       ji.Fields.Summary,
            Description: ji.Fields.Description,
            Status:      ji.Fields.Status.Name,
            Priority:    ji.Fields.Priority.Name,
            UpdatedAt:   ji.Fields.Updated,
            Source:      "jira",
        }

        if ji.Fields.Assignee != nil {
            issue.Assignee = ji.Fields.Assignee.DisplayName
        }

        issues = append(issues, issue)
    }

    return TransformOutput{Issues: issues}, nil
}
```

## Step 4: Create the Store Activity

Add the storage logic:

```go title="activities.go (continued)"
// StoreInput contains issues to store
type StoreInput struct {
    Issues []Issue
}

// StoreOutput reports what was stored
type StoreOutput struct {
    Stored  int
    Updated int
}

func storeIssues(ctx context.Context, input StoreInput) (StoreOutput, error) {
    log.Printf("Storing %d issues", len(input.Issues))

    // Your storage logic here - database, API, etc.
    // For this example, we simulate storage
    stored := 0
    updated := 0

    for _, issue := range input.Issues {
        // Check if issue exists (pseudo-code)
        exists := false // db.Exists(issue.ID)

        if exists {
            // db.Update(issue)
            updated++
        } else {
            // db.Insert(issue)
            stored++
        }
    }

    log.Printf("Stored: %d new, %d updated", stored, updated)

    return StoreOutput{
        Stored:  stored,
        Updated: updated,
    }, nil
}
```

## Step 5: Build the Flow

Create `main.go` with the complete flow:

```go title="main.go"
package main

import (
    "context"
    "log"
    "time"

    "github.com/resolute/resolute/core"
)

func main() {
    // Define nodes with typed inputs/outputs
    fetchNode := core.NewNode("fetch-issues", fetchIssues, FetchInput{}).
        WithTimeout(2 * time.Minute).
        WithRetry(core.RetryPolicy{
            InitialInterval:    5 * time.Second,
            BackoffCoefficient: 2.0,
            MaximumAttempts:    3,
        })

    transformNode := core.NewNode("transform-issues", transformIssues, TransformInput{}).
        WithTimeout(1 * time.Minute)

    storeNode := core.NewNode("store-issues", storeIssues, StoreInput{}).
        WithTimeout(2 * time.Minute).
        WithRetry(core.RetryPolicy{
            InitialInterval:    time.Second,
            MaximumAttempts:    5,
        })

    // Build the flow
    flow := core.NewFlow("jira-sync").
        TriggeredBy(core.Schedule("*/15 * * * *")). // Every 15 minutes
        Then(fetchNode).
        Then(transformNode).
        Then(storeNode).
        Build()

    log.Printf("Starting worker for flow: %s", flow.Name())

    // Run the worker
    core.NewWorker().
        WithConfig(core.WorkerConfig{
            TaskQueue:    "jira-sync-queue",
            TemporalHost: "localhost:7233",
        }).
        WithFlow(flow).
        Run()
}
```

## Step 6: Wire Up Data Flow

The nodes need to pass data between each other. Use input functions to connect outputs to inputs:

```go title="main.go (updated)"
package main

import (
    "context"
    "log"
    "time"

    "github.com/resolute/resolute/core"
)

func main() {
    // Fetch node - uses cursor for incremental sync
    fetchNode := core.NewNode("fetch-issues", fetchIssues, FetchInput{}).
        WithInputFunc(func(state *core.FlowState) FetchInput {
            cursor := state.GetCursor("jira-issues")
            since := cursor.TimeOr(time.Now().AddDate(0, 0, -7)) // Default: last 7 days

            return FetchInput{
                Project:    "MYPROJECT",
                Since:      since,
                MaxResults: 100,
            }
        }).
        WithTimeout(2 * time.Minute).
        WithRetry(core.RetryPolicy{
            InitialInterval:    5 * time.Second,
            BackoffCoefficient: 2.0,
            MaximumAttempts:    3,
        })

    // Transform node - receives fetch output
    transformNode := core.NewNode("transform-issues", transformIssues, TransformInput{}).
        WithInputFunc(func(state *core.FlowState) TransformInput {
            fetchResult := core.Get[FetchOutput](state, "fetch-issues")
            return TransformInput{
                Issues: fetchResult.Issues,
            }
        }).
        WithTimeout(1 * time.Minute)

    // Store node - receives transform output
    storeNode := core.NewNode("store-issues", storeIssues, StoreInput{}).
        WithInputFunc(func(state *core.FlowState) StoreInput {
            transformResult := core.Get[TransformOutput](state, "transform-issues")
            return StoreInput{
                Issues: transformResult.Issues,
            }
        }).
        WithTimeout(2 * time.Minute).
        WithRetry(core.RetryPolicy{
            InitialInterval:    time.Second,
            MaximumAttempts:    5,
        })

    // Update cursor after successful sync
    updateCursorNode := core.NewNode("update-cursor", updateCursor, UpdateCursorInput{}).
        WithInputFunc(func(state *core.FlowState) UpdateCursorInput {
            fetchResult := core.Get[FetchOutput](state, "fetch-issues")
            if len(fetchResult.Issues) == 0 {
                return UpdateCursorInput{}
            }
            // Use the latest issue's update time as new cursor
            latest := fetchResult.Issues[len(fetchResult.Issues)-1]
            return UpdateCursorInput{
                Source:   "jira-issues",
                Position: latest.Fields.Updated.Format(time.RFC3339),
            }
        })

    // Build the flow
    flow := core.NewFlow("jira-sync").
        TriggeredBy(core.Schedule("*/15 * * * *")).
        Then(fetchNode).
        Then(transformNode).
        Then(storeNode).
        Then(updateCursorNode).
        Build()

    log.Printf("Starting worker for flow: %s", flow.Name())

    core.NewWorker().
        WithConfig(core.WorkerConfig{
            TaskQueue:    "jira-sync-queue",
            TemporalHost: "localhost:7233",
        }).
        WithFlow(flow).
        Run()
}

// UpdateCursorInput tracks sync position
type UpdateCursorInput struct {
    Source   string
    Position string
}

type UpdateCursorOutput struct {
    Updated bool
}

func updateCursor(ctx context.Context, input UpdateCursorInput) (UpdateCursorOutput, error) {
    if input.Source == "" {
        return UpdateCursorOutput{Updated: false}, nil
    }
    log.Printf("Cursor updated: %s = %s", input.Source, input.Position)
    return UpdateCursorOutput{Updated: true}, nil
}
```

## Step 7: Run and Test

Start the worker:

```bash
go run .
```

In another terminal, trigger a manual execution:

```bash
temporal workflow start \
    --task-queue jira-sync-queue \
    --type jira-sync \
    --workflow-id jira-sync-manual-1
```

View in Temporal UI at [http://localhost:8233](http://localhost:8233).

## Step 8: Add Unit Tests

Create `flow_test.go`:

```go title="flow_test.go"
package main

import (
    "testing"
    "time"

    "github.com/resolute/resolute/core"
    jira "github.com/resolute/resolute-jira"
)

func TestJiraSyncFlow(t *testing.T) {
    // Create the flow (same as main.go)
    flow := buildJiraSyncFlow()

    // Create test harness
    tester := core.NewFlowTester(t, flow)

    // Mock the fetch activity
    tester.MockActivity("fetch-issues", func(input FetchInput) (FetchOutput, error) {
        return FetchOutput{
            Issues: []jira.Issue{
                {
                    ID:  "10001",
                    Key: "MYPROJECT-123",
                    Fields: jira.IssueFields{
                        Summary:  "Test Issue",
                        Status:   jira.Status{Name: "Open"},
                        Priority: jira.Priority{Name: "High"},
                        Updated:  time.Now(),
                    },
                },
            },
            Total:   1,
            HasMore: false,
        }, nil
    })

    // Mock transform (use real implementation)
    tester.MockActivity("transform-issues", transformIssues)

    // Mock store
    tester.MockActivity("store-issues", func(input StoreInput) (StoreOutput, error) {
        return StoreOutput{
            Stored:  len(input.Issues),
            Updated: 0,
        }, nil
    })

    // Mock cursor update
    tester.MockActivity("update-cursor", updateCursor)

    // Execute the flow
    result := tester.Execute()

    // Assertions
    if result.Error != nil {
        t.Fatalf("Flow failed: %v", result.Error)
    }

    // Verify store was called with transformed issues
    storeCall := tester.GetActivityCall("store-issues")
    storeInput := storeCall.Input.(StoreInput)

    if len(storeInput.Issues) != 1 {
        t.Errorf("Expected 1 issue, got %d", len(storeInput.Issues))
    }

    if storeInput.Issues[0].Key != "MYPROJECT-123" {
        t.Errorf("Expected key MYPROJECT-123, got %s", storeInput.Issues[0].Key)
    }

    if storeInput.Issues[0].Source != "jira" {
        t.Errorf("Expected source 'jira', got %s", storeInput.Issues[0].Source)
    }
}

func TestJiraSyncFlow_EmptyResults(t *testing.T) {
    flow := buildJiraSyncFlow()
    tester := core.NewFlowTester(t, flow)

    // Mock empty fetch
    tester.MockActivity("fetch-issues", func(input FetchInput) (FetchOutput, error) {
        return FetchOutput{
            Issues:  []jira.Issue{},
            Total:   0,
            HasMore: false,
        }, nil
    })

    tester.MockActivity("transform-issues", transformIssues)
    tester.MockActivity("store-issues", storeIssues)
    tester.MockActivity("update-cursor", updateCursor)

    result := tester.Execute()

    if result.Error != nil {
        t.Fatalf("Flow failed: %v", result.Error)
    }

    // Verify cursor was not updated
    cursorCall := tester.GetActivityCall("update-cursor")
    cursorInput := cursorCall.Input.(UpdateCursorInput)

    if cursorInput.Source != "" {
        t.Error("Cursor should not be updated for empty results")
    }
}

func buildJiraSyncFlow() *core.Flow {
    // Same flow building logic as main.go
    // Extract to a shared function
    fetchNode := core.NewNode("fetch-issues", fetchIssues, FetchInput{}).
        WithInputFunc(func(state *core.FlowState) FetchInput {
            cursor := state.GetCursor("jira-issues")
            since := cursor.TimeOr(time.Now().AddDate(0, 0, -7))
            return FetchInput{
                Project:    "MYPROJECT",
                Since:      since,
                MaxResults: 100,
            }
        })

    transformNode := core.NewNode("transform-issues", transformIssues, TransformInput{}).
        WithInputFunc(func(state *core.FlowState) TransformInput {
            fetchResult := core.Get[FetchOutput](state, "fetch-issues")
            return TransformInput{Issues: fetchResult.Issues}
        })

    storeNode := core.NewNode("store-issues", storeIssues, StoreInput{}).
        WithInputFunc(func(state *core.FlowState) StoreInput {
            transformResult := core.Get[TransformOutput](state, "transform-issues")
            return StoreInput{Issues: transformResult.Issues}
        })

    updateCursorNode := core.NewNode("update-cursor", updateCursor, UpdateCursorInput{}).
        WithInputFunc(func(state *core.FlowState) UpdateCursorInput {
            fetchResult := core.Get[FetchOutput](state, "fetch-issues")
            if len(fetchResult.Issues) == 0 {
                return UpdateCursorInput{}
            }
            latest := fetchResult.Issues[len(fetchResult.Issues)-1]
            return UpdateCursorInput{
                Source:   "jira-issues",
                Position: latest.Fields.Updated.Format(time.RFC3339),
            }
        })

    return core.NewFlow("jira-sync").
        TriggeredBy(core.Schedule("*/15 * * * *")).
        Then(fetchNode).
        Then(transformNode).
        Then(storeNode).
        Then(updateCursorNode).
        Build()
}
```

Run tests:

```bash
go test -v
```

## Key Concepts Demonstrated

| Concept | What You Learned |
|---------|------------------|
| **Input Functions** | `WithInputFunc()` connects node outputs to inputs dynamically |
| **Typed State Access** | `core.Get[T](state, key)` retrieves outputs with type safety |
| **Cursors** | `state.GetCursor()` tracks incremental sync position |
| **Retry Policies** | `WithRetry()` handles transient failures automatically |
| **Flow Testing** | `FlowTester` mocks activities for unit tests |

## What's Next

You've built a production-ready data sync workflow. Continue learning:

- **[Core Concepts](/docs/concepts/overview/)** - Deep dive into flows, nodes, and state
- **[Parallel Execution](/docs/guides/building-flows/parallel-execution/)** - Run nodes concurrently
- **[Compensation (Saga)](/docs/guides/advanced-patterns/compensation-saga/)** - Handle failures with rollback
- **[Testing Guide](/docs/guides/testing/flow-tester/)** - Complete testing strategies
