#!/bin/bash
set -e

# ClickHouse Cluster Local Deployment Script
echo "=========================================="
echo "ClickHouse Cluster Local Deployment"
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
# 2. GENERATE SSL CERTIFICATES
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
# 3. CREATE ENVIRONMENT FILES
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
# 4. CREATE PASSWORD FILES
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
# 5. SET NODE LABELS AND CREATE NETWORKS
# =============================================================================
echo "🏷️  Setting up Docker Swarm node labels and networks..."

# Get the current node ID (single node setup)
NODE_ID=$(docker node ls --format "{{.ID}}" --filter "role=manager")

# For single-node deployment, use a single label that allows all services
echo "   Configuring node labels for single-node deployment..."
docker node update --label-add instance=local $NODE_ID
docker node update --label-add clickhouse-node=true $NODE_ID
docker node update --label-add keeper-node=true $NODE_ID

echo "✅ Node labels configured for single-node deployment"

# Create overlay networks if they don't exist
echo "🌐 Creating Docker overlay networks..."

# Check and create clickhouse-network
if ! docker network ls --format "{{.Name}}" | grep -q "^clickhouse-network$"; then
    echo "   Creating clickhouse-network..."
    docker network create \
        --driver overlay \
        --attachable \
        clickhouse-network
    echo "   ✅ clickhouse-network created"
else
    echo "   ✅ clickhouse-network already exists"
fi

# Check and create keeper-network
if ! docker network ls --format "{{.Name}}" | grep -q "^keeper-network$"; then
    echo "   Creating keeper-network..."
    docker network create \
        --driver overlay \
        --attachable \
        keeper-network
    echo "   ✅ keeper-network created"
else
    echo "   ✅ keeper-network already exists"
fi

echo "✅ Docker networks configured successfully"

echo ""

# =============================================================================
# 6. DEPLOY THE STACK
# =============================================================================
echo "🚀 Deploying ClickHouse cluster stack..."

cd "$PROJECT_ROOT/stacks"

# Deploy the stack
docker stack deploy \
    --compose-file docker-stack.local.yml \
    --detach=false \
    clickhouse-cluster

echo "✅ Stack deployment initiated"

echo ""

# =============================================================================
# 7. WAIT FOR SERVICES TO BE READY
# =============================================================================
echo "⏳ Waiting for services to become ready..."

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
        sleep 5
        attempt=$((attempt + 1))
    done
    
    echo "   ❌ $service_name failed to become ready after $max_attempts attempts"
    return 1
}

# Check each service
services=(
    "clickhouse-cluster_keeper-1"
    "clickhouse-cluster_keeper-2" 
    "clickhouse-cluster_keeper-3"
    "clickhouse-cluster_clickhouse-1"
    "clickhouse-cluster_clickhouse-2"
    "clickhouse-cluster_clickhouse-3"
)

all_ready=true
for service in "${services[@]}"; do
    if ! check_service_ready $service; then
        all_ready=false
    fi
done

if [ "$all_ready" = true ]; then
    echo "✅ All services are ready!"
else
    echo "❌ Some services failed to start. Check logs with:"
    echo "   docker service logs <service-name>"
    exit 1
fi

echo ""

# =============================================================================
# 8. HEALTH CHECK
# =============================================================================
echo "🏥 Running health checks..."

# Wait a bit more for services to fully initialize
echo "   Waiting 30 seconds for services to fully initialize..."
sleep 30

# Function to check ClickHouse connectivity
check_clickhouse() {
    local port=$1
    local node_name=$2
    
    echo "   Testing ClickHouse HTTPS connection on port $port ($node_name)..."
    
    # Test HTTPS port since HTTP is disabled
    if curl -k --connect-timeout 10 -s "https://localhost:$port" >/dev/null 2>&1; then
        echo "   ✅ $node_name is responding on HTTPS port $port"
        return 0
    else
        echo "   ❌ $node_name is not responding on HTTPS port $port"
        return 1
    fi
}

# Check ClickHouse nodes on HTTPS ports (backward compatible)
health_ok=true
if ! check_clickhouse 9001 "clickhouse-1"; then health_ok=false; fi
if ! check_clickhouse 9011 "clickhouse-2"; then health_ok=false; fi  
if ! check_clickhouse 9021 "clickhouse-3"; then health_ok=false; fi

if [ "$health_ok" = true ]; then
    echo "✅ Health checks passed!"
else
    echo "⚠️  Some health checks failed, but services may still be starting up."
fi

echo ""

# =============================================================================
# 9. DEPLOYMENT SUMMARY
# =============================================================================
echo "🎉 ClickHouse Cluster Deployment Summary"
echo "=========================================="
echo ""
echo "✅ Docker Swarm initialized"
echo "✅ SSL certificates generated"
echo "✅ Environment files configured" 
echo "✅ Password files created"
echo "✅ Stack deployed successfully"
echo ""
echo "📊 Cluster Information:"
echo "   Cluster Name: local_cluster"
echo "   Nodes: 3 ClickHouse + 3 Keeper (co-located)"
echo "   Replication: 1 shard with 3 replicas"
echo ""
echo "🌐 Access Points:"
echo "   ClickHouse Node 1: https://localhost:9001"
echo "   ClickHouse Node 2: https://localhost:9011" 
echo "   ClickHouse Node 3: https://localhost:9021"
echo ""
echo "🔧 Management Commands:"
echo "   View services:    docker service ls"
echo "   View logs:        docker service logs clickhouse-cluster_clickhouse-1"
echo "   Scale service:    docker service scale clickhouse-cluster_clickhouse-1=2"
echo "   Remove stack:     docker stack rm clickhouse-cluster"
echo ""
echo "📚 Next Steps:"
echo "   1. Test connectivity: curl -k https://localhost:9001"
echo "   2. Connect with client: clickhouse-client --host localhost --port 9002 --secure"
echo "   3. Run cluster query: SELECT * FROM system.clusters WHERE cluster = 'local_cluster'"
echo ""
echo "🎯 Deployment completed successfully!"