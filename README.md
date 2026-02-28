# PostgreSQL 18 with zhparser (Traditional Chinese)

A custom PostgreSQL 18 Docker image with:

- **zhparser** - Chinese full-text search with SCWS segmentation
- **Traditional Chinese dictionary** - Pre-configured for Traditional Chinese (Cantonese/HK/TW)
- **pgvector** - Vector similarity search for AI/ML applications
- **pg_trgm** - Trigram extension for fuzzy text matching

Multi-arch support for **amd64** and **arm64** (Apple Silicon).

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

# Connect and verify
docker exec -it postgres-zhparser psql -U postgres -d mydb -c "SELECT * FROM pg_extension WHERE extname IN ('zhparser', 'vector', 'pg_trgm');"
```

## Docker Compose

```yaml
services:
  postgres:
    image: postgres-18-zhparser-cht:latest
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: mydb
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data

volumes:
  postgres_data:
```

## Features

### Chinese Full-Text Search

The image automatically initializes the `chinese_zh` text search configuration for the first database created:

```sql
-- Search Chinese text
SELECT * FROM articles
WHERE to_tsvector('chinese_zh', content) @@ to_tsquery('chinese_zh', '人工智能');

-- Create a GIN index for Chinese search
CREATE INDEX idx_articles_search ON articles
USING GIN (to_tsvector('chinese_zh', title || ' ' || content));
```

### Custom Dictionary

Add custom words for better segmentation:

```sql
-- Add custom words
INSERT INTO zhparser.zhprs_custom_word (word) VALUES
    ('中美關係'),
    ('人工智能'),
    ('金融科技');

-- Sync the dictionary
SELECT sync_zhprs_custom_word();
```

### Vector Search (pgvector)

```sql
-- Create vector extension
CREATE EXTENSION vector;

-- Create table with embedding column
CREATE TABLE documents (
    id SERIAL PRIMARY KEY,
    content TEXT,
    embedding vector(1024)
);

-- Create index for similarity search
CREATE INDEX idx_documents_embedding ON documents
USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);
```

### Trigram Search (pg_trgm)

```sql
-- Create pg_trgm extension
CREATE EXTENSION pg_trgm;

-- Fuzzy search
SELECT * FROM users WHERE name % 'Jonh';

-- Create GIN index for fuzzy matching
CREATE INDEX idx_users_name ON users USING GIN (name gin_trgm_ops);
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `POSTGRES_USER` | - | Superuser name |
| `POSTGRES_PASSWORD` | - | Superuser password |
| `POSTGRES_DB` | - | Database to create |
| `PGDATA` | `/var/lib/postgresql/data` | Data directory |

## Building

```bash
# Standard build
docker build -t postgres-18-zhparser-cht:latest .

# Build with no cache (clean build)
docker build --no-cache -t postgres-18-zhparser-cht:latest .

# Build for specific platform
docker buildx build --platform linux/arm64 -t postgres-18-zhparser-cht:arm64 .
docker buildx build --platform linux/amd64 -t postgres-18-zhparser-cht:amd64 .
```

## Version Information

| Component | Version |
|-----------|---------|
| PostgreSQL | 18.x |
| zhparser | v2.3 |
| SCWS | 1.2.3 |
| pgvector | v0.8.2 |
| pg_trgm | REL_18_2 |
| Dictionary | Traditional Chinese (cht.utf8) |

All components use pinned versions for reproducible builds. Dictionary files are bundled in the repository for reliable builds without external network dependencies.

## License

- PostgreSQL: [PostgreSQL License](https://www.postgresql.org/about/licence/)
- zhparser: [BSD License](https://github.com/amutu/zhparser)
- SCWS: [Apache 2.0](https://github.com/hightman/scws)
- pgvector: [PostgreSQL License](https://github.com/pgvector/pgvector)
