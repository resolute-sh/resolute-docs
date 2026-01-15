.PHONY: dev build clean preview help

# Development server
dev:
	@echo "Starting documentation server..."
	npm run dev

# Production build
build:
	@echo "Building documentation..."
	npm run build

# Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	rm -rf public resources .hugo_build.lock

# Preview production build
preview:
	@echo "Previewing production build..."
	npm run preview

# Help
help:
	@echo "Available targets:"
	@echo "  make dev     - Start documentation dev server (localhost:1313)"
	@echo "  make build   - Build documentation for production"
	@echo "  make clean   - Clean build artifacts"
	@echo "  make preview - Preview production build"
	@echo "  make help    - Show this help"
