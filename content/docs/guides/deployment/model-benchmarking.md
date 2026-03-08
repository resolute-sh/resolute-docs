---
title: "Model Benchmarking"
description: "Comparing LLM models for agentic workflows"
weight: 40
toc: true
---

# Model Benchmarking

When building agentic workflows with `resolute-agent`, the choice of LLM model directly impacts report quality, execution cost, and reliability. This guide covers how to benchmark models and make informed production decisions.

## Why Benchmark

Agentic workflows differ from simple prompt/response use cases. The model must:

1. **Use tools correctly** — construct valid arguments for function calls across many tools
2. **Follow instructions** — use provided data (IDs, names) from the prompt, not ask for them
3. **Plan multi-step sequences** — decide which tools to call and in what order
4. **Synthesize across sources** — combine data from multiple tool responses into coherent output
5. **Recognize patterns** — identify recurring issues, historical trends, and correlations

A model that excels at chat may fail at tool orchestration. Benchmarking against your actual workflow is the only reliable way to evaluate.

## Methodology

### 1. Pick a Representative Input

Choose a real input that exercises the full workflow. For incident review, use an actual incident ID that has:
- Multiple alerts and log entries
- Historical precedent (past incidents on the same service)
- Related tickets and documentation
- Slack channel discussion

### 2. Hold Everything Constant

When comparing models, only the LLM configuration should change:

```bash
# Switch model via env var
kubectl set env deploy/my-agent-flow \
  AGENT_PROVIDER_TYPE=<anthropic|ollama> \
  AGENT_BASE_URL=<url> \
  AGENT_MODEL=<model>

kubectl rollout status deployment my-agent-flow
```

Keep the same:
- System prompt
- MCP tool configuration and tool count
- Cost limits and max iterations
- Compaction threshold
- Input data (same incident/trigger)

### 3. Trigger and Collect

Trigger the workflow and extract metrics from Temporal:

```bash
# Trigger via webhook
curl -X POST http://localhost:8080/hooks/trigger \
  -H "Content-Type: application/json" \
  -d '{"event": {...}}'

# Extract metrics from the agent child workflow
temporal workflow show --workflow-id <id>/agent-<name> \
  --namespace default --output json
```

The agent child workflow output contains all metrics needed for comparison.

## Metrics to Compare

### Quantitative

| Metric | What It Tells You |
|--------|-------------------|
| **Iterations** | How efficiently the model plans — fewer iterations = better planning |
| **Input tokens** | Total context consumed — affects cost and compaction frequency |
| **Output tokens** | Response verbosity |
| **Cost (USD)** | Direct API cost per run |
| **Duration** | Wall-clock time including tool calls |
| **Tool calls** | Total tools invoked — compare against expected minimum |
| **Tool errors** | Errors from tools (distinguish model errors from API limitations) |
| **Compaction triggered** | Whether context exceeded threshold — indicates context efficiency |

### Qualitative

Score each model's output on:

| Criterion | What to Look For |
|-----------|-----------------|
| **Correctness** | Did it identify the right entity/issue? |
| **Completeness** | Did it gather data from all available sources? |
| **Actionability** | Are the recommendations specific and useful? |
| **Pattern recognition** | Did it find historical patterns and correlations? |
| **Format compliance** | Does the output match the requested structure? |

## Capability Requirements by Workflow Type

Different agentic workflows have different model requirements:

| Workflow Type | Tool Count | Key Requirement | Minimum Model Class |
|--------------|-----------|-----------------|---------------------|
| Simple Q&A with tools | 5-10 | Basic function calling | 14B+ local, Haiku-class API |
| Multi-source synthesis | 20-50 | Instruction following + synthesis | 32B+ local, Sonnet-class API |
| Complex orchestration | 50-100+ | Planning + tool use + synthesis | 70B+ local, Sonnet/Opus-class API |

## Common Failure Modes

### Model ignores provided data
The model asks "which incident should I investigate?" instead of using the ID from the prompt. This indicates insufficient instruction-following capability for the tool count.

### Model doesn't support tool use
Some local models lack function calling support entirely. Ollama will return a 400 error. Check model compatibility before benchmarking.

### Excessive iterations
The model calls tools one at a time instead of planning a sequence. Results in 2-3x more iterations than necessary. The data quality may still be acceptable, but cost and latency increase.

### Context overflow without compaction
Without compaction enabled, large tool responses (e.g., 72 Atlassian tools with full schemas) can exhaust the context window. Always configure compaction for workflows with many tools.

## Token Efficiency Analysis

Compare input tokens per iteration across models:

```
Tokens/iteration = Total input tokens / Iterations
```

Lower tokens/iteration with the same output quality indicates better planning — the model is making fewer, more targeted tool calls. However, extremely low token counts may indicate the model is skipping important data sources.

Track `PerTurnInputTokens` from the agent output to identify context growth patterns:
- **Linear growth**: Normal — each iteration adds tool results
- **Sudden spikes (>2x)**: Large tool response or redundant calls
- **Flat after compaction**: Compaction working as expected

## Model Categories

### API Models (Anthropic, OpenAI)

**Pros**: Best quality, no infrastructure, consistent availability
**Cons**: Per-token cost, data leaves your network, rate limits

Best for: Production workloads where quality matters more than cost.

### Cloud-Routed Models (Ollama cloud tags)

**Pros**: Zero direct cost, good quality on large models
**Cons**: Routes through third-party infrastructure, rate limits, not truly self-hosted

Best for: Development, benchmarking, cost-constrained environments without data sovereignty requirements.

### Local Models (Ollama local)

**Pros**: No API cost, data stays on-premises, no rate limits
**Cons**: Requires GPU infrastructure, quality varies significantly with parameter count

Best for: Air-gapped environments, high-volume low-cost processing, data sovereignty requirements.

## Reproducing Benchmarks

A complete benchmark run:

```bash
# 1. Deploy with target model
kubectl set env deploy/my-agent-flow \
  AGENT_PROVIDER_TYPE=anthropic \
  AGENT_MODEL=claude-sonnet-4-6
kubectl rollout status deployment my-agent-flow

# 2. Port-forward
kubectl port-forward deploy/my-agent-flow 9090:8080 &

# 3. Trigger with test input
curl -X POST http://localhost:9090/hooks/trigger \
  -H "Content-Type: application/json" \
  -d @test-payload.json

# 4. Wait for completion, then extract metrics
temporal workflow show \
  --workflow-id <workflow-id>/agent-<name> \
  --namespace default --output json

# 5. Repeat steps 1-4 for each model
```

Save the workflow output JSON for each run. The output contains: `iterations`, `input_tokens`, `output_tokens`, `total_cost`, `duration`, `verdict`, `per_turn_input_tokens`, `tokens_saved_by_compact`, `tool_calls`, and `response`.

## Decision Framework

```
Is report quality critical?
├── Yes → Claude Sonnet 4.6 (or Opus for maximum quality)
└── No
    ├── Is cost the primary constraint?
    │   ├── Yes, and cloud API is OK → Claude Haiku 4.5
    │   └── Yes, and must be self-hosted → Qwen3.5 32B+ (test first)
    └── Is data sovereignty required?
        ├── Yes → Local model with sufficient parameters (test 32B+)
        └── No → Claude Haiku 4.5 (best quality/cost ratio)
```

## See Also

- **[Agent Provider](/docs/reference/providers/agent/)** — Agent configuration and observability
- **[Ops Buddy](/docs/examples/ops-buddy/)** — Example with benchmark results
- **[Worker Configuration](/docs/guides/deployment/worker-configuration/)** — Deployment settings
