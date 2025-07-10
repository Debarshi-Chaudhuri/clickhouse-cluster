#!/bin/bash
set -e

# ClickHouse Cluster Health Check Script
echo "=========================================="
echo "ClickHouse Cluster Health Check"
echo "=========================================="

# =============================================================================
# 1. DOCKER SWARM HEALTH
# =============================================================================
echo "🐳 Checking Docker Swarm status..."

if ! docker node ls >/dev/null 2>&1; then
    echo "❌ Docker Swarm is not initialized"
    exit 1
fi

echo "✅ Docker Swarm is running"
echo ""

# =============================================================================
# 2. SERVICE STATUS
# =============================================================================
echo "📋 Checking service status..."

services=(
    "clickhouse-cluster_keeper-1"
    "clickhouse-cluster_keeper-2" 
    "clickhouse-cluster_keeper-3"
    "clickhouse-cluster_clickhouse-1"
    "clickhouse-cluster_clickhouse-2"
    "clickhouse-cluster_clickhouse-3"
)

all_services_running=true

for service in "${services[@]}"; do
    if docker service ps $service --filter "desired-state=running" --format "{{.CurrentState}}" | grep -q "Running"; then
        replicas=$(docker service ls --filter "name=$service" --format "{{.Replicas}}")
        echo "✅ $service: $replicas"
    else
        echo "❌ $service: Not running"
        all_services_running=false
    fi
done

if [ "$all_services_running" = false ]; then
    echo ""
    echo "❌ Some services are not running. Check with: docker service ps <service-name>"
    exit 1
fi

echo ""

# =============================================================================
# 3. CLICKHOUSE CONNECTIVITY
# =============================================================================
echo "🔗 Testing ClickHouse connectivity..."

# Function to test ClickHouse HTTP endpoint
test_clickhouse_http() {
    local port=$1
    local node_name=$2
    
    if curl -k --connect-timeout 5 -s "https://localhost:$port" >/dev/null 2>&1; then
        echo "✅ $node_name HTTPS (port $port): Responding"
        return 0
    else
        echo "❌ $node_name HTTPS (port $port): Not responding"
        return 1
    fi
}

# Test each ClickHouse node
connectivity_ok=true
if ! test_clickhouse_http 8123 "clickhouse-1"; then connectivity_ok=false; fi
if ! test_clickhouse_http 8124 "clickhouse-2"; then connectivity_ok=false; fi
if ! test_clickhouse_http 8125 "clickhouse-3"; then connectivity_ok=false; fi

echo ""

# =============================================================================
# 4. KEEPER CONNECTIVITY
# =============================================================================
echo "🔑 Testing Keeper connectivity..."

# Function to test Keeper port
test_keeper() {
    local port=$1
    local node_name=$2
    
    if nc -z localhost $port 2>/dev/null; then
        echo "✅ $node_name (port $port): Responding"
        return 0
    else
        echo "❌ $node_name (port $port): Not responding"
        return 1
    fi
}

# Test each Keeper node
keeper_ok=true
if ! test_keeper 2181 "keeper-1"; then keeper_ok=false; fi
if ! test_keeper 2182 "keeper-2"; then keeper_ok=false; fi
if ! test_keeper 2183 "keeper-3"; then keeper_ok=false; fi

echo ""

# =============================================================================
# 5. CLUSTER HEALTH (if ClickHouse is responding)
# =============================================================================
if [ "$connectivity_ok" = true ]; then
    echo "🏥 Testing cluster health..."
    
    # Test cluster configuration
    echo "   Testing cluster configuration..."
    if timeout 10 curl -k -s "https://localhost:8123/?query=SELECT%20*%20FROM%20system.clusters%20WHERE%20cluster%20=%20%27local_cluster%27%20FORMAT%20TabSeparated" | grep -q "local_cluster"; then
        echo "✅ Cluster configuration is accessible"
        
        # Count cluster nodes
        node_count=$(timeout 10 curl -k -s "https://localhost:8123/?query=SELECT%20count()%20FROM%20system.clusters%20WHERE%20cluster%20=%20%27local_cluster%27" 2>/dev/null || echo "0")
        echo "✅ Cluster has $node_count configured nodes"
        
    else
        echo "❌ Cluster configuration not accessible"
        connectivity_ok=false
    fi
    
    # Test system tables
    echo "   Testing system tables access..."
    if timeout 10 curl -k -s "https://localhost:8123/?query=SELECT%20version()%20FORMAT%20TabSeparated" >/dev/null 2>&1; then
        version=$(timeout 10 curl -k -s "https://localhost:8123/?query=SELECT%20version()%20FORMAT%20TabSeparated" 2>/dev/null)
        echo "✅ ClickHouse version: $version"
    else
        echo "❌ Cannot query ClickHouse system tables"
        connectivity_ok=false
    fi
else
    echo "⚠️  Skipping cluster health checks (ClickHouse not responding)"
fi

echo ""

# =============================================================================
# 6. RESOURCE USAGE
# =============================================================================
echo "📊 Resource usage summary..."

# Docker system info
echo "   Docker system resource usage:"
docker system df --format "table {{.Type}}\t{{.TotalCount}}\t{{.Size}}\t{{.Reclaimable}}"

echo ""

# Service resource usage (if available)
echo "   Service resource usage:"
docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}" $(docker ps --format "{{.Names}}" | grep -E "(clickhouse|keeper)" | head -6) 2>/dev/null || echo "   Resource stats not available"

echo ""

# =============================================================================
# 7. HEALTH SUMMARY
# =============================================================================
echo "📋 Health Check Summary"
echo "========================"

if [ "$all_services_running" = true ]; then
    echo "✅ All services running"
else
    echo "❌ Service issues detected"
fi

if [ "$connectivity_ok" = true ]; then
    echo "✅ ClickHouse connectivity OK"
else
    echo "❌ ClickHouse connectivity issues"
fi

if [ "$keeper_ok" = true ]; then
    echo "✅ Keeper connectivity OK" 
else
    echo "❌ Keeper connectivity issues"
fi

echo ""

# Overall health status
if [ "$all_services_running" = true ] && [ "$connectivity_ok" = true ] && [ "$keeper_ok" = true ]; then
    echo "🎉 Cluster is healthy!"
    echo ""
    echo "🔗 Connection examples:"
    echo "   HTTP:  curl -k 'https://localhost:8123/?query=SELECT%201'"
    echo "   CLI:   clickhouse-client --host localhost --port 9002 --secure"
    echo ""
    exit 0
else
    echo "⚠️  Cluster has health issues!"
    echo ""
    echo "🔧 Troubleshooting commands:"
    echo "   docker service ls"
    echo "   docker service logs clickhouse-cluster_clickhouse-1"
    echo "   docker service logs clickhouse-cluster_keeper-1"
    echo ""
    exit 1
fi