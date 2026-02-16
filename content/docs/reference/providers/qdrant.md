---
title: "Qdrant Provider"
description: "Qdrant Provider - Resolute documentation"
weight: 30
toc: true
---


# Qdrant Provider

The Qdrant provider integrates with Qdrant vector database for storing, searching, and managing vector embeddings.

## Installation

```bash
go get github.com/resolute/resolute/providers/qdrant
```

## Configuration

### QdrantConfig

```go
type QdrantConfig struct {
    Host     string // Qdrant server host (e.g., "localhost:6334")
    APIKey   string // API key for authentication (optional)
    UseTLS   bool   // Enable TLS connection
    Timeout  time.Duration // Request timeout
}
```

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `QDRANT_HOST` | Qdrant server address | `localhost:6334` |
| `QDRANT_API_KEY` | API key for authentication | - |
| `QDRANT_USE_TLS` | Enable TLS | `false` |

## Provider Constructor

### NewProvider

```go
func NewProvider(cfg QdrantConfig) *QdrantProvider
```

Creates a new Qdrant provider.

**Parameters:**
- `cfg` - Qdrant configuration

**Returns:** `*QdrantProvider` implementing `core.Provider`

**Example:**
```go
provider := qdrant.NewProvider(qdrant.QdrantConfig{
    Host:   os.Getenv("QDRANT_HOST"),
    APIKey: os.Getenv("QDRANT_API_KEY"),
    UseTLS: true,
})
```

## Types

### Point

```go
type Point struct {
    ID      string            `json:"id"`
    Vector  []float32         `json:"vector"`
    Payload map[string]any    `json:"payload"`
}
```

### ScoredPoint

```go
type ScoredPoint struct {
    ID      string            `json:"id"`
    Score   float32           `json:"score"`
    Vector  []float32         `json:"vector"`
    Payload map[string]any    `json:"payload"`
}
```

### Filter

```go
type Filter struct {
    Must    []Condition `json:"must"`
    Should  []Condition `json:"should"`
    MustNot []Condition `json:"must_not"`
}

type Condition struct {
    Field string `json:"field"`
    Match Match  `json:"match"`
}

type Match struct {
    Value    any      `json:"value"`
    Values   []any    `json:"values"`
    Range    *Range   `json:"range"`
}

type Range struct {
    GT  *float64 `json:"gt"`
    GTE *float64 `json:"gte"`
    LT  *float64 `json:"lt"`
    LTE *float64 `json:"lte"`
}
```

### CollectionConfig

```go
type CollectionConfig struct {
    Name           string `json:"name"`
    VectorSize     int    `json:"vector_size"`
    Distance       string `json:"distance"` // "Cosine", "Euclid", "Dot"
    OnDiskPayload  bool   `json:"on_disk_payload"`
    ShardNumber    int    `json:"shard_number"`
    ReplicationFactor int `json:"replication_factor"`
}
```

## Activities

### Search

Performs vector similarity search.

**Input:**
```go
type SearchInput struct {
    Collection  string    `json:"collection"`
    Vector      []float32 `json:"vector"`
    Limit       int       `json:"limit"`
    Filter      *Filter   `json:"filter"`
    WithPayload bool      `json:"with_payload"`
    WithVector  bool      `json:"with_vector"`
    ScoreThreshold float32 `json:"score_threshold"`
}
```

**Output:**
```go
type SearchOutput struct {
    Results []ScoredPoint `json:"results"`
    Count   int           `json:"count"`
}
```

**Node Factory:**
```go
func Search(input SearchInput) *core.Node[SearchInput, SearchOutput]
```

**Example:**
```go
searchNode := qdrant.Search(qdrant.SearchInput{
    Collection:  "documents",
    Vector:      queryEmbedding,
    Limit:       10,
    WithPayload: true,
    Filter: &qdrant.Filter{
        Must: []qdrant.Condition{
            {Field: "category", Match: qdrant.Match{Value: "technical"}},
        },
    },
})
```

### SearchBatch

Performs multiple vector searches in a single request.

**Input:**
```go
type SearchBatchInput struct {
    Collection string      `json:"collection"`
    Searches   []SearchInput `json:"searches"`
}
```

**Output:**
```go
type SearchBatchOutput struct {
    Results [][]ScoredPoint `json:"results"`
}
```

**Node Factory:**
```go
func SearchBatch(input SearchBatchInput) *core.Node[SearchBatchInput, SearchBatchOutput]
```

### Upsert

Inserts or updates points in a collection.

**Input:**
```go
type UpsertInput struct {
    Collection string  `json:"collection"`
    Points     []Point `json:"points"`
    Wait       bool    `json:"wait"` // Wait for operation to complete
}
```

**Output:**
```go
type UpsertOutput struct {
    Status    string `json:"status"`
    Upserted  int    `json:"upserted"`
}
```

**Node Factory:**
```go
func Upsert(input UpsertInput) *core.Node[UpsertInput, UpsertOutput]
```

**Example:**
```go
upsertNode := qdrant.Upsert(qdrant.UpsertInput{
    Collection: "documents",
    Points: []qdrant.Point{
        {
            ID:     "doc-1",
            Vector: embedding1,
            Payload: map[string]any{
                "title":    "Document Title",
                "category": "technical",
            },
        },
    },
    Wait: true,
})
```

#### Automatic Payload Fields

When upserting embeddings from a DataRef, the Upsert activity automatically adds metadata to each point's payload:

- `source_id` — the original document ID
- `source` — the data source identifier (e.g., "jira", "confluence", "pagerduty"), included when `Document.Source` is non-empty

These fields enable filtering search results by origin:

```go
searchNode := qdrant.Search(qdrant.SearchInput{
    Collection: "knowledge",
    Vector:     queryVector,
    Limit:      10,
    Filter: &qdrant.Filter{
        Must: []qdrant.Condition{
            {Field: "source", Match: qdrant.Match{Value: "jira"}},
        },
    },
})
```

### UpsertBatch

Inserts points in batches for large datasets.

**Input:**
```go
type UpsertBatchInput struct {
    Collection string  `json:"collection"`
    Points     []Point `json:"points"`
    BatchSize  int     `json:"batch_size"` // Points per batch (default: 100)
    Wait       bool    `json:"wait"`
}
```

**Output:**
```go
type UpsertBatchOutput struct {
    Status   string `json:"status"`
    Upserted int    `json:"upserted"`
    Batches  int    `json:"batches"`
}
```

**Node Factory:**
```go
func UpsertBatch(input UpsertBatchInput) *core.Node[UpsertBatchInput, UpsertBatchOutput]
```

### Delete

Deletes points from a collection.

**Input:**
```go
type DeleteInput struct {
    Collection string   `json:"collection"`
    IDs        []string `json:"ids"`
    Filter     *Filter  `json:"filter"`
    Wait       bool     `json:"wait"`
}
```

**Output:**
```go
type DeleteOutput struct {
    Status  string `json:"status"`
    Deleted int    `json:"deleted"`
}
```

**Node Factory:**
```go
func Delete(input DeleteInput) *core.Node[DeleteInput, DeleteOutput]
```

**Example:**
```go
// Delete by IDs
deleteNode := qdrant.Delete(qdrant.DeleteInput{
    Collection: "documents",
    IDs:        []string{"doc-1", "doc-2"},
})

// Delete by filter
deleteNode := qdrant.Delete(qdrant.DeleteInput{
    Collection: "documents",
    Filter: &qdrant.Filter{
        Must: []qdrant.Condition{
            {Field: "expired", Match: qdrant.Match{Value: true}},
        },
    },
})
```

### GetPoints

Retrieves specific points by ID.

**Input:**
```go
type GetPointsInput struct {
    Collection  string   `json:"collection"`
    IDs         []string `json:"ids"`
    WithPayload bool     `json:"with_payload"`
    WithVector  bool     `json:"with_vector"`
}
```

**Output:**
```go
type GetPointsOutput struct {
    Points []Point `json:"points"`
}
```

**Node Factory:**
```go
func GetPoints(input GetPointsInput) *core.Node[GetPointsInput, GetPointsOutput]
```

### Scroll

Iterates through all points in a collection.

**Input:**
```go
type ScrollInput struct {
    Collection  string  `json:"collection"`
    Filter      *Filter `json:"filter"`
    Limit       int     `json:"limit"`
    Offset      string  `json:"offset"` // Point ID to start from
    WithPayload bool    `json:"with_payload"`
    WithVector  bool    `json:"with_vector"`
}
```

**Output:**
```go
type ScrollOutput struct {
    Points     []Point `json:"points"`
    NextOffset string  `json:"next_offset"`
}
```

**Node Factory:**
```go
func Scroll(input ScrollInput) *core.Node[ScrollInput, ScrollOutput]
```

### CreateCollection

Creates a new collection.

**Input:**
```go
type CreateCollectionInput struct {
    Config CollectionConfig `json:"config"`
}
```

**Output:**
```go
type CreateCollectionOutput struct {
    Status string `json:"status"`
}
```

**Node Factory:**
```go
func CreateCollection(input CreateCollectionInput) *core.Node[CreateCollectionInput, CreateCollectionOutput]
```

**Example:**
```go
createNode := qdrant.CreateCollection(qdrant.CreateCollectionInput{
    Config: qdrant.CollectionConfig{
        Name:       "documents",
        VectorSize: 384,
        Distance:   "Cosine",
    },
})
```

### DeleteCollection

Deletes a collection.

**Input:**
```go
type DeleteCollectionInput struct {
    Name string `json:"name"`
}
```

**Output:**
```go
type DeleteCollectionOutput struct {
    Status string `json:"status"`
}
```

**Node Factory:**
```go
func DeleteCollection(input DeleteCollectionInput) *core.Node[DeleteCollectionInput, DeleteCollectionOutput]
```

### CollectionInfo

Gets collection information.

**Input:**
```go
type CollectionInfoInput struct {
    Name string `json:"name"`
}
```

**Output:**
```go
type CollectionInfoOutput struct {
    Status       string `json:"status"`
    VectorsCount int64  `json:"vectors_count"`
    PointsCount  int64  `json:"points_count"`
    Config       CollectionConfig `json:"config"`
}
```

**Node Factory:**
```go
func CollectionInfo(input CollectionInfoInput) *core.Node[CollectionInfoInput, CollectionInfoOutput]
```

## Usage Patterns

### Basic Semantic Search

```go
flow := core.NewFlow("semantic-search").
    TriggeredBy(core.Manual("api")).
    Then(ollama.Embed(ollama.EmbedInput{
        Model: "nomic-embed-text",
        Input: core.Output("input.query"),
    }).As("embedding")).
    Then(qdrant.Search(qdrant.SearchInput{
        Collection:  "documents",
        Vector:      core.Output("embedding.Embeddings[0]"),
        Limit:       10,
        WithPayload: true,
    }).As("results")).
    Build()
```

### Embedding Pipeline with Qdrant Storage

```go
flow := core.NewFlow("embedding-pipeline").
    TriggeredBy(core.Schedule("0 2 * * *")).
    Then(fetchDocumentsNode.As("docs")).
    Then(ollama.EmbedBatch(ollama.EmbedBatchInput{
        Model:     "nomic-embed-text",
        Texts:     core.Output("docs.texts"),
        BatchSize: 32,
    }).As("embeddings")).
    Then(preparePointsNode.As("points")).
    Then(qdrant.UpsertBatch(qdrant.UpsertBatchInput{
        Collection: "documents",
        Points:     core.Output("points.data"),
        BatchSize:  100,
        Wait:       true,
    })).
    Build()
```

### Filtered Search

```go
searchNode := qdrant.Search(qdrant.SearchInput{
    Collection: "products",
    Vector:     queryVector,
    Limit:      20,
    Filter: &qdrant.Filter{
        Must: []qdrant.Condition{
            {Field: "category", Match: qdrant.Match{Value: "electronics"}},
            {Field: "in_stock", Match: qdrant.Match{Value: true}},
            {Field: "price", Match: qdrant.Match{Range: &qdrant.Range{
                GTE: ptr(10.0),
                LTE: ptr(100.0),
            }}},
        },
    },
    WithPayload: true,
})
```

### Collection Setup Flow

```go
flow := core.NewFlow("setup-collection").
    TriggeredBy(core.Manual("setup")).
    Then(qdrant.CreateCollection(qdrant.CreateCollectionInput{
        Config: qdrant.CollectionConfig{
            Name:       "documents",
            VectorSize: 384,
            Distance:   "Cosine",
        },
    })).
    Build()
```

### Scroll Through All Points

```go
flow := core.NewFlow("export-collection").
    TriggeredBy(core.Manual("export")).
    Then(qdrant.Scroll(qdrant.ScrollInput{
        Collection:  "documents",
        Limit:       100,
        WithPayload: true,
    }).As("page")).
    While(func(s *core.FlowState) bool {
        page := core.Get[qdrant.ScrollOutput](s, "page")
        return page.NextOffset != ""
    }).
        Then(exportPageNode).
        Then(nextScrollNode).
    EndWhile().
    Build()
```

## Complete Example

```go
package main

import (
    "os"
    "time"

    "github.com/resolute/resolute/core"
    "github.com/resolute/resolute/providers/ollama"
    "github.com/resolute/resolute/providers/qdrant"
)

func main() {
    // Configure providers
    ollamaProvider := ollama.NewProvider(ollama.OllamaConfig{
        Host:    "http://localhost:11434",
        Timeout: 10 * time.Minute,
    })

    qdrantProvider := qdrant.NewProvider(qdrant.QdrantConfig{
        Host:   os.Getenv("QDRANT_HOST"),
        APIKey: os.Getenv("QDRANT_API_KEY"),
    })

    // Build RAG query flow
    flow := core.NewFlow("rag-query").
        TriggeredBy(core.Manual("query")).
        // Embed the query
        Then(ollama.Embed(ollama.EmbedInput{
            Model: "nomic-embed-text",
            Input: core.Output("input.query"),
        }).As("query-embedding")).
        // Search for relevant documents
        Then(qdrant.Search(qdrant.SearchInput{
            Collection:     "knowledge-base",
            Vector:         core.Output("query-embedding.Embeddings[0]"),
            Limit:          5,
            WithPayload:    true,
            ScoreThreshold: 0.7,
        }).As("context")).
        // Generate response
        Then(ollama.Chat(ollama.ChatInput{
            Model: "llama3.2",
            Messages: []ollama.Message{
                {Role: "system", Content: "Answer questions based on the provided context."},
                {Role: "user", Content: core.Output("context.formatted_query")},
            },
        }).As("response")).
        Build()

    // Run worker
    err := core.NewWorker().
        WithConfig(core.WorkerConfig{
            TaskQueue: "rag-queries",
        }).
        WithFlow(flow).
        WithProviders(ollamaProvider, qdrantProvider).
        Run()

    if err != nil {
        panic(err)
    }
}
```

## See Also

- **[Ollama Provider](/docs/reference/providers/ollama/)** - Embedding generation
- **[Embedding Pipeline Example](/docs/examples/embedding-pipeline/)** - Complete pipeline
- **[Data References](/docs/guides/advanced-patterns/data-references/)** - Large vector handling
