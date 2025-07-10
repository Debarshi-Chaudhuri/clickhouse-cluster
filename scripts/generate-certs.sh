#!/bin/bash

# Create local SSL directory if it doesn't exist
mkdir -p ./secrets/ssl/local

# Set certificate directory
CERT_DIR="./secrets/ssl/local"

# Certificate configuration
COUNTRY="US"
STATE="Local"
CITY="Development"
ORG="ClickHouse Local"
ORG_UNIT="Development"
COMMON_NAME="clickhouse-local"

echo "Generating SSL certificates for local ClickHouse cluster..."

# Generate CA private key
openssl genrsa -out "$CERT_DIR/ca.key" 4096

# Generate CA certificate
openssl req -new -x509 -days 365 -key "$CERT_DIR/ca.key" -out "$CERT_DIR/ca.crt" -subj "/C=$COUNTRY/ST=$STATE/L=$CITY/O=$ORG/OU=$ORG_UNIT/CN=ClickHouse-CA"

# Generate ClickHouse server private key
openssl genrsa -out "$CERT_DIR/clickhouse-server.key" 4096

# Generate ClickHouse server certificate signing request
openssl req -new -key "$CERT_DIR/clickhouse-server.key" -out "$CERT_DIR/clickhouse-server.csr" -subj "/C=$COUNTRY/ST=$STATE/L=$CITY/O=$ORG/OU=$ORG_UNIT/CN=clickhouse-server"

# Generate ClickHouse server certificate
openssl x509 -req -in "$CERT_DIR/clickhouse-server.csr" -CA "$CERT_DIR/ca.crt" -CAkey "$CERT_DIR/ca.key" -CAcreateserial -out "$CERT_DIR/clickhouse-server.crt" -days 365

# Generate Keeper private key
openssl genrsa -out "$CERT_DIR/keeper.key" 4096

# Generate Keeper certificate signing request
openssl req -new -key "$CERT_DIR/keeper.key" -out "$CERT_DIR/keeper.csr" -subj "/C=$COUNTRY/ST=$STATE/L=$CITY/O=$ORG/OU=$ORG_UNIT/CN=clickhouse-keeper"

# Generate Keeper certificate
openssl x509 -req -in "$CERT_DIR/keeper.csr" -CA "$CERT_DIR/ca.crt" -CAkey "$CERT_DIR/ca.key" -CAcreateserial -out "$CERT_DIR/keeper.crt" -days 365

# Clean up CSR files
rm "$CERT_DIR/clickhouse-server.csr" "$CERT_DIR/keeper.csr"

# Set proper permissions
chmod 600 "$CERT_DIR"/*.key
chmod 644 "$CERT_DIR"/*.crt

echo "SSL certificates generated successfully in $CERT_DIR"
echo "Generated files:"
echo "  - ca.crt (Certificate Authority)"
echo "  - ca.key (CA Private Key)"
echo "  - clickhouse-server.crt (ClickHouse Server Certificate)"
echo "  - clickhouse-server.key (ClickHouse Server Private Key)"
echo "  - keeper.crt (Keeper Certificate)"
echo "  - keeper.key (Keeper Private Key)"