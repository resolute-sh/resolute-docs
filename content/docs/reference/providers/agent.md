---
title: "Agent Provider"
description: "Agent Provider - Resolute documentation"
weight: 10
toc: true
---

# Agent Provider

The Agent provider runs agentic LLM loops as Temporal activities. It connects an LLM (Anthropic Claude, Ollama, or any OpenAI-compatible endpoint) to MCP tool servers, executes a multi-turn conversation, and returns the final response with cost and usage metadata.

## Installation

```bash
go get github.com/resolute-sh/resolute-agent@v0.1.0
```

## Provider Registration

```go
import (
    agent "github.com/resolute-sh/resolute-agent"
)

// Register with worker
agent.RegisterActivities(w)

// Or use Provider() for introspection
provider := agent.Provider()
```

## Types

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
    PerRunUSD  float64 // Max cost per single Run invocation
    PerHourUSD float64 // Max cumulative cost across all runs per hour
    PerDayUSD  float64 // Max cumulative cost across all runs per day
}
```

The cost tracker is process-global — hourly and daily limits apply across all concurrent flows sharing the same worker.

### ToolCallDetail

```go
type ToolCallDetail struct {
    Name     string
    Duration time.Duration
    IsError  bool
}
```

## Activities

### Run

Executes a multi-turn agentic loop: sends a prompt to the LLM, dispatches tool calls to MCP servers, feeds results back, and repeats until the model stops or limits are hit.

**Input:**
```go
type RunInput struct {
    ProviderType string           // "anthropic" (default), "ollama", or "openai-compat"
    BaseURL      string           // Endpoint URL for ollama/openai-compat
    APIKey       string           // API key for openai-compat (ignored by ollama)
    Model        string           // Model identifier (e.g., "claude-sonnet-4-6")
    MaxTokens    int64            // Max tokens per LLM response
    SystemPrompt string           // System prompt for the agent
    UserPrompt   string           // Initial user message
    MaxTurns     int              // Maximum conversation turns
    MCPServers   []MCPServerConfig // MCP servers to spawn
    Memory       []string         // Additional context appended to system prompt
    CostLimits   CostLimits       // Budget guardrails
}
```

**Output:**
```go
type RunOutput struct {
    Response     string           // Final text response from the agent
    TurnsUsed    int              // Actual turns consumed
    InputTokens  int64            // Total input tokens across all turns
    OutputTokens int64            // Total output tokens across all turns
    CostUSD      float64          // Estimated cost in USD
    Duration     time.Duration    // Wall-clock execution time
    ToolCalls    []ToolCallDetail // Per-tool timing and error info
    PromptHash   string           // SHA-256 prefix of system prompt (for tracking)
    Succeeded    bool             // Whether the agent produced a response
}
```

**Node Factory:**
```go
func Run(input RunInput) *core.Node[RunInput, RunOutput]
```

**Example:**
```go
reviewNode := agent.Run(agent.RunInput{
    ProviderType: "anthropic",
    Model:        "claude-sonnet-4-6",
    MaxTokens:    8192,
    SystemPrompt: "You are a code review assistant.",
    UserPrompt:   "Review the latest pull request.",
    MaxTurns:     20,
    MCPServers: []agent.MCPServerConfig{
        {
            Name:    "github",
            Command: "npx",
            Args:    []string{"-y", "@modelcontextprotocol/server-github"},
            Env: map[string]string{
                "GITHUB_TOKEN": os.Getenv("GITHUB_TOKEN"),
            },
        },
    },
    CostLimits: agent.CostLimits{
        PerRunUSD: 1.00,
    },
})
```

## Supported LLM Providers

| ProviderType | Backend | Required Fields |
|-------------|---------|----------------|
| `"anthropic"` (default) | Anthropic API | `ANTHROPIC_API_KEY` env var |
| `"ollama"` | Local Ollama | `BaseURL` |
| `"openai-compat"` | Any OpenAI-compatible endpoint | `BaseURL`, `APIKey` |

## Behavior

- **Retry logic**: API calls retry up to 5 times with exponential backoff. Rate-limit responses (429) wait 60 seconds.
- **Heartbeating**: Each turn sends a Temporal heartbeat for long-running agents.
- **Tool routing**: MCP tools are namespaced as `mcp__<server>__<tool>` to avoid collisions across servers.
- **Result truncation**: Tool results exceeding 20,000 characters are truncated.
- **Cost tracking**: Built-in token-based cost estimation for Claude models. Unknown models report $0.

## Built-in Pricing

| Model | Input (per 1M tokens) | Output (per 1M tokens) |
|-------|----------------------|------------------------|
| `claude-sonnet-4-6` | $3.00 | $15.00 |
| `claude-opus-4-6` | $15.00 | $75.00 |
| `claude-haiku-4-5` | $0.80 | $4.00 |

## Usage Patterns

### Incident Review with MCP Tools

```go
flow := core.NewFlow("incident-review").
    TriggeredBy(core.Webhook("/hooks/pagerduty")).
    Then(parseWebhookNode.As("webhook")).
    Then(agent.Run(agent.RunInput{
        Model:        "claude-sonnet-4-6",
        MaxTokens:    8192,
        SystemPrompt: incidentReviewPrompt,
        UserPrompt:   core.Output("webhook.UserPrompt"),
        MaxTurns:     30,
        MCPServers: []agent.MCPServerConfig{
            {
                Name:    "pagerduty",
                Command: "uvx",
                Args:    []string{"pagerduty-mcp"},
                Env:     map[string]string{"PAGERDUTY_USER_API_KEY": os.Getenv("PD_KEY")},
            },
        },
        CostLimits: agent.CostLimits{PerRunUSD: 2.00},
    }).As("review").WithTimeout(15 * time.Minute)).
    Then(notifySlackNode).
    Build()
```

### Local LLM with Ollama

```go
agentNode := agent.Run(agent.RunInput{
    ProviderType: "ollama",
    BaseURL:      "http://localhost:11434/v1",
    Model:        "llama3.2",
    MaxTokens:    4096,
    SystemPrompt: "You are a helpful assistant.",
    UserPrompt:   core.Output("input.question"),
    MaxTurns:     10,
})
```

## See Also

- **[PagerDuty Provider](/docs/reference/providers/pagerduty/)** — Incident management
- **[Slack Provider](/docs/reference/providers/slack/)** — Notifications
- **[PD Incident Reviewer Example](/docs/examples/pd-incident-reviewer/)** — Complete working example
