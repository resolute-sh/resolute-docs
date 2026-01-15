---
title: "Confluence Provider"
description: "Confluence Provider - Resolute documentation"
weight: 40
toc: true
---


# Confluence Provider

The Confluence provider integrates with Atlassian Confluence for wiki content management, page operations, and space administration.

## Installation

```bash
go get github.com/resolute/resolute/providers/confluence
```

## Configuration

### ConfluenceConfig

```go
type ConfluenceConfig struct {
    BaseURL  string // Confluence instance URL
    Email    string // User email for authentication
    APIToken string // API token for authentication
}
```

### Environment Variables

| Variable | Description | Required |
|----------|-------------|----------|
| `CONFLUENCE_BASE_URL` | Confluence instance URL | Yes |
| `CONFLUENCE_EMAIL` | Authentication email | Yes |
| `CONFLUENCE_API_TOKEN` | API token | Yes |

## Provider Constructor

### NewProvider

```go
func NewProvider(cfg ConfluenceConfig) *ConfluenceProvider
```

Creates a new Confluence provider.

**Parameters:**
- `cfg` - Confluence configuration

**Returns:** `*ConfluenceProvider` implementing `core.Provider`

**Example:**
```go
provider := confluence.NewProvider(confluence.ConfluenceConfig{
    BaseURL:  os.Getenv("CONFLUENCE_BASE_URL"),
    Email:    os.Getenv("CONFLUENCE_EMAIL"),
    APIToken: os.Getenv("CONFLUENCE_API_TOKEN"),
})
```

## Types

### Page

```go
type Page struct {
    ID          string            `json:"id"`
    Title       string            `json:"title"`
    SpaceKey    string            `json:"space_key"`
    Body        string            `json:"body"`
    Version     int               `json:"version"`
    Status      string            `json:"status"`
    CreatedAt   time.Time         `json:"created_at"`
    UpdatedAt   time.Time         `json:"updated_at"`
    CreatedBy   string            `json:"created_by"`
    Labels      []string          `json:"labels"`
    Ancestors   []PageRef         `json:"ancestors"`
    Children    []PageRef         `json:"children"`
    Metadata    map[string]string `json:"metadata"`
}

type PageRef struct {
    ID    string `json:"id"`
    Title string `json:"title"`
}
```

### Space

```go
type Space struct {
    Key         string    `json:"key"`
    Name        string    `json:"name"`
    Description string    `json:"description"`
    Type        string    `json:"type"` // "global" or "personal"
    Status      string    `json:"status"`
    CreatedAt   time.Time `json:"created_at"`
}
```

### Attachment

```go
type Attachment struct {
    ID          string    `json:"id"`
    Title       string    `json:"title"`
    Filename    string    `json:"filename"`
    MediaType   string    `json:"media_type"`
    FileSize    int64     `json:"file_size"`
    DownloadURL string    `json:"download_url"`
    CreatedAt   time.Time `json:"created_at"`
}
```

### SearchResult

```go
type SearchResult struct {
    ID       string `json:"id"`
    Type     string `json:"type"` // "page", "blogpost", "attachment"
    Title    string `json:"title"`
    SpaceKey string `json:"space_key"`
    Excerpt  string `json:"excerpt"`
    URL      string `json:"url"`
}
```

## Activities

### GetPage

Retrieves a page by ID.

**Input:**
```go
type GetPageInput struct {
    ID         string   `json:"id"`
    Expand     []string `json:"expand"` // "body.storage", "version", "children", etc.
}
```

**Output:**
```go
type GetPageOutput struct {
    Page Page `json:"page"`
}
```

**Node Factory:**
```go
func GetPage(input GetPageInput) *core.Node[GetPageInput, GetPageOutput]
```

**Example:**
```go
getPageNode := confluence.GetPage(confluence.GetPageInput{
    ID:     "12345",
    Expand: []string{"body.storage", "version"},
})
```

### GetPageByTitle

Retrieves a page by title within a space.

**Input:**
```go
type GetPageByTitleInput struct {
    SpaceKey string   `json:"space_key"`
    Title    string   `json:"title"`
    Expand   []string `json:"expand"`
}
```

**Output:**
```go
type GetPageByTitleOutput struct {
    Page  Page `json:"page"`
    Found bool `json:"found"`
}
```

**Node Factory:**
```go
func GetPageByTitle(input GetPageByTitleInput) *core.Node[GetPageByTitleInput, GetPageByTitleOutput]
```

### FetchPages

Fetches pages from a space with optional filtering.

**Input:**
```go
type FetchPagesInput struct {
    SpaceKey   string    `json:"space_key"`
    Status     string    `json:"status"` // "current", "archived", "draft"
    Limit      int       `json:"limit"`
    Start      int       `json:"start"`
    Expand     []string  `json:"expand"`
    Cursor     string    `json:"cursor"` // For incremental sync
}
```

**Output:**
```go
type FetchPagesOutput struct {
    Pages      []Page `json:"pages"`
    Total      int    `json:"total"`
    HasMore    bool   `json:"has_more"`
    NextCursor string `json:"next_cursor"`
}
```

**Node Factory:**
```go
func FetchPages(input FetchPagesInput) *core.Node[FetchPagesInput, FetchPagesOutput]
```

**Example:**
```go
fetchNode := confluence.FetchPages(confluence.FetchPagesInput{
    SpaceKey: "DOCS",
    Limit:    50,
    Expand:   []string{"body.storage"},
    Cursor:   core.CursorFor("confluence"),
})
```

### CreatePage

Creates a new page.

**Input:**
```go
type CreatePageInput struct {
    SpaceKey   string   `json:"space_key"`
    Title      string   `json:"title"`
    Body       string   `json:"body"`        // Storage format (HTML/XHTML)
    ParentID   string   `json:"parent_id"`   // Optional parent page
    Labels     []string `json:"labels"`
}
```

**Output:**
```go
type CreatePageOutput struct {
    ID      string `json:"id"`
    Title   string `json:"title"`
    Version int    `json:"version"`
    URL     string `json:"url"`
}
```

**Node Factory:**
```go
func CreatePage(input CreatePageInput) *core.Node[CreatePageInput, CreatePageOutput]
```

**Example:**
```go
createNode := confluence.CreatePage(confluence.CreatePageInput{
    SpaceKey: "DOCS",
    Title:    "API Documentation",
    Body:     "<p>API documentation content...</p>",
    Labels:   []string{"api", "documentation"},
})
```

### UpdatePage

Updates an existing page.

**Input:**
```go
type UpdatePageInput struct {
    ID       string `json:"id"`
    Title    string `json:"title"`
    Body     string `json:"body"`
    Version  int    `json:"version"` // Current version (for conflict detection)
}
```

**Output:**
```go
type UpdatePageOutput struct {
    ID      string `json:"id"`
    Version int    `json:"version"`
    Updated bool   `json:"updated"`
}
```

**Node Factory:**
```go
func UpdatePage(input UpdatePageInput) *core.Node[UpdatePageInput, UpdatePageOutput]
```

### DeletePage

Deletes a page.

**Input:**
```go
type DeletePageInput struct {
    ID string `json:"id"`
}
```

**Output:**
```go
type DeletePageOutput struct {
    Deleted bool `json:"deleted"`
}
```

**Node Factory:**
```go
func DeletePage(input DeletePageInput) *core.Node[DeletePageInput, DeletePageOutput]
```

### Search

Searches Confluence using CQL (Confluence Query Language).

**Input:**
```go
type SearchInput struct {
    CQL        string   `json:"cql"`
    Limit      int      `json:"limit"`
    Start      int      `json:"start"`
    Expand     []string `json:"expand"`
}
```

**Output:**
```go
type SearchOutput struct {
    Results []SearchResult `json:"results"`
    Total   int            `json:"total"`
    HasMore bool           `json:"has_more"`
}
```

**Node Factory:**
```go
func Search(input SearchInput) *core.Node[SearchInput, SearchOutput]
```

**Example:**
```go
searchNode := confluence.Search(confluence.SearchInput{
    CQL:   "space = DOCS AND type = page AND text ~ 'authentication'",
    Limit: 25,
})
```

### GetAttachments

Gets attachments for a page.

**Input:**
```go
type GetAttachmentsInput struct {
    PageID string `json:"page_id"`
    Limit  int    `json:"limit"`
    Start  int    `json:"start"`
}
```

**Output:**
```go
type GetAttachmentsOutput struct {
    Attachments []Attachment `json:"attachments"`
    Total       int          `json:"total"`
}
```

**Node Factory:**
```go
func GetAttachments(input GetAttachmentsInput) *core.Node[GetAttachmentsInput, GetAttachmentsOutput]
```

### AddLabels

Adds labels to a page.

**Input:**
```go
type AddLabelsInput struct {
    PageID string   `json:"page_id"`
    Labels []string `json:"labels"`
}
```

**Output:**
```go
type AddLabelsOutput struct {
    Labels []string `json:"labels"`
}
```

**Node Factory:**
```go
func AddLabels(input AddLabelsInput) *core.Node[AddLabelsInput, AddLabelsOutput]
```

### GetSpace

Gets space information.

**Input:**
```go
type GetSpaceInput struct {
    Key    string   `json:"key"`
    Expand []string `json:"expand"`
}
```

**Output:**
```go
type GetSpaceOutput struct {
    Space Space `json:"space"`
}
```

**Node Factory:**
```go
func GetSpace(input GetSpaceInput) *core.Node[GetSpaceInput, GetSpaceOutput]
```

## Usage Patterns

### Documentation Sync Flow

```go
flow := core.NewFlow("doc-sync").
    TriggeredBy(core.Schedule("0 */4 * * *")).
    Then(confluence.FetchPages(confluence.FetchPagesInput{
        SpaceKey: "DOCS",
        Cursor:   core.CursorFor("confluence"),
        Limit:    50,
        Expand:   []string{"body.storage"},
    }).As("pages")).
    When(func(s *core.FlowState) bool {
        pages := core.Get[confluence.FetchPagesOutput](s, "pages")
        return len(pages.Pages) > 0
    }).
        Then(processDocsNode).
        Then(updateSearchIndexNode).
    EndWhen().
    Build()
```

### Page Creation with Error Handling

```go
createPage := confluence.CreatePage(confluence.CreatePageInput{
    SpaceKey: "DOCS",
    Title:    core.Output("input.title"),
    Body:     core.Output("input.content"),
}).OnError(confluence.DeletePage(confluence.DeletePageInput{
    ID: core.Output("create-page.ID"),
}))

flow := core.NewFlow("create-documentation").
    TriggeredBy(core.Manual("api")).
    Then(createPage.As("create-page")).
    Then(addMetadataNode).
    Build()
```

### Knowledge Base Search

```go
flow := core.NewFlow("kb-search").
    TriggeredBy(core.Manual("search")).
    Then(confluence.Search(confluence.SearchInput{
        CQL:   core.Output("input.cql_query"),
        Limit: 20,
    }).As("results")).
    Then(rankResultsNode).
    Build()
```

### Content Migration Flow

```go
flow := core.NewFlow("content-migration").
    TriggeredBy(core.Manual("migrate")).
    Then(confluence.FetchPages(confluence.FetchPagesInput{
        SpaceKey: "OLD-DOCS",
        Limit:    100,
    }).As("source-pages")).
    ForEach(core.Output("source-pages.Pages")).
        Then(transformContentNode).
        Then(confluence.CreatePage(confluence.CreatePageInput{
            SpaceKey: "NEW-DOCS",
            Title:    core.Output("current.Title"),
            Body:     core.Output("transformed.Body"),
        })).
    EndForEach().
    Build()
```

## Complete Example

```go
package main

import (
    "os"
    "time"

    "github.com/resolute/resolute/core"
    "github.com/resolute/resolute/providers/confluence"
    "github.com/resolute/resolute/providers/ollama"
    "github.com/resolute/resolute/providers/qdrant"
)

func main() {
    // Configure providers
    confluenceProvider := confluence.NewProvider(confluence.ConfluenceConfig{
        BaseURL:  os.Getenv("CONFLUENCE_BASE_URL"),
        Email:    os.Getenv("CONFLUENCE_EMAIL"),
        APIToken: os.Getenv("CONFLUENCE_API_TOKEN"),
    }).WithRateLimit(100, time.Minute)

    ollamaProvider := ollama.NewProvider(ollama.OllamaConfig{
        Host: "http://localhost:11434",
    })

    qdrantProvider := qdrant.NewProvider(qdrant.QdrantConfig{
        Host: os.Getenv("QDRANT_HOST"),
    })

    // Build documentation indexing flow
    flow := core.NewFlow("confluence-indexer").
        TriggeredBy(core.Schedule("0 2 * * *")).
        Then(confluence.FetchPages(confluence.FetchPagesInput{
            SpaceKey: "DOCS",
            Cursor:   core.CursorFor("confluence-docs"),
            Limit:    50,
            Expand:   []string{"body.storage"},
        }).As("pages")).
        When(func(s *core.FlowState) bool {
            pages := core.Get[confluence.FetchPagesOutput](s, "pages")
            return len(pages.Pages) > 0
        }).
            Then(extractTextNode.As("texts")).
            Then(ollama.EmbedBatch(ollama.EmbedBatchInput{
                Model:     "nomic-embed-text",
                Texts:     core.Output("texts.content"),
                BatchSize: 32,
            }).As("embeddings")).
            Then(preparePointsNode.As("points")).
            Then(qdrant.UpsertBatch(qdrant.UpsertBatchInput{
                Collection: "confluence-docs",
                Points:     core.Output("points.data"),
                BatchSize:  100,
            })).
        EndWhen().
        Build()

    // Run worker
    err := core.NewWorker().
        WithConfig(core.WorkerConfig{
            TaskQueue: "confluence-indexer",
        }).
        WithFlow(flow).
        WithProviders(confluenceProvider, ollamaProvider, qdrantProvider).
        Run()

    if err != nil {
        panic(err)
    }
}
```

## See Also

- **[Jira Provider](/docs/reference/providers/jira/)** - Issue tracking integration
- **[Embedding Pipeline Example](/docs/examples/embedding-pipeline/)** - Document embedding
- **[Pagination](/docs/guides/advanced-patterns/pagination/)** - Handling large datasets
