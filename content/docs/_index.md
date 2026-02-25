---
title: "Documentation"
description: "Resolute documentation - AgentOrchestration as Code for Go"
weight: 1
---

# Resolute

[![Version](https://img.shields.io/badge/version-v0.4.0--alpha-blue)](https://github.com/resolute-sh/resolute/releases) [![Go](https://img.shields.io/badge/Go-1.22+-00ADD8?logo=go)](https://go.dev) [![License](https://img.shields.io/badge/license-MIT-green)](https://github.com/resolute-sh/resolute/blob/main/LICENSE)

**Agent Orchestration as Code** - Build fault-tolerant workflows with Go.

Resolute is a workflow framework built on [Temporal](https://temporal.io) that lets you define complex, long-running workflows using familiar Go code. It provides a developer-friendly abstraction layer while maintaining Temporal's durability guarantees.

## Why Resolute?

- **Type-Safe Workflows**: Leverage Go generics for compile-time correctness
- **Fluent API**: Build workflows with an intuitive, chainable builder pattern
- **Built-in Patterns**: Compensation (Saga), pagination, rate limiting out of the box
- **Provider Ecosystem**: Pre-built integrations for Jira, Confluence, Ollama, Qdrant, and more
- **Testing Made Easy**: Mock activities and test flows without Temporal infrastructure

## Quick Example

```go
package main

import "github.com/resolute/resolute/core"

func main() {
    // Define a simple data sync workflow
    flow := core.NewFlow("data-sync").
        TriggeredBy(core.Schedule("0 2 * * *")).  // Run daily at 2 AM
        Then(jira.FetchIssues(jira.Input{
            Project: "PLATFORM",
            Since:   core.CursorFor("jira"),      // Incremental sync
        })).
        Then(transform.ChunkDocuments(transform.Input{
            DocumentsRef: core.OutputRef("jira_issues"),
        })).
        Then(ollama.BatchEmbed(ollama.Input{
            DocumentsRef: core.OutputRef("chunks"),
        })).
        Then(qdrant.Upsert(qdrant.Input{
            Collection:   "knowledge-base",
            EmbeddingsRef: core.OutputRef("embeddings"),
        })).
        Build()

    // Run the worker
    core.NewWorker().
        WithFlow(flow).
        WithProviders(jira.Provider, transform.Provider, ollama.Provider, qdrant.Provider).
        Run()
}
```

## What's New

See the **[v0.4.0-alpha release notes](/docs/releases/v0.4.0-alpha/)** for the latest changes, including flow hooks, gate nodes, child workflows, dynamic templates, and new Bitbucket/Slack providers.

## Getting Started

Ready to build your first workflow?

1. **[Prerequisites](/docs/getting-started/prerequisites/)** - Set up your environment
2. **[Installation](/docs/getting-started/installation/)** - Install Resolute
3. **[Quickstart](/docs/getting-started/quickstart/)** - Build your first flow in 5 minutes
