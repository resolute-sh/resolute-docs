---
title: "Incident Response"
description: "Incident Response - Resolute documentation"
weight: 40
toc: true
---


# Incident Response Example

This example demonstrates a multi-system incident response automation that integrates PagerDuty, Jira, Slack, and runbook execution.

## Overview

The incident response workflow:
1. Receives PagerDuty webhook on incident trigger
2. Creates a Jira incident ticket
3. Notifies the on-call team in Slack
4. Executes automated diagnostics
5. Updates incident with findings
6. Auto-resolves if conditions are met

## Architecture

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  PagerDuty  │────▶│   Resolute  │────▶│    Jira     │
│  (Webhook)  │     │   (Flow)    │     │  (Ticket)   │
└─────────────┘     └──────┬──────┘     └─────────────┘
                          │
        ┌─────────────────┼─────────────────┐
        ▼                 ▼                 ▼
  ┌───────────┐    ┌───────────┐    ┌───────────┐
  │   Slack   │    │ Diagnostics│   │ Auto-Fix  │
  │  (Notify) │    │  (Runbook) │   │  (Maybe)  │
  └───────────┘    └───────────┘    └───────────┘
```

## Complete Code

```go
package main

import (
    "context"
    "os"
    "time"

    "github.com/resolute/resolute/core"
    "github.com/resolute/resolute/providers/jira"
    "github.com/resolute/resolute/providers/pagerduty"
    "github.com/resolute/resolute/providers/transform"
)

func main() {
    // Configure providers
    pdProvider := pagerduty.NewProvider(pagerduty.PagerDutyConfig{
        APIKey: os.Getenv("PAGERDUTY_API_KEY"),
    })

    jiraProvider := jira.NewProvider(jira.JiraConfig{
        BaseURL:  os.Getenv("JIRA_BASE_URL"),
        Email:    os.Getenv("JIRA_EMAIL"),
        APIToken: os.Getenv("JIRA_API_TOKEN"),
    })

    transformProvider := transform.NewProvider()

    // Build incident response flow
    flow := core.NewFlow("incident-response").
        TriggeredBy(core.Webhook("/pagerduty/incident")).

        // Parse webhook payload
        Then(parseWebhookNode.As("event")).

        // Handle based on event type
        When(isIncidentTriggered).
            // Parallel: Create ticket + Notify + Run diagnostics
            Parallel().
                Then(jira.CreateIssue(jira.CreateInput{
                    Project:     "OPS",
                    IssueType:   "Incident",
                    Summary:     core.Output("event.Title"),
                    Description: core.Output("event.Description"),
                    Priority:    mapSeverityToPriority,
                    Labels:      []string{"incident", "automated"},
                }).As("ticket")).

                Then(notifySlackChannelNode.As("slack-notified")).

                Then(runDiagnosticsNode.As("diagnostics")).
            EndParallel().

            // Add diagnostics to Jira ticket
            Then(jira.AddComment(jira.CommentInput{
                IssueKey: core.Output("ticket.Key"),
                Body:     core.Output("diagnostics.Summary"),
            })).

            // Add diagnostics to PagerDuty
            Then(pagerduty.AddNote(pagerduty.AddNoteInput{
                IncidentID: core.Output("event.IncidentID"),
                Content:    core.Output("diagnostics.Summary"),
            })).

            // Check if auto-remediation is possible
            When(canAutoRemediate).
                Then(executeRemediationNode.As("remediation")).
                When(remediationSucceeded).
                    // Auto-resolve the incident
                    Then(pagerduty.ResolveEvent(pagerduty.ResolveEventInput{
                        RoutingKey: os.Getenv("PAGERDUTY_ROUTING_KEY"),
                        DedupKey:   core.Output("event.DedupKey"),
                    })).
                    Then(jira.TransitionIssue(jira.TransitionInput{
                        IssueKey:   core.Output("ticket.Key"),
                        Transition: "Resolve",
                        Resolution: "Auto-remediated",
                    })).
                    Then(notifyResolutionNode).
                EndWhen().
            EndWhen().
        EndWhen().

        // Handle acknowledgment events
        When(isIncidentAcknowledged).
            Then(updateJiraAssigneeNode).
            Then(notifyAckInSlackNode).
        EndWhen().

        // Handle resolution events
        When(isIncidentResolved).
            Then(jira.TransitionIssue(jira.TransitionInput{
                IssueKey:   core.Output("event.LinkedTicket"),
                Transition: "Resolve",
            })).
            Then(notifyResolutionInSlackNode).
        EndWhen().

        Build()

    // Run worker
    err := core.NewWorker().
        WithConfig(core.WorkerConfig{
            TaskQueue: "incident-response",
        }).
        WithFlow(flow).
        WithProviders(pdProvider, jiraProvider, transformProvider).
        Run()

    if err != nil {
        panic(err)
    }
}

// Event type predicates
func isIncidentTriggered(s *core.FlowState) bool {
    event := core.Get[WebhookEvent](s, "event")
    return event.Type == "incident.triggered"
}

func isIncidentAcknowledged(s *core.FlowState) bool {
    event := core.Get[WebhookEvent](s, "event")
    return event.Type == "incident.acknowledged"
}

func isIncidentResolved(s *core.FlowState) bool {
    event := core.Get[WebhookEvent](s, "event")
    return event.Type == "incident.resolved"
}

func canAutoRemediate(s *core.FlowState) bool {
    diagnostics := core.Get[DiagnosticsOutput](s, "diagnostics")
    return diagnostics.RemediationAvailable && diagnostics.Confidence > 0.9
}

func remediationSucceeded(s *core.FlowState) bool {
    remediation := core.Get[RemediationOutput](s, "remediation")
    return remediation.Success
}

// Webhook payload parsing
type WebhookEvent struct {
    Type         string `json:"type"`
    IncidentID   string `json:"incident_id"`
    Title        string `json:"title"`
    Description  string `json:"description"`
    Severity     string `json:"severity"`
    DedupKey     string `json:"dedup_key"`
    Service      string `json:"service"`
    LinkedTicket string `json:"linked_ticket"`
}

var parseWebhookNode = core.NewNode("parse-webhook", parseWebhook)

func parseWebhook(ctx context.Context, input map[string]any) (WebhookEvent, error) {
    // Parse PagerDuty webhook format
    return WebhookEvent{
        Type:        input["event"].(map[string]any)["event_type"].(string),
        IncidentID:  input["event"].(map[string]any)["data"].(map[string]any)["id"].(string),
        Title:       input["event"].(map[string]any)["data"].(map[string]any)["title"].(string),
        // ... more parsing
    }, nil
}

// Diagnostics execution
type DiagnosticsOutput struct {
    Summary              string `json:"summary"`
    RemediationAvailable bool   `json:"remediation_available"`
    Confidence           float64 `json:"confidence"`
    Checks               []Check `json:"checks"`
}

type Check struct {
    Name   string `json:"name"`
    Status string `json:"status"`
    Output string `json:"output"`
}

var runDiagnosticsNode = core.NewNode("run-diagnostics", runDiagnostics)

func runDiagnostics(ctx context.Context, input WebhookEvent) (DiagnosticsOutput, error) {
    var checks []Check

    // Run service-specific diagnostics
    switch input.Service {
    case "api-gateway":
        checks = runAPIGatewayChecks()
    case "database":
        checks = runDatabaseChecks()
    case "cache":
        checks = runCacheChecks()
    default:
        checks = runGenericChecks()
    }

    return DiagnosticsOutput{
        Summary:              formatChecks(checks),
        RemediationAvailable: hasKnownRemediation(checks),
        Confidence:           calculateConfidence(checks),
        Checks:               checks,
    }, nil
}

// Remediation execution
type RemediationOutput struct {
    Success bool   `json:"success"`
    Action  string `json:"action"`
    Output  string `json:"output"`
}

var executeRemediationNode = core.NewNode("execute-remediation", executeRemediation)

func executeRemediation(ctx context.Context, input DiagnosticsOutput) (RemediationOutput, error) {
    // Execute known remediation based on diagnostics
    // Examples: restart service, scale up, clear cache, etc.
    return RemediationOutput{
        Success: true,
        Action:  "restarted-service",
        Output:  "Service restarted successfully",
    }, nil
}
```

## Key Patterns Demonstrated

### 1. Webhook Trigger

```go
core.Webhook("/pagerduty/incident")
```

Exposes an HTTP endpoint that triggers the workflow. The webhook payload is available via `core.Input()`.

### 2. Conditional Branching

```go
When(isIncidentTriggered).
    // Handle triggered events
EndWhen().
When(isIncidentAcknowledged).
    // Handle ack events
EndWhen().
```

Route execution based on event type or any state predicate.

### 3. Parallel Execution

```go
Parallel().
    Then(createJiraTicketNode).
    Then(notifySlackNode).
    Then(runDiagnosticsNode).
EndParallel()
```

Execute independent tasks concurrently to reduce incident response time.

### 4. Nested Conditions

```go
When(canAutoRemediate).
    Then(executeRemediationNode).
    When(remediationSucceeded).
        Then(resolveIncidentNode).
    EndWhen().
EndWhen()
```

Complex decision trees with multiple conditions.

## On-Call Integration

Get on-call info for targeted notifications:

```go
flow := core.NewFlow("incident-with-oncall").
    TriggeredBy(core.Webhook("/incident")).
    Then(parseWebhookNode.As("event")).

    // Get current on-call
    Then(pagerduty.GetOnCalls(pagerduty.GetOnCallsInput{
        EscalationPolicyIDs: []string{os.Getenv("ESCALATION_POLICY")},
        Since:               time.Now(),
        Until:               time.Now().Add(time.Hour),
    }).As("oncall")).

    // Direct message on-call engineer
    Then(slackDMNode).
    Build()
```

## Incident Metrics Collection

Track incident response metrics:

```go
flow := core.NewFlow("incident-with-metrics").
    TriggeredBy(core.Webhook("/incident")).
    Then(recordIncidentStartNode.As("metrics")).
    Then(handleIncidentNode).
    Then(recordIncidentEndNode).
    Then(publishMetricsNode).
    Build()

type IncidentMetrics struct {
    IncidentID       string        `json:"incident_id"`
    TimeToAck        time.Duration `json:"time_to_ack"`
    TimeToResolve    time.Duration `json:"time_to_resolve"`
    AutoRemediated   bool          `json:"auto_remediated"`
    DiagnosticsRun   []string      `json:"diagnostics_run"`
}
```

## Escalation Flow

Handle escalation when initial response fails:

```go
flow := core.NewFlow("incident-with-escalation").
    TriggeredBy(core.Webhook("/incident")).
    Then(handleIncidentNode.As("response")).

    // Set escalation timer
    Then(core.Timer(15 * time.Minute).As("escalation-timer")).

    When(notAcknowledgedAfterTimer).
        Then(pagerduty.TriggerEvent(pagerduty.TriggerEventInput{
            RoutingKey: os.Getenv("ESCALATION_ROUTING_KEY"),
            Summary:    "Incident not acknowledged - escalating",
            Severity:   "high",
        })).
        Then(notifyManagementSlackNode).
    EndWhen().
    Build()
```

## Post-Incident Automation

Automate post-incident tasks:

```go
postIncidentFlow := core.NewFlow("post-incident").
    TriggeredBy(core.Signal("incident-resolved")).

    // Create post-mortem document
    Then(confluence.CreatePage(confluence.CreatePageInput{
        SpaceKey: "INCIDENTS",
        Title:    core.Output("input.incident_title") + " - Post-Mortem",
        Body:     postMortemTemplate,
    }).As("postmortem")).

    // Schedule post-mortem meeting
    Then(schedulePostMortemMeetingNode).

    // Update incident ticket with post-mortem link
    Then(jira.AddComment(jira.CommentInput{
        IssueKey: core.Output("input.ticket_key"),
        Body:     "Post-mortem: " + core.Output("postmortem.URL"),
    })).

    Build()
```

## Environment Variables

```bash
# PagerDuty
export PAGERDUTY_API_KEY="your-api-key"
export PAGERDUTY_ROUTING_KEY="your-routing-key"
export ESCALATION_POLICY="POLICY123"

# Jira
export JIRA_BASE_URL="https://your-org.atlassian.net"
export JIRA_EMAIL="your-email@company.com"
export JIRA_API_TOKEN="your-api-token"

# Slack
export SLACK_BOT_TOKEN="xoxb-..."
export SLACK_INCIDENT_CHANNEL="C0123456789"
```

## Best Practices

| Practice | Rationale |
|----------|-----------|
| Parallel notifications | Reduce time-to-notify |
| Automated diagnostics | Provide immediate context |
| Auto-remediation with confidence threshold | Only auto-fix when certain |
| Link all systems | Jira ticket linked to PagerDuty incident |
| Audit trail | Log all actions for post-mortem |

## See Also

- **[PagerDuty Provider](/docs/reference/providers/pagerduty/)** - Full API reference
- **[Jira Provider](/docs/reference/providers/jira/)** - Issue management
- **[Parallel Execution](/docs/guides/building-flows/parallel-execution/)** - Concurrent steps
- **[Conditional Logic](/docs/guides/building-flows/conditional-logic/)** - Branching flows
