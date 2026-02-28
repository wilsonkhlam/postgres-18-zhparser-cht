#!/bin/bash
# Test script for PostgreSQL 18 with zhparser (Traditional Chinese)
# Usage: ./test.sh [image_name]

set -e

# Configuration
IMAGE_NAME="${1:-postgres-18-zhparser-cht:latest}"
CONTAINER_NAME="postgres-zhparser-test"
POSTGRES_USER="testuser"
POSTGRES_PASSWORD="testpass"
POSTGRES_DB="testdb"
HOST_PORT="5433"
TIMEOUT=60

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0

# Helper functions
log_info() {
    echo -e "${YELLOW}[INFO]${NC} $1"
}

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((TESTS_PASSED++))
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((TESTS_FAILED++))
}

run_sql() {
    docker exec -i "$CONTAINER_NAME" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tAc "$1"
}

run_sql_file() {
    docker exec -i "$CONTAINER_NAME" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f "$1"
}

cleanup() {
    log_info "Cleaning up..."
    docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
}

# Register cleanup on exit
trap cleanup EXIT

# ============================================
# Test 1: Build the image
# ============================================
test_build() {
    log_info "Test 1: Building Docker image..."

    if docker build -t "$IMAGE_NAME" . 2>&1 | tail -5; then
        log_pass "Docker image built successfully"
    else
        log_fail "Failed to build Docker image"
        exit 1
    fi
}

# ============================================
# Test 2: Start container
# ============================================
test_start_container() {
    log_info "Test 2: Starting container..."

    cleanup

    docker run -d \
        --name "$CONTAINER_NAME" \
        -e POSTGRES_USER="$POSTGRES_USER" \
        -e POSTGRES_PASSWORD="$POSTGRES_PASSWORD" \
        -e POSTGRES_DB="$POSTGRES_DB" \
        -p "$HOST_PORT:5432" \
        "$IMAGE_NAME" > /dev/null

    # Wait for PostgreSQL to be ready
    log_info "Waiting for PostgreSQL to be ready..."
    local count=0
    while ! docker exec "$CONTAINER_NAME" pg_isready -U "$POSTGRES_USER" -q; do
        if [ $count -ge $TIMEOUT ]; then
            log_fail "PostgreSQL did not become ready within ${TIMEOUT}s"
            exit 1
        fi
        sleep 1
        ((count++))
    done

    # Additional wait for initialization scripts to complete
    sleep 3

    log_pass "Container started and PostgreSQL is ready"
}

# ============================================
# Test 3: Verify extensions are installed
# ============================================
test_extensions() {
    log_info "Test 3: Verifying extensions..."

    # Test zhparser
    local zhparser=$(run_sql "SELECT extname FROM pg_extension WHERE extname = 'zhparser';")
    if [ "$zhparser" = "zhparser" ]; then
        log_pass "zhparser extension is installed"
    else
        log_fail "zhparser extension is NOT installed"
    fi

    # Test pgvector
    local vector=$(run_sql "SELECT extname FROM pg_extension WHERE extname = 'vector';")
    if [ "$vector" = "vector" ]; then
        log_pass "pgvector extension is installed"
    else
        log_fail "pgvector extension is NOT installed"
    fi

    # Test pg_trgm
    local pgtrgm=$(run_sql "SELECT extname FROM pg_extension WHERE extname = 'pg_trgm';")
    if [ "$pgtrgm" = "pg_trgm" ]; then
        log_pass "pg_trgm extension is installed"
    else
        log_fail "pg_trgm extension is NOT installed"
    fi
}

# ============================================
# Test 4: Verify chinese_zh text search config
# ============================================
test_chinese_config() {
    log_info "Test 4: Verifying Chinese text search configuration..."

    local config=$(run_sql "SELECT cfgname FROM pg_ts_config WHERE cfgname = 'chinese_zh';")
    if [ "$config" = "chinese_zh" ]; then
        log_pass "chinese_zh text search configuration exists"
    else
        log_fail "chinese_zh text search configuration does NOT exist"
    fi
}

# ============================================
# Test 5: Chinese word segmentation
# ============================================
test_segmentation() {
    log_info "Test 5: Testing Chinese word segmentation..."

    # Test basic segmentation
    local tokens=$(run_sql "SELECT to_tsvector('chinese_zh', '人工智能正在改變世界');")

    if echo "$tokens" | grep -q "人工智能"; then
        log_pass "Chinese word segmentation works: '人工智能' recognized"
    else
        log_fail "Chinese word segmentation failed for '人工智能'"
    fi

    # Test Traditional Chinese
    local tokens2=$(run_sql "SELECT to_tsvector('chinese_zh', '香港是國際金融中心');")

    if echo "$tokens2" | grep -q "香港" && echo "$tokens2" | grep -q "金融"; then
        log_pass "Traditional Chinese segmentation works: '香港', '金融' recognized"
    else
        log_fail "Traditional Chinese segmentation failed"
    fi
}

# ============================================
# Test 6: Chinese full-text search
# ============================================
test_fulltext_search() {
    log_info "Test 6: Testing Chinese full-text search..."

    # Create test table
    run_sql "CREATE TABLE test_articles (id SERIAL PRIMARY KEY, title TEXT, content TEXT);"

    # Insert Chinese test data
    run_sql "INSERT INTO test_articles (title, content) VALUES
        ('人工智能發展', '人工智能技術正在快速發展，機器學習和深度學習是核心技術'),
        ('金融科技', '金融科技改變了傳統銀行業務，數字貨幣和區塊鏈技術受到關注'),
        ('氣候變化', '全球氣候變化對環境造成重大影響，需要各國共同努力');"

    # Create GIN index
    run_sql "CREATE INDEX idx_test_search ON test_articles USING GIN (to_tsvector('chinese_zh', title || ' ' || content));"

    # Test search for "人工智能"
    local result=$(run_sql "SELECT title FROM test_articles WHERE to_tsvector('chinese_zh', title || ' ' || content) @@ to_tsquery('chinese_zh', '人工智能');")

    if [ "$result" = "人工智能發展" ]; then
        log_pass "Full-text search for '人工智能' found correct article"
    else
        log_fail "Full-text search failed for '人工智能'"
    fi

    # Test search for "金融"
    local result2=$(run_sql "SELECT title FROM test_articles WHERE to_tsvector('chinese_zh', title || ' ' || content) @@ to_tsquery('chinese_zh', '金融');")

    if [ "$result2" = "金融科技" ]; then
        log_pass "Full-text search for '金融' found correct article"
    else
        log_fail "Full-text search failed for '金融'"
    fi

    # Cleanup
    run_sql "DROP TABLE test_articles;"
}

# ============================================
# Test 7: Custom dictionary
# ============================================
test_custom_dictionary() {
    log_info "Test 7: Testing custom dictionary..."

    # Check custom word table exists
    local table=$(run_sql "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_schema = 'zhparser' AND table_name = 'zhprs_custom_word');")

    if [ "$table" = "t" ]; then
        log_pass "Custom word table exists"
    else
        log_fail "Custom word table does NOT exist"
    fi

    # Add custom words
    run_sql "INSERT INTO zhparser.zhprs_custom_word (word) VALUES ('中美關係'), ('深度學習') ON CONFLICT DO NOTHING;"

    # Sync dictionary
    run_sql "SELECT sync_zhprs_custom_word();"

    # Verify sync function works
    local sync_result=$?
    if [ $sync_result -eq 0 ]; then
        log_pass "Custom dictionary sync function works"
    else
        log_fail "Custom dictionary sync function failed"
    fi

    # Verify words were added
    local count=$(run_sql "SELECT COUNT(*) FROM zhparser.zhprs_custom_word WHERE word IN ('中美關係', '深度學習');")
    if [ "$count" = "2" ]; then
        log_pass "Custom words added successfully"
    else
        log_fail "Failed to add custom words"
    fi
}

# ============================================
# Test 8: Vector similarity (pgvector)
# ============================================
test_vector_search() {
    log_info "Test 8: Testing vector similarity search..."

    # Create table with vector column
    run_sql "CREATE TABLE test_vectors (id SERIAL PRIMARY KEY, content TEXT, embedding vector(3));"

    # Insert test data
    run_sql "INSERT INTO test_vectors (content, embedding) VALUES
        ('文檔A', '[1, 0, 0]'),
        ('文檔B', '[0.9, 0.1, 0]'),
        ('文檔C', '[0, 1, 0]');"

    # Test similarity search
    local result=$(run_sql "SELECT content FROM test_vectors ORDER BY embedding <=> '[1, 0, 0]'::vector LIMIT 1;")

    if [ "$result" = "文檔A" ]; then
        log_pass "Vector similarity search works"
    else
        log_fail "Vector similarity search failed"
    fi

    # Cleanup
    run_sql "DROP TABLE test_vectors;"
}

# ============================================
# Test 9: Trigram search (pg_trgm)
# ============================================
test_trigram_search() {
    log_info "Test 9: Testing trigram fuzzy search..."

    # Create test table
    run_sql "CREATE TABLE test_names (id SERIAL PRIMARY KEY, name TEXT);"

    # Insert test data
    run_sql "INSERT INTO test_names (name) VALUES ('張小明'), ('李小華'), '王美麗', ('陳大文');"

    # Create trigram index
    run_sql "CREATE INDEX idx_test_names ON test_names USING GIN (name gin_trgm_ops);"

    # Test similarity search
    local result=$(run_sql "SELECT name FROM test_names WHERE name % '張小明' ORDER BY similarity(name, '張小明') DESC LIMIT 1;")

    if [ "$result" = "張小明" ]; then
        log_pass "Trigram similarity search works"
    else
        log_fail "Trigram similarity search failed"
    fi

    # Cleanup
    run_sql "DROP TABLE test_names;"
}

# ============================================
# Test 10: Complex Chinese text
# ============================================
test_complex_chinese() {
    log_info "Test 10: Testing complex Chinese text handling..."

    # Test with mixed Traditional/Simplified and punctuation
    local complex_text='這是一個關於「人工智能」的測試文章。文章包含繁體字和简体字，還有標點符號！'

    local tokens=$(run_sql "SELECT to_tsvector('chinese_zh', '$complex_text');")

    # Check that key terms are extracted
    if echo "$tokens" | grep -q "人工智能"; then
        log_pass "Complex text: '人工智能' extracted"
    else
        log_fail "Complex text: failed to extract '人工智能'"
    fi

    if echo "$tokens" | grep -q "測試"; then
        log_pass "Complex text: '測試' extracted"
    else
        log_fail "Complex text: failed to extract '測試'"
    fi
}

# ============================================
# Main test runner
# ============================================
main() {
    echo "============================================"
    echo "PostgreSQL 18 zhparser Test Suite"
    echo "Image: $IMAGE_NAME"
    echo "============================================"
    echo ""

    test_build
    test_start_container
    test_extensions
    test_chinese_config
    test_segmentation
    test_fulltext_search
    test_custom_dictionary
    test_vector_search
    test_trigram_search
    test_complex_chinese

    echo ""
    echo "============================================"
    echo "Test Results"
    echo "============================================"
    echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Failed: ${RED}$TESTS_FAILED${NC}"
    echo ""

    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "${GREEN}All tests passed!${NC}"
        exit 0
    else
        echo -e "${RED}Some tests failed!${NC}"
        exit 1
    fi
}

main "$@"
