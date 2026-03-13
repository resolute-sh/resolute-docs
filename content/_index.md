---
title: "Resolute"
description: "Agent Orchestration as Code — Run durable LLM agents in production Go workflows. Crash-proof execution, cost guardrails, and MCP tool integration powered by Temporal."
lead: "Agent Orchestration as Code"
subtitle: "Run durable LLM agents in production Go workflows. Crash-proof execution, cost guardrails, and MCP tool integration — powered by Temporal."
date: 2024-01-01T00:00:00+00:00
lastmod: 2024-01-01T00:00:00+00:00
draft: false
seo:
  title: "Resolute — Agent Orchestration as Code"
  description: "Run durable LLM agents in production Go workflows. Crash-proof execution, cost guardrails, and MCP tool integration — powered by Temporal."
  canonical: ""
  noindex: false
---

```go
flow := core.NewFlow("incident-review").
    TriggeredBy(core.Webhook("/hooks/incident")).
    Then(pagerduty.ParseWebhook(webhookInput).As("webhook")).
    When(func(s *core.FlowState) bool {
        return !core.GetOr(s, "webhook", pagerduty.ParseWebhookOutput{}).Skipped
    }).
    Then(agent.Node("reviewer", agent.NodeConfig{
        LLM:          agent.LLMConfig{Model: "claude-sonnet-4-6", MaxTokens: 8192},
        SystemPrompt: reviewPrompt,
        UserPrompt:   core.Output("webhook.UserPrompt"),
        Tools: []agent.Tool{
            agent.MCPTool("pagerduty", pagerdutyMCP),
            agent.MCPTool("jira", jiraMCP),
            agent.MCPTool("slack", slackMCP),
        },
        CostLimits: agent.CostLimits{PerRunUSD: 2.00, PerDayUSD: 100.00},
        Compaction: agent.CompactionConfig{ThresholdTokens: 80000, KeepRecent: 4},
    }).As("review").WithTimeout(15 * time.Minute)).
    Then(slack.NotifyReport(reportInput)).
    Build()
```
