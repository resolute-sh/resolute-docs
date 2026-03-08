---
title: "Agent Provider"
description: "Agent Provider - Resolute documentation"
weight: 10
toc: true
---

# Agent Provider

The Agent provider runs durable agentic LLM loops as Temporal child workflows. It connects an LLM (Anthropic Claude, Ollama, or any OpenAI-compatible endpoint) to MCP tool servers and resolute provider activities, executes a multi-turn conversation with automatic context compaction, and returns the final response with cost, token, and observability metadata.

## Installation

```bash
go get github.com/resolute-sh/resolute-agent@latest
```

## Architecture

The agent runs as a **Temporal child workflow** (`agent.workflow`), not a plain activity. This gives it:

- **Durable execution** — survives worker restarts mid-conversation
- **Per-iteration heartbeating** — Temporal tracks liveness at each LLM turn
- **Signal-based observer pattern** — parent flow can inspect and override agent decisions between iterations
- **Automatic context compaction** — summarizes older messages when token count exceeds a threshold

```
Parent Flow Workflow
    │
    ├── ParseWebhook (activity)
    │
    ├── Agent Child Workflow ◄── agent.Node("reviewer", config)
    │       │
    │       ├── MCP Discover (activity)
    │       │
    │       └── Loop:
    │           ├── LLM Call (activity)
    │           ├── Tool Dispatch (activity per tool)
    │           ├── Observer Signal ←→ Parent (if configured)
    │           ├── Loop Detection (hash-based)
    │           ├── Context Growth Check (per-turn token tracking)
    │           └── Compaction (if threshold exceeded)
    │
    └── NotifyReport (activity)
```

## Provider Registration

```go
import (
    agent "github.com/resolute-sh/resolute-agent"
)

provider := agent.Provider()

core.NewWorker().
    WithFlow(myFlow).
    WithProviders(provider).
    Run()
```

## Types

### LLMConfig

```go
type LLMConfig struct {
    ProviderType string // "anthropic" (default), "ollama", or "openai-compat"
    BaseURL      string // Endpoint URL for ollama/openai-compat
    APIKey       string // API key (ignored by ollama)
    Model        string // Model identifier (e.g., "claude-sonnet-4-6")
    MaxTokens    int64  // Max tokens per LLM response
}
```

### CompactionConfig

Controls automatic context summarization when the conversation grows too large.

```go
type CompactionConfig struct {
    ThresholdTokens int64  // Trigger compaction above this token count (e.g., 80000)
    KeepRecent      int    // Number of recent messages to preserve (e.g., 4)
    Model           string // Model for summarization (defaults to agent model)
}
```

When compaction triggers, older messages are summarized into a single message. The agent logs `tokens_before`, `tokens_after`, and `tokens_saved` for ROI tracking.

### MCPServerConfig

Defines an MCP server process to spawn for tool access.

```go
type MCPServerConfig struct {
    Name       string            // Server identifier (used in tool name prefix)
    Command    string            // Executable (e.g., "uvx", "npx")
    Args       []string          // Command arguments
    Env        map[string]string // Environment variables
    AllowTools []string          // Allowlist of tool names (empty = all)
}
```

Tools are exposed to the LLM with qualified names: `mcp__<server-name>__<tool-name>`.

### CostLimits

Optional budget thresholds. Zero values disable the corresponding limit.

```go
type CostLimits struct {
    PerRunUSD  float64 // Max cost per single agent run
    PerHourUSD float64 // Max cumulative cost across all runs per hour
    PerDayUSD  float64 // Max cumulative cost across all runs per day
}
```

The cost tracker is process-global — hourly and daily limits apply across all concurrent flows sharing the same worker.

### NodeConfig

```go
type NodeConfig struct {
    LLM              LLMConfig
    SystemPrompt     string
    UserPrompt       string           // Supports core.Output() magic markers
    MaxIterations    int              // Default: 20
    Tools            []Tool           // MCP servers and provider activities
    Memory           []string         // Additional context appended to system prompt
    Observer         Observer         // Optional per-iteration evaluation function
    CostLimits       CostLimits
    Compaction       CompactionConfig
    LLMTimeout       time.Duration    // Default: 2m per LLM call
    ToolTimeout      time.Duration    // Default: 5m per tool call
    EscalationSignal string           // Signal name for observer escalation
    CustomPricing    *ModelPricing    // Cost calculation for non-built-in models
}
```

### Tool Sources

The agent accepts tools from two sources:

```go
// MCP server — discovers tools via MCP protocol
agent.MCPTool("pagerduty", agent.MCPServerConfig{
    Command: "uvx",
    Args:    []string{"pagerduty-mcp"},
    Env:     map[string]string{"PAGERDUTY_USER_API_KEY": os.Getenv("PD_KEY")},
})

// Resolute provider — exposes provider activities as LLM-callable tools
agent.ProviderTool("slack", slack.Provider())
```

### NodeOutput

Stored in FlowState under the key set by `.As()`.

```go
type NodeOutput struct {
    Response             string           // Final text response
    Succeeded            bool             // Whether the agent produced a response
    Iterations           int              // Actual iterations consumed
    TotalCost            float64          // Estimated cost in USD
    InputTokens          int64            // Total input tokens
    OutputTokens         int64            // Total output tokens
    ToolCalls            []ToolCallDetail // Per-tool timing and error info
    Duration             time.Duration    // Wall-clock execution time
    Verdict              Verdict          // Final observer verdict
    Summaries            []string         // Compaction summaries (if any)
    PerTurnInputTokens   []int64          // Input tokens per iteration
    TokensSavedByCompact int64            // Tokens reclaimed by compaction
}
```

### ToolCallDetail

```go
type ToolCallDetail struct {
    Name     string
    Duration time.Duration
    IsError  bool
}
```

### Verdict

The observer returns a verdict after each iteration:

```go
const (
    VerdictContinue Verdict = iota // Keep going
    VerdictSucceed                  // Stop — agent succeeded
    VerdictFail                     // Stop — agent failed
    VerdictEscalate                 // Stop — needs human intervention
)
```

## Creating Agent Nodes

Use `agent.Node()` to create an agent step in a flow:

```go
reviewNode := agent.Node("reviewer", agent.NodeConfig{
    LLM: agent.LLMConfig{
        ProviderType: "anthropic",
        Model:        "claude-sonnet-4-6",
        MaxTokens:    8192,
    },
    SystemPrompt:  "You are an incident review assistant...",
    UserPrompt:    core.Output("webhook.UserPrompt"),
    MaxIterations: 30,
    Tools: []agent.Tool{
        agent.MCPTool("pagerduty", agent.MCPServerConfig{
            Command: "uvx",
            Args:    []string{"pagerduty-mcp"},
            Env:     map[string]string{"PAGERDUTY_USER_API_KEY": os.Getenv("PD_KEY")},
        }),
        agent.MCPTool("github", agent.MCPServerConfig{
            Command: "npx",
            Args:    []string{"-y", "@modelcontextprotocol/server-github"},
            Env:     map[string]string{"GITHUB_TOKEN": os.Getenv("GITHUB_TOKEN")},
        }),
    },
    CostLimits: agent.CostLimits{PerRunUSD: 2.00},
    Compaction: agent.CompactionConfig{
        ThresholdTokens: 80000,
        KeepRecent:      4,
    },
}).As("review")
```

Then place it in a flow:

```go
flow := core.NewFlow("incident-review").
    TriggeredBy(core.Webhook("/hooks/pagerduty")).
    Then(parseWebhookNode.As("webhook")).
    Then(reviewNode.WithTimeout(15 * time.Minute)).
    Then(notifyNode).
    Build()
```

## Observer Pattern

The observer function runs in the parent workflow context after each agent iteration. It receives read-only state and returns a verdict.

```go
reviewNode := agent.Node("reviewer", agent.NodeConfig{
    // ... LLM, tools, etc.
    Observer: func(ctx agent.ObserverContext) agent.Verdict {
        if ctx.TotalCost > 5.0 {
            return agent.VerdictFail
        }
        if ctx.Iteration > 20 && ctx.TotalCost < 0.10 {
            return agent.VerdictFail // stuck in a loop
        }
        return agent.VerdictContinue
    },
})
```

The observer communicates with the child workflow via Temporal signals — no shared memory, fully durable.

## Custom Pricing

For models not in the built-in pricing table, provide a `ModelPricing` struct:

```go
agent.NodeConfig{
    LLM: agent.LLMConfig{
        ProviderType: "ollama",
        BaseURL:      "http://localhost:11434/v1",
        Model:        "qwen3.5:32b",
        MaxTokens:    16384,
    },
    CustomPricing: &agent.ModelPricing{
        InputPerMillionTokens:  0.50,
        OutputPerMillionTokens: 1.50,
    },
}
```

## Supported LLM Providers

| ProviderType | Backend | Required Fields |
|-------------|---------|----------------|
| `"anthropic"` (default) | Anthropic API | `ANTHROPIC_API_KEY` env var |
| `"ollama"` | Local Ollama (OpenAI-compat) | `BaseURL` (e.g., `http://localhost:11434/v1`) |
| `"openai-compat"` | Any OpenAI-compatible endpoint | `BaseURL`, `APIKey` |

Ollama models must support tool use (function calling) via the OpenAI-compatible API. Not all models do — test with your target model before deploying.

## Built-in Pricing

| Model | Input (per 1M tokens) | Output (per 1M tokens) |
|-------|----------------------|------------------------|
| `claude-sonnet-4-6` | $3.00 | $15.00 |
| `claude-opus-4-6` | $15.00 | $75.00 |
| `claude-haiku-4-5` | $0.80 | $4.00 |

## Observability

The agent emits structured logs at key points:

| Event | Fields |
|-------|--------|
| **MCP tools discovered** | `tool_count`, `schema_bytes`, `estimated_tokens` |
| **Provider tools registered** | `tool_count`, `schema_bytes`, `estimated_tokens` |
| **Iteration completed** | `iteration`, `input_tokens`, `output_tokens`, `cost` |
| **Context growth warning** | `current_tokens`, `previous_tokens`, `growth_ratio` (>2x) |
| **Loop detected** | `tool_name`, `consecutive_failures`, `hash` |
| **Compaction completed** | `tokens_before`, `tokens_after`, `tokens_saved` |

`PerTurnInputTokens` in the output tracks input token count per iteration, enabling post-hoc analysis of context growth patterns.

`TokensSavedByCompact` reports total tokens reclaimed across all compaction cycles during the run.

## Behavior

- **Child workflow**: The agent runs as a Temporal child workflow, not a plain activity. This enables durable execution across worker restarts.
- **Retry logic**: LLM API calls retry up to 5 times with exponential backoff. Rate-limit responses (429) wait 60 seconds.
- **Heartbeating**: Each iteration sends a Temporal heartbeat.
- **Tool routing**: MCP tools are namespaced as `mcp__<server>__<tool>`. Provider tools are namespaced as `<provider>__<activity>`.
- **Result truncation**: Tool results exceeding 20,000 characters are truncated.
- **Loop detection**: Consecutive identical tool calls (same name + input hash) are detected. After 3 consecutive failures, the agent intervenes.
- **Context compaction**: When token count exceeds the configured threshold, older messages are summarized to reduce context size while preserving key information.

## Usage Patterns

### Incident Review with MCP Tools

```go
flow := core.NewFlow("incident-review").
    TriggeredBy(core.Webhook("/hooks/incident")).
    Then(parseWebhookNode.As("webhook")).
    Then(agent.Node("reviewer", agent.NodeConfig{
        LLM: agent.LLMConfig{
            Model:    "claude-sonnet-4-6",
            MaxTokens: 8192,
        },
        SystemPrompt:  reviewPrompt,
        UserPrompt:    core.Output("webhook.UserPrompt"),
        MaxIterations: 30,
        Tools: []agent.Tool{
            agent.MCPTool("pagerduty", pagerdutyMCP),
            agent.MCPTool("jira", jiraMCP),
        },
        CostLimits: agent.CostLimits{PerRunUSD: 2.00},
        Compaction: agent.CompactionConfig{
            ThresholdTokens: 80000,
            KeepRecent:      4,
        },
    }).As("review").WithTimeout(15 * time.Minute)).
    Then(notifySlackNode).
    Build()
```

### Local LLM with Ollama

```go
agentNode := agent.Node("assistant", agent.NodeConfig{
    LLM: agent.LLMConfig{
        ProviderType: "ollama",
        BaseURL:      "http://localhost:11434/v1",
        Model:        "qwen3.5:32b",
        MaxTokens:    4096,
    },
    SystemPrompt:  "You are a helpful assistant.",
    UserPrompt:    core.Output("input.question"),
    MaxIterations: 10,
    Tools: []agent.Tool{
        agent.MCPTool("filesystem", agent.MCPServerConfig{
            Command: "npx",
            Args:    []string{"-y", "@modelcontextprotocol/server-filesystem", "/data"},
        }),
    },
})
```

### Provider Activities as Agent Tools

Expose resolute provider activities directly to the LLM:

```go
agentNode := agent.Node("ops", agent.NodeConfig{
    LLM: agent.LLMConfig{Model: "claude-sonnet-4-6", MaxTokens: 8192},
    SystemPrompt: "You are an operations assistant.",
    UserPrompt:   "Check the current on-call schedule.",
    Tools: []agent.Tool{
        agent.ProviderTool("pagerduty", pagerduty.Provider()),
        agent.ProviderTool("slack", slack.Provider()),
    },
})
```

## See Also

- **[PagerDuty Provider](/docs/reference/providers/pagerduty/)** — Incident management
- **[Slack Provider](/docs/reference/providers/slack/)** — Notifications
- **[Ops Buddy Example](/docs/examples/ops-buddy/)** — Complete working example
- **[Model Benchmarking](/docs/guides/deployment/model-benchmarking/)** — Comparing LLM models for agentic workflows
