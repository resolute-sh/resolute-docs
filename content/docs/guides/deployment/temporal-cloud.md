---
title: "Temporal Cloud"
description: "Temporal Cloud - Resolute documentation"
weight: 20
toc: true
---


# Temporal Cloud Deployment

Temporal Cloud provides a fully managed Temporal service. This guide covers connecting Resolute workers to Temporal Cloud.

## Prerequisites

- Temporal Cloud account ([cloud.temporal.io](https://cloud.temporal.io))
- Namespace created in Temporal Cloud
- mTLS certificates generated

## Connection Configuration

### Basic Setup

```go
package main

import (
    "crypto/tls"
    "log"
    "os"

    "github.com/resolute/resolute/core"
    "go.temporal.io/sdk/client"

    "myapp/flows"
)

func main() {
    // Load mTLS certificates
    cert, err := tls.LoadX509KeyPair(
        os.Getenv("TEMPORAL_TLS_CERT"),
        os.Getenv("TEMPORAL_TLS_KEY"),
    )
    if err != nil {
        log.Fatalf("load cert: %v", err)
    }

    // Connect to Temporal Cloud
    c, err := client.Dial(client.Options{
        HostPort:  os.Getenv("TEMPORAL_HOST"), // e.g., "myns.abc123.tmprl.cloud:7233"
        Namespace: os.Getenv("TEMPORAL_NAMESPACE"),
        ConnectionOptions: client.ConnectionOptions{
            TLS: &tls.Config{
                Certificates: []tls.Certificate{cert},
            },
        },
    })
    if err != nil {
        log.Fatalf("dial temporal: %v", err)
    }
    defer c.Close()

    // Build worker with existing client
    worker := core.NewWorker().
        WithConfig(core.WorkerConfig{
            TaskQueue: "data-sync",
        })

    if err := worker.Build(); err != nil {
        log.Fatal(err)
    }

    // Use pre-configured client
    // (WorkerBuilder uses its own client by default,
    // so we access the underlying worker directly)
    w := worker.Worker()
    w.RegisterWorkflow(flows.DataSyncFlow.Execute)

    if err := w.Run(worker.InterruptCh()); err != nil {
        log.Fatal(err)
    }
}
```

### Environment Variables

Configure via environment for different stages:

| Variable | Description | Example |
|----------|-------------|---------|
| `TEMPORAL_HOST` | Temporal Cloud endpoint | `myns.abc123.tmprl.cloud:7233` |
| `TEMPORAL_NAMESPACE` | Cloud namespace | `myns.abc123` |
| `TEMPORAL_TLS_CERT` | Path to client certificate | `/certs/client.pem` |
| `TEMPORAL_TLS_KEY` | Path to client key | `/certs/client.key` |

## mTLS Certificate Setup

### Generate Certificates

Use Temporal CLI or OpenSSL:

```bash
# Using Temporal CLI
temporal cloud certificate generate \
    --namespace myns.abc123 \
    --output-dir ./certs

# Results:
# ./certs/client.pem  (certificate)
# ./certs/client.key  (private key)
```

### Certificate Rotation

Implement certificate rotation for production:

```go
type CertReloader struct {
    certPath string
    keyPath  string
    cert     *tls.Certificate
    mu       sync.RWMutex
}

func NewCertReloader(certPath, keyPath string) (*CertReloader, error) {
    r := &CertReloader{
        certPath: certPath,
        keyPath:  keyPath,
    }
    if err := r.reload(); err != nil {
        return nil, err
    }
    return r, nil
}

func (r *CertReloader) reload() error {
    cert, err := tls.LoadX509KeyPair(r.certPath, r.keyPath)
    if err != nil {
        return err
    }
    r.mu.Lock()
    r.cert = &cert
    r.mu.Unlock()
    return nil
}

func (r *CertReloader) GetCertificate(*tls.ClientHelloInfo) (*tls.Certificate, error) {
    r.mu.RLock()
    defer r.mu.RUnlock()
    return r.cert, nil
}

// Watch for certificate changes
func (r *CertReloader) Watch(ctx context.Context) {
    ticker := time.NewTicker(time.Hour)
    for {
        select {
        case <-ctx.Done():
            return
        case <-ticker.C:
            if err := r.reload(); err != nil {
                log.Printf("reload cert: %v", err)
            }
        }
    }
}
```

Use in client configuration:

```go
reloader, err := NewCertReloader(certPath, keyPath)
if err != nil {
    log.Fatal(err)
}

go reloader.Watch(ctx)

c, err := client.Dial(client.Options{
    HostPort:  temporalHost,
    Namespace: namespace,
    ConnectionOptions: client.ConnectionOptions{
        TLS: &tls.Config{
            GetClientCertificate: func(*tls.CertificateRequestInfo) (*tls.Certificate, error) {
                return reloader.GetCertificate(nil)
            },
        },
    },
})
```

## Namespace Configuration

### Creating a Namespace

Via Temporal Cloud UI or CLI:

```bash
temporal cloud namespace create \
    --namespace myns \
    --region us-west-2 \
    --retention 30d
```

### Namespace Settings

| Setting | Recommendation |
|---------|----------------|
| **Retention** | 30 days for production, 7 days for dev |
| **Region** | Match your worker deployment region |
| **Search Attributes** | Define for workflow queries |

### Search Attributes

Register custom search attributes:

```bash
temporal cloud namespace search-attributes add \
    --namespace myns.abc123 \
    --name CustomerId --type Keyword \
    --name Priority --type Int
```

Use in workflows:

```go
func (f *Flow) Execute(ctx workflow.Context, input FlowInput) error {
    workflow.UpsertSearchAttributes(ctx, map[string]interface{}{
        "CustomerId": input.CustomerID,
        "Priority":   input.Priority,
    })
    // ...
}
```

## Worker Deployment

### Kubernetes Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: resolute-worker
spec:
  replicas: 3
  selector:
    matchLabels:
      app: resolute-worker
  template:
    metadata:
      labels:
        app: resolute-worker
    spec:
      containers:
      - name: worker
        image: myregistry/resolute-worker:latest
        env:
        - name: TEMPORAL_HOST
          value: "myns.abc123.tmprl.cloud:7233"
        - name: TEMPORAL_NAMESPACE
          value: "myns.abc123"
        - name: TEMPORAL_TLS_CERT
          value: "/certs/client.pem"
        - name: TEMPORAL_TLS_KEY
          value: "/certs/client.key"
        - name: TASK_QUEUE
          value: "production"
        volumeMounts:
        - name: temporal-certs
          mountPath: /certs
          readOnly: true
        resources:
          requests:
            cpu: "500m"
            memory: "512Mi"
          limits:
            cpu: "2"
            memory: "2Gi"
      volumes:
      - name: temporal-certs
        secret:
          secretName: temporal-cloud-certs
---
apiVersion: v1
kind: Secret
metadata:
  name: temporal-cloud-certs
type: Opaque
data:
  client.pem: <base64-encoded-cert>
  client.key: <base64-encoded-key>
```

### Horizontal Pod Autoscaling

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: resolute-worker-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: resolute-worker
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
```

## Observability

### Metrics

Temporal Cloud provides built-in metrics. Export to your observability stack:

```go
import (
    "go.temporal.io/sdk/client"
    "go.temporal.io/sdk/contrib/opentelemetry"
    "go.opentelemetry.io/otel"
)

// Configure OpenTelemetry
tp := initTracerProvider() // Your tracer setup
otel.SetTracerProvider(tp)

// Use with Temporal client
interceptor, err := opentelemetry.NewTracingInterceptor(opentelemetry.TracerOptions{})
if err != nil {
    log.Fatal(err)
}

c, err := client.Dial(client.Options{
    HostPort:     temporalHost,
    Namespace:    namespace,
    Interceptors: []interceptor.ClientInterceptor{interceptor},
})
```

### Cloud Metrics Dashboard

Access via Temporal Cloud UI:
- Workflow execution counts
- Activity execution latency
- Task queue depth
- Error rates

### Alerts

Configure alerts in Temporal Cloud:
- High workflow failure rate
- Task queue backlog growth
- Long-running workflows

## Multi-Region Setup

### Active-Passive

```
┌────────────────┐     ┌─────────────────────┐
│  Workers       │────▶│  Temporal Cloud     │
│  (us-west-2)   │     │  (us-west-2)        │
└────────────────┘     └─────────────────────┘
                              │
                              │ Replication
                              ▼
                       ┌─────────────────────┐
                       │  Temporal Cloud     │
                       │  (us-east-1)        │
                       │  (standby)          │
                       └─────────────────────┘
```

### Active-Active (Multiple Task Queues)

```go
// Regional worker configuration
func workerConfig(region string) core.WorkerConfig {
    return core.WorkerConfig{
        TaskQueue: fmt.Sprintf("workflows-%s", region),
        // ... other config
    }
}

// Route workflows to regional queues
func startWorkflow(ctx context.Context, c client.Client, region string, input Input) error {
    _, err := c.ExecuteWorkflow(ctx, client.StartWorkflowOptions{
        TaskQueue: fmt.Sprintf("workflows-%s", region),
    }, workflow, input)
    return err
}
```

## Cost Optimization

### Actions Pricing

Temporal Cloud bills by actions. Optimize:

1. **Batch operations**: Combine multiple small activities
2. **Reduce polling**: Use signals instead of activity-based polling
3. **Optimize heartbeats**: Use appropriate intervals

### Worker Sizing

Match worker count to workload:

```go
// Scale workers based on queue depth
func autoScale(ctx context.Context, c client.Client, queue string) {
    for {
        desc, _ := c.DescribeTaskQueue(ctx, queue, temporal.TaskQueueTypeActivity)
        backlog := desc.GetBacklogCountHint()

        // Scale up if backlog growing
        if backlog > 1000 {
            // Trigger scale-up
        }

        time.Sleep(time.Minute)
    }
}
```

## Security Best Practices

### 1. Least Privilege

Create separate namespaces for environments:
- `myapp-prod.abc123`
- `myapp-staging.abc123`
- `myapp-dev.abc123`

### 2. Certificate Management

- Store certificates in secret managers (Vault, AWS Secrets Manager)
- Rotate certificates before expiration
- Use separate certificates per environment

### 3. Network Security

- Deploy workers in private subnets
- Use VPC peering if available
- Restrict outbound to Temporal Cloud endpoints only

## Troubleshooting

### Connection Issues

```go
// Test connectivity
func testConnection() error {
    c, err := client.Dial(options)
    if err != nil {
        return fmt.Errorf("dial: %w", err)
    }
    defer c.Close()

    // Check service health
    _, err = c.CheckHealth(context.Background(), &client.CheckHealthRequest{})
    if err != nil {
        return fmt.Errorf("health check: %w", err)
    }

    return nil
}
```

### Common Errors

| Error | Cause | Solution |
|-------|-------|----------|
| `certificate required` | Missing mTLS cert | Check TEMPORAL_TLS_CERT path |
| `namespace not found` | Wrong namespace | Verify namespace in Cloud UI |
| `connection refused` | Wrong host | Check TEMPORAL_HOST format |
| `permission denied` | Invalid cert | Regenerate certificates |

### Debug Logging

```go
import "go.temporal.io/sdk/log"

logger := log.NewStructuredLogger(slog.Default())

c, err := client.Dial(client.Options{
    Logger: logger,
    // ...
})
```

## Migration from Self-Hosted

### 1. Set Up Cloud Namespace

Create namespace in Temporal Cloud matching your configuration.

### 2. Update Worker Configuration

```go
// Before (self-hosted)
cfg := core.WorkerConfig{
    TemporalHost: "temporal.internal:7233",
    Namespace:    "default",
}

// After (Temporal Cloud)
cfg := core.WorkerConfig{
    TemporalHost: "myns.abc123.tmprl.cloud:7233",
    Namespace:    "myns.abc123",
}
// Plus mTLS configuration
```

### 3. Migrate Running Workflows

Workflows must complete on old cluster before cutover, or use:
- Workflow versioning for gradual migration
- Dual-write pattern during transition

## See Also

- **[Worker Configuration](/docs/guides/deployment/worker-configuration/)** - Worker options
- **[Self-Hosted](/docs/guides/deployment/self-hosted/)** - Self-hosted deployment
- **[Temporal Cloud Docs](https://docs.temporal.io/cloud)** - Official documentation
