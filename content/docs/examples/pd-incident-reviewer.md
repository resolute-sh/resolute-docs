---
title: "PD Incident Reviewer"
description: "PD Incident Reviewer - Resolute documentation"
weight: 50
toc: true
---

# PD Incident Reviewer

An automated on-call assistant that listens for PagerDuty webhooks, uses an LLM agent with MCP tool servers to gather context from PagerDuty, Jira, Confluence, and Slack, then posts an operator-first incident brief to a Slack channel.

## Overview

When a PagerDuty incident fires, the on-call engineer needs context fast. This flow:

1. Receives a PagerDuty V3 webhook
2. Validates the signature and filters by allowed services
3. Launches a Claude agent equipped with MCP tools
4. The agent gathers incident details, past incidents, related Jira tickets, Confluence runbooks, and Slack history
5. Produces a structured incident brief
6. Posts the brief to Slack with cost and duration metadata

The engineer gets a ready-to-act report in under 60 seconds.

## Architecture

```
PagerDuty Webhook (:8080)
        │
        ▼
┌─────────────────────┐
│  ParseWebhook       │  Validate signature, extract incident ID,
│  (pagerduty)        │  filter by allowed services
└────────┬────────────┘
         │
         ▼
┌─────────────────────┐
│  Agent Run           │  Multi-turn LLM loop with MCP tools:
│  (agent)             │  • pagerduty-mcp  (incidents, alerts, logs)
│                      │  • mcp-atlassian  (Jira, Confluence)
│                      │  • server-slack   (channel history)
└────────┬────────────┘
         │
         ▼
┌─────────────────────┐
│  NotifyReport        │  Post Block Kit report to Slack
│  (slack)             │  with cost, duration, model info
└─────────────────────┘
```

## Complete Code

### Flow Definition

```go
package pdreviewer

import (
    "os"
    "time"

    agent "github.com/resolute-sh/resolute-agent"
    pagerduty "github.com/resolute-sh/resolute-pagerduty"
    slack "github.com/resolute-sh/resolute-slack"
    "github.com/resolute-sh/resolute/core"
)

const FlowName = "pd-incident-reviewer"

func BuildFlow(cfg FlowConfig) *core.Flow {
    return core.NewFlow(FlowName).
        TriggeredBy(
            core.Webhook("/hooks/pagerduty"),
        ).
        Then(pagerduty.ParseWebhook(pagerduty.ParseWebhookInput{
            RawPayload:      core.InputData("webhook_payload"),
            RawHeaders:      core.InputData("webhook_headers"),
            WebhookSecret:   cfg.PagerDuty.WebhookSecret,
            AllowedServices: cfg.PagerDuty.AllowedServices,
        }).
            As("webhook").
            WithTimeout(30 * time.Second)).
        When(func(s *core.FlowState) bool {
            webhook := core.GetOr(s, "webhook", pagerduty.ParseWebhookOutput{})
            return !webhook.Skipped
        }).
        Then(agent.Run(agent.RunInput{
            ProviderType: cfg.Agent.ProviderType,
            BaseURL:      cfg.Agent.BaseURL,
            APIKey:       cfg.Agent.APIKey,
            Model:        cfg.Agent.Model,
            MaxTokens:    cfg.Agent.MaxTokens,
            SystemPrompt: cfg.Agent.SystemPrompt,
            UserPrompt:   core.Output("webhook.UserPrompt"),
            MaxTurns:     cfg.Agent.MaxTurns,
            MCPServers:   buildMCPServers(),
            CostLimits: agent.CostLimits{
                PerRunUSD:  cfg.CostGuard.PerRunUSD,
                PerHourUSD: cfg.CostGuard.PerHourUSD,
                PerDayUSD:  cfg.CostGuard.PerDayUSD,
            },
        }).
            As("review").
            WithTimeout(15 * time.Minute).
            WithRetry(core.RetryPolicy{MaximumAttempts: 1})).
        Then(slack.NotifyReport(slack.NotifyReportInput{
            WebhookURL:  cfg.Slack.WebhookURL,
            Header:      "Incident Review Complete",
            Label1:      "Incident",
            Value1:      core.Output("webhook.IncidentID"),
            Label2:      "Service",
            Value2:      core.Output("webhook.ServiceName"),
            Body:        core.Output("review.Response"),
            CostUSD:     core.Output("review.CostUSD"),
            Duration:    core.Output("review.Duration"),
            TurnsUsed:   core.Output("review.TurnsUsed"),
            Succeeded:   core.Output("review.Succeeded"),
            LLMProvider: cfg.Agent.ProviderType,
            LLMModel:    cfg.Agent.Model,
            FailHeader:  "Incident Review Failed",
            FailMessage: "The automated review failed. Check Temporal UI for details.",
        }).
            WithTimeout(30 * time.Second)).
        EndWhen().
        Build()
}
```

### MCP Server Configuration

The agent connects to three MCP servers for tool access:

```go
func buildMCPServers() []agent.MCPServerConfig {
    return []agent.MCPServerConfig{
        {
            Name:    "pagerduty",
            Command: "uvx",
            Args:    []string{"pagerduty-mcp", "--enable-write-tools"},
            Env: map[string]string{
                "PAGERDUTY_USER_API_KEY": os.Getenv("PAGERDUTY_USER_API_KEY"),
                "PAGERDUTY_API_HOST":     "https://api.pagerduty.com",
            },
            AllowTools: []string{
                "get_incident", "list_alerts_from_incident", "list_incident_notes",
                "list_log_entries", "get_past_incidents", "get_related_incidents",
                "list_services", "get_service", "list_oncalls",
                "get_escalation_policy", "get_user_data",
            },
        },
        {
            Name:    "atlassian",
            Command: "uvx",
            Args:    []string{"mcp-atlassian"},
            Env: map[string]string{
                "JIRA_URL":             os.Getenv("JIRA_URL"),
                "JIRA_USERNAME":        os.Getenv("JIRA_USERNAME"),
                "JIRA_API_TOKEN":       os.Getenv("JIRA_API_TOKEN"),
                "CONFLUENCE_URL":       os.Getenv("CONFLUENCE_URL"),
                "CONFLUENCE_USERNAME":  os.Getenv("CONFLUENCE_USERNAME"),
                "CONFLUENCE_API_TOKEN": os.Getenv("CONFLUENCE_API_TOKEN"),
            },
        },
        {
            Name:    "slack",
            Command: "npx",
            Args:    []string{"-y", "@modelcontextprotocol/server-slack"},
            Env: map[string]string{
                "SLACK_BOT_TOKEN": os.Getenv("SLACK_BOT_TOKEN"),
                "SLACK_TEAM_ID":   os.Getenv("SLACK_TEAM_ID"),
            },
        },
    }
}
```

### Worker Entry Point

```go
package pdreviewer

import (
    "log"

    agent "github.com/resolute-sh/resolute-agent"
    pagerduty "github.com/resolute-sh/resolute-pagerduty"
    slack "github.com/resolute-sh/resolute-slack"
    "github.com/resolute-sh/resolute/core"
)

func Run() error {
    cfg := LoadFlowConfig()

    return core.NewWorker().
        WithConfig(core.WorkerConfig{
            TaskQueue:     "pd-incident-reviewer-queue",
            MaxConcurrent: cfg.WorkerLimits.MaxConcurrentActivities,
        }).
        WithFlow(BuildFlow(cfg)).
        WithProviders(
            agent.Provider(),
            pagerduty.Provider(),
            slack.Provider(),
        ).
        WithWebhookServer(":8080").
        WithHealthServer(":8081").
        Run()
}
```

## Key Patterns

### 1. Webhook Trigger with Signature Verification

```go
core.Webhook("/hooks/pagerduty")
```

PagerDuty V3 webhooks are validated via HMAC-SHA256 before processing. Set `PAGERDUTY_WEBHOOK_SECRET` to enable.

### 2. Service Filtering

Only incidents from allowed services are processed. Others are marked `Skipped` and the flow short-circuits via the `When` gate.

### 3. Agentic LLM with MCP Tools

The agent autonomously decides which tools to call based on the system prompt. The `AllowTools` field on the PagerDuty MCP server restricts it to read-only operations.

### 4. Cost Guardrails

Three tiers of budget protection:
- **Per-run**: Stops the agent if a single review exceeds the limit
- **Per-hour**: Protects against incident storms
- **Per-day**: Hard daily ceiling

### 5. Structured Slack Reporting

`NotifyReport` handles both success and failure paths. On success, it renders the markdown report as Block Kit with metadata. On failure, it posts a concise error message.

## Environment Variables

```bash
# PagerDuty
PAGERDUTY_WEBHOOK_SECRET=     # V3 webhook signing secret
PAGERDUTY_ALLOWED_SERVICES=   # Comma-separated service names
PAGERDUTY_USER_API_KEY=       # API key for MCP server

# Agent
AGENT_PROVIDER_TYPE=anthropic # "anthropic", "ollama", or "openai-compat"
AGENT_MODEL=claude-sonnet-4-6
AGENT_MAX_TOKENS=8192
AGENT_MAX_TURNS=30
AGENT_SYSTEM_PROMPT_FILE=     # Path to custom prompt file (optional)
AGENT_BASE_URL=               # For ollama/openai-compat
AGENT_API_KEY=                # For openai-compat

# Cost Guards
AGENT_COST_LIMIT_PER_RUN_USD=0
AGENT_COST_LIMIT_PER_HOUR_USD=0
AGENT_COST_LIMIT_PER_DAY_USD=0

# Jira / Confluence (for MCP server)
JIRA_URL=https://your-org.atlassian.net
JIRA_USERNAME=your-email@company.com
JIRA_API_TOKEN=
CONFLUENCE_URL=https://your-org.atlassian.net/wiki
CONFLUENCE_USERNAME=your-email@company.com
CONFLUENCE_API_TOKEN=

# Slack
SLACK_WEBHOOK_URL=            # Incoming webhook for report notifications
SLACK_BOT_TOKEN=              # Bot token for MCP server (channel reads)
SLACK_TEAM_ID=                # Workspace ID for MCP server

# Worker
WORKER_MAX_CONCURRENT_ACTIVITIES=2
```

## Report Output

The agent produces a structured markdown report:

```markdown
# [Incident Title]

> **[NEW ISSUE / RECURRING]** | **Urgency**: High | **Status**: Triggered
> **Service**: api-gateway | **ID**: P1234567 | **Since**: 2 minutes ago

## What Do I Do Right Now?
1. Follow SOP-API-Gateway-5xx — key steps: check pod logs, verify upstream health
2. Check Grafana dashboard for error rate spike
3. If > 50% error rate, escalate to platform-team

## What's Happening?
- API gateway returning 502 errors on /api/v2/users endpoint
- Upstream user-service pods in CrashLoopBackOff
- Blast radius: all authenticated API requests

## Has This Happened Before?
- **Feb 15**: Similar 502 spike, resolved by restarting user-service (12 min)
- **Jan 28**: OOM kill on user-service, resolved by memory limit increase (25 min)
- Pattern: 3rd occurrence in 35 days — root cause is memory leak in user-service

## Open Tickets
| Ticket | Summary | Status | Assignee |
|--------|---------|--------|----------|
| PLAT-892 | user-service memory leak | In Progress | @jane |

## Slack Activity
- **14:32** @oncall-bot — P1 triggered for api-gateway
- **14:33** @jane — Looking into it, seeing OOM kills

## Follow-Up
- Prioritize PLAT-892 memory leak fix
- Add memory usage alerting threshold at 80%
- Update runbook with OOM-specific recovery steps
```

## See Also

- **[Agent Provider](/docs/reference/providers/agent/)** — LLM agent activity reference
- **[PagerDuty Provider](/docs/reference/providers/pagerduty/)** — Webhook parsing and incident APIs
- **[Slack Provider](/docs/reference/providers/slack/)** — NotifyReport and SendMessage
- **[Incident Response Example](/docs/examples/incident-response/)** — Traditional (non-agentic) incident automation
