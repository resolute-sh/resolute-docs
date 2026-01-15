---
title: "Prerequisites"
description: "Prerequisites - Resolute documentation"
weight: 10
toc: true
---


# Prerequisites

Before getting started with Resolute, ensure you have the following set up.

## Go

Resolute requires **Go 1.22** or later.

```bash
# Check your Go version
go version
```

If you need to install or update Go, visit [go.dev/dl](https://go.dev/dl/).

## Temporal

Resolute is built on Temporal, so you'll need a Temporal server running.

### Option 1: Temporal Dev Server (Recommended for Development)

The fastest way to get started:

```bash
# Install Temporal CLI
brew install temporal  # macOS
# or
curl -sSf https://temporal.download/cli.sh | sh

# Start development server
temporal server start-dev
```

This starts a local Temporal server at `localhost:7233` with the Web UI at `localhost:8233`.

### Option 2: Docker Compose

For a more complete local setup:

```bash
git clone https://github.com/temporalio/docker-compose.git
cd docker-compose
docker compose up
```

### Option 3: Temporal Cloud

For production or team development, use [Temporal Cloud](https://temporal.io/cloud).

## IDE Setup

### VS Code

Recommended extensions:
- **Go** - Official Go extension
- **Go Test Explorer** - For running tests

### GoLand

Go support is built-in. No additional configuration needed.

## Verify Your Setup

```bash
# Verify Go
go version
# Expected: go version go1.22.x ...

# Verify Temporal (if using CLI)
temporal server start-dev &
temporal workflow list
# Expected: Empty list (no workflows yet)
```

## Next Steps

Ready to install Resolute? Continue to [Installation](/docs/getting-started/installation/).
