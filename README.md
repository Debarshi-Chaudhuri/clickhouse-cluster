# ClickHouse Cluster - Local Development Setup

A production-ready ClickHouse cluster with ClickHouse Keeper for local development and testing.

## 🏗️ Architecture

- **3 ClickHouse Servers** - Replicated cluster (1 shard, 3 replicas)
- **3 ClickHouse Keepers** - Coordination and consensus
- **Docker Swarm** - Container orchestration
- **mTLS Security** - Certificate-based authentication
- **High Availability** - Automatic failover and replication

## 📁 Project Structure

```
clickhouse-cluster/
├── config/
│   ├── clickhouse/
│   │   ├── local/              # Local client configs
│   │   ├── production/         # Production client configs  
│   │   ├── templates/          # Server config templates
│   │   └── entrypoint.sh       # Template processor
│   └── keeper/
│       ├── templates/          # Keeper config templates
│       └── entrypoint.sh       # Template processor
├── env/
│   ├── .env.common            # Common environment variables
│   ├── .env.node1             # Node 1 specific variables
│   ├── .env.node2             # Node 2 specific variables
│   └── .env.node3             # Node 3 specific variables
├── scripts/
│   ├── deploy-local.sh        # Main deployment script
│   ├── health-check.sh        # Health monitoring
│   ├── init-cluster.sh        # Cluster initialization
│   └── generate-certs.sh      # SSL certificate generation
├── stacks/
│   └── docker-stack.local.yml # Docker Swarm stack definition
└── secrets/                   # Generated SSL certificates and passwords
```

## 🚀 Quick Start

### Prerequisites

- **Docker** (v20.10+)
- **Docker Compose** (v2.0+)
- **Linux/macOS** (tested environments)

### 1. Clone and Setup

```bash
git clone <repository-url>
cd clickhouse-cluster
```

### 2. Deploy the Cluster

```bash
# Make scripts executable
chmod +x scripts/*.sh

# Deploy the entire cluster
./scripts/deploy-local.sh
```

The deployment script will:
- ✅ Check prerequisites (Docker, Docker Compose)
- ✅ Initialize Docker Swarm (if not already initialized)
- ✅ Generate SSL certificates for mTLS
- ✅ Create environment files for each node
- ✅ Generate random passwords
- ✅ Deploy the stack with 6 services
- ✅ Wait for all services to be ready
- ✅ Run basic health checks

### 3. Verify Health

```bash
# Run comprehensive health checks
./scripts/health-check.sh
```

### 4. Initialize Cluster

```bash
# Create sample database and test replication
./scripts/init-cluster.sh
```

## 🔗 Access Points

After successful deployment:

| Service | URL | Purpose |
|---------|-----|---------|
| ClickHouse-1 | https://localhost:8123 | Primary node web interface |
| ClickHouse-2 | https://localhost:8124 | Secondary node web interface |
| ClickHouse-3 | https://localhost:8125 | Tertiary node web interface |

### Client Connections

#### Using ClickHouse Client

```bash
# Option 1: With client config file
clickhouse-client --config-file config/clickhouse/local/client-config.xml

# Option 2: Direct connection with mTLS
clickhouse-client \
  --host localhost \
  --port 9002 \
  --secure \
  --user beaver \
  --key secrets/ssl/local/clickhouse-server.key \
  --cert secrets/ssl/local/clickhouse-server.crt \
  --caconfig secrets/ssl/local/ca.crt
```

#### Using HTTP API

```bash
# Basic query
curl -k 'https://localhost:8123/?query=SELECT version()'

# With authentication (if needed)
curl -k 'https://localhost:8123/' \
  --cert secrets/ssl/local/clickhouse-server.crt \
  --key secrets/ssl/local/clickhouse-server.key \
  --cacert secrets/ssl/local/ca.crt \
  --data-urlencode "query=SELECT * FROM system.clusters"
```

## 🔧 Management Commands

### View Services

```bash
# List all services
docker service ls

# View service details
docker service ps clickhouse-cluster_clickhouse-1
```

### View Logs

```bash
# ClickHouse logs
docker service logs clickhouse-cluster_clickhouse-1
docker service logs clickhouse-cluster_clickhouse-2
docker service logs clickhouse-cluster_clickhouse-3

# Keeper logs
docker service logs clickhouse-cluster_keeper-1
docker service logs clickhouse-cluster_keeper-2
docker service logs clickhouse-cluster_keeper-3

# Follow logs in real-time
docker service logs -f clickhouse-cluster_clickhouse-1
```

### Health Monitoring

```bash
# Run health checks
./scripts/health-check.sh

# Check individual services
docker service ps clickhouse-cluster_clickhouse-1
```

### Cluster Operations

```bash
# Scale a service (if needed)
docker service scale clickhouse-cluster_clickhouse-1=1

# Update a service
docker service update clickhouse-cluster_clickhouse-1

# View cluster configuration
curl -k 'https://localhost:8123/?query=SELECT * FROM system.clusters'
```

## 🗄️ Database Operations

### Basic Queries

```sql
-- Check cluster status
SELECT * FROM system.clusters WHERE cluster = 'local_cluster';

-- View databases
SHOW DATABASES;

-- View sample data (created by init-cluster.sh)
SELECT * FROM sample_db.events ORDER BY event_time;

-- Distributed query across all nodes
SELECT count(*) FROM cluster('local_cluster', sample_db.events);
```

### Create Replicated Tables

```sql
-- Create database on cluster
CREATE DATABASE my_app ON CLUSTER local_cluster;

-- Create replicated table
CREATE TABLE my_app.user_events ON CLUSTER local_cluster
(
    timestamp DateTime,
    user_id UInt32,
    event_type String,
    properties String
)
ENGINE = ReplicatedMergeTree('/clickhouse/tables/{shard}/user_events', '{replica}')
ORDER BY (timestamp, user_id)
PARTITION BY toYYYYMM(timestamp);

-- Insert data (automatically replicated)
INSERT INTO my_app.user_events VALUES
    (now(), 1001, 'login', '{"ip": "192.168.1.1"}'),
    (now(), 1002, 'page_view', '{"page": "/dashboard"}');
```

## 🔒 Security Features

### mTLS Authentication

- **No passwords required** - Certificate-based authentication
- **Encrypted communication** - All traffic uses TLS 1.2+
- **Mutual authentication** - Both client and server verify certificates
- **Custom CA** - Self-signed certificates for local development

### Available Users

| User | Role | Access Level |
|------|------|-------------|
| `beaver` | Admin | Full cluster access |
| `metabase` | Reporting | Read-only access |
| `interserver` | System | Internal replication |

### Certificate Locations

```
secrets/ssl/local/
├── ca.crt                    # Certificate Authority
├── ca.key                    # CA private key  
├── clickhouse-server.crt     # Server certificate
├── clickhouse-server.key     # Server private key
├── keeper.crt               # Keeper certificate
└── keeper.key               # Keeper private key
```

## 🧹 Cleanup

### Stop Services

```bash
# Remove the entire stack
docker stack rm clickhouse-cluster

# Wait for cleanup to complete
docker system prune -f --volumes
```

### Reset Everything

```bash
# Remove stack
docker stack rm clickhouse-cluster

# Remove generated files
rm -rf secrets/
rm -f env/.env.clickhouse*

# Remove Docker Swarm (optional)
docker swarm leave --force
```

## 🔍 Troubleshooting

### Common Issues

#### Services Not Starting

```bash
# Check service status
docker service ls
docker service ps clickhouse-cluster_clickhouse-1

# View logs for errors
docker service logs clickhouse-cluster_clickhouse-1
```

#### SSL Certificate Issues

```bash
# Regenerate certificates
rm -rf secrets/ssl/local/
./scripts/generate-certs.sh
docker stack rm clickhouse-cluster
./scripts/deploy-local.sh
```

#### Connection Issues

```bash
# Test basic connectivity
curl -k https://localhost:8123

# Check if ports are open
netstat -tlnp | grep -E '(8123|8124|8125|9000|9001|9002)'

# Verify certificates
openssl x509 -in secrets/ssl/local/clickhouse-server.crt -text -noout
```

#### Environment Variable Issues

```bash
# Check generated environment files
cat env/.env.clickhouse1
cat env/.env.clickhouse2
cat env/.env.clickhouse3

# Verify required variables are set
grep -E "CLICKHOUSE_SERVER_ID|INSTANCE_NAME|CLUSTER_NAME" env/.env.clickhouse1
```

### Health Check Failed

```bash
# Run detailed health check
./scripts/health-check.sh

# Check specific service
docker service logs clickhouse-cluster_keeper-1

# Test Keeper connectivity
nc -z localhost 9181 && echo "Keeper-1 OK"
nc -z localhost 9182 && echo "Keeper-2 OK" 
nc -z localhost 9183 && echo "Keeper-3 OK"
```

### Performance Issues

```bash
# Check resource usage
docker stats

# Check system resources
free -h
df -h

# View service resource limits
docker service inspect clickhouse-cluster_clickhouse-1
```

## 📚 Additional Resources

### Configuration Customization

- Edit `env/.env.common` for cluster-wide settings
- Edit `env/.env.nodeX` for node-specific settings
- Modify templates in `config/clickhouse/templates/` for advanced configuration

### Production Deployment

- Use `docker-stack.prod.yml` for production deployment
- Update certificate paths for production SSL certificates
- Configure EBS volumes for persistent storage
- Set up CloudFormation templates for AWS deployment

### Monitoring

- Enable query logging in environment files
- Set up external monitoring with Prometheus
- Configure alerts for service health
- Monitor disk usage and performance metrics
