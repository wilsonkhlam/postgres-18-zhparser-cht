# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Custom PostgreSQL 18 Docker image with Chinese full-text search support via zhparser, vector similarity search via pgvector, and fuzzy matching via pg_trgm. Pre-configured for Traditional Chinese (Cantonese/HK/TW).

## Quick Start

```bash
# Build the image
docker build -t postgres-18-zhparser-cht:latest .

# Run a container
docker run -d \
  --name postgres-zhparser \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_PASSWORD=postgres \
  -e POSTGRES_DB=mydb \
  -p 5432:5432 \
  postgres-18-zhparser-cht:latest

# Run tests
./test.sh
```

## Project Structure

```
.
├── Dockerfile                              # Multi-stage build for PostgreSQL 18 + extensions
├── docker-entrypoint-initdb.d-zhparser.sh  # Auto-init zhparser on first database
├── configure-zhparser-custom-dict.sh       # Configure custom dictionary path
├── test.sh                                 # Test suite for validation
├── README.md                               # User documentation
└── CLAUDE.md                               # This file
```

## Components

| Component | Version | Purpose |
|-----------|---------|---------|
| PostgreSQL | 18.x | Database server |
| zhparser | master | Chinese word segmentation with SCWS |
| SCWS | 1.2.3 | Simple Chinese Word Segmentation library |
| pgvector | master | Vector similarity search |
| pg_trgm | REL_18_2 | Trigram fuzzy matching |

## Dockerfile Notes

- Multi-stage build: builder stage compiles extensions, final stage copies only runtime files
- Multi-arch: supports both amd64 and arm64 (Apple Silicon)
- Traditional Chinese dictionary downloaded from xunsearch.com

## Chinese Full-Text Search

The image auto-initializes the `chinese_zh` text search configuration for the first database created:

```sql
-- Basic search
SELECT * FROM articles
WHERE to_tsvector('chinese_zh', content) @@ to_tsquery('chinese_zh', '人工智能');

-- With GIN index
CREATE INDEX idx_search ON articles
USING GIN (to_tsvector('chinese_zh', title || ' ' || content));
```

## Custom Dictionary

Add domain-specific words for better segmentation:

```sql
INSERT INTO zhparser.zhprs_custom_word (word) VALUES ('中美關係'), ('深度學習');
SELECT sync_zhprs_custom_word();
```

Note: The sync function requires write permission to `/usr/local/share/postgresql/tsearch_data/zh_custom.txt`.

## Testing

The test script (`test.sh`) validates:
- Docker image build
- Extension installation (zhparser, pgvector, pg_trgm)
- Chinese text search configuration
- Word segmentation (Traditional and Simplified)
- Full-text search with GIN index
- Custom dictionary functionality
- Vector similarity search
- Trigram fuzzy search

```bash
# Run all tests
./test.sh

# Test specific image
./test.sh my-image:tag
```

## Updating PostgreSQL Version

When updating to a new PostgreSQL version:

1. Update `PG_CONTAINER_VERSION` arg in Dockerfile
2. Update pg_trgm git branch to matching version (e.g., `REL_19_0` for PostgreSQL 19)
3. Rebuild and test: `./test.sh`

## Common Issues

### pg_trgm build fails

Ensure the pg_trgm git branch matches the PostgreSQL version. Check available tags at https://github.com/postgres/postgres/tags

### Chinese segmentation incorrect

Add custom words to the dictionary for domain-specific terms that aren't segmented correctly.

### Container fails to start

Check logs: `docker logs postgres-zhparser`
