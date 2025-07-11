#!/bin/bash
set -e

echo "Starting ClickHouse Keeper configuration processing..."

# Create keeper config directories
mkdir -p /etc/clickhouse-keeper
mkdir -p /etc/clickhouse-keeper/keeper_config.d

# Keeper-specific template directory - UPDATED PATH
TEMPLATE_DIR="/etc/clickhouse-keeper/templates"
CONFIG_DIR="/etc/clickhouse-keeper/keeper_config.d"

# Function to substitute environment variables in template files
substitute_template() {
    local template_file="$1"
    local output_file="$2"
    
    echo "Processing template: $template_file -> $output_file"
    
    # Use sed to substitute environment variables (works without envsubst)
    sed 's/\${KEEPER_SERVER_ID}/'"$KEEPER_SERVER_ID"'/g; 
         s/\${INSTANCE_NAME}/'"$INSTANCE_NAME"'/g;
         s/\${LOG_LEVEL}/'"${LOG_LEVEL:-information}"'/g;
         s/\${CONSOLE_LOG_LEVEL}/'"${CONSOLE_LOG_LEVEL:-warning}"'/g;
         s/\${TIMEZONE}/'"${TIMEZONE:-UTC}"'/g' \
    "$template_file" > "$output_file"
    
    # Set proper permissions
    chmod 644 "$output_file"
}

# Create main config.xml (minimal - loads keeper_config.d automatically)
echo "Creating main config.xml..."
cat > /etc/clickhouse-keeper/keeper_config.xml <<EOF
<?xml version="1.0"?>
<clickhouse>
    <!-- Main ClickHouse Keeper configuration -->
    <!-- Additional configurations are auto-loaded from keeper_config.d/ -->
    <logger>
        <level>${LOG_LEVEL:-information}</level>
        <console>true</console>
    </logger>
    
    <listen_host>0.0.0.0</listen_host>
</clickhouse>
EOF
chmod 644 /etc/clickhouse-keeper/keeper_config.xml
echo "✅ Main config.xml created"

# Process templates from both templates and local directories
TEMPLATES_DIR="/etc/clickhouse-keeper/templates"
LOCAL_DIR="/etc/clickhouse-keeper/local"

total_template_count=0

# Process templates from templates directory
if [ -d "$TEMPLATES_DIR" ]; then
    echo "Processing ClickHouse Keeper configuration templates from templates directory..."
    
    template_count=0
    for template_file in "$TEMPLATES_DIR"/*.xml; do
        if [ -f "$template_file" ]; then
            base_name=$(basename "$template_file")
            output_file="$CONFIG_DIR/$base_name"
            
            substitute_template "$template_file" "$output_file"
            template_count=$((template_count + 1))
            echo "   Processed from templates: $base_name"
        fi
    done
    
    total_template_count=$((total_template_count + template_count))
    echo "Successfully processed $template_count template(s) from templates directory!"
else
    echo "Warning: Templates directory $TEMPLATES_DIR not found"
fi

# Process templates from local directory  
if [ -d "$LOCAL_DIR" ]; then
    echo "Processing ClickHouse Keeper configuration templates from local directory..."
    
    local_count=0
    for template_file in "$LOCAL_DIR"/*.xml; do
        if [ -f "$template_file" ]; then
            base_name=$(basename "$template_file")
            output_file="$CONFIG_DIR/$base_name"
            
            substitute_template "$template_file" "$output_file"
            local_count=$((local_count + 1))
            echo "   Processed from local: $base_name"
        fi
    done
    
    total_template_count=$((total_template_count + local_count))
    echo "Successfully processed $local_count template(s) from local directory!"
else
    echo "Warning: Local directory $LOCAL_DIR not found"
fi

# Process any subdirectories in templates directory
if [ -d "$TEMPLATES_DIR" ]; then
    for subdir in "$TEMPLATES_DIR"/*/; do
        if [ -d "$subdir" ]; then
            subdir_name=$(basename "$subdir")
            mkdir -p "$CONFIG_DIR/$subdir_name"
            
            echo "Processing subdirectory: $subdir_name"
            for template_file in "$subdir"*.xml; do
                if [ -f "$template_file" ]; then
                    base_name=$(basename "$template_file")
                    output_file="$CONFIG_DIR/$subdir_name/$base_name"
                    
                    substitute_template "$template_file" "$output_file"
                    total_template_count=$((total_template_count + 1))
                    echo "   Processed from $subdir_name: $base_name"
                fi
            done
        fi
    done
fi

if [ $total_template_count -eq 0 ]; then
    echo "Warning: No .xml files found in any template directories"
    echo "Checked directories:"
    echo "  - $TEMPLATES_DIR"
    echo "  - $LOCAL_DIR"
else
    echo "Successfully processed $total_template_count Keeper configuration template(s) total!"
fi

# Validate required environment variables for Keeper
echo "Validating Keeper environment variables..."

required_vars=(
    "KEEPER_SERVER_ID"
    "INSTANCE_NAME"
)

for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        echo "Error: Required environment variable $var is not set"
        exit 1
    fi
done

echo "Keeper environment variables validated successfully!"

# Print Keeper configuration summary
echo "=== ClickHouse Keeper Configuration Summary ==="
echo "Keeper Server ID: $KEEPER_SERVER_ID"
echo "Instance Name: $INSTANCE_NAME"
echo "Log Level: ${LOG_LEVEL:-information}"
echo "Console Log Level: ${CONSOLE_LOG_LEVEL:-warning}"
echo "Timezone: ${TIMEZONE:-UTC}"
echo "================================================="

# Validate Keeper Server ID is within valid range (1-255)
if [ "$KEEPER_SERVER_ID" -lt 1 ] || [ "$KEEPER_SERVER_ID" -gt 255 ]; then
    echo "Error: KEEPER_SERVER_ID must be between 1 and 255, got: $KEEPER_SERVER_ID"
    exit 1
fi

# Create necessary directories for Keeper
echo "Creating Keeper directories..."
mkdir -p /var/lib/clickhouse-keeper/coordination/log
mkdir -p /var/lib/clickhouse-keeper/coordination/snapshots
mkdir -p /var/log/clickhouse-keeper
mkdir -p /var/run/clickhouse-keeper

# Set proper permissions for Keeper directories (running as root)
echo "Setting Keeper directory permissions..."

# Data directory - CRITICAL, must be writable
if ! chown -R root:root /var/lib/clickhouse-keeper; then
    echo "ERROR: Cannot change ownership of data directory /var/lib/clickhouse-keeper"
    echo "This is critical for Keeper operation. Check volume mounts and permissions."
    exit 1
fi
echo "✅ Data directory permissions set successfully"

# Log directory - CRITICAL, must be writable  
if ! chown -R root:root /var/log/clickhouse-keeper; then
    echo "ERROR: Cannot change ownership of log directory /var/log/clickhouse-keeper"
    echo "This is critical for Keeper logging. Check volume mounts and permissions."
    exit 1
fi
echo "✅ Log directory permissions set successfully"

# PID directory - CRITICAL, must be writable
if ! chown -R root:root /var/run/clickhouse-keeper; then
    echo "ERROR: Cannot change ownership of PID directory /var/run/clickhouse-keeper"
    echo "This is critical for Keeper process management. Check permissions."
    exit 1
fi
echo "✅ PID directory permissions set successfully"

# Generated config files - IMPORTANT, should be writable
echo "Setting permissions on generated config files..."
config_files_processed=0
for config_file in /etc/clickhouse-keeper/keeper_config.d/*.xml; do
    if [ -f "$config_file" ]; then
        if [ -w "$config_file" ]; then
            if chown root:root "$config_file"; then
                echo "✅ Set ownership for $config_file"
                config_files_processed=$((config_files_processed + 1))
            else
                echo "⚠️  Warning: Could not change ownership of $config_file (but file exists)"
            fi
        else
            echo "ℹ️  Skipping read-only file: $config_file"
        fi
    fi
done

if [ $config_files_processed -eq 0 ]; then
    echo "⚠️  Warning: No writable config files found to set permissions on"
else
    echo "✅ Processed $config_files_processed config files in keeper_config.d/"
fi

# Test write access to critical directories
echo "Testing write access to critical directories..."

# Test data directory write access
if ! touch /var/lib/clickhouse-keeper/.write_test 2>/dev/null; then
    echo "ERROR: Cannot write to data directory /var/lib/clickhouse-keeper"
    echo "Keeper will not be able to store data. Check volume mounts and permissions."
    exit 1
fi
rm -f /var/lib/clickhouse-keeper/.write_test
echo "✅ Data directory write access confirmed"

# Test log directory write access
if ! touch /var/log/clickhouse-keeper/.write_test 2>/dev/null; then
    echo "ERROR: Cannot write to log directory /var/log/clickhouse-keeper"
    echo "Keeper will not be able to write logs. Check volume mounts and permissions."
    exit 1
fi
rm -f /var/log/clickhouse-keeper/.write_test
echo "✅ Log directory write access confirmed"

# Test PID directory write access
if ! touch /var/run/clickhouse-keeper/.write_test 2>/dev/null; then
    echo "ERROR: Cannot write to PID directory /var/run/clickhouse-keeper"
    echo "Keeper will not be able to write PID file. Check permissions."
    exit 1
fi
rm -f /var/run/clickhouse-keeper/.write_test
echo "✅ PID directory write access confirmed"

# Display generated configuration files (for debugging)
echo "Generated Keeper configuration files:"
echo "Main config:"
ls -la /etc/clickhouse-keeper/keeper_config.xml
echo "keeper_config.d/ files (auto-loaded):"
ls -la $CONFIG_DIR/ 2>/dev/null || echo "No files in keeper_config.d/"

# Check if the keeper config file exists in keeper_config.d (expect keeper-config.xml in keeper_config.d)
if [ ! -f "$CONFIG_DIR/keeper-config.xml" ]; then
    echo "Error: Keeper configuration file not found at $CONFIG_DIR/keeper-config.xml"
    echo "Make sure you have a keeper-config.xml file in the templates directory"
    echo "Template directory: $TEMPLATE_DIR"
    exit 1
fi

echo "Keeper configuration validation completed successfully!"

# Start ClickHouse Keeper with main config (auto-loads keeper_config.d/)
echo "Starting ClickHouse Keeper server..."
echo "Main config: /etc/clickhouse-keeper/keeper_config.xml"
echo "Additional configs auto-loaded from: /etc/clickhouse-keeper/keeper_config.d/"
exec clickhouse-keeper --config-file=/etc/clickhouse-keeper/keeper_config.xml --pid-file=/var/run/clickhouse-keeper/clickhouse-keeper.pid