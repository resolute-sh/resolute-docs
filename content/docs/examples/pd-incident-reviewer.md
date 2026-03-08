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
3. Launches an agent equipped with MCP tools as a durable child workflow
4. The agent gathers incident details, past incidents, related tickets, runbooks, and channel history
5. Produces a structured incident brief
6. Posts the brief to Slack with cost and duration metadata

The engineer gets a ready-to-act report in under 2 minutes.

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
│  Agent Node          │  Durable child workflow with MCP tools:
│  (agent)             │  • pagerduty-mcp  (incidents, alerts, logs)
│                      │  • mcp-atlassian  (Jira, Confluence)
│                      │  • server-slack   (channel history)
│                      │  Includes: compaction, loop detection,
│                      │  per-turn token tracking
└────────┬────────────┘
         │
         ▼
┌─────────────────────┐
│  NotifyReport        │  Post Block Kit report to Slack
│  (slack)             │  with cost, duration, model info
└─────────────────────┘
```

## Flow Definition

The flow uses `agent.Node()` which runs the agent as a Temporal child workflow — durable across worker restarts and observable via Temporal UI.

```go
func BuildFlow(cfg FlowConfig) *core.Flow {
    return core.NewFlow("incident-reviewer").
        TriggeredBy(core.Webhook("/hooks/incident")).
        Then(pagerduty.ParseWebhook(pagerduty.ParseWebhookInput{
            RawPayload:      core.InputData("webhook_payload"),
            RawHeaders:      core.InputData("webhook_headers"),
            WebhookSecret:   cfg.WebhookSecret,
            AllowedServices: cfg.AllowedServices,
        }).As("webhook").WithTimeout(30 * time.Second)).
        When(func(s *core.FlowState) bool {
            webhook := core.GetOr(s, "webhook", pagerduty.ParseWebhookOutput{})
            return !webhook.Skipped
        }).
        Then(agent.Node("reviewer", agent.NodeConfig{
            LLM: agent.LLMConfig{
                ProviderType: cfg.LLM.ProviderType,
                BaseURL:      cfg.LLM.BaseURL,
                APIKey:       cfg.LLM.APIKey,
                Model:        cfg.LLM.Model,
                MaxTokens:    cfg.LLM.MaxTokens,
            },
            SystemPrompt:  cfg.SystemPrompt,
            UserPrompt:    core.Output("webhook.UserPrompt"),
            MaxIterations: 30,
            Tools:         buildTools(),
            CostLimits: agent.CostLimits{
                PerRunUSD:  cfg.CostLimits.PerRunUSD,
                PerHourUSD: cfg.CostLimits.PerHourUSD,
                PerDayUSD:  cfg.CostLimits.PerDayUSD,
            },
            Compaction: agent.CompactionConfig{
                ThresholdTokens: 80000,
                KeepRecent:      4,
            },
        }).As("review").WithTimeout(15 * time.Minute)).
        Then(slack.NotifyReport(slack.NotifyReportInput{
            WebhookURL:  cfg.SlackWebhookURL,
            Header:      "Incident Review Complete",
            Label1:      "Incident",
            Value1:      core.Output("webhook.IncidentID"),
            Label2:      "Service",
            Value2:      core.Output("webhook.ServiceName"),
            Body:        core.Output("review.Response"),
            CostUSD:     core.Output("review.TotalCost"),
            Duration:    core.Output("review.Duration"),
            TurnsUsed:   core.Output("review.Iterations"),
            Succeeded:   core.Output("review.Succeeded"),
            LLMProvider: cfg.LLM.ProviderType,
            LLMModel:    cfg.LLM.Model,
            FailHeader:  "Incident Review Failed",
            FailMessage: "The automated review failed. Check Temporal UI.",
        }).WithTimeout(30 * time.Second)).
        EndWhen().
        Build()
}
```

## MCP Tool Configuration

The agent connects to three MCP servers for tool access. Use `AllowTools` on the incident management server to restrict to read-only operations.

```go
func buildTools() []agent.Tool {
    return []agent.Tool{
        agent.MCPTool("pagerduty", agent.MCPServerConfig{
            Command: "uvx",
            Args:    []string{"pagerduty-mcp", "--enable-write-tools"},
            Env: map[string]string{
                "PAGERDUTY_USER_API_KEY": os.Getenv("PAGERDUTY_USER_API_KEY"),
            },
            AllowTools: []string{
                "get_incident", "list_alerts_from_incident",
                "list_incident_notes", "list_log_entries",
                "get_past_incidents", "get_related_incidents",
                "list_services", "get_service",
                "list_oncalls", "get_escalation_policy", "get_user_data",
            },
        }),
        agent.MCPTool("atlassian", agent.MCPServerConfig{
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
        }),
        agent.MCPTool("slack", agent.MCPServerConfig{
            Command: "npx",
            Args:    []string{"-y", "@modelcontextprotocol/server-slack"},
            Env: map[string]string{
                "SLACK_BOT_TOKEN": os.Getenv("SLACK_BOT_TOKEN"),
                "SLACK_TEAM_ID":   os.Getenv("SLACK_TEAM_ID"),
            },
        }),
    }
}
```

## Worker Entry Point

```go
func Run() error {
    cfg := LoadConfig()

    return core.NewWorker().
        WithConfig(core.WorkerConfig{
            TaskQueue:     "incident-reviewer-queue",
            MaxConcurrent: 2,
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

### 1. Durable Agent as Child Workflow

`agent.Node()` runs the LLM loop as a Temporal child workflow. If the worker crashes mid-conversation, the workflow resumes from the last completed iteration — no lost context, no re-running tool calls.

### 2. Context Compaction

With 90+ available tools across PagerDuty, Jira, Confluence, and Slack, tool schemas alone consume ~25K tokens. The compaction config triggers automatic summarization when total context exceeds 80K tokens, keeping the last 4 messages intact.

### 3. Service Filtering

Only incidents from allowed services are processed. Others are marked `Skipped` and the flow short-circuits via the `When` gate.

### 4. Cost Guardrails

Three tiers of budget protection:
- **Per-run**: Stops the agent if a single review exceeds the limit
- **Per-hour**: Protects against incident storms
- **Per-day**: Hard daily ceiling

### 5. Multi-Model Support

Switch the LLM provider via environment variables without code changes:

```bash
# Anthropic (production)
AGENT_PROVIDER_TYPE=anthropic
AGENT_MODEL=claude-sonnet-4-6

# Ollama (local/self-hosted)
AGENT_PROVIDER_TYPE=ollama
AGENT_BASE_URL=http://localhost:11434/v1
AGENT_MODEL=qwen3.5:32b
```

## Model Selection

The agent orchestrates 90+ MCP tools, requiring strong tool-use capability. Key requirements in priority order:

1. **Tool use** — must support function calling via OpenAI-compatible API
2. **Instruction following** — must use the incident ID from the prompt, not ask for it
3. **Multi-source synthesis** — combine data from PagerDuty, Jira, Confluence, Slack
4. **Pattern recognition** — identify recurring incidents from historical data

Benchmark results from testing against the same incident:

| Model | Status | Duration | Iterations | Cost | Report Quality |
|-------|--------|----------|------------|------|----------------|
| Claude Sonnet 4.6 | Pass | ~2m | 4 | ~$0.65 | Excellent |
| Claude Haiku 4.5 | Pass | ~1.5m | 9 | ~$0.28 | Good |
| Qwen3.5 397B (cloud) | Pass | ~1.5m | 3 | $0.00 | Good |
| Qwen3.5 9B (local) | Fail | — | — | — | Failed to use incident ID |
| phi4 14B (local) | Fail | — | — | — | No tool-use support |

See **[Model Benchmarking](/docs/guides/deployment/model-benchmarking/)** for methodology and detailed comparison.

## Environment Variables

```bash
# Incident Management
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
AGENT_COST_LIMIT_PER_RUN_USD=2.0
AGENT_COST_LIMIT_PER_HOUR_USD=20.0
AGENT_COST_LIMIT_PER_DAY_USD=100.0

# Jira / Confluence (for MCP server)
JIRA_URL=https://your-org.atlassian.net
JIRA_USERNAME=
JIRA_API_TOKEN=
CONFLUENCE_URL=https://your-org.atlassian.net/wiki
CONFLUENCE_USERNAME=
CONFLUENCE_API_TOKEN=

# Slack
SLACK_WEBHOOK_URL=            # Incoming webhook for report notifications
SLACK_BOT_TOKEN=              # Bot token for MCP server (channel reads)
SLACK_TEAM_ID=                # Workspace ID for MCP server

# Worker
WORKER_MAX_CONCURRENT_ACTIVITIES=2
```

## Report Output

The agent produces a structured markdown report. The system prompt defines the expected format — adapt it to your team's needs:

```markdown
# [Incident Title]

> **[NEW ISSUE / RECURRING]** | **Urgency**: High | **Status**: Triggered
> **Service**: api-gateway | **ID**: P1234567 | **Since**: 2 minutes ago

## What Do I Do Right Now?
1. Follow the relevant SOP — key steps: check pod logs, verify upstream health
2. Check monitoring dashboard for error rate spike
3. If > 50% error rate, escalate to platform team

## What's Happening?
- API gateway returning 502 errors on /api/v2/users endpoint
- Upstream user-service pods in CrashLoopBackOff
- Blast radius: all authenticated API requests

## Has This Happened Before?
- **Feb 15**: Similar 502 spike, resolved by restarting user-service (12 min)
- **Jan 28**: OOM kill on user-service, resolved by memory limit increase (25 min)
- Pattern: 3rd occurrence in 35 days — root cause is memory leak

## Open Tickets
| Ticket | Summary | Status | Assignee |
|--------|---------|--------|----------|
| PLAT-892 | user-service memory leak | In Progress | @jane |

## Follow-Up
- Prioritize memory leak fix
- Add memory usage alerting threshold at 80%
- Update runbook with OOM-specific recovery steps
```

## Deployment

Deploy as a standard Kubernetes deployment with Temporal connectivity:

```yaml
env:
  - name: AGENT_PROVIDER_TYPE
    value: "anthropic"
  - name: AGENT_MODEL
    value: "claude-sonnet-4-6"
  - name: ANTHROPIC_API_KEY
    valueFrom:
      secretKeyRef:
        name: llm-credentials
        key: anthropic-api-key
```

The webhook endpoint listens on port 8080. Configure your incident management platform to send webhooks to `http://<service>:8080/hooks/incident`.

## See Also

- **[Agent Provider](/docs/reference/providers/agent/)** — Agent node reference
- **[PagerDuty Provider](/docs/reference/providers/pagerduty/)** — Webhook parsing and incident APIs
- **[Slack Provider](/docs/reference/providers/slack/)** — NotifyReport and SendMessage
- **[Model Benchmarking](/docs/guides/deployment/model-benchmarking/)** — Comparing LLM models
- **[Incident Response Example](/docs/examples/incident-response/)** — Traditional (non-agentic) incident automation
