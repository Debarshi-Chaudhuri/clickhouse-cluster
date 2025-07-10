#!/bin/bash
set -e

# ClickHouse Cluster Initialization Script
echo "=========================================="
echo "ClickHouse Cluster Initialization"
echo "=========================================="

# =============================================================================
# 1. WAIT FOR CLUSTER TO BE READY
# =============================================================================
echo "⏳ Waiting for cluster to be fully ready..."

# Function to execute ClickHouse query
execute_query() {
    local query="$1"
    curl -k -s "https://localhost:9001/?query=$query"
}

# Wait for ClickHouse to respond
max_attempts=30
attempt=1

while [ $attempt -le $max_attempts ]; do
    if execute_query "SELECT%201" >/dev/null 2>&1; then
        echo "✅ ClickHouse is responding"
        break
    fi
    
    echo "   Attempt $attempt/$max_attempts - waiting for ClickHouse..."
    sleep 5
    attempt=$((attempt + 1))
done

if [ $attempt -gt $max_attempts ]; then
    echo "❌ ClickHouse failed to become ready"
    exit 1
fi

# Wait a bit more for cluster coordination to stabilize
echo "   Waiting for cluster coordination to stabilize..."
sleep 15

echo ""

# =============================================================================
# 2. VERIFY CLUSTER CONFIGURATION
# =============================================================================
echo "🔍 Verifying cluster configuration..."

# Check cluster definition
echo "   Checking cluster definition..."
echo "   Debug: Executing cluster query..."

cluster_info=$(execute_query "SELECT%20cluster,%20shard_num,%20replica_num,%20host_name%20FROM%20system.clusters%20WHERE%20cluster%20=%20%27local_cluster%27%20FORMAT%20TabSeparated")

echo "   Debug: Query result length: ${#cluster_info}"
echo "   Debug: Query result: '$cluster_info'"

if [ -z "$cluster_info" ]; then
    echo "❌ Cluster 'local_cluster' not found in system.clusters"
    echo "   Debug: Let's check what clusters exist..."
    all_clusters=$(execute_query "SELECT%20cluster%20FROM%20system.clusters%20FORMAT%20TabSeparated")
    echo "   Available clusters: '$all_clusters'"
    exit 1
fi

echo "✅ Cluster configuration found:"
echo "$cluster_info" | while read line; do
    echo "   $line"
done

echo ""

# =============================================================================
# 3. CREATE SAMPLE DATABASE AND TABLES
# =============================================================================
echo "🗄️  Creating sample database and tables..."

# Create sample database
echo "   Creating sample database..."
execute_query "CREATE DATABASE IF NOT EXISTS sample_db ON CLUSTER local_cluster" >/dev/null

# Create a simple ReplicatedMergeTree table
echo "   Creating sample replicated table..."
create_table_query="
CREATE TABLE IF NOT EXISTS sample_db.events ON CLUSTER local_cluster
(
    event_time DateTime,
    user_id UInt32,
    event_type String,
    value Float32
)
ENGINE = ReplicatedMergeTree('/clickhouse/tables/{shard}/events', '{replica}')
ORDER BY (event_time, user_id)
PARTITION BY toYYYYMM(event_time)
SETTINGS index_granularity = 8192
"

execute_query "$create_table_query" >/dev/null
echo "✅ Sample table created successfully"

# Insert sample data
echo "   Inserting sample data..."
insert_query="
INSERT INTO sample_db.events VALUES
    ('2024-01-01 10:00:00', 1001, 'login', 1.0),
    ('2024-01-01 10:05:00', 1002, 'page_view', 2.5),
    ('2024-01-01 10:10:00', 1001, 'purchase', 99.99),
    ('2024-01-01 10:15:00', 1003, 'login', 1.0),
    ('2024-01-01 10:20:00', 1002, 'logout', 1.0)
"

execute_query "$insert_query" >/dev/null
echo "✅ Sample data inserted"

echo ""

# =============================================================================
# 4. VERIFY REPLICATION
# =============================================================================
echo "🔄 Verifying replication across nodes..."

# Function to check table on specific node
check_table_on_node() {
    local port=$1
    local node_name=$2
    
    echo "   Checking $node_name (port $port)..."
    
    local count=$(timeout 30 curl -k -s "https://localhost:$port/?query=SELECT%20count()%20FROM%20sample_db.events" 2>/dev/null || echo "0")
    
    if [ "$count" = "5" ]; then
        echo "   ✅ $node_name: $count rows (replication working)"
        return 0
    else
        echo "   ❌ $node_name: $count rows (expected 5)"
        return 1
    fi
}

# Check each node with correct ports
replication_ok=true
if ! check_table_on_node 9001 "clickhouse-1"; then replication_ok=false; fi
if ! check_table_on_node 9011 "clickhouse-2"; then replication_ok=false; fi
if ! check_table_on_node 9021 "clickhouse-3"; then replication_ok=false; fi

if [ "$replication_ok" = true ]; then
    echo "✅ Replication is working correctly across all nodes"
else
    echo "⚠️  Replication issues detected - data may still be synchronizing"
fi

echo ""

# =============================================================================
# 5. TEST DISTRIBUTED QUERIES
# =============================================================================
echo "🌐 Testing distributed queries..."

# Test distributed query
echo "   Testing cluster-wide query..."
distributed_result=$(execute_query "SELECT cluster, count() as total_events FROM cluster('local_cluster', sample_db.events) GROUP BY cluster FORMAT TabSeparated" 2>/dev/null || echo "")

if echo "$distributed_result" | grep -q "local_cluster"; then
    total_events=$(echo "$distributed_result" | cut -f2)
    echo "✅ Distributed query successful: $total_events total events across cluster"
else
    echo "❌ Distributed query failed"
fi

echo ""

# =============================================================================
# 6. DISPLAY CLUSTER INFORMATION
# =============================================================================
echo "📊 Cluster Information Summary"
echo "=============================="

# Cluster status
echo "🏷️  Cluster Details:"
execute_query "
SELECT 
    cluster,
    shard_num,
    replica_num,
    host_name,
    port,
    is_local
FROM system.clusters 
WHERE cluster = 'local_cluster'
ORDER BY shard_num, replica_num
FORMAT Pretty
"

echo ""

# Database and tables
echo "🗄️  Databases and Tables:"
execute_query "
SELECT 
    database,
    name as table_name,
    engine
FROM system.tables 
WHERE database NOT IN ('system', 'information_schema', 'INFORMATION_SCHEMA')
ORDER BY database, name
FORMAT Pretty
"

echo ""

# =============================================================================
# 7. PROVIDE USAGE EXAMPLES
# =============================================================================
echo "📚 Usage Examples"
echo "=================="
echo ""
echo "🔗 Connection Examples:"
echo "   # HTTP API:"
echo "   curl -k 'https://localhost:9001/?query=SELECT version()'"
echo ""
echo "   # ClickHouse Client (if installed):"
echo "   clickhouse-client --host localhost --port 9002 --secure"
echo ""
echo "🗃️  Sample Queries:"
echo "   # Check cluster status:"
echo "   SELECT * FROM system.clusters WHERE cluster = 'local_cluster'"
echo ""
echo "   # Query sample data:"
echo "   SELECT * FROM sample_db.events ORDER BY event_time"
echo ""
echo "   # Distributed aggregation:"
echo "   SELECT event_type, count() FROM cluster('local_cluster', sample_db.events) GROUP BY event_type"
echo ""
echo "   # Create your own replicated table:"
echo "   CREATE TABLE my_db.my_table ON CLUSTER local_cluster (...) ENGINE = ReplicatedMergeTree('/clickhouse/tables/{shard}/my_table', '{replica}') ORDER BY ..."
echo ""
echo "🎯 Cluster initialization completed successfully!"