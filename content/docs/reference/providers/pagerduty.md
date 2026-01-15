---
title: "PagerDuty Provider"
description: "PagerDuty Provider - Resolute documentation"
weight: 50
toc: true
---


# PagerDuty Provider

The PagerDuty provider integrates with PagerDuty for incident management, alerting, and on-call scheduling.

## Installation

```bash
go get github.com/resolute/resolute/providers/pagerduty
```

## Configuration

### PagerDutyConfig

```go
type PagerDutyConfig struct {
    APIKey     string // PagerDuty API key
    ServiceKey string // Default service integration key (optional)
}
```

### Environment Variables

| Variable | Description | Required |
|----------|-------------|----------|
| `PAGERDUTY_API_KEY` | PagerDuty API key | Yes |
| `PAGERDUTY_SERVICE_KEY` | Default service integration key | No |

## Provider Constructor

### NewProvider

```go
func NewProvider(cfg PagerDutyConfig) *PagerDutyProvider
```

Creates a new PagerDuty provider.

**Parameters:**
- `cfg` - PagerDuty configuration

**Returns:** `*PagerDutyProvider` implementing `core.Provider`

**Example:**
```go
provider := pagerduty.NewProvider(pagerduty.PagerDutyConfig{
    APIKey:     os.Getenv("PAGERDUTY_API_KEY"),
    ServiceKey: os.Getenv("PAGERDUTY_SERVICE_KEY"),
})
```

## Types

### Incident

```go
type Incident struct {
    ID               string           `json:"id"`
    IncidentNumber   int              `json:"incident_number"`
    Title            string           `json:"title"`
    Description      string           `json:"description"`
    Status           string           `json:"status"` // "triggered", "acknowledged", "resolved"
    Urgency          string           `json:"urgency"` // "high", "low"
    Priority         *Priority        `json:"priority"`
    Service          ServiceRef       `json:"service"`
    Assignments      []Assignment     `json:"assignments"`
    EscalationPolicy EscalationRef    `json:"escalation_policy"`
    CreatedAt        time.Time        `json:"created_at"`
    LastStatusChange time.Time        `json:"last_status_change_at"`
    ResolvedAt       *time.Time       `json:"resolved_at"`
}

type ServiceRef struct {
    ID   string `json:"id"`
    Name string `json:"name"`
}

type EscalationRef struct {
    ID   string `json:"id"`
    Name string `json:"name"`
}

type Assignment struct {
    At       time.Time `json:"at"`
    Assignee UserRef   `json:"assignee"`
}

type UserRef struct {
    ID    string `json:"id"`
    Name  string `json:"name"`
    Email string `json:"email"`
}
```

### Priority

```go
type Priority struct {
    ID          string `json:"id"`
    Name        string `json:"name"`
    Description string `json:"description"`
    Order       int    `json:"order"`
}
```

### Event

```go
type Event struct {
    RoutingKey  string            `json:"routing_key"`
    EventAction string            `json:"event_action"` // "trigger", "acknowledge", "resolve"
    DedupKey    string            `json:"dedup_key"`
    Payload     EventPayload      `json:"payload"`
    Links       []EventLink       `json:"links"`
    Images      []EventImage      `json:"images"`
}

type EventPayload struct {
    Summary       string            `json:"summary"`
    Source        string            `json:"source"`
    Severity      string            `json:"severity"` // "critical", "error", "warning", "info"
    Timestamp     string            `json:"timestamp"`
    Component     string            `json:"component"`
    Group         string            `json:"group"`
    Class         string            `json:"class"`
    CustomDetails map[string]any    `json:"custom_details"`
}

type EventLink struct {
    Href string `json:"href"`
    Text string `json:"text"`
}

type EventImage struct {
    Src  string `json:"src"`
    Href string `json:"href"`
    Alt  string `json:"alt"`
}
```

### OnCall

```go
type OnCall struct {
    User             UserRef       `json:"user"`
    Schedule         ScheduleRef   `json:"schedule"`
    EscalationPolicy EscalationRef `json:"escalation_policy"`
    EscalationLevel  int           `json:"escalation_level"`
    Start            time.Time     `json:"start"`
    End              time.Time     `json:"end"`
}

type ScheduleRef struct {
    ID   string `json:"id"`
    Name string `json:"name"`
}
```

## Activities

### TriggerEvent

Triggers a new event (creates an incident).

**Input:**
```go
type TriggerEventInput struct {
    RoutingKey  string            `json:"routing_key"`
    Summary     string            `json:"summary"`
    Source      string            `json:"source"`
    Severity    string            `json:"severity"`
    DedupKey    string            `json:"dedup_key"`
    Component   string            `json:"component"`
    Group       string            `json:"group"`
    Class       string            `json:"class"`
    CustomDetails map[string]any  `json:"custom_details"`
    Links       []EventLink       `json:"links"`
}
```

**Output:**
```go
type TriggerEventOutput struct {
    Status   string `json:"status"`
    Message  string `json:"message"`
    DedupKey string `json:"dedup_key"`
}
```

**Node Factory:**
```go
func TriggerEvent(input TriggerEventInput) *core.Node[TriggerEventInput, TriggerEventOutput]
```

**Example:**
```go
triggerNode := pagerduty.TriggerEvent(pagerduty.TriggerEventInput{
    RoutingKey: os.Getenv("PAGERDUTY_ROUTING_KEY"),
    Summary:    "Database connection pool exhausted",
    Source:     "monitoring-service",
    Severity:   "critical",
    DedupKey:   "db-pool-exhausted",
    Component:  "database",
    CustomDetails: map[string]any{
        "pool_size":  100,
        "active":     100,
        "waiting":    50,
    },
})
```

### AcknowledgeEvent

Acknowledges an existing event.

**Input:**
```go
type AcknowledgeEventInput struct {
    RoutingKey string `json:"routing_key"`
    DedupKey   string `json:"dedup_key"`
}
```

**Output:**
```go
type AcknowledgeEventOutput struct {
    Status  string `json:"status"`
    Message string `json:"message"`
}
```

**Node Factory:**
```go
func AcknowledgeEvent(input AcknowledgeEventInput) *core.Node[AcknowledgeEventInput, AcknowledgeEventOutput]
```

### ResolveEvent

Resolves an existing event.

**Input:**
```go
type ResolveEventInput struct {
    RoutingKey string `json:"routing_key"`
    DedupKey   string `json:"dedup_key"`
}
```

**Output:**
```go
type ResolveEventOutput struct {
    Status  string `json:"status"`
    Message string `json:"message"`
}
```

**Node Factory:**
```go
func ResolveEvent(input ResolveEventInput) *core.Node[ResolveEventInput, ResolveEventOutput]
```

**Example:**
```go
resolveNode := pagerduty.ResolveEvent(pagerduty.ResolveEventInput{
    RoutingKey: os.Getenv("PAGERDUTY_ROUTING_KEY"),
    DedupKey:   "db-pool-exhausted",
})
```

### GetIncident

Gets incident details by ID.

**Input:**
```go
type GetIncidentInput struct {
    ID string `json:"id"`
}
```

**Output:**
```go
type GetIncidentOutput struct {
    Incident Incident `json:"incident"`
}
```

**Node Factory:**
```go
func GetIncident(input GetIncidentInput) *core.Node[GetIncidentInput, GetIncidentOutput]
```

### ListIncidents

Lists incidents with filtering options.

**Input:**
```go
type ListIncidentsInput struct {
    Statuses   []string  `json:"statuses"`   // Filter by status
    ServiceIDs []string  `json:"service_ids"` // Filter by service
    Since      time.Time `json:"since"`
    Until      time.Time `json:"until"`
    Urgencies  []string  `json:"urgencies"`
    Limit      int       `json:"limit"`
    Offset     int       `json:"offset"`
}
```

**Output:**
```go
type ListIncidentsOutput struct {
    Incidents []Incident `json:"incidents"`
    Total     int        `json:"total"`
    More      bool       `json:"more"`
}
```

**Node Factory:**
```go
func ListIncidents(input ListIncidentsInput) *core.Node[ListIncidentsInput, ListIncidentsOutput]
```

**Example:**
```go
listNode := pagerduty.ListIncidents(pagerduty.ListIncidentsInput{
    Statuses:   []string{"triggered", "acknowledged"},
    Urgencies:  []string{"high"},
    Since:      time.Now().Add(-24 * time.Hour),
    Limit:      50,
})
```

### UpdateIncident

Updates an incident's status or properties.

**Input:**
```go
type UpdateIncidentInput struct {
    ID         string `json:"id"`
    Status     string `json:"status"`
    Resolution string `json:"resolution"`
    Title      string `json:"title"`
    Urgency    string `json:"urgency"`
    PriorityID string `json:"priority_id"`
}
```

**Output:**
```go
type UpdateIncidentOutput struct {
    Incident Incident `json:"incident"`
}
```

**Node Factory:**
```go
func UpdateIncident(input UpdateIncidentInput) *core.Node[UpdateIncidentInput, UpdateIncidentOutput]
```

### AddNote

Adds a note to an incident.

**Input:**
```go
type AddNoteInput struct {
    IncidentID string `json:"incident_id"`
    Content    string `json:"content"`
}
```

**Output:**
```go
type AddNoteOutput struct {
    NoteID string `json:"note_id"`
}
```

**Node Factory:**
```go
func AddNote(input AddNoteInput) *core.Node[AddNoteInput, AddNoteOutput]
```

### GetOnCalls

Gets current on-call users.

**Input:**
```go
type GetOnCallsInput struct {
    ScheduleIDs        []string  `json:"schedule_ids"`
    EscalationPolicyIDs []string `json:"escalation_policy_ids"`
    Since              time.Time `json:"since"`
    Until              time.Time `json:"until"`
}
```

**Output:**
```go
type GetOnCallsOutput struct {
    OnCalls []OnCall `json:"oncalls"`
}
```

**Node Factory:**
```go
func GetOnCalls(input GetOnCallsInput) *core.Node[GetOnCallsInput, GetOnCallsOutput]
```

**Example:**
```go
onCallNode := pagerduty.GetOnCalls(pagerduty.GetOnCallsInput{
    EscalationPolicyIDs: []string{"POLICY123"},
    Since:               time.Now(),
    Until:               time.Now().Add(24 * time.Hour),
})
```

### ListServices

Lists PagerDuty services.

**Input:**
```go
type ListServicesInput struct {
    Query  string `json:"query"`
    Limit  int    `json:"limit"`
    Offset int    `json:"offset"`
}
```

**Output:**
```go
type ListServicesOutput struct {
    Services []ServiceRef `json:"services"`
    Total    int          `json:"total"`
}
```

**Node Factory:**
```go
func ListServices(input ListServicesInput) *core.Node[ListServicesInput, ListServicesOutput]
```

## Usage Patterns

### Automated Alerting Flow

```go
flow := core.NewFlow("database-monitor").
    TriggeredBy(core.Schedule("*/5 * * * *")).
    Then(checkDatabaseHealthNode.As("health")).
    When(func(s *core.FlowState) bool {
        health := core.Get[HealthCheckOutput](s, "health")
        return health.Status == "critical"
    }).
        Then(pagerduty.TriggerEvent(pagerduty.TriggerEventInput{
            RoutingKey: os.Getenv("PAGERDUTY_ROUTING_KEY"),
            Summary:    core.Output("health.message"),
            Source:     "database-monitor",
            Severity:   "critical",
            DedupKey:   "db-health-check",
        })).
    EndWhen().
    Build()
```

### Incident Response Automation

```go
flow := core.NewFlow("incident-response").
    TriggeredBy(core.Webhook("/pagerduty/webhook")).
    Then(parseWebhookNode.As("event")).
    When(func(s *core.FlowState) bool {
        event := core.Get[WebhookEvent](s, "event")
        return event.Type == "incident.triggered"
    }).
        Then(gatherDiagnosticsNode.As("diagnostics")).
        Then(pagerduty.AddNote(pagerduty.AddNoteInput{
            IncidentID: core.Output("event.incident_id"),
            Content:    core.Output("diagnostics.summary"),
        })).
        Then(notifySlackNode).
    EndWhen().
    Build()
```

### Auto-Resolution Flow

```go
flow := core.NewFlow("auto-resolve").
    TriggeredBy(core.Schedule("*/5 * * * *")).
    Then(checkServiceHealthNode.As("health")).
    When(func(s *core.FlowState) bool {
        health := core.Get[HealthOutput](s, "health")
        return health.Status == "healthy"
    }).
        Then(pagerduty.ResolveEvent(pagerduty.ResolveEventInput{
            RoutingKey: os.Getenv("PAGERDUTY_ROUTING_KEY"),
            DedupKey:   "service-health-check",
        })).
    EndWhen().
    Build()
```

### On-Call Notification Flow

```go
flow := core.NewFlow("on-call-notify").
    TriggeredBy(core.Manual("notify")).
    Then(pagerduty.GetOnCalls(pagerduty.GetOnCallsInput{
        EscalationPolicyIDs: []string{os.Getenv("ESCALATION_POLICY_ID")},
        Since:               time.Now(),
        Until:               time.Now().Add(time.Hour),
    }).As("oncall")).
    Then(sendDirectMessageNode).
    Build()
```

### Incident Metrics Flow

```go
flow := core.NewFlow("incident-metrics").
    TriggeredBy(core.Schedule("0 0 * * *")).
    Then(pagerduty.ListIncidents(pagerduty.ListIncidentsInput{
        Statuses: []string{"resolved"},
        Since:    time.Now().Add(-24 * time.Hour),
        Until:    time.Now(),
        Limit:    100,
    }).As("incidents")).
    Then(calculateMetricsNode.As("metrics")).
    Then(publishMetricsNode).
    Build()
```

## Complete Example

```go
package main

import (
    "os"
    "time"

    "github.com/resolute/resolute/core"
    "github.com/resolute/resolute/providers/pagerduty"
)

func main() {
    // Configure provider
    pdProvider := pagerduty.NewProvider(pagerduty.PagerDutyConfig{
        APIKey: os.Getenv("PAGERDUTY_API_KEY"),
    })

    // Build intelligent alerting flow
    flow := core.NewFlow("smart-alerting").
        TriggeredBy(core.Schedule("*/5 * * * *")).
        // Check system health
        Then(checkSystemHealthNode.As("health")).
        // Alert on critical issues
        When(func(s *core.FlowState) bool {
            health := core.Get[HealthOutput](s, "health")
            return health.Status == "critical"
        }).
            Then(pagerduty.TriggerEvent(pagerduty.TriggerEventInput{
                RoutingKey: os.Getenv("PAGERDUTY_ROUTING_KEY"),
                Summary:    core.Output("health.message"),
                Source:     "health-monitor",
                Severity:   "critical",
                DedupKey:   "system-health",
                Component:  core.Output("health.component"),
                CustomDetails: map[string]any{
                    "metrics": core.Output("health.metrics"),
                },
            })).
            Then(pagerduty.GetOnCalls(pagerduty.GetOnCallsInput{
                EscalationPolicyIDs: []string{os.Getenv("ESCALATION_POLICY")},
            }).As("oncall")).
            Then(notifyOnCallSlackNode).
        EndWhen().
        // Auto-resolve when healthy
        When(func(s *core.FlowState) bool {
            health := core.Get[HealthOutput](s, "health")
            return health.Status == "healthy" && health.WasCritical
        }).
            Then(pagerduty.ResolveEvent(pagerduty.ResolveEventInput{
                RoutingKey: os.Getenv("PAGERDUTY_ROUTING_KEY"),
                DedupKey:   "system-health",
            })).
        EndWhen().
        Build()

    // Run worker
    err := core.NewWorker().
        WithConfig(core.WorkerConfig{
            TaskQueue: "alerting",
        }).
        WithFlow(flow).
        WithProviders(pdProvider).
        Run()

    if err != nil {
        panic(err)
    }
}
```

## See Also

- **[Jira Provider](/docs/reference/providers/jira/)** - Issue tracking
- **[Error Handling](/docs/guides/building-flows/error-handling/)** - Handling failures
- **[Conditional Logic](/docs/guides/building-flows/conditional-logic/)** - Branching flows
