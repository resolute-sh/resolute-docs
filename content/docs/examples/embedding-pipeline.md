---
title: "Embedding Pipeline"
description: "Embedding Pipeline - Resolute documentation"
weight: 20
toc: true
---


# Embedding Pipeline Example

This example demonstrates a complete RAG (Retrieval-Augmented Generation) pipeline that syncs Confluence documentation to a Qdrant vector database using Ollama for embeddings.

## Overview

The pipeline:
1. Incrementally fetches Confluence pages (using cursors)
2. Extracts and chunks text content
3. Generates embeddings with Ollama
4. Stores vectors in Qdrant for semantic search

## Architecture

```
┌─────────────┐     ┌──────────────┐     ┌─────────────┐     ┌─────────────┐
│  Confluence │────▶│  Text        │────▶│   Ollama    │────▶│   Qdrant    │
│  (Source)   │     │  Extraction  │     │  Embedding  │     │  (Vector DB)│
└─────────────┘     └──────────────┘     └─────────────┘     └─────────────┘
       │                                                            │
       └────────────────── Cursor State ───────────────────────────┘
```

## Prerequisites

- Running Temporal server
- Confluence API credentials
- Ollama running locally with `nomic-embed-text` model
- Qdrant instance

## Complete Code

```go
package main

import (
    "os"
    "time"

    "github.com/resolute/resolute/core"
    "github.com/resolute/resolute/providers/confluence"
    "github.com/resolute/resolute/providers/ollama"
    "github.com/resolute/resolute/providers/qdrant"
    "github.com/resolute/resolute/providers/transform"
)

func main() {
    // Configure providers
    confluenceProvider := confluence.NewProvider(confluence.ConfluenceConfig{
        BaseURL:  os.Getenv("CONFLUENCE_BASE_URL"),
        Email:    os.Getenv("CONFLUENCE_EMAIL"),
        APIToken: os.Getenv("CONFLUENCE_API_TOKEN"),
    }).WithRateLimit(100, time.Minute)

    ollamaProvider := ollama.NewProvider(ollama.OllamaConfig{
        Host:    "http://localhost:11434",
        Timeout: 10 * time.Minute,
    })

    qdrantProvider := qdrant.NewProvider(qdrant.QdrantConfig{
        Host:   os.Getenv("QDRANT_HOST"),
        APIKey: os.Getenv("QDRANT_API_KEY"),
    })

    transformProvider := transform.NewProvider()

    // Build the embedding pipeline
    flow := core.NewFlow("confluence-embedder").
        TriggeredBy(core.Schedule("0 2 * * *")). // 2 AM daily

        // Fetch pages incrementally using cursor
        Then(confluence.FetchPages(confluence.FetchPagesInput{
            SpaceKey: "DOCS",
            Cursor:   core.CursorFor("confluence-docs"),
            Limit:    50,
            Expand:   []string{"body.storage"},
        }).As("pages")).

        // Process only if there are new pages
        When(func(s *core.FlowState) bool {
            pages := core.Get[confluence.FetchPagesOutput](s, "pages")
            return len(pages.Pages) > 0
        }).
            // Extract text from HTML
            Then(extractTextNode.As("texts")).

            // Chunk text for embedding
            Then(transform.Chunk(transform.ChunkInput{
                Items: core.Output("texts.Documents"),
                Size:  512, // Characters per chunk
            }).As("chunks")).

            // Generate embeddings in batches
            Then(ollama.EmbedBatch(ollama.EmbedBatchInput{
                Model:     "nomic-embed-text",
                Texts:     core.Output("chunks.Items"),
                BatchSize: 32,
            }).As("embeddings")).

            // Prepare points for Qdrant
            Then(preparePointsNode.As("points")).

            // Store in vector database
            Then(qdrant.UpsertBatch(qdrant.UpsertBatchInput{
                Collection: "confluence-docs",
                Points:     core.Output("points.Data"),
                BatchSize:  100,
                Wait:       true,
            }).As("stored")).
        EndWhen().
        Build()

    // Run worker
    err := core.NewWorker().
        WithConfig(core.WorkerConfig{
            TaskQueue: "embedding-pipeline",
        }).
        WithFlow(flow).
        WithProviders(
            confluenceProvider,
            ollamaProvider,
            qdrantProvider,
            transformProvider,
        ).
        Run()

    if err != nil {
        panic(err)
    }
}

// Custom nodes for text extraction and point preparation

type ExtractInput struct {
    Pages []confluence.Page `json:"pages"`
}

type ExtractOutput struct {
    Documents []Document `json:"documents"`
}

type Document struct {
    ID      string `json:"id"`
    Title   string `json:"title"`
    Content string `json:"content"`
    URL     string `json:"url"`
}

var extractTextNode = core.NewNode("extract-text", extractText)

func extractText(ctx context.Context, input ExtractInput) (ExtractOutput, error) {
    var docs []Document
    for _, page := range input.Pages {
        text := stripHTML(page.Body) // Remove HTML tags
        docs = append(docs, Document{
            ID:      page.ID,
            Title:   page.Title,
            Content: text,
            URL:     page.URL,
        })
    }
    return ExtractOutput{Documents: docs}, nil
}

type PreparePointsInput struct {
    Chunks     []string    `json:"chunks"`
    Embeddings [][]float32 `json:"embeddings"`
    Metadata   []Document  `json:"metadata"`
}

type PreparePointsOutput struct {
    Data []qdrant.Point `json:"data"`
}

var preparePointsNode = core.NewNode("prepare-points", preparePoints)

func preparePoints(ctx context.Context, input PreparePointsInput) (PreparePointsOutput, error) {
    var points []qdrant.Point
    for i, embedding := range input.Embeddings {
        points = append(points, qdrant.Point{
            ID:     fmt.Sprintf("%s-%d", input.Metadata[i].ID, i),
            Vector: embedding,
            Payload: map[string]any{
                "title":   input.Metadata[i].Title,
                "content": input.Chunks[i],
                "url":     input.Metadata[i].URL,
            },
        })
    }
    return PreparePointsOutput{Data: points}, nil
}
```

## Key Patterns Demonstrated

### 1. Incremental Sync with Cursors

```go
confluence.FetchPages(confluence.FetchPagesInput{
    Cursor: core.CursorFor("confluence-docs"),
    // ...
})
```

`core.CursorFor()` automatically tracks the last processed position. On subsequent runs, only new/updated pages are fetched.

### 2. Batch Processing

```go
ollama.EmbedBatch(ollama.EmbedBatchInput{
    BatchSize: 32,
    // ...
})

qdrant.UpsertBatch(qdrant.UpsertBatchInput{
    BatchSize: 100,
    // ...
})
```

Batch operations efficiently process large datasets while respecting memory and API limits.

### 3. Conditional Execution

```go
When(func(s *core.FlowState) bool {
    pages := core.Get[confluence.FetchPagesOutput](s, "pages")
    return len(pages.Pages) > 0
}).
    // Only runs if there are new pages
EndWhen()
```

Avoid unnecessary processing when there's nothing to do.

### 4. Rate Limiting

```go
confluenceProvider := confluence.NewProvider(...).
    WithRateLimit(100, time.Minute)
```

Built-in rate limiting prevents API throttling.

## Semantic Search Query Flow

Add a companion flow for querying the embedded documents:

```go
queryFlow := core.NewFlow("semantic-search").
    TriggeredBy(core.Manual("api")).

    // Embed the query
    Then(ollama.Embed(ollama.EmbedInput{
        Model: "nomic-embed-text",
        Input: core.Input("query"),
    }).As("query-embedding")).

    // Search vector database
    Then(qdrant.Search(qdrant.SearchInput{
        Collection:     "confluence-docs",
        Vector:         core.Output("query-embedding.Embeddings[0]"),
        Limit:          5,
        WithPayload:    true,
        ScoreThreshold: 0.7,
    }).As("results")).

    // Format response
    Then(formatResultsNode).
    Build()
```

## Collection Setup

Before running the pipeline, create the Qdrant collection:

```go
setupFlow := core.NewFlow("setup-collection").
    TriggeredBy(core.Manual("setup")).
    Then(qdrant.CreateCollection(qdrant.CreateCollectionInput{
        Config: qdrant.CollectionConfig{
            Name:       "confluence-docs",
            VectorSize: 768, // nomic-embed-text dimension
            Distance:   "Cosine",
        },
    })).
    Build()
```

## Environment Setup

```bash
# Confluence
export CONFLUENCE_BASE_URL="https://your-org.atlassian.net/wiki"
export CONFLUENCE_EMAIL="your-email@company.com"
export CONFLUENCE_API_TOKEN="your-api-token"

# Qdrant
export QDRANT_HOST="localhost:6334"
export QDRANT_API_KEY="your-api-key"  # Optional for local

# Start Ollama and pull model
ollama pull nomic-embed-text
```

## Performance Considerations

| Factor | Recommendation |
|--------|----------------|
| Chunk size | 256-1024 characters depending on content |
| Batch size | 32-64 for embeddings, 100 for Qdrant |
| Schedule | Off-peak hours for full reindex |
| Rate limits | Match source API limits |

## Error Handling

Add compensation for partial failures:

```go
Then(qdrant.UpsertBatch(...).
    OnError(logFailedPointsNode).
    WithRetry(3, time.Minute))
```

## See Also

- **[Ollama Provider](/docs/reference/providers/ollama/)** - Embedding models
- **[Qdrant Provider](/docs/reference/providers/qdrant/)** - Vector operations
- **[Confluence Provider](/docs/reference/providers/confluence/)** - Page fetching
- **[Pagination](/docs/guides/advanced-patterns/pagination/)** - Handling large datasets
