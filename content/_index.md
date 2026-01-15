---
title: "Resolute"
description: "Workflow Orchestration as Code - Build fault-tolerant workflows with Go. Type-safe, fluent API built on Temporal."
lead: "Workflow Orchestration  as Code. Build fault-tolerant workflows with Go. Type-safe, fluent API built on Temporal."
date: 2024-01-01T00:00:00+00:00
lastmod: 2024-01-01T00:00:00+00:00
draft: false
seo:
  title: "Resolute - Workflow Orchestration  as Code"
  description: "Workflow Orchestration  as Code. Build fault-tolerant workflows with Go. Type-safe, fluent API built on Temporal."
  canonical: ""
  noindex: false
---

```go
flow := core.NewFlow("knowledge-sync").
    TriggeredBy(core.Schedule("0 * * * *")).
    Then(jira.FetchIssues(jira.Input{
        Project: "PLATFORM",
        Since:   core.CursorFor("jira"),
    })).
    Then(transform.ChunkDocuments(transform.Input{
        DocumentsRef: core.OutputRef("jira_issues"),
    })).
    Then(qdrant.Upsert(qdrant.Input{
        Collection: "knowledge-base",
    })).
    Build()
```
