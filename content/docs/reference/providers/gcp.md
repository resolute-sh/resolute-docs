---
title: "GCP Provider"
description: "GCP Provider - Resolute documentation"
weight: 35
toc: true
---

# GCP Provider

The GCP provider integrates with Google Cloud Platform services. Currently supports GKE version availability checks across regions.

## Installation

```bash
go get github.com/resolute-sh/resolute-gcp@v0.1.0
```

## Configuration

### ProviderConfig

```go
type ProviderConfig struct {
    ProjectID string // GCP project ID
}
```

### Authentication

Uses Application Default Credentials (ADC). Set up via:

```bash
gcloud auth application-default login
```

Or configure a service account with the `container.clusterManager.getServerConfig` permission.

### Provider Registration

```go
import (
    "github.com/resolute-sh/resolute-gcp"
)

provider := gcp.Provider(gcp.ProviderConfig{
    ProjectID: os.Getenv("GCP_PROJECT_ID"),
})
```

The provider includes a health check that verifies GKE API connectivity on startup.

## Activities

### CheckVersion

Checks if a GKE version is available for both master and node pools across specified regions.

**Input:**
```go
type CheckVersionInput struct {
    ProjectID string   // GCP project ID
    Version   string   // GKE version to check (e.g., "1.29.1-gke.1589000")
    Regions   []string // Regions to check (e.g., ["us-central1", "europe-west1"])
}
```

**Output:**
```go
type CheckVersionOutput struct {
    Version          string   // Checked version
    TotalRegions     int      // Number of regions checked
    AvailableRegions []string // Regions where version is available
    FailedRegions    []string // Regions where version is unavailable or check failed
    AllAvailable     bool     // True if available in all requested regions
}
```

**Node Factory:**
```go
func CheckVersion(input CheckVersionInput) *core.Node[CheckVersionInput, CheckVersionOutput]
```

**Example:**
```go
checkNode := gcp.CheckVersion(gcp.CheckVersionInput{
    ProjectID: os.Getenv("GCP_PROJECT_ID"),
    Version:   "1.29.1-gke.1589000",
    Regions:   []string{"us-central1", "us-east1", "europe-west1"},
})
```

## Usage Patterns

### GKE Version Rollout Monitor

```go
flow := core.NewFlow("gke-version-check").
    TriggeredBy(core.Schedule("0 8 * * *")).
    Then(gcp.CheckVersion(gcp.CheckVersionInput{
        ProjectID: os.Getenv("GCP_PROJECT_ID"),
        Version:   os.Getenv("TARGET_GKE_VERSION"),
        Regions:   []string{"us-central1", "us-east1", "europe-west1"},
    }).As("check")).
    When(func(s *core.FlowState) bool {
        result := core.Get[gcp.CheckVersionOutput](s, "check")
        return result.AllAvailable
    }).
        Then(notifyReadyNode).
    EndWhen().
    Build()
```

## See Also

- **[Kubernetes Provider](/docs/reference/providers/k8s/)** — Run Kubernetes Jobs
- **[Triggers](/docs/concepts/triggers/)** — Schedule triggers
