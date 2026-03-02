---
title: "Kubernetes Provider"
description: "Kubernetes Provider - Resolute documentation"
weight: 40
toc: true
---

# Kubernetes Provider

The Kubernetes provider creates and monitors batch Jobs on a Kubernetes cluster. It uses in-cluster authentication and polls for completion with Temporal heartbeating.

## Installation

```bash
go get github.com/resolute-sh/resolute-k8s@v0.1.0
```

## Configuration

### Authentication

Uses in-cluster service account credentials automatically. The worker must run inside a Kubernetes cluster with a service account that has permissions to create and read Jobs in the target namespace.

Required RBAC:
```yaml
rules:
  - apiGroups: ["batch"]
    resources: ["jobs"]
    verbs: ["create", "get"]
```

### Provider Registration

```go
import (
    "github.com/resolute-sh/resolute-k8s"
)

// Register with worker
k8s.RegisterActivities(w)

// Or use Provider() for introspection
provider := k8s.Provider()
```

## Activities

### RunJob

Creates a Kubernetes batch Job and polls until completion, failure, or timeout.

**Input:**
```go
type RunJobInput struct {
    Name            string            // Job name
    Namespace       string            // Target namespace
    Image           string            // Container image
    ImagePullPolicy corev1.PullPolicy // Pull policy (e.g., corev1.PullAlways)
    Args            []string          // Container arguments
    Env             map[string]string // Environment variables
    EnvFromSecret   string            // Secret name to load env vars from
    Labels          map[string]string // Labels applied to Job and Pod
    BackoffLimit    int32             // Max retries before marking failed
    TTLSeconds      int32             // TTL after completion (default: 3600)
    PollInterval    time.Duration     // Status poll interval (default: 10s)
    Timeout         time.Duration     // Max wait time (default: 30m)
}
```

**Output:**
```go
type RunJobOutput struct {
    JobName   string // Created Job name
    Succeeded bool   // Whether the Job succeeded
    Message   string // Status message
}
```

**Node Factory:**
```go
func RunJob(input RunJobInput) *core.Node[RunJobInput, RunJobOutput]
```

**Example:**
```go
jobNode := k8s.RunJob(k8s.RunJobInput{
    Name:      "data-export-job",
    Namespace: "batch-jobs",
    Image:     "us-docker.pkg.dev/my-project/images/exporter:latest",
    Args:      []string{"--format", "csv", "--output", "/data/export.csv"},
    EnvFromSecret: "exporter-credentials",
    Labels: map[string]string{
        "app": "data-exporter",
    },
    BackoffLimit: 2,
    Timeout:      10 * time.Minute,
})
```

## Usage Patterns

### Scheduled Batch Processing

```go
flow := core.NewFlow("nightly-export").
    TriggeredBy(core.Schedule("0 2 * * *")).
    Then(k8s.RunJob(k8s.RunJobInput{
        Name:          "nightly-export",
        Namespace:     "batch",
        Image:         os.Getenv("EXPORTER_IMAGE"),
        EnvFromSecret: "export-secrets",
        Timeout:       1 * time.Hour,
    }).As("export")).
    When(func(s *core.FlowState) bool {
        result := core.Get[k8s.RunJobOutput](s, "export")
        return result.Succeeded
    }).
        Then(notifySuccessNode).
    EndWhen().
    Build()
```

### Job as Part of a Pipeline

```go
flow := core.NewFlow("ml-pipeline").
    TriggeredBy(core.Manual("train")).
    Then(prepareDataNode.As("data")).
    Then(k8s.RunJob(k8s.RunJobInput{
        Name:      "training-job",
        Namespace: "ml",
        Image:     "training-image:v2",
        Args:      []string{"--dataset", core.Output("data.path")},
        Env: map[string]string{
            "EPOCHS": "50",
        },
        Timeout: 2 * time.Hour,
    }).As("training")).
    Then(evaluateModelNode).
    Build()
```

## See Also

- **[GCP Provider](/docs/reference/providers/gcp/)** — GKE version checks
- **[Error Handling](/docs/guides/building-flows/error-handling/)** — Handling Job failures
