# PostgreSQL 18 with zhparser (Chinese full-text search), pgvector, and pg_trgm
# Multi-arch build supporting both amd64 and arm64
# Uses Traditional Chinese dictionary by default

ARG PG_CONTAINER_VERSION=18
FROM docker.io/library/postgres:${PG_CONTAINER_VERSION}-alpine AS builder

# Install build dependencies
RUN set -ex \
    && apk --no-cache add \
        git \
        build-base \
        linux-headers \
        make \
        postgresql-dev \
        automake \
        libtool \
        autoconf \
        m4 \
        curl \
        cmake \
        clang19 \
        llvm19-dev

# Build SCWS (Simple Chinese Word Segmentation)
RUN set -ex \
    && git clone --branch 1.2.3 --single-branch --depth 1 https://github.com/hightman/scws.git \
    && cd scws \
    && touch README && aclocal && autoconf && autoheader && libtoolize && automake --add-missing \
    && ./configure \
    && make -j$(nproc) \
    && make install

# Build zhparser
RUN set -ex \
    && git clone --branch v2.3 --single-branch --depth 1 https://github.com/amutu/zhparser.git \
    && cd zhparser \
    && make -j$(nproc) \
    && make install

# Build pgvector (use version 0.8.2 for PostgreSQL 18 support)
RUN set -ex \
    && git clone --branch v0.8.2 --single-branch --depth 1 https://github.com/pgvector/pgvector.git \
    && cd pgvector \
    && make -j$(nproc) \
    && make install

# Build pg_trgm (trigram extension for fuzzy matching)
# Note: pg_trgm is part of contrib, but we build it explicitly
# Use matching PostgreSQL version (REL_18_2 for PostgreSQL 18.2)
RUN set -ex \
    && git clone --branch REL_18_2 --single-branch --depth 1 https://github.com/postgres/postgres.git \
    && cd postgres/contrib/pg_trgm \
    && make -j$(nproc) USE_PGXS=1 \
    && make install USE_PGXS=1

# Final stage
FROM docker.io/library/postgres:${PG_CONTAINER_VERSION}-alpine

# Set locale (C.UTF-8 supports UTF-8 for Traditional Chinese)
ENV LANG=C.UTF-8

# Install runtime dependencies
RUN set -ex \
    && apk --no-cache add \
        libstdc++ \
        icu-libs

# Create extension directories
RUN mkdir -p /usr/local/lib/postgresql/bitcode

# Copy SCWS libraries
COPY --from=builder /usr/local/lib/libscws.so.1 /usr/local/lib/
COPY --from=builder /usr/local/lib/libscws.so.1.1.0 /usr/local/lib/

# Copy zhparser extension
COPY --from=builder /usr/local/lib/postgresql/zhparser.so /usr/local/lib/postgresql/
COPY --from=builder /usr/local/share/postgresql/extension/zhparser.control /usr/local/share/postgresql/extension/
COPY --from=builder /usr/local/share/postgresql/extension/zhparser--1.0.sql /usr/local/share/postgresql/extension/
# Rename SQL file to match control file version (2.3)
RUN mv /usr/local/share/postgresql/extension/zhparser--1.0.sql /usr/local/share/postgresql/extension/zhparser--2.3.sql

# Copy pgvector extension
COPY --from=builder /usr/local/lib/postgresql/vector.so /usr/local/lib/postgresql/
COPY --from=builder /usr/local/share/postgresql/extension/vector.control /usr/local/share/postgresql/extension/
COPY --from=builder /usr/local/share/postgresql/extension/vector--*.sql /usr/local/share/postgresql/extension/

# Copy pg_trgm extension
COPY --from=builder /usr/local/lib/postgresql/pg_trgm.so /usr/local/lib/postgresql/
COPY --from=builder /usr/local/share/postgresql/extension/pg_trgm.control /usr/local/share/postgresql/extension/
COPY --from=builder /usr/local/share/postgresql/extension/pg_trgm--*.sql /usr/local/share/postgresql/extension/

# Copy SCWS dictionary files (includes Simplified Chinese by default)
COPY --from=builder /usr/local/share/postgresql/tsearch_data/ /usr/local/share/postgresql/tsearch_data/

# Fix permissions for custom dictionary sync
# sync_zhprs_custom_word() writes to /usr/local/share/postgresql/tsearch_data/zh_custom.txt
# PostgreSQL runs as postgres user, so change ownership accordingly
RUN chown -R postgres:postgres /usr/local/share/postgresql/tsearch_data/

# Copy pre-downloaded Traditional Chinese dictionary and rules
# Note: Replaces the default Simplified Chinese dictionary with Traditional Chinese
COPY scws-dict-cht-utf8.tar.bz2 rules.tgz /tmp/
RUN set -ex \
    && apk --no-cache add bzip2 \
    && cd /tmp \
    && tar xvjf scws-dict-cht-utf8.tar.bz2 \
    && tar xvzf rules.tgz \
    && rm -f /usr/local/share/postgresql/tsearch_data/dict.utf8.xdb \
    && mv dict_cht.utf8.xdb /usr/local/share/postgresql/tsearch_data/dict.utf8.xdb \
    && mv rules_cht.utf8.ini /usr/local/share/postgresql/tsearch_data/rules.utf8.ini \
    && rm -rf /tmp/scws-dict-cht-utf8.tar.bz2 /tmp/rules.tgz /tmp/*.ini /tmp/*.xdb

# Update library cache
RUN ldconfig /usr/local/lib || true

# Copy zhparser initialization and configuration scripts
COPY docker-entrypoint-initdb.d-zhparser.sh /docker-entrypoint-initdb.d/10-zhparser.sh
COPY configure-zhparser-custom-dict.sh /docker-entrypoint-initdb.d/20-configure-zhparser-custom-dict.sh

# Make scripts executable
RUN chmod +x /docker-entrypoint-initdb.d/10-zhparser.sh
RUN chmod +x /docker-entrypoint-initdb.d/20-configure-zhparser-custom-dict.sh
