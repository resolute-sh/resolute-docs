---
title: "Self-Hosted Deployment"
description: "Self-Hosted Deployment - Resolute documentation"
weight: 30
toc: true
---


# Self-Hosted Deployment

Run Temporal and Resolute workers in your own infrastructure for full control over data and configuration.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        Your Infrastructure                       │
│                                                                  │
│  ┌──────────────┐     ┌──────────────┐     ┌──────────────┐    │
│  │   Worker 1   │     │   Worker 2   │     │   Worker N   │    │
│  │  (Resolute)  │     │  (Resolute)  │     │  (Resolute)  │    │
│  └──────┬───────┘     └──────┬───────┘     └──────┬───────┘    │
│         │                    │                    │             │
│         └────────────────────┼────────────────────┘             │
│                              │                                  │
│                              ▼                                  │
│                    ┌──────────────────┐                        │
│                    │  Temporal Server │                        │
│                    │   (Frontend)     │                        │
│                    └────────┬─────────┘                        │
│                              │                                  │
│         ┌────────────────────┼────────────────────┐            │
│         ▼                    ▼                    ▼            │
│  ┌────────────┐      ┌────────────┐      ┌────────────┐       │
│  │  History   │      │  Matching  │      │   Worker   │       │
│  │  Service   │      │  Service   │      │  Service   │       │
│  └────────────┘      └────────────┘      └────────────┘       │
│         │                    │                    │            │
│         └────────────────────┼────────────────────┘            │
│                              ▼                                  │
│                    ┌──────────────────┐                        │
│                    │    Database      │                        │
│                    │ (PostgreSQL/etc) │                        │
│                    └──────────────────┘                        │
└─────────────────────────────────────────────────────────────────┘
```

## Temporal Server Setup

### Docker Compose (Development)

Quick start for development:

```yaml
# docker-compose.yml
version: "3.9"
services:
  postgresql:
    image: postgres:15
    environment:
      POSTGRES_USER: temporal
      POSTGRES_PASSWORD: temporal
      POSTGRES_DB: temporal
    volumes:
      - postgres-data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U temporal"]
      interval: 5s
      timeout: 5s
      retries: 5

  temporal:
    image: temporalio/auto-setup:latest
    depends_on:
      postgresql:
        condition: service_healthy
    environment:
      - DB=postgresql
      - DB_PORT=5432
      - POSTGRES_USER=temporal
      - POSTGRES_PWD=temporal
      - POSTGRES_SEEDS=postgresql
      - DYNAMIC_CONFIG_FILE_PATH=/etc/temporal/dynamicconfig/development.yaml
    ports:
      - "7233:7233"
    volumes:
      - ./dynamicconfig:/etc/temporal/dynamicconfig

  temporal-ui:
    image: temporalio/ui:latest
    depends_on:
      - temporal
    environment:
      - TEMPORAL_ADDRESS=temporal:7233
      - TEMPORAL_CORS_ORIGINS=http://localhost:3000
    ports:
      - "8080:8080"

volumes:
  postgres-data:
```

Dynamic config file:

```yaml
# dynamicconfig/development.yaml
frontend.enableClientVersionCheck:
  - value: true
    constraints: {}
```

### Kubernetes (Production)

Use the official Helm chart:

```bash
# Add Temporal Helm repository
helm repo add temporal https://temporal.io/helm-charts
helm repo update

# Install with PostgreSQL
helm install temporal temporal/temporal \
  --set server.replicaCount=3 \
  --set cassandra.enabled=false \
  --set mysql.enabled=false \
  --set postgresql.enabled=true \
  --set prometheus.enabled=true \
  --set grafana.enabled=true
```

Custom values:

```yaml
# values.yaml
server:
  replicaCount: 3
  resources:
    requests:
      cpu: "500m"
      memory: "1Gi"
    limits:
      cpu: "2"
      memory: "4Gi"

frontend:
  replicaCount: 2

history:
  replicaCount: 3

matching:
  replicaCount: 2

worker:
  replicaCount: 1

postgresql:
  enabled: true
  auth:
    postgresPassword: "your-secure-password"
  primary:
    persistence:
      size: 50Gi
```

### Database Options

| Database | Use Case |
|----------|----------|
| **PostgreSQL** | Recommended for most deployments |
| **MySQL** | Alternative if PostgreSQL unavailable |
| **Cassandra** | Large scale (>100 workers) |
| **SQLite** | Local development only |

PostgreSQL production config:

```yaml
# PostgreSQL with high availability
postgresql:
  architecture: replication
  primary:
    persistence:
      size: 100Gi
    resources:
      requests:
        cpu: "2"
        memory: "8Gi"
  readReplicas:
    replicaCount: 2
```

## Worker Deployment

### Docker Container

```dockerfile
# Dockerfile
FROM golang:1.22-alpine AS builder

WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -o /worker ./cmd/worker

FROM alpine:latest
RUN apk --no-cache add ca-certificates
COPY --from=builder /worker /worker
ENTRYPOINT ["/worker"]
```

Build and run:

```bash
docker build -t myapp/worker:latest .
docker run -e TEMPORAL_HOST=temporal:7233 \
           -e TASK_QUEUE=production \
           myapp/worker:latest
```

### Kubernetes Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: resolute-worker
  labels:
    app: resolute-worker
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
        image: myapp/worker:latest
        env:
        - name: TEMPORAL_HOST
          value: "temporal-frontend.temporal:7233"
        - name: TEMPORAL_NAMESPACE
          value: "default"
        - name: TASK_QUEUE
          value: "production"
        - name: WORKER_MAX_CONCURRENT
          value: "50"
        # Provider credentials from secrets
        - name: JIRA_API_TOKEN
          valueFrom:
            secretKeyRef:
              name: provider-credentials
              key: jira-token
        - name: SLACK_TOKEN
          valueFrom:
            secretKeyRef:
              name: provider-credentials
              key: slack-token
        resources:
          requests:
            cpu: "250m"
            memory: "256Mi"
          limits:
            cpu: "1"
            memory: "1Gi"
        livenessProbe:
          httpGet:
            path: /health
            port: 8081
          initialDelaySeconds: 10
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /health
            port: 8081
          initialDelaySeconds: 5
          periodSeconds: 5
---
apiVersion: v1
kind: Secret
metadata:
  name: provider-credentials
type: Opaque
stringData:
  jira-token: "your-jira-token"
  slack-token: "your-slack-token"
```

### Worker Code

```go
package main

import (
    "log"
    "net/http"
    "os"
    "strconv"
    "sync/atomic"

    "github.com/resolute/resolute/core"

    "myapp/flows"
    "myapp/providers/jira"
    "myapp/providers/slack"
)

var healthy int32 = 1

func main() {
    // Health endpoint for Kubernetes probes
    go func() {
        http.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
            if atomic.LoadInt32(&healthy) == 1 {
                w.WriteHeader(http.StatusOK)
            } else {
                w.WriteHeader(http.StatusServiceUnavailable)
            }
        })
        http.ListenAndServe(":8081", nil)
    }()

    // Configure worker
    cfg := configFromEnv()

    // Initialize providers
    jiraProvider := jira.NewProvider(jira.Config{
        BaseURL:  os.Getenv("JIRA_BASE_URL"),
        APIToken: os.Getenv("JIRA_API_TOKEN"),
    })

    slackProvider := slack.NewProvider(slack.Config{
        Token: os.Getenv("SLACK_TOKEN"),
    })

    // Run worker
    err := core.NewWorker().
        WithConfig(cfg).
        WithFlow(flows.DataSyncFlow).
        WithProviders(jiraProvider, slackProvider).
        Run()

    atomic.StoreInt32(&healthy, 0)
    if err != nil {
        log.Fatal(err)
    }
}

func configFromEnv() core.WorkerConfig {
    maxConcurrent := 50
    if v := os.Getenv("WORKER_MAX_CONCURRENT"); v != "" {
        if n, err := strconv.Atoi(v); err == nil {
            maxConcurrent = n
        }
    }

    return core.WorkerConfig{
        TemporalHost:  os.Getenv("TEMPORAL_HOST"),
        Namespace:     os.Getenv("TEMPORAL_NAMESPACE"),
        TaskQueue:     os.Getenv("TASK_QUEUE"),
        MaxConcurrent: maxConcurrent,
    }
}
```

## Scaling

### Horizontal Scaling

Add more worker replicas:

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
  maxReplicas: 20
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300
```

### Task Queue Partitioning

Split workloads across queues:

```go
// High-priority queue
highPriorityWorker := core.NewWorker().
    WithConfig(core.WorkerConfig{
        TaskQueue:     "priority-high",
        MaxConcurrent: 10,
    }).
    WithFlow(criticalFlow)

// Standard queue
standardWorker := core.NewWorker().
    WithConfig(core.WorkerConfig{
        TaskQueue:     "standard",
        MaxConcurrent: 100,
    }).
    WithFlow(standardFlow)
```

Deploy dedicated workers per queue:

```yaml
# High priority workers (fewer, faster)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: worker-priority-high
spec:
  replicas: 2
  template:
    spec:
      containers:
      - name: worker
        env:
        - name: TASK_QUEUE
          value: "priority-high"
        resources:
          requests:
            cpu: "1"
            memory: "1Gi"
---
# Standard workers (more, bulk processing)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: worker-standard
spec:
  replicas: 10
  template:
    spec:
      containers:
      - name: worker
        env:
        - name: TASK_QUEUE
          value: "standard"
        resources:
          requests:
            cpu: "500m"
            memory: "512Mi"
```

## Observability

### Prometheus Metrics

Temporal server exposes metrics on port 9090:

```yaml
# prometheus.yml
scrape_configs:
  - job_name: 'temporal'
    static_configs:
      - targets: ['temporal-frontend:9090']

  - job_name: 'temporal-history'
    static_configs:
      - targets: ['temporal-history:9090']

  - job_name: 'temporal-matching'
    static_configs:
      - targets: ['temporal-matching:9090']
```

Key metrics to monitor:

| Metric | Description | Alert Threshold |
|--------|-------------|-----------------|
| `temporal_workflow_count` | Active workflows | > 10,000 |
| `temporal_activity_schedule_to_start_latency` | Task queue latency | > 5s |
| `temporal_workflow_task_queue_backlog` | Pending tasks | > 1,000 |
| `temporal_service_errors` | Error rate | > 1% |

### Grafana Dashboards

Import official Temporal dashboards:
- Temporal Server Overview
- Workflow Metrics
- Activity Metrics
- Task Queue Metrics

### Worker Metrics

Export custom metrics from workers:

```go
import (
    "github.com/prometheus/client_golang/prometheus"
    "github.com/prometheus/client_golang/prometheus/promhttp"
)

var (
    workflowsProcessed = prometheus.NewCounterVec(
        prometheus.CounterOpts{
            Name: "resolute_workflows_processed_total",
            Help: "Total workflows processed by this worker",
        },
        []string{"flow", "status"},
    )

    activityDuration = prometheus.NewHistogramVec(
        prometheus.HistogramOpts{
            Name:    "resolute_activity_duration_seconds",
            Help:    "Activity execution duration",
            Buckets: prometheus.DefBuckets,
        },
        []string{"activity"},
    )
)

func init() {
    prometheus.MustRegister(workflowsProcessed, activityDuration)
}

func main() {
    // Expose metrics endpoint
    go func() {
        http.Handle("/metrics", promhttp.Handler())
        http.ListenAndServe(":9090", nil)
    }()

    // ... worker setup
}
```

### Distributed Tracing

Integrate OpenTelemetry:

```go
import (
    "go.opentelemetry.io/otel"
    "go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
    "go.opentelemetry.io/otel/sdk/trace"
    "go.temporal.io/sdk/contrib/opentelemetry"
)

func initTracing() (*trace.TracerProvider, error) {
    exporter, err := otlptracegrpc.New(context.Background(),
        otlptracegrpc.WithEndpoint("otel-collector:4317"),
        otlptracegrpc.WithInsecure(),
    )
    if err != nil {
        return nil, err
    }

    tp := trace.NewTracerProvider(
        trace.WithBatcher(exporter),
        trace.WithResource(resource.NewWithAttributes(
            semconv.ServiceName("resolute-worker"),
        )),
    )
    otel.SetTracerProvider(tp)
    return tp, nil
}

func main() {
    tp, err := initTracing()
    if err != nil {
        log.Fatal(err)
    }
    defer tp.Shutdown(context.Background())

    // Create tracing interceptor
    interceptor, _ := opentelemetry.NewTracingInterceptor(
        opentelemetry.TracerOptions{},
    )

    // Use with Temporal client
    c, _ := client.Dial(client.Options{
        Interceptors: []interceptor.ClientInterceptor{interceptor},
    })
}
```

## High Availability

### Temporal Server HA

Run multiple replicas:

```yaml
# Helm values for HA
server:
  replicaCount: 3

frontend:
  replicaCount: 3

history:
  replicaCount: 3

matching:
  replicaCount: 3
```

### Database HA

PostgreSQL with streaming replication:

```yaml
postgresql:
  architecture: replication
  primary:
    persistence:
      size: 100Gi
  readReplicas:
    replicaCount: 2
    persistence:
      size: 100Gi
```

### Worker HA

Deploy across availability zones:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: resolute-worker
spec:
  replicas: 6
  template:
    spec:
      topologySpreadConstraints:
      - maxSkew: 1
        topologyKey: topology.kubernetes.io/zone
        whenUnsatisfiable: DoNotSchedule
        labelSelector:
          matchLabels:
            app: resolute-worker
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm:
              labelSelector:
                matchLabels:
                  app: resolute-worker
              topologyKey: kubernetes.io/hostname
```

## Security

### Network Policies

Restrict traffic between components:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: temporal-frontend
spec:
  podSelector:
    matchLabels:
      app: temporal-frontend
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: resolute-worker
    ports:
    - port: 7233
```

### mTLS (Internal)

Enable mTLS for internal Temporal communication:

```yaml
# Helm values
server:
  config:
    tls:
      internode:
        server:
          certFile: /certs/server.pem
          keyFile: /certs/server.key
        client:
          certFile: /certs/client.pem
          keyFile: /certs/client.key
```

### Secret Management

Use external secret operators:

```yaml
# External Secrets Operator
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: provider-credentials
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend
    kind: SecretStore
  target:
    name: provider-credentials
  data:
  - secretKey: jira-token
    remoteRef:
      key: secret/data/myapp/jira
      property: api_token
  - secretKey: slack-token
    remoteRef:
      key: secret/data/myapp/slack
      property: token
```

## Backup and Recovery

### Database Backups

Automated PostgreSQL backups:

```yaml
# Using kubernetes-cronner or similar
apiVersion: batch/v1
kind: CronJob
metadata:
  name: temporal-db-backup
spec:
  schedule: "0 2 * * *"
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: backup
            image: postgres:15
            command:
            - /bin/sh
            - -c
            - |
              pg_dump -h temporal-postgresql -U temporal temporal | \
              gzip > /backups/temporal-$(date +%Y%m%d).sql.gz
            volumeMounts:
            - name: backups
              mountPath: /backups
          volumes:
          - name: backups
            persistentVolumeClaim:
              claimName: backup-storage
```

### Disaster Recovery

1. **Database restore**: Restore from backup to new PostgreSQL
2. **Temporal re-deploy**: Point to restored database
3. **Workers reconnect**: Workers automatically reconnect

```bash
# Restore database
gunzip < temporal-20240115.sql.gz | psql -h new-postgresql -U temporal temporal

# Update Temporal to use new database
helm upgrade temporal temporal/temporal \
  --set postgresql.enabled=false \
  --set server.config.persistence.default.sql.host=new-postgresql
```

## Troubleshooting

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| Workers not picking up tasks | Wrong task queue | Verify TASK_QUEUE matches workflow |
| High latency | Database bottleneck | Scale database, add read replicas |
| Workflow timeouts | Worker crashed | Check worker logs, increase replicas |
| Connection refused | Temporal not ready | Check Temporal pod status |

### Debug Commands

```bash
# Check Temporal services
kubectl get pods -l app.kubernetes.io/name=temporal

# View Temporal logs
kubectl logs -l app.kubernetes.io/component=frontend

# Check worker connectivity
kubectl exec -it worker-pod -- nc -zv temporal-frontend 7233

# List running workflows
temporal workflow list --namespace default
```

### Temporal CLI

Install and configure:

```bash
# Install
curl -sSf https://temporal.download/cli.sh | sh

# Configure for self-hosted
export TEMPORAL_ADDRESS=temporal-frontend:7233
export TEMPORAL_NAMESPACE=default

# List workflows
temporal workflow list

# Describe workflow
temporal workflow describe -w workflow-id

# Terminate stuck workflow
temporal workflow terminate -w workflow-id --reason "manual cleanup"
```

## See Also

- **[Worker Configuration](/docs/guides/deployment/worker-configuration/)** - Worker options
- **[Temporal Cloud](/docs/guides/deployment/temporal-cloud/)** - Managed service
- **[Temporal Self-Hosted Docs](https://docs.temporal.io/self-hosted-guide)** - Official guide
