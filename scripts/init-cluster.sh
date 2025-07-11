#!/bin/bash

echo "=========================================="
echo "Simple ClickHouse Cluster Test"
echo "=========================================="

# Simple query function
query() {
    local sql="$1"
    local port="${2:-9001}"
    curl -k -s -X POST "https://localhost:$port/" -d "$sql" 2>/dev/null
}

# Test basic connectivity
echo "1. Testing basic connectivity..."
for port in 9001 9011 9021; do
    node=$((port - 9000))
    result=$(query "SELECT 1" $port)
    if [ "$result" = "1" ]; then
        echo "✅ ClickHouse-$node (port $port): Working"
    else
        echo "❌ ClickHouse-$node (port $port): Failed"
    fi
done

echo ""

# Test cluster visibility
echo "2. Testing cluster configuration..."
cluster_result=$(query "SELECT count() FROM system.clusters WHERE cluster = 'local_cluster'")
if [ "$cluster_result" = "3" ]; then
    echo "✅ Cluster 'local_cluster': 3 nodes visible"
else
    echo "❌ Cluster 'local_cluster': Only $cluster_result nodes visible"
fi

echo ""

# Test Keeper connectivity
echo "3. Testing Keeper connectivity..."
keeper_result=$(query "SELECT count() FROM system.zookeeper WHERE path = '/'")
if [ ! -z "$keeper_result" ] && [ "$keeper_result" != "0" ]; then
    echo "✅ Keeper: Connected"
    keeper_working=true
else
    echo "❌ Keeper: Not accessible"
    keeper_working=false
fi

echo ""

# Test database creation
echo "4. Testing database creation..."
if [ "$keeper_working" = true ]; then
    db_result=$(query "CREATE DATABASE IF NOT EXISTS test_db ON CLUSTER local_cluster" 2>&1)
    if echo "$db_result" | grep -q "Exception\|Error"; then
        echo "❌ Cluster database creation: Failed"
        echo "   Error: $db_result"
        use_cluster=false
    else
        echo "✅ Cluster database creation: Working"
        use_cluster=true
    fi
else
    db_result=$(query "CREATE DATABASE IF NOT EXISTS test_db")
    if echo "$db_result" | grep -q "Exception\|Error"; then
        echo "❌ Local database creation: Failed"
    else
        echo "✅ Local database creation: Working"
    fi
    use_cluster=false
fi

echo ""

# Test table creation
echo "5. Testing table creation..."
if [ "$use_cluster" = true ]; then
    table_result=$(query "CREATE TABLE IF NOT EXISTS test_db.test_table ON CLUSTER local_cluster (id UInt32, name String) ENGINE = ReplicatedMergeTree('/clickhouse/tables/{shard}/test_table', '{replica}') ORDER BY id" 2>&1)
    if echo "$table_result" | grep -q "Exception\|Error"; then
        echo "❌ Replicated table creation: Failed"
        echo "   Error: $table_result"
    else
        echo "✅ Replicated table creation: Working"
    fi
else
    table_result=$(query "CREATE TABLE IF NOT EXISTS test_db.test_table (id UInt32, name String) ENGINE = MergeTree ORDER BY id")
    if echo "$table_result" | grep -q "Exception\|Error"; then
        echo "❌ Local table creation: Failed"
    else
        echo "✅ Local table creation: Working"
    fi
fi

echo ""

# Test data insertion and querying
echo "6. Testing data operations..."
insert_result=$(query "INSERT INTO test_db.test_table VALUES (1, 'test')")
if echo "$insert_result" | grep -q "Exception\|Error"; then
    echo "❌ Data insertion: Failed"
else
    select_result=$(query "SELECT count() FROM test_db.test_table")
    if [ "$select_result" = "1" ]; then
        echo "✅ Data operations: Working"
    else
        echo "❌ Data operations: Insert worked but select failed"
    fi
fi

echo ""

# Cleanup
echo "7. Cleaning up..."
if [ "$use_cluster" = true ]; then
    query "DROP DATABASE IF EXISTS test_db ON CLUSTER local_cluster" >/dev/null 2>&1
else
    query "DROP DATABASE IF EXISTS test_db" >/dev/null 2>&1
fi
echo "✅ Cleanup completed"

echo ""
echo "=========================================="
echo "Summary:"
if [ "$keeper_working" = true ] && [ "$use_cluster" = true ]; then
    echo "🎉 Cluster is fully functional!"
    echo "   ✓ Replicated tables supported"
    echo "   ✓ Distributed DDL working"
elif [ "$keeper_working" = false ]; then
    echo "⚠️  Keeper issues detected"
    echo "   ✓ Basic queries work"
    echo "   ✗ Use local tables only"
else
    echo "⚠️  Partial functionality"
    echo "   ✓ Basic connectivity working"
    echo "   ? Mixed results on cluster features"
fi
echo "=========================================="