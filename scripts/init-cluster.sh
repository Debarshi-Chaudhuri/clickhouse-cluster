#!/bin/bash

echo "=========================================="
echo "ClickHouse Cluster Setup and Test"
echo "=========================================="

echo "1. Testing basic connectivity..."
echo "Node 1:"
curl -k -s -X POST "https://localhost:9001/" -d "SELECT 1"
echo ""
echo "Node 2:"
curl -k -s -X POST "https://localhost:9011/" -d "SELECT 1"
echo ""
echo "Node 3:"
curl -k -s -X POST "https://localhost:9021/" -d "SELECT 1"
echo ""

echo "2. Testing cluster configuration..."
curl -k -s -X POST "https://localhost:9001/" -d "SELECT count() FROM system.clusters WHERE cluster = 'local_cluster'"
echo ""

echo "3. Testing Keeper connectivity..."
curl -k -s -X POST "https://localhost:9001/" -d "SELECT count() FROM system.zookeeper WHERE path = '/'"
echo ""

echo "4. Creating database on cluster..."
curl -k -s -X POST "https://localhost:9001/" -d "CREATE DATABASE IF NOT EXISTS one_pice_dev ON CLUSTER local_cluster"
echo ""

echo "5. Creating replicated table..."
curl -k -s -X POST "https://localhost:9001/" -d "CREATE TABLE IF NOT EXISTS one_pice_dev.events ON CLUSTER local_cluster (event_time DateTime, user_id UInt32, event_type String) ENGINE = ReplicatedMergeTree('/clickhouse/tables/{shard}/events', '{replica}') ORDER BY (event_time, user_id) PARTITION BY toYYYYMM(event_time)"
echo ""

echo "6. Inserting test data..."
curl -k -s -X POST "https://localhost:9001/" -d "INSERT INTO one_pice_dev.events VALUES ('2024-01-01 10:00:00', 1001, 'login'), ('2024-01-01 10:05:00', 1002, 'page_view'), ('2024-01-01 10:10:00', 1001, 'purchase')"
echo ""

echo "7. Waiting for replication..."
sleep 10

echo "8. Testing replication - checking data on all nodes..."
echo "Node 1 data count:"
curl -k -s -X POST "https://localhost:9001/" -d "SELECT hostName(), count() FROM one_pice_dev.events"
echo ""
echo "Node 2 data count:"
curl -k -s -X POST "https://localhost:9011/" -d "SELECT hostName(), count() FROM one_pice_dev.events"
echo ""
echo "Node 3 data count:"
curl -k -s -X POST "https://localhost:9021/" -d "SELECT hostName(), count() FROM one_pice_dev.events"
echo ""

echo "9. Testing new data insertion and replication..."
curl -k -s -X POST "https://localhost:9001/" -d "INSERT INTO one_pice_dev.events VALUES ('2024-01-01 11:00:00', 2001, 'test_replication')"
echo ""
sleep 5

echo "10. Final replication check..."
echo "Node 1 final count:"
curl -k -s -X POST "https://localhost:9001/" -d "SELECT hostName(), count() FROM one_pice_dev.events"
echo ""
echo "Node 2 final count:"
curl -k -s -X POST "https://localhost:9011/" -d "SELECT hostName(), count() FROM one_pice_dev.events"
echo ""
echo "Node 3 final count:"
curl -k -s -X POST "https://localhost:9021/" -d "SELECT hostName(), count() FROM one_pice_dev.events"
echo ""

echo "=========================================="
echo "Setup completed!"
echo "If all nodes show the same count, replication is working!"
echo "=========================================="