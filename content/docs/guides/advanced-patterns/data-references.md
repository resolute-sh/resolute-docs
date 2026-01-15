---
title: "Data References"
description: "Data References - Resolute documentation"
weight: 40
toc: true
---


# Data References (Claim Check Pattern)

Data References implement the "claim check" pattern for handling large datasets that shouldn't pass through Temporal's event history. Instead of storing large payloads in workflow state, store a reference to external storage.

## Why Data References?

Temporal has payload size limits:
- Default: 2MB per payload
- Event history grows with each activity input/output

For large datasets (thousands of items, large documents):
- Workflow history becomes huge
- Performance degrades
- Risk of hitting size limits

The solution: store data externally, pass references through the workflow.

## The Claim Check Pattern

```
Without Data References          With Data References
────────────────────────        ─────────────────────────────

┌──────────┐                    ┌──────────┐
│  Fetch   │                    │  Fetch   │
│ 10K items│                    │ 10K items│
└────┬─────┘                    └────┬─────┘
     │                               │
     │ 10K items                     │ Store to S3
     │ in history                    │ Return ref only
     ▼                               ▼
┌──────────┐                    ┌──────────┐
│ Process  │                    │ Process  │
│ 10K items│                    │ (ref)    │
└────┬─────┘                    └────┬─────┘
     │                               │
     │ 10K results                   │ Load from S3
     │ in history                    │ Store results to S3
     ▼                               ▼
┌──────────┐                    ┌──────────┐
│  Store   │                    │  Store   │
└──────────┘                    └──────────┘

History: ~60MB                  History: ~1KB
```

## DataRef Structure

```go
type DataRef struct {
    StorageKey string // Key in external storage (e.g., S3 path)
    Backend    string // Storage backend identifier
}
```

## Basic Pattern

### 1. Store Data and Return Reference

```go
type FetchOutput struct {
    Ref   core.DataRef // Reference to stored data
    Count int          // Metadata (small, ok in history)
}

func fetchIssues(ctx context.Context, input FetchInput) (FetchOutput, error) {
    // Fetch large dataset
    issues, err := jiraClient.FetchAll(ctx, input.JQL)
    if err != nil {
        return FetchOutput{}, err
    }

    // Store to S3 instead of returning directly
    ref, err := storage.Store(ctx, "issues", issues)
    if err != nil {
        return FetchOutput{}, fmt.Errorf("store issues: %w", err)
    }

    return FetchOutput{
        Ref:   ref,
        Count: len(issues),
    }, nil
}
```

### 2. Load Data Using Reference

```go
type ProcessInput struct {
    IssuesRef core.DataRef
    BatchSize int
}

func processIssues(ctx context.Context, input ProcessInput) (ProcessOutput, error) {
    // Load data from reference
    var issues []Issue
    if err := storage.Load(ctx, input.IssuesRef, &issues); err != nil {
        return ProcessOutput{}, fmt.Errorf("load issues: %w", err)
    }

    // Process the data
    results := make([]ProcessedIssue, 0, len(issues))
    for _, issue := range issues {
        result := process(issue)
        results = append(results, result)
    }

    // Store results and return reference
    ref, err := storage.Store(ctx, "processed", results)
    if err != nil {
        return ProcessOutput{}, err
    }

    return ProcessOutput{
        Ref:       ref,
        Processed: len(results),
    }, nil
}
```

### 3. Pass Reference Between Nodes

```go
processNode := core.NewNode("process", processIssues, ProcessInput{}).
    WithInputFunc(func(s *core.FlowState) ProcessInput {
        fetchResult := core.Get[FetchOutput](s, "fetch")
        return ProcessInput{
            IssuesRef: fetchResult.Ref,  // Pass reference, not data
            BatchSize: 100,
        }
    })
```

## Storage Backend Implementation

### S3 Backend Example

```go
package storage

import (
    "bytes"
    "context"
    "encoding/json"
    "fmt"

    "github.com/aws/aws-sdk-go-v2/aws"
    "github.com/aws/aws-sdk-go-v2/service/s3"
    "github.com/resolute/resolute/core"
)

type S3Storage struct {
    client *s3.Client
    bucket string
}

func NewS3Storage(client *s3.Client, bucket string) *S3Storage {
    return &S3Storage{
        client: client,
        bucket: bucket,
    }
}

func (s *S3Storage) Store(ctx context.Context, prefix string, data interface{}) (core.DataRef, error) {
    // Generate unique key
    key := fmt.Sprintf("%s/%s.json", prefix, uuid.New().String())

    // Serialize data
    body, err := json.Marshal(data)
    if err != nil {
        return core.DataRef{}, fmt.Errorf("marshal data: %w", err)
    }

    // Upload to S3
    _, err = s.client.PutObject(ctx, &s3.PutObjectInput{
        Bucket: aws.String(s.bucket),
        Key:    aws.String(key),
        Body:   bytes.NewReader(body),
    })
    if err != nil {
        return core.DataRef{}, fmt.Errorf("upload to s3: %w", err)
    }

    return core.DataRef{
        StorageKey: key,
        Backend:    "s3",
    }, nil
}

func (s *S3Storage) Load(ctx context.Context, ref core.DataRef, dest interface{}) error {
    // Download from S3
    result, err := s.client.GetObject(ctx, &s3.GetObjectInput{
        Bucket: aws.String(s.bucket),
        Key:    aws.String(ref.StorageKey),
    })
    if err != nil {
        return fmt.Errorf("download from s3: %w", err)
    }
    defer result.Body.Close()

    // Deserialize
    if err := json.NewDecoder(result.Body).Decode(dest); err != nil {
        return fmt.Errorf("decode data: %w", err)
    }

    return nil
}

func (s *S3Storage) Delete(ctx context.Context, ref core.DataRef) error {
    _, err := s.client.DeleteObject(ctx, &s3.DeleteObjectInput{
        Bucket: aws.String(s.bucket),
        Key:    aws.String(ref.StorageKey),
    })
    return err
}
```

## Complete Example

Data enrichment pipeline with external storage:

```go
package main

import (
    "context"
    "fmt"
    "time"

    "github.com/resolute/resolute/core"
)

var storage *S3Storage

type Issue struct {
    ID          string
    Key         string
    Summary     string
    Description string
}

type EnrichedIssue struct {
    Issue
    Embedding []float32
    Tags      []string
}

type FetchOutput struct {
    Ref   core.DataRef
    Count int
}

type EnrichOutput struct {
    Ref       core.DataRef
    Enriched  int
    Skipped   int
}

type StoreOutput struct {
    Stored int
}

func fetchIssues(ctx context.Context, input FetchInput) (FetchOutput, error) {
    issues, err := jiraClient.FetchAll(ctx, input.JQL)
    if err != nil {
        return FetchOutput{}, err
    }

    ref, err := storage.Store(ctx, "fetch/issues", issues)
    if err != nil {
        return FetchOutput{}, err
    }

    return FetchOutput{
        Ref:   ref,
        Count: len(issues),
    }, nil
}

func enrichIssues(ctx context.Context, input EnrichInput) (EnrichOutput, error) {
    // Load issues from reference
    var issues []Issue
    if err := storage.Load(ctx, input.IssuesRef, &issues); err != nil {
        return EnrichOutput{}, err
    }

    // Enrich each issue
    enriched := make([]EnrichedIssue, 0, len(issues))
    var skipped int
    for _, issue := range issues {
        embedding, err := ollama.Embed(ctx, issue.Description)
        if err != nil {
            skipped++
            continue
        }

        enriched = append(enriched, EnrichedIssue{
            Issue:     issue,
            Embedding: embedding,
            Tags:      extractTags(issue),
        })
    }

    // Store enriched data
    ref, err := storage.Store(ctx, "enrich/issues", enriched)
    if err != nil {
        return EnrichOutput{}, err
    }

    return EnrichOutput{
        Ref:      ref,
        Enriched: len(enriched),
        Skipped:  skipped,
    }, nil
}

func storeToVectorDB(ctx context.Context, input StoreInput) (StoreOutput, error) {
    // Load enriched issues
    var issues []EnrichedIssue
    if err := storage.Load(ctx, input.EnrichedRef, &issues); err != nil {
        return StoreOutput{}, err
    }

    // Upsert to vector database
    for _, issue := range issues {
        if err := qdrant.Upsert(ctx, issue.ID, issue.Embedding, issue); err != nil {
            return StoreOutput{}, fmt.Errorf("upsert %s: %w", issue.ID, err)
        }
    }

    return StoreOutput{Stored: len(issues)}, nil
}

func main() {
    fetchNode := core.NewNode("fetch", fetchIssues, FetchInput{
        JQL: "project = PLATFORM",
    }).WithTimeout(30 * time.Minute)

    enrichNode := core.NewNode("enrich", enrichIssues, EnrichInput{}).
        WithInputFunc(func(s *core.FlowState) EnrichInput {
            result := core.Get[FetchOutput](s, "fetch")
            return EnrichInput{IssuesRef: result.Ref}
        }).
        WithTimeout(1 * time.Hour)

    storeNode := core.NewNode("store", storeToVectorDB, StoreInput{}).
        WithInputFunc(func(s *core.FlowState) StoreInput {
            result := core.Get[EnrichOutput](s, "enrich")
            return StoreInput{EnrichedRef: result.Ref}
        }).
        WithTimeout(30 * time.Minute)

    flow := core.NewFlow("issue-enrichment").
        TriggeredBy(core.Schedule("0 2 * * *")).  // Daily at 2 AM
        Then(fetchNode).
        Then(enrichNode).
        Then(storeNode).
        Build()

    core.NewWorker().
        WithConfig(core.WorkerConfig{TaskQueue: "enrichment"}).
        WithFlow(flow).
        Run()
}
```

## Using OutputRef Magic Marker

For simpler cases, use `OutputRef` to automatically resolve references:

```go
// Fetch stores data and returns output with Ref field
type FetchOutput struct {
    Ref   core.DataRef
    Count int
}

// Enrich uses OutputRef marker
enrichNode := core.NewNode("enrich", enrichIssues, EnrichInput{
    IssuesRef: core.OutputRef("fetch"),  // Auto-resolves to FetchOutput.Ref
})
```

The framework extracts the `Ref` field from the referenced node's output.

## Cleanup

Delete temporary data after workflow completes:

```go
func cleanupRefs(ctx context.Context, input CleanupInput) (CleanupOutput, error) {
    for _, ref := range input.Refs {
        if err := storage.Delete(ctx, ref); err != nil {
            log.Printf("Failed to delete %s: %v", ref.StorageKey, err)
        }
    }
    return CleanupOutput{Deleted: len(input.Refs)}, nil
}

cleanupNode := core.NewNode("cleanup", cleanupRefs, CleanupInput{}).
    WithInputFunc(func(s *core.FlowState) CleanupInput {
        return CleanupInput{
            Refs: []core.DataRef{
                core.Get[FetchOutput](s, "fetch").Ref,
                core.Get[EnrichOutput](s, "enrich").Ref,
            },
        }
    })

flow := core.NewFlow("pipeline").
    Then(fetchNode).
    Then(enrichNode).
    Then(storeNode).
    Then(cleanupNode).  // Clean up temporary data
    Build()
```

## When to Use Data References

### Use Data References When:
- Processing thousands of items
- Data size exceeds 1MB
- Workflow has many steps passing large data
- You need to persist intermediate results

### Use Direct Data When:
- Small datasets (< 1000 items or < 100KB)
- Simple workflows with few steps
- Data is already aggregated/summarized
- Convenience outweighs storage overhead

## Best Practices

### 1. Include Metadata in Output

```go
type FetchOutput struct {
    Ref   core.DataRef  // Reference for large data
    Count int           // Item count (useful for logging/monitoring)
    Size  int64         // Data size in bytes
}
```

### 2. Use TTL for Temporary Data

```go
func (s *S3Storage) StoreWithTTL(ctx context.Context, prefix string, data interface{}, ttl time.Duration) (core.DataRef, error) {
    // Set S3 lifecycle rule or object expiration
    expires := time.Now().Add(ttl)

    _, err := s.client.PutObject(ctx, &s3.PutObjectInput{
        Bucket:  aws.String(s.bucket),
        Key:     aws.String(key),
        Body:    bytes.NewReader(body),
        Expires: aws.Time(expires),
    })
    // ...
}
```

### 3. Handle Missing References

```go
func loadWithFallback(ctx context.Context, ref core.DataRef, dest interface{}) error {
    err := storage.Load(ctx, ref, dest)
    if err != nil {
        if isNotFoundError(err) {
            // Handle gracefully - data may have expired
            log.Printf("Reference %s not found, using empty data", ref.StorageKey)
            return nil
        }
        return err
    }
    return nil
}
```

### 4. Compress Large Data

```go
func (s *S3Storage) StoreCompressed(ctx context.Context, prefix string, data interface{}) (core.DataRef, error) {
    body, _ := json.Marshal(data)

    var compressed bytes.Buffer
    gz := gzip.NewWriter(&compressed)
    gz.Write(body)
    gz.Close()

    // Upload compressed data
    // ...
}
```

## See Also

- **[Magic Markers](/docs/guides/advanced-patterns/magic-markers/)** - OutputRef and CursorFor
- **[FlowState](/docs/concepts/state/)** - State management
- **[Pagination](/docs/guides/advanced-patterns/pagination/)** - Handling large result sets
