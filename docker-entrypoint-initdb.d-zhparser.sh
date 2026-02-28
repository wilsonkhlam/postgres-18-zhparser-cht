#!/bin/bash
set -e

# This script initializes zhparser with Traditional Chinese support
# It runs automatically when PostgreSQL database is initialized

# Find the database name (first non-system database)
DB_NAME=$(psql -tXAc -U "$POSTGRES_USER" -d postgres -c "SELECT datname FROM pg_database WHERE datistemplate = false AND datname != 'postgres' ORDER BY datname LIMIT 1" | head -n 1)

if [ -z "$DB_NAME" ]; then
    echo "No database found, skipping zhparser initialization"
    exit 0
fi

echo "Initializing zhparser for database: $DB_NAME"

# Initialize zhparser extension and configuration
psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$DB_NAME" <<EOSQL
-- Create zhparser extension
CREATE EXTENSION IF NOT EXISTS zhparser;

-- Create text search configuration with zhparser
DROP TEXT SEARCH CONFIGURATION IF EXISTS chinese_zh CASCADE;
CREATE TEXT SEARCH CONFIGURATION chinese_zh (PARSER = zhparser);
COMMENT ON TEXT SEARCH CONFIGURATION chinese_zh IS 'Chinese text search configuration with zhparser';

-- Add mapping to simple dictionary
ALTER TEXT SEARCH CONFIGURATION chinese_zh ADD MAPPING FOR a,b,c,d,e,f,g,h,i,j,k,l,m,n,o,p,q,r,s,t,u,v,w,x,y,z WITH simple;

-- Create zhparser schema for custom dictionary
CREATE SCHEMA IF NOT EXISTS zhparser;

-- Create custom word table
CREATE TABLE IF NOT EXISTS zhparser.zhprs_custom_word (
    word TEXT PRIMARY KEY,
    tf DOUBLE PRECISION DEFAULT 1.0,
    idf DOUBLE PRECISION DEFAULT 1.0,
    attr CHAR(1) DEFAULT '@' CHECK (attr IN ('@', '!'))
);

-- Create sync function for custom dictionary
CREATE OR REPLACE FUNCTION sync_zhprs_custom_word()
RETURNS void
LANGUAGE plpgsql
AS \$function\$
declare
    data_dir text;
    dict_path text;
    time_tag_path text;
    query text;
    custom_dict_path text;
begin
    select setting from pg_settings where name='data_directory' into data_dir;

    -- Write to the base directory (for zhparser per-database)
    select data_dir || '/base' || '/zhprs_dict_' || current_database() || '.txt' into dict_path;
    select data_dir || '/base' || '/zhprs_dict_' || current_database() || '.tag' into time_tag_path;

    query = \$q\$copy (select word, tf, idf, attr from zhparser.zhprs_custom_word) to '\$q\$ || dict_path || \$q\$' encoding 'utf8' \$q\$;
    execute query;
    query = \$q\$copy (select now()) to '\$q\$  || time_tag_path || \$q\$'\$q\$;
    execute query;

    -- Also write to the global custom dictionary file for zhparser.extra_dicts
    -- This file is loaded if zhparser.extra_dicts is configured in postgresql.conf
    select '/usr/local/share/postgresql/tsearch_data/zh_custom.txt' into custom_dict_path;

    -- Build the custom dictionary content
    query := format(\$q\$COPY (SELECT word, tf, idf, attr FROM zhparser.zhprs_custom_word) TO PROGRAM %L with csv delimiter E'\t'\$q\$, format('cat > %s', custom_dict_path));
    execute query;
end;
\$function\$;

-- Grant necessary permissions
GRANT USAGE ON SCHEMA zhparser TO PUBLIC;
GRANT SELECT, INSERT, UPDATE, DELETE ON zhparser.zhprs_custom_word TO PUBLIC;
GRANT EXECUTE ON FUNCTION sync_zhprs_custom_word() TO PUBLIC;

EOSQL

echo "zhparser initialized successfully for database: $DB_NAME"
