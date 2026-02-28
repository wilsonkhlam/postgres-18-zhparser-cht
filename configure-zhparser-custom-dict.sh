#!/bin/bash
set -e

# This script configures zhparser to use custom dictionaries
# It runs automatically during Docker container initialization

# Find postgresql.conf
PGCONF=$(find /var/lib/postgresql -name postgresql.conf 2>/dev/null | head -1)

if [ -z "$PGCONF" ]; then
    echo "Warning: postgresql.conf not found"
    exit 0
fi

# Check if zhparser.extra_dicts is already configured
if grep -q "^zhparser.extra_dicts" "$PGCONF"; then
    echo "zhparser.extra_dicts already configured"
    exit 0
fi

# Add zhparser.extra_dicts configuration
echo ""
echo "# zhparser custom dictionary configuration" >> "$PGCONF"
echo "zhparser.extra_dicts = '/usr/local/share/postgresql/tsearch_data/zh_custom.txt'" >> "$PGCONF"

echo "zhparser.extra_dicts configured in $PGCONF"

# Reload PostgreSQL configuration if server is running
if pg_isready -q; then
    echo "Reloading PostgreSQL configuration..."
    psql -U "$POSTGRES_USER" -d postgres -c "SELECT pg_reload_conf();" > /dev/null 2>&1 || true
fi

echo "zhparser custom dictionary configuration complete"
