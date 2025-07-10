#!/bin/bash
set -e

echo "Starting ClickHouse configuration processing..."

# Create config.d directory if it doesn't exist
mkdir -p /etc/clickhouse-server/config.d

# ClickHouse-specific template directory
TEMPLATE_DIR="/etc/clickhouse-server/templates"
CONFIG_DIR="/etc/clickhouse-server/config.d"

# Function to substitute environment variables in template files
substitute_template() {
    local template_file="$1"
    local output_file="$2"
    
    echo "Processing template: $template_file -> $output_file"
    
    # Use sed to substitute environment variables (works without envsubst)
    sed 's/\${CLICKHOUSE_SERVER_ID}/'"$CLICKHOUSE_SERVER_ID"'/g; 
         s/\${INSTANCE_NAME}/'"$INSTANCE_NAME"'/g;
         s/\${INTERSERVER_HOST}/'"$INTERSERVER_HOST"'/g;
         s/\${CLUSTER_NAME}/'"$CLUSTER_NAME"'/g;
         s/\${DEFAULT_DATABASE}/'"$DEFAULT_DATABASE"'/g;
         s/\${HTTPS_PORT}/'"${HTTPS_PORT:-9001}"'/g;
         s/\${TCP_SECURE_PORT}/'"${TCP_SECURE_PORT:-9002}"'/g;
         s/\${POSTGRESQL_PORT}/'"${POSTGRESQL_PORT:-9003}"'/g;
         s/\${INTERSERVER_HTTPS_PORT}/'"${INTERSERVER_HTTPS_PORT:-9010}"'/g;
         s/\${GRPC_SECURE_PORT}/'"${GRPC_SECURE_PORT:-9100}"'/g;
         s/\${PROMETHEUS_PORT}/'"${PROMETHEUS_PORT:-9363}"'/g;
         s/\${INTERSERVER_USER}/'"${INTERSERVER_USER:-interserver}"'/g;
         s/\${LOG_LEVEL}/'"${LOG_LEVEL:-information}"'/g;
         s/\${CONSOLE_LOG_LEVEL}/'"${CONSOLE_LOG_LEVEL:-warning}"'/g;
         s/\${QUERY_LOG_ENABLED}/'"${QUERY_LOG_ENABLED:-true}"'/g;
         s/\${QUERY_THREAD_LOG_ENABLED}/'"${QUERY_THREAD_LOG_ENABLED:-false}"'/g;
         s/\${PART_LOG_ENABLED}/'"${PART_LOG_ENABLED:-true}"'/g;
         s/\${METRIC_LOG_ENABLED}/'"${METRIC_LOG_ENABLED:-false}"'/g;
         s/\${TRACE_LOG_ENABLED}/'"${TRACE_LOG_ENABLED:-false}"'/g;
         s/\${SESSION_LOG_ENABLED}/'"${SESSION_LOG_ENABLED:-true}"'/g;
         s/\${SYSLOG_ENABLED}/'"${SYSLOG_ENABLED:-false}"'/g;
         s/\${QUERY_LOG_SAMPLE_RATE}/'"${QUERY_LOG_SAMPLE_RATE:-1}"'/g;
         s/\${TRACE_LOG_SAMPLE_RATE}/'"${TRACE_LOG_SAMPLE_RATE:-1000}"'/g;
         s/\${TEXT_LOG_ENABLED}/'"${TEXT_LOG_ENABLED:-true}"'/g;
         s/\${MAX_SERVER_MEMORY}/'"${MAX_SERVER_MEMORY:-0}"'/g;
         s/\${MAX_MEMORY_RATIO}/'"${MAX_MEMORY_RATIO:-0.8}"'/g;
         s/\${MEMORY_OVERCOMMIT_DENOMINATOR}/'"${MEMORY_OVERCOMMIT_DENOMINATOR:-1073741824}"'/g;
         s/\${MAX_CONNECTIONS}/'"${MAX_CONNECTIONS:-2048}"'/g;
         s/\${MAX_CONCURRENT_QUERIES}/'"${MAX_CONCURRENT_QUERIES:-500}"'/g;
         s/\${MAX_CONCURRENT_SELECT}/'"${MAX_CONCURRENT_SELECT:-400}"'/g;
         s/\${MAX_CONCURRENT_INSERT}/'"${MAX_CONCURRENT_INSERT:-100}"'/g;
         s/\${UNCOMPRESSED_CACHE_SIZE}/'"${UNCOMPRESSED_CACHE_SIZE:-8589934592}"'/g;
         s/\${MARK_CACHE_SIZE}/'"${MARK_CACHE_SIZE:-5368709120}"'/g;
         s/\${INDEX_CACHE_SIZE}/'"${INDEX_CACHE_SIZE:-1073741824}"'/g;
         s/\${MMAP_CACHE_SIZE}/'"${MMAP_CACHE_SIZE:-1000}"'/g;
         s/\${BACKGROUND_POOL_SIZE}/'"${BACKGROUND_POOL_SIZE:-16}"'/g;
         s/\${BACKGROUND_CONCURRENCY_RATIO}/'"${BACKGROUND_CONCURRENCY_RATIO:-2}"'/g;
         s/\${BACKGROUND_SCHEDULE_POOL}/'"${BACKGROUND_SCHEDULE_POOL:-16}"'/g;
         s/\${BACKGROUND_FETCHES_POOL}/'"${BACKGROUND_FETCHES_POOL:-8}"'/g;
         s/\${BACKGROUND_MOVE_POOL}/'"${BACKGROUND_MOVE_POOL:-8}"'/g;
         s/\${BACKGROUND_COMMON_POOL}/'"${BACKGROUND_COMMON_POOL:-8}"'/g;
         s/\${MAX_EXECUTION_TIME}/'"${MAX_EXECUTION_TIME:-1800}"'/g;
         s/\${MAX_QUERY_SIZE}/'"${MAX_QUERY_SIZE:-268435456}"'/g;
         s/\${MAX_OPEN_FILES}/'"${MAX_OPEN_FILES:-262144}"'/g;
         s/\${DISTRIBUTED_POOL_SIZE}/'"${DISTRIBUTED_POOL_SIZE:-1024}"'/g;
         s/\${EXTERNAL_GROUP_BY_BYTES}/'"${EXTERNAL_GROUP_BY_BYTES:-20000000000}"'/g;
         s/\${EXTERNAL_SORT_BYTES}/'"${EXTERNAL_SORT_BYTES:-20000000000}"'/g;
         s/\${MAX_THREADS}/'"${MAX_THREADS:-0}"'/g;
         s/\${TIMEZONE}/'"${TIMEZONE:-UTC}"'/g;
         s/\${KEEP_ALIVE_TIMEOUT}/'"${KEEP_ALIVE_TIMEOUT:-10}"'/g;
         s/\${USER_MAX_EXECUTION_TIME}/'"${USER_MAX_EXECUTION_TIME:-1800}"'/g;
         s/\${COMPRESSION_METHOD}/'"${COMPRESSION_METHOD:-lz4}"'/g;
         s/\${COMPRESSION_LEVEL}/'"${COMPRESSION_LEVEL:-1}"'/g;
         s/\${NETWORK_COMPRESSION}/'"${NETWORK_COMPRESSION:-lz4}"'/g;
         s/\${S3_ENDPOINT}/'"${S3_ENDPOINT:-}"'/g;
         s/\${S3_ACCESS_KEY}/'"${S3_ACCESS_KEY:-}"'/g;
         s/\${S3_SECRET_KEY}/'"${S3_SECRET_KEY:-}"'/g;
         s/\${S3_BUCKET_NAME}/'"${S3_BUCKET_NAME:-}"'/g;
         s/\${S3_REGION}/'"${S3_REGION:-}"'/g' \
    "$template_file" > "$output_file"
    
    # Set proper permissions
    chmod 644 "$output_file"
}

# Process all ClickHouse template files dynamically
if [ -d "$TEMPLATE_DIR" ]; then
    echo "Processing ClickHouse configuration templates..."
    
    # Find all .xml files and process them as templates
    template_count=0
    for template_file in "$TEMPLATE_DIR"/*.xml; do
        # Check if file exists (handles case where no .xml files exist)
        if [ -f "$template_file" ]; then
            # Get the base filename 
            base_name=$(basename "$template_file")
            output_file="$CONFIG_DIR/$base_name"
            
            substitute_template "$template_file" "$output_file"
            template_count=$((template_count + 1))
        fi
    done
    
    # Also process any subdirectories with templates
    for subdir in "$TEMPLATE_DIR"/*/; do
        if [ -d "$subdir" ]; then
            subdir_name=$(basename "$subdir")
            mkdir -p "$CONFIG_DIR/$subdir_name"
            
            for template_file in "$subdir"*.xml; do
                if [ -f "$template_file" ]; then
                    base_name=$(basename "$template_file")
                    output_file="$CONFIG_DIR/$subdir_name/$base_name"
                    
                    substitute_template "$template_file" "$output_file"
                    template_count=$((template_count + 1))
                fi
            done
        fi
    done
    
    if [ $template_count -eq 0 ]; then
        echo "Warning: No .xml files found in $TEMPLATE_DIR"
    else
        echo "Successfully processed $template_count configuration template(s)!"
    fi
else
    echo "Warning: Template directory $TEMPLATE_DIR not found"
fi

# Validate required environment variables
echo "Validating environment variables..."

required_vars=(
    "CLICKHOUSE_SERVER_ID"
    "INSTANCE_NAME" 
    "INTERSERVER_HOST"
    "CLUSTER_NAME"
    "DEFAULT_DATABASE"
)

for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        echo "Error: Required environment variable $var is not set"
        exit 1
    fi
done

echo "Environment variables validated successfully!"

# Print configuration summary
echo "=== ClickHouse Configuration Summary ==="
echo "Server ID: $CLICKHOUSE_SERVER_ID"
echo "Instance Name: $INSTANCE_NAME"
echo "Interserver Host: $INTERSERVER_HOST"
echo "========================================"

# Wait for Keeper services to be ready (hardcoded keeper nodes)
echo "Waiting for ClickHouse Keeper services to be ready..."

# Hardcoded keeper nodes (matching our templates)
keeper_nodes=("keeper-1:2181" "keeper-2:2181" "keeper-3:2181")

for keeper in "${keeper_nodes[@]}"; do
    keeper_host=$(echo "$keeper" | cut -d':' -f1)
    keeper_port=$(echo "$keeper" | cut -d':' -f2)
    
    echo "Checking connectivity to $keeper_host:$keeper_port..."
    
    # Wait up to 60 seconds for each keeper
    timeout=60
    while ! nc -z "$keeper_host" "$keeper_port" 2>/dev/null; do
        if [ $timeout -le 0 ]; then
            echo "Warning: Could not connect to $keeper_host:$keeper_port after 60 seconds"
            break
        fi
        echo "Waiting for $keeper_host:$keeper_port... ($timeout seconds remaining)"
        sleep 2
        timeout=$((timeout - 2))
    done
    
    if nc -z "$keeper_host" "$keeper_port" 2>/dev/null; then
        echo "Successfully connected to $keeper_host:$keeper_port"
    fi
done

echo "Keeper connectivity check completed."

# Display generated configuration files (for debugging)
echo "Generated configuration files:"
ls -la $CONFIG_DIR/

# Start ClickHouse server
echo "Starting ClickHouse server..."
exec /entrypoint.sh "$@"