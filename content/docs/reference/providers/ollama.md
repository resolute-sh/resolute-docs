---
title: "Ollama Provider"
description: "Ollama Provider - Resolute documentation"
weight: 20
toc: true
---


# Ollama Provider

The Ollama provider integrates with local Ollama instances for running LLM inference, embeddings generation, and text completion.

## Installation

```bash
go get github.com/resolute/resolute/providers/ollama
```

## Configuration

### OllamaConfig

```go
type OllamaConfig struct {
    Host    string        // Ollama server host (default: "http://localhost:11434")
    Timeout time.Duration // Request timeout (default: 5m)
}
```

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `OLLAMA_HOST` | Ollama server URL | `http://localhost:11434` |
| `OLLAMA_TIMEOUT` | Request timeout | `5m` |

## Provider Constructor

### NewProvider

```go
func NewProvider(cfg OllamaConfig) *OllamaProvider
```

Creates a new Ollama provider.

**Parameters:**
- `cfg` - Ollama configuration

**Returns:** `*OllamaProvider` implementing `core.Provider`

**Example:**
```go
provider := ollama.NewProvider(ollama.OllamaConfig{
    Host:    "http://localhost:11434",
    Timeout: 10 * time.Minute,
})
```

## Types

### Message

```go
type Message struct {
    Role    string `json:"role"`    // "system", "user", or "assistant"
    Content string `json:"content"` // Message content
}
```

### GenerateOptions

```go
type GenerateOptions struct {
    Temperature   float64 `json:"temperature"`    // Sampling temperature (0.0-1.0)
    TopP          float64 `json:"top_p"`          // Nucleus sampling threshold
    TopK          int     `json:"top_k"`          // Top-k sampling
    NumPredict    int     `json:"num_predict"`    // Max tokens to generate
    Stop          []string `json:"stop"`          // Stop sequences
    RepeatPenalty float64 `json:"repeat_penalty"` // Repetition penalty
}
```

### EmbeddingOptions

```go
type EmbeddingOptions struct {
    Truncate bool `json:"truncate"` // Truncate input if too long
}
```

## Activities

### Generate

Generates text completion using a specified model.

**Input:**
```go
type GenerateInput struct {
    Model   string          `json:"model"`   // Model name (e.g., "llama3.2")
    Prompt  string          `json:"prompt"`  // Input prompt
    System  string          `json:"system"`  // System prompt
    Options GenerateOptions `json:"options"` // Generation options
    Stream  bool            `json:"stream"`  // Enable streaming (default: false)
}
```

**Output:**
```go
type GenerateOutput struct {
    Response         string `json:"response"`
    Model            string `json:"model"`
    TotalDuration    int64  `json:"total_duration"`
    LoadDuration     int64  `json:"load_duration"`
    PromptEvalCount  int    `json:"prompt_eval_count"`
    EvalCount        int    `json:"eval_count"`
}
```

**Node Factory:**
```go
func Generate(input GenerateInput) *core.Node[GenerateInput, GenerateOutput]
```

**Example:**
```go
generateNode := ollama.Generate(ollama.GenerateInput{
    Model:  "llama3.2",
    Prompt: "Explain the concept of workflows in software engineering",
    System: "You are a helpful technical writer.",
    Options: ollama.GenerateOptions{
        Temperature: 0.7,
        NumPredict:  500,
    },
})
```

### Chat

Conducts a multi-turn chat conversation.

**Input:**
```go
type ChatInput struct {
    Model    string          `json:"model"`
    Messages []Message       `json:"messages"`
    Options  GenerateOptions `json:"options"`
    Stream   bool            `json:"stream"`
}
```

**Output:**
```go
type ChatOutput struct {
    Message          Message `json:"message"`
    Model            string  `json:"model"`
    TotalDuration    int64   `json:"total_duration"`
    PromptEvalCount  int     `json:"prompt_eval_count"`
    EvalCount        int     `json:"eval_count"`
}
```

**Node Factory:**
```go
func Chat(input ChatInput) *core.Node[ChatInput, ChatOutput]
```

**Example:**
```go
chatNode := ollama.Chat(ollama.ChatInput{
    Model: "llama3.2",
    Messages: []ollama.Message{
        {Role: "system", Content: "You are a code reviewer."},
        {Role: "user", Content: "Review this function for bugs..."},
    },
    Options: ollama.GenerateOptions{
        Temperature: 0.3,
    },
})
```

### Embed

Generates embeddings for text input.

**Input:**
```go
type EmbedInput struct {
    Model   string           `json:"model"`   // Embedding model (e.g., "nomic-embed-text")
    Input   string           `json:"input"`   // Single text input
    Inputs  []string         `json:"inputs"`  // Multiple text inputs
    Options EmbeddingOptions `json:"options"` // Embedding options
}
```

**Output:**
```go
type EmbedOutput struct {
    Embeddings [][]float32 `json:"embeddings"`
    Model      string      `json:"model"`
}
```

**Node Factory:**
```go
func Embed(input EmbedInput) *core.Node[EmbedInput, EmbedOutput]
```

**Example:**
```go
// Single text
embedNode := ollama.Embed(ollama.EmbedInput{
    Model: "nomic-embed-text",
    Input: "What is workflow orchestration?",
})

// Batch embedding
embedNode := ollama.Embed(ollama.EmbedInput{
    Model: "nomic-embed-text",
    Inputs: []string{
        "First document text",
        "Second document text",
        "Third document text",
    },
})
```

### EmbedBatch

Generates embeddings for a batch of texts with automatic batching.

**Input:**
```go
type EmbedBatchInput struct {
    Model     string   `json:"model"`
    Texts     []string `json:"texts"`
    BatchSize int      `json:"batch_size"` // Texts per batch (default: 32)
}
```

**Output:**
```go
type EmbedBatchOutput struct {
    Embeddings [][]float32 `json:"embeddings"`
    Count      int         `json:"count"`
}
```

**Node Factory:**
```go
func EmbedBatch(input EmbedBatchInput) *core.Node[EmbedBatchInput, EmbedBatchOutput]
```

**Example:**
```go
embedBatchNode := ollama.EmbedBatch(ollama.EmbedBatchInput{
    Model:     "nomic-embed-text",
    Texts:     documentTexts, // Can be hundreds of texts
    BatchSize: 64,
})
```

### ListModels

Lists available models on the Ollama server.

**Input:**
```go
type ListModelsInput struct{}
```

**Output:**
```go
type ListModelsOutput struct {
    Models []ModelInfo `json:"models"`
}

type ModelInfo struct {
    Name       string    `json:"name"`
    ModifiedAt time.Time `json:"modified_at"`
    Size       int64     `json:"size"`
    Digest     string    `json:"digest"`
}
```

**Node Factory:**
```go
func ListModels(input ListModelsInput) *core.Node[ListModelsInput, ListModelsOutput]
```

### PullModel

Pulls (downloads) a model from the Ollama library.

**Input:**
```go
type PullModelInput struct {
    Name     string `json:"name"`     // Model name to pull
    Insecure bool   `json:"insecure"` // Allow insecure connections
}
```

**Output:**
```go
type PullModelOutput struct {
    Status string `json:"status"`
}
```

**Node Factory:**
```go
func PullModel(input PullModelInput) *core.Node[PullModelInput, PullModelOutput]
```

## Usage Patterns

### Text Generation Flow

```go
flow := core.NewFlow("text-generator").
    TriggeredBy(core.Manual("api")).
    Then(ollama.Generate(ollama.GenerateInput{
        Model:  "llama3.2",
        Prompt: core.Output("input.prompt"),
        Options: ollama.GenerateOptions{
            Temperature: 0.7,
            NumPredict:  1000,
        },
    }).As("generation")).
    Build()
```

### Embedding Pipeline

```go
flow := core.NewFlow("embedding-pipeline").
    TriggeredBy(core.Schedule("0 2 * * *")).
    Then(fetchDocumentsNode.As("docs")).
    Then(ollama.EmbedBatch(ollama.EmbedBatchInput{
        Model:     "nomic-embed-text",
        Texts:     core.Output("docs.texts"),
        BatchSize: 32,
    }).As("embeddings")).
    Then(storeVectorsNode).
    Build()
```

### RAG (Retrieval-Augmented Generation)

```go
flow := core.NewFlow("rag-query").
    TriggeredBy(core.Manual("api")).
    // Generate query embedding
    Then(ollama.Embed(ollama.EmbedInput{
        Model: "nomic-embed-text",
        Input: core.Output("input.query"),
    }).As("query-embedding")).
    // Search vector store
    Then(qdrant.Search(qdrant.SearchInput{
        Collection: "documents",
        Vector:     core.Output("query-embedding.Embeddings[0]"),
        Limit:      5,
    }).As("context")).
    // Generate response with context
    Then(ollama.Chat(ollama.ChatInput{
        Model: "llama3.2",
        Messages: []ollama.Message{
            {Role: "system", Content: "Answer based on the provided context."},
            {Role: "user", Content: core.Output("context.formatted_prompt")},
        },
    }).As("response")).
    Build()
```

### Model Preparation Flow

```go
flow := core.NewFlow("model-setup").
    TriggeredBy(core.Manual("setup")).
    Then(ollama.ListModels(ollama.ListModelsInput{}).As("available")).
    When(func(s *core.FlowState) bool {
        models := core.Get[ollama.ListModelsOutput](s, "available")
        for _, m := range models.Models {
            if m.Name == "llama3.2" {
                return false // Model already exists
            }
        }
        return true
    }).
        Then(ollama.PullModel(ollama.PullModelInput{
            Name: "llama3.2",
        })).
    EndWhen().
    Build()
```

## Complete Example

```go
package main

import (
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
        Host: "localhost:6334",
    })

    // Document processing node
    processDocsNode := core.NewNode("process-docs", ProcessDocsActivity, ProcessDocsInput{})

    // Build embedding pipeline
    flow := core.NewFlow("document-embedder").
        TriggeredBy(core.Schedule("0 3 * * *")).
        Then(fetchNewDocumentsNode.As("docs")).
        When(func(s *core.FlowState) bool {
            docs := core.Get[FetchDocsOutput](s, "docs")
            return len(docs.Documents) > 0
        }).
            Then(processDocsNode.As("processed")).
            Then(ollama.EmbedBatch(ollama.EmbedBatchInput{
                Model:     "nomic-embed-text",
                Texts:     core.Output("processed.texts"),
                BatchSize: 32,
            }).As("embeddings")).
            Then(qdrant.Upsert(qdrant.UpsertInput{
                Collection: "documents",
                Points:     core.Output("embeddings.points"),
            })).
        EndWhen().
        Build()

    // Run worker
    err := core.NewWorker().
        WithConfig(core.WorkerConfig{
            TaskQueue: "embeddings",
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

- **[Qdrant Provider](/docs/reference/providers/qdrant/)** - Vector storage
- **[Embedding Pipeline Example](/docs/examples/embedding-pipeline/)** - Complete example
- **[Rate Limiting](/docs/guides/advanced-patterns/rate-limiting/)** - Managing inference load
