# ClickHouse Cluster Debug Commands

A comprehensive list of commands to debug and verify your ClickHouse cluster setup.

## Quick Health Check

```bash
# Test basic connectivity to all nodes
curl -k -s "https://localhost:9001/" && echo "✅ Node 1 responding"
curl -k -s "https://localhost:9011/" && echo "✅ Node 2 responding"
curl -k -s "https://localhost:9021/" && echo "✅ Node 3 responding"

# Test interserver ports
curl -k -s "https://localhost:9010/" && echo "✅ Interserver 1 responding"
curl -k -s "https://localhost:9020/" && echo "✅ Interserver 2 responding"
curl -k -s "https://localhost:9030/" && echo "✅ Interserver 3 responding"
```

## Docker Services Status

```bash
# Check all running services
docker service ls

# Check specific ClickHouse services
docker service ls --filter "label=com.docker.stack.namespace=clickhouse-servers"

# Check specific Keeper services
docker service ls --filter "label=com.docker.stack.namespace=clickhouse-keepers"

# Check service replicas and status
docker service ps clickhouse-servers_clickhouse-1
docker service ps clickhouse-servers_clickhouse-2
docker service ps clickhouse-servers_clickhouse-3
docker service ps clickhouse-keepers_keeper-1
docker service ps clickhouse-keepers_keeper-2
docker service ps clickhouse-keepers_keeper-3
```

## Logs Inspection

```bash
# View recent logs from ClickHouse nodes
docker service logs --tail 50 clickhouse-servers_clickhouse-1
docker service logs --tail 50 clickhouse-servers_clickhouse-2
docker service logs --tail 50 clickhouse-servers_clickhouse-3

# View recent logs from Keeper nodes
docker service logs --tail 50 clickhouse-keepers_keeper-1
docker service logs --tail 50 clickhouse-keepers_keeper-2
docker service logs --tail 50 clickhouse-keepers_keeper-3

# Follow logs in real-time
docker service logs -f clickhouse-servers_clickhouse-1

# Filter logs for errors
docker service logs clickhouse-servers_clickhouse-1 | grep -i "error\|exception\|fail"

# Filter logs for replication issues
docker service logs clickhouse-servers_clickhouse-2 | grep -i "replica\|fetch\|connection"
```

## Keeper Health Check

```bash
# Check Keeper stats (requires netcat)
echo "stat" | openssl s_client -connect localhost:9181 -quiet
echo "stat" | openssl s_client -connect localhost:9182 -quiet
echo "stat" | openssl s_client -connect localhost:9183 -quiet

# Check if Keeper is responding (alternative method)
echo "ruok" | openssl s_client -connect localhost:9181 -quiet
echo "ruok" | openssl s_client -connect localhost:9182 -quiet
echo "ruok" | openssl s_client -connect localhost:9183 -quiet

```

## ClickHouse Cluster Queries

### Basic Connectivity Tests
```bash
# Test simple queries on each node
curl -k -X POST "https://localhost:9001/" -d "SELECT version()"
curl -k -X POST "https://localhost:9011/" -d "SELECT version()"
curl -k -X POST "https://localhost:9021/" -d "SELECT version()"

# Check hostname of each node
curl -k -X POST "https://localhost:9001/" -d "SELECT hostName()"
curl -k -X POST "https://localhost:9011/" -d "SELECT hostName()"
curl -k -X POST "https://localhost:9021/" -d "SELECT hostName()"
```

### Cluster Configuration
```bash
# Check cluster configuration from each node
curl -k -X POST "https://localhost:9001/" -d "SELECT cluster, shard_num, replica_num, host_name, port, is_local FROM system.clusters WHERE cluster = 'local_cluster'"
curl -k -X POST "https://localhost:9011/" -d "SELECT cluster, shard_num, replica_num, host_name, port, is_local FROM system.clusters WHERE cluster = 'local_cluster'"
curl -k -X POST "https://localhost:9021/" -d "SELECT cluster, shard_num, replica_num, host_name, port, is_local FROM system.clusters WHERE cluster = 'local_cluster'"

# Check macros configuration
curl -k -X POST "https://localhost:9001/" -d "SELECT * FROM system.macros"
curl -k -X POST "https://localhost:9011/" -d "SELECT * FROM system.macros"
curl -k -X POST "https://localhost:9021/" -d "SELECT * FROM system.macros"
```

### Keeper Connectivity from ClickHouse
```bash
# Test Keeper connectivity from each ClickHouse node
curl -k -X POST "https://localhost:9001/" -d "SELECT count() FROM system.zookeeper WHERE path = '/'"
curl -k -X POST "https://localhost:9011/" -d "SELECT count() FROM system.zookeeper WHERE path = '/'"
curl -k -X POST "https://localhost:9021/" -d "SELECT count() FROM system.zookeeper WHERE path = '/'"

# Check Keeper path for your table
curl -k -X POST "https://localhost:9001/" -d "SELECT name FROM system.zookeeper WHERE path = '/clickhouse/tables/01/events/replicas'"
```

## Replication Status

### Check Replica Status
```bash
# View replica information
curl -k -X POST "https://localhost:9001/" -d "SELECT database, table, replica_name, is_leader, is_readonly, absolute_delay FROM system.replicas WHERE database = 'one_pice_dev'"

# Detailed replica status
curl -k -X POST "https://localhost:9001/" -d "SELECT database, table, replica_name, is_leader, is_readonly, is_session_expired, queue_size, inserts_in_queue, log_max_index, log_pointer, last_queue_update FROM system.replicas WHERE database = 'one_pice_dev'"
```

### Check Replication Queue
```bash
# Check replication queue (should be empty when healthy)
curl -k -X POST "https://localhost:9001/" -d "SELECT * FROM system.replication_queue WHERE database = 'one_pice_dev'"

# Check for stuck operations
curl -k -X POST "https://localhost:9001/" -d "SELECT database, table, replica_name, type, create_time, required_quorum, is_currently_executing FROM system.replication_queue WHERE database = 'one_pice_dev' ORDER BY create_time"
```

### Check Data Parts
```bash
# Check what parts exist on each node
curl -k -X POST "https://localhost:9001/" -d "SELECT database, table, name, active FROM system.parts WHERE database = 'one_pice_dev' AND table = 'events' AND active = 1"
curl -k -X POST "https://localhost:9011/" -d "SELECT database, table, name, active FROM system.parts WHERE database = 'one_pice_dev' AND table = 'events' AND active = 1"
curl -k -X POST "https://localhost:9021/" -d "SELECT database, table, name, active FROM system.parts WHERE database = 'one_pice_dev' AND table = 'events' AND active = 1"
```

## Data Verification

### Check Data Consistency
```bash
# Count records on each node (should be identical)
curl -k -X POST "https://localhost:9001/" -d "SELECT hostName(), count() FROM one_pice_dev.events"
curl -k -X POST "https://localhost:9011/" -d "SELECT hostName(), count() FROM one_pice_dev.events"
curl -k -X POST "https://localhost:9021/" -d "SELECT hostName(), count() FROM one_pice_dev.events"

# Check specific data
curl -k -X POST "https://localhost:9001/" -d "SELECT * FROM one_pice_dev.events ORDER BY event_time LIMIT 5"
```

### Test Replication
```bash
# Insert test data and verify replication
curl -k -X POST "https://localhost:9001/" -d "INSERT INTO one_pice_dev.events VALUES ('2025-07-11 15:00:00', 9999, 'debug_test')"

# Wait a few seconds, then check all nodes
sleep 5
curl -k -X POST "https://localhost:9001/" -d "SELECT count() FROM one_pice_dev.events WHERE event_type = 'debug_test'"
curl -k -X POST "https://localhost:9011/" -d "SELECT count() FROM one_pice_dev.events WHERE event_type = 'debug_test'"
curl -k -X POST "https://localhost:9021/" -d "SELECT count() FROM one_pice_dev.events WHERE event_type = 'debug_test'"
```

## System Information

### Resource Usage
```bash
# Check Docker container resource usage
docker stats --no-stream

# Check ClickHouse system metrics
curl -k -X POST "https://localhost:9001/" -d "SELECT metric, value FROM system.metrics WHERE metric LIKE '%Memory%' ORDER BY metric"

# Check disk usage
curl -k -X POST "https://localhost:9001/" -d "SELECT name, path, free_space, total_space FROM system.disks"
```

### Configuration Verification
```bash
# Check loaded configuration
curl -k -X POST "https://localhost:9001/" -d "SELECT name, value FROM system.server_settings WHERE name LIKE '%port%'"

# Check SSL configuration
curl -k -X POST "https://localhost:9001/" -d "SELECT name, value FROM system.server_settings WHERE name LIKE '%ssl%'"

# Check users and permissions
curl -k -X POST "https://localhost:9001/" -d "SELECT name, auth_type, host_ip, host_names FROM system.users"
```

## Network Debugging

### Container Network Inspection
```bash
# Check container network configuration
docker network ls
docker network inspect shared-network

# Check container IP addresses
docker ps --format "table {{.Names}}\t{{.Ports}}"

# Test DNS resolution between containers
container_name=$(docker ps --filter "name=clickhouse-servers_clickhouse-1" --format "{{.Names}}" | head -1)
docker exec "$container_name" nslookup clickhouse-servers_clickhouse-2
docker exec "$container_name" nslookup clickhouse-keepers_keeper-1
```

### Port Connectivity
```bash
# Test internal connectivity (from inside container)
container_name=$(docker ps --filter "name=clickhouse-servers_clickhouse-1" --format "{{.Names}}" | head -1)
docker exec "$container_name" nc -z clickhouse-servers_clickhouse-2 9002
docker exec "$container_name" nc -z clickhouse-servers_clickhouse-2 9010
docker exec "$container_name" nc -z clickhouse-keepers_keeper-1 9181
```

## Troubleshooting Commands

### Restart Replication
```bash
# Force restart replication on all nodes
curl -k -X POST "https://localhost:9001/" -d "SYSTEM RESTART REPLICA one_pice_dev.events"
curl -k -X POST "https://localhost:9011/" -d "SYSTEM RESTART REPLICA one_pice_dev.events"
curl -k -X POST "https://localhost:9021/" -d "SYSTEM RESTART REPLICA one_pice_dev.events"

# Force sync replica
curl -k -X POST "https://localhost:9001/" -d "SYSTEM SYNC REPLICA one_pice_dev.events"
```

### Clear Caches
```bash
# Clear DNS cache
curl -k -X POST "https://localhost:9001/" -d "SYSTEM DROP DNS CACHE"

# Clear mark cache
curl -k -X POST "https://localhost:9001/" -d "SYSTEM DROP MARK CACHE"

# Reload configuration
curl -k -X POST "https://localhost:9001/" -d "SYSTEM RELOAD CONFIG"
```

## Error Investigation

### Common Error Patterns
```bash
# Check for connection errors
docker service logs clickhouse-servers_clickhouse-2 | grep -i "connection\|timeout\|refused"

# Check for SSL errors
docker service logs clickhouse-servers_clickhouse-1 | grep -i "ssl\|certificate\|tls"

# Check for Keeper errors
docker service logs clickhouse-keepers_keeper-1 | grep -i "error\|exception\|fail"

# Check for replication errors
docker service logs clickhouse-servers_clickhouse-2 | grep -i "replica\|fetch\|part"
```

### Performance Monitoring
```bash
# Check slow queries
curl -k -X POST "https://localhost:9001/" -d "SELECT query, query_duration_ms, memory_usage FROM system.query_log WHERE query_duration_ms > 1000 ORDER BY event_time DESC LIMIT 10"

# Check replication lag
curl -k -X POST "https://localhost:9001/" -d "SELECT database, table, replica_name, absolute_delay FROM system.replicas WHERE absolute_delay > 0"
```

## Clean Restart Process

If you need to completely restart the cluster:

```bash
# Remove stacks
docker stack rm clickhouse-servers
docker stack rm clickhouse-keepers

# Wait for cleanup
sleep 30

# Remove network
docker network rm shared-network

# Redeploy
cd stacks/
docker network create --driver overlay --attachable shared-network
docker stack deploy --compose-file docker-stack.keepers.yml clickhouse-keepers
sleep 60
docker stack deploy --compose-file docker-stack.clickhouse.yml clickhouse-servers
```

## Expected Healthy Output

When everything is working correctly, you should see:

- **Keeper stats**: All keepers responding with follower/leader status
- **Cluster queries**: All nodes showing 3 replicas in `system.clusters`
- **Replication queue**: Empty (`system.replication_queue`)
- **Data consistency**: Same counts on all nodes
- **Replica status**: `is_readonly = 0`, `absolute_delay = 0`

Save this file as `DEBUG-COMMANDS.md` for quick reference when troubleshooting your ClickHouse cluster.