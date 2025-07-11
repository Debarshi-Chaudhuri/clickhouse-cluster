#!/bin/bash
set -e

# ClickHouse Cluster Local Deployment Script with Unified Network
echo "=========================================="
echo "ClickHouse Cluster Sequential Deployment"
echo "=========================================="

# Change to script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "Project root: $PROJECT_ROOT"
echo ""

# =============================================================================
# 1. PREREQUISITES CHECK
# =============================================================================
echo "🔍 Checking prerequisites..."

# Check if Docker is running
if ! docker info >/dev/null 2>&1; then
    echo "❌ Docker is not running. Please start Docker and try again."
    exit 1
fi
echo "✅ Docker is running"

# Check if Docker Compose is available
if ! docker compose version >/dev/null 2>&1; then
    echo "❌ Docker Compose is not available. Please install Docker Compose."
    exit 1
fi
echo "✅ Docker Compose is available"

# Check if we're in a swarm (if not, initialize)
if ! docker node ls >/dev/null 2>&1; then
    echo "🔧 Initializing Docker Swarm..."
    docker swarm init --advertise-addr 127.0.0.1
    echo "✅ Docker Swarm initialized"
else
    echo "✅ Docker Swarm is already initialized"
fi

echo ""

# =============================================================================
# 2. CLEANUP EXISTING STACKS AND NETWORKS
# =============================================================================
echo "🧹 Cleaning up existing stacks and networks..."

# Remove existing stacks if they exist
if docker stack ls --format "{{.Name}}" | grep -q "^clickhouse-servers$"; then
    echo "   Removing existing ClickHouse servers stack..."
    docker stack rm clickhouse-servers
fi

if docker stack ls --format "{{.Name}}" | grep -q "^clickhouse-keepers$"; then
    echo "   Removing existing ClickHouse keepers stack..."
    docker stack rm clickhouse-keepers
fi

if docker stack ls --format "{{.Name}}" | grep -q "^clickhouse-cluster$"; then
    echo "   Removing existing combined stack..."
    docker stack rm clickhouse-cluster
fi

# Wait for cleanup
if docker stack ls --format "{{.Name}}" | grep -q "clickhouse"; then
    echo "   Waiting for stack cleanup to complete..."
    sleep 30
fi

# Clean up old networks (but ignore errors)
echo "   Cleaning up old networks..."
docker network rm clickhouse-network 2>/dev/null || true
docker network rm keeper-network 2>/dev/null || true
docker network rm shared-network 2>/dev/null || true

echo "✅ Cleanup completed"
echo ""

# =============================================================================
# 3. GENERATE SSL CERTIFICATES
# =============================================================================
echo "🔒 Generating SSL certificates for local development..."

cd "$PROJECT_ROOT/scripts"

# Check if certificates already exist
if [ -f "$PROJECT_ROOT/secrets/ssl/local/ca.crt" ]; then
    echo "📜 SSL certificates already exist. Skipping generation."
    echo "   To regenerate certificates, delete the secrets/ssl/local/ directory first."
else
    echo "📜 Generating new SSL certificates..."
    chmod +x generate-certs.sh
    ./generate-certs.sh
    echo "✅ SSL certificates generated successfully"
fi

# Make entrypoint scripts executable
echo "🔧 Setting up entrypoint script permissions..."
chmod +x "$PROJECT_ROOT/config/clickhouse/entrypoint.sh"
chmod +x "$PROJECT_ROOT/config/keeper/entrypoint.sh"
echo "✅ Entrypoint scripts permissions set"

echo ""

# =============================================================================
# 4. CREATE ENVIRONMENT FILES
# =============================================================================
echo "⚙️  Setting up environment files..."

cd "$PROJECT_ROOT/env"

# Create combined environment files for each service
echo "📝 Creating combined environment files..."

# Combine common + node-specific environment files
cat .env.common .env.node1 > .env.clickhouse1
cat .env.common .env.node2 > .env.clickhouse2
cat .env.common .env.node3 > .env.clickhouse3

echo "✅ Environment files created:"
echo "   - .env.clickhouse1 (for clickhouse-1 and keeper-1)"
echo "   - .env.clickhouse2 (for clickhouse-2 and keeper-2)"
echo "   - .env.clickhouse3 (for clickhouse-3 and keeper-3)"

echo ""

# =============================================================================
# 5. CREATE PASSWORD FILES
# =============================================================================
echo "🔑 Setting up password files..."

# Create password directories
mkdir -p "$PROJECT_ROOT/secrets/passwords/local"

# Generate random password for interserver communication
if [ ! -f "$PROJECT_ROOT/secrets/passwords/local/clickhouse-password.txt" ]; then
    echo "📝 Generating random interserver password..."
    openssl rand -base64 32 > "$PROJECT_ROOT/secrets/passwords/local/clickhouse-password.txt"
    chmod 600 "$PROJECT_ROOT/secrets/passwords/local/clickhouse-password.txt"
    echo "✅ Interserver password generated"
else
    echo "🔑 Interserver password already exists"
fi

echo ""

# =============================================================================
# 6. SET NODE LABELS AND CREATE UNIFIED NETWORK
# =============================================================================
echo "🏷️  Setting up Docker Swarm node labels and unified network..."

# Get the current node ID (single node setup)
NODE_ID=$(docker node ls --format "{{.ID}}" --filter "role=manager")

# For single-node deployment, use a single label that allows all services
echo "   Configuring node labels for single-node deployment..."
docker node update --label-add instance=local $NODE_ID
docker node update --label-add clickhouse-node=true $NODE_ID
docker node update --label-add keeper-node=true $NODE_ID

echo "✅ Node labels configured for single-node deployment"

# Create unified overlay network
echo "🌐 Creating unified Docker overlay network..."

# Check if network already exists, create if not
if ! docker network ls --format "{{.Name}}" | grep -q "^shared-network$"; then
    echo "   Creating shared-network..."
    docker network create \
        --driver overlay \
        --attachable \
        shared-network
    echo "   ✅ shared-network created"
else
    echo "   ✅ shared-network already exists"
fi

echo "✅ Docker unified network configured successfully"

echo ""

# =============================================================================
# 7. DEPLOY KEEPER STACK FIRST
# =============================================================================
echo "🚀 Phase 1: Deploying ClickHouse Keeper stack..."

cd "$PROJECT_ROOT/stacks"

# Deploy Keeper stack
echo "📋 Deploying Keeper services..."
docker stack deploy \
    --compose-file docker-stack.keepers.yml \
    --detach=false \
    clickhouse-keepers

echo "✅ Keeper stack deployment initiated"

# Function to check service readiness
check_service_ready() {
    local service_name=$1
    local max_attempts=60
    local attempt=1
    
    echo "   Checking $service_name..."
    
    while [ $attempt -le $max_attempts ]; do
        if docker service ps $service_name --filter "desired-state=running" --format "{{.CurrentState}}" | grep -q "Running"; then
            echo "   ✅ $service_name is ready"
            return 0
        fi
        
        echo "   ⏳ Attempt $attempt/$max_attempts - waiting for $service_name..."
        sleep 10
        attempt=$((attempt + 1))
    done
    
    echo "   ❌ $service_name failed to become ready after $max_attempts attempts"
    return 1
}

# Wait for Keeper services to be ready
echo "⏳ Waiting for Keeper services to become ready..."

keeper_services=(
    "clickhouse-keepers_keeper-1"
    "clickhouse-keepers_keeper-2" 
    "clickhouse-keepers_keeper-3"
)

all_keepers_ready=true
for service in "${keeper_services[@]}"; do
    if ! check_service_ready $service; then
        all_keepers_ready=false
    fi
done

if [ "$all_keepers_ready" = false ]; then
    echo "❌ Some Keeper services failed to start. Check logs with:"
    echo "   docker service logs clickhouse-keepers_keeper-1"
    exit 1
fi

echo "✅ All Keeper services are ready!"

# =============================================================================
# 8. DEPLOY CLICKHOUSE STACK
# =============================================================================
echo "🚀 Phase 2: Deploying ClickHouse server stack..."

# Deploy ClickHouse stack
echo "📋 Deploying ClickHouse services..."
docker stack deploy \
    --compose-file docker-stack.clickhouse.yml \
    --detach=false \
    clickhouse-servers

echo "✅ ClickHouse stack deployment initiated"

# Wait for ClickHouse services to be ready
echo "⏳ Waiting for ClickHouse services to become ready..."

clickhouse_services=(
    "clickhouse-servers_clickhouse-1"
    "clickhouse-servers_clickhouse-2"
    "clickhouse-servers_clickhouse-3"
)

all_clickhouse_ready=true
for service in "${clickhouse_services[@]}"; do
    if ! check_service_ready $service; then
        all_clickhouse_ready=false
    fi
done

if [ "$all_clickhouse_ready" = false ]; then
    echo "❌ Some ClickHouse services failed to start. Check logs with:"
    echo "   docker service logs clickhouse-servers_clickhouse-1"
    exit 1
fi

echo "✅ All ClickHouse services are ready!"

echo ""

# =============================================================================
# 9. COMPREHENSIVE HEALTH CHECK
# =============================================================================
echo "🏥 Running comprehensive health checks..."

# Wait for services to fully initialize
echo "   Waiting 60 seconds for services to fully initialize..."
sleep 60

# Function to check ClickHouse connectivity
check_clickhouse() {
    local port=$1
    local node_name=$2
    
    echo "   Testing ClickHouse HTTPS connection on port $port ($node_name)..."
    
    if curl -k --connect-timeout 10 -s "https://localhost:$port" >/dev/null 2>&1; then
        echo "   ✅ $node_name is responding on HTTPS port $port"
        return 0
    else
        echo "   ❌ $node_name is not responding on HTTPS port $port"
        return 1
    fi
}

# Test ClickHouse connectivity
health_ok=true
if ! check_clickhouse 9001 "clickhouse-1"; then health_ok=false; fi
if ! check_clickhouse 9011 "clickhouse-2"; then health_ok=false; fi  
if ! check_clickhouse 9021 "clickhouse-3"; then health_ok=false; fi

# Test interserver connectivity
echo "   Testing interserver HTTPS ports..."
if curl -k --connect-timeout 5 -s "https://localhost:9010" >/dev/null 2>&1; then
    echo "   ✅ Interserver port 9010 responding"
else
    echo "   ⚠️  Interserver port 9010 not responding"
fi

# Test cluster formation (if ClickHouse is responding)
if [ "$health_ok" = true ]; then
    echo "   Testing cluster connectivity..."
    if curl -k -s "https://localhost:9001/?query=SELECT%20*%20FROM%20system.clusters%20WHERE%20cluster%20=%20%27local_cluster%27" | grep -q "local_cluster"; then
        echo "   ✅ ClickHouse cluster is accessible and configured"
    else
        echo "   ⚠️  ClickHouse cluster configuration may not be ready yet"
    fi
fi

# Test replication if cluster is working
if [ "$health_ok" = true ]; then
    echo "   Testing data replication..."
    # Insert a test record
    curl -k -s -X POST "https://localhost:9001/" -d "CREATE DATABASE IF NOT EXISTS test_replication" >/dev/null 2>&1
    curl -k -s -X POST "https://localhost:9001/" -d "CREATE TABLE IF NOT EXISTS test_replication.test_table ON CLUSTER local_cluster (id UInt32, message String) ENGINE = ReplicatedMergeTree('/clickhouse/tables/{shard}/test_table', '{replica}') ORDER BY id" >/dev/null 2>&1
    curl -k -s -X POST "https://localhost:9001/" -d "INSERT INTO test_replication.test_table VALUES (1, 'replication_test')" >/dev/null 2>&1
    
    sleep 5
    
    # Check if data replicated
    count1=$(curl -k -s -X POST "https://localhost:9001/" -d "SELECT count() FROM test_replication.test_table" 2>/dev/null || echo "0")
    count2=$(curl -k -s -X POST "https://localhost:9011/" -d "SELECT count() FROM test_replication.test_table" 2>/dev/null || echo "0")
    count3=$(curl -k -s -X POST "https://localhost:9021/" -d "SELECT count() FROM test_replication.test_table" 2>/dev/null || echo "0")
    
    if [ "$count1" = "$count2" ] && [ "$count2" = "$count3" ] && [ "$count1" != "0" ]; then
        echo "   ✅ Data replication is working (all nodes: $count1 records)"
    else
        echo "   ⚠️  Data replication may not be working (counts: $count1, $count2, $count3)"
    fi
    
    # Cleanup test table
    curl -k -s -X POST "https://localhost:9001/" -d "DROP DATABASE IF EXISTS test_replication ON CLUSTER local_cluster" >/dev/null 2>&1
fi

if [ "$health_ok" = true ]; then
    echo "✅ Health checks passed!"
else
    echo "⚠️  Some health checks failed, but services may still be starting up."
fi

echo ""

# =============================================================================
# 10. DEPLOYMENT SUMMARY
# =============================================================================
echo "🎉 ClickHouse Cluster Sequential Deployment Summary"
echo "=================================================="
echo ""
echo "✅ Docker Swarm initialized"
echo "✅ SSL certificates generated"
echo "✅ Environment files configured" 
echo "✅ Password files created"
echo "✅ Unified network (shared-network) created"
echo "✅ Keeper cluster deployed and ready"
echo "✅ ClickHouse cluster deployed and ready"
echo ""
echo "📊 Cluster Information:"
echo "   Cluster Name: local_cluster"
echo "   Network: shared-network"
echo "   Keeper Stack: clickhouse-keepers"
echo "   ClickHouse Stack: clickhouse-servers"
echo "   Nodes: 3 ClickHouse + 3 Keeper"
echo "   Replication: 1 shard with 3 replicas"
echo ""
echo "🌐 Access Points:"
echo "   ClickHouse Node 1: https://localhost:9001 (interserver: 9010)"
echo "   ClickHouse Node 2: https://localhost:9011 (interserver: 9020)" 
echo "   ClickHouse Node 3: https://localhost:9021 (interserver: 9030)"
echo ""
echo "   Keeper Node 1: localhost:9181"
echo "   Keeper Node 2: localhost:9182"
echo "   Keeper Node 3: localhost:9183"
echo ""
echo "🔧 Management Commands:"
echo "   View all stacks:         docker stack ls"
echo "   View keeper services:    docker service ls --filter label=com.docker.stack.namespace=clickhouse-keepers"
echo "   View clickhouse services: docker service ls --filter label=com.docker.stack.namespace=clickhouse-servers"
echo "   View keeper logs:        docker service logs clickhouse-keepers_keeper-1"
echo "   View clickhouse logs:    docker service logs clickhouse-servers_clickhouse-1"
echo "   Remove keeper stack:     docker stack rm clickhouse-keepers"
echo "   Remove clickhouse stack: docker stack rm clickhouse-servers"
echo ""
echo "📚 Next Steps:"
echo "   1. Test connectivity: curl -k https://localhost:9001"
echo "   2. Connect with client: clickhouse-client --host localhost --port 9002 --secure"
echo "   3. Run cluster query: SELECT * FROM system.clusters WHERE cluster = 'local_cluster'"
echo "   4. Test replication: INSERT INTO your_table VALUES (...)"
echo ""
echo "🎯 Sequential deployment completed successfully!"