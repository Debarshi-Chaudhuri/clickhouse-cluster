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

echo "Generating unified SSL certificates for local ClickHouse cluster..."

# =============================================================================
# 1. GENERATE CA PRIVATE KEY AND CERTIFICATE
# =============================================================================
echo "Creating Certificate Authority (CA)..."

# Generate CA private key
openssl genrsa -out "$CERT_DIR/ca.key" 4096

# Create CA configuration file
cat > "$CERT_DIR/ca.conf" <<EOF
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_ca
prompt = no

[req_distinguished_name]
C = $COUNTRY
ST = $STATE
L = $CITY
O = $ORG
OU = $ORG_UNIT
CN = ClickHouse-CA

[v3_ca]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = critical,CA:true
keyUsage = critical,digitalSignature,cRLSign,keyCertSign
EOF

# Generate CA certificate
openssl req -new -x509 -days 365 -key "$CERT_DIR/ca.key" -out "$CERT_DIR/ca.crt" -config "$CERT_DIR/ca.conf"

echo "✅ CA certificate created"

# =============================================================================
# 2. GENERATE UNIFIED SERVICE CERTIFICATE (for both ClickHouse and Keeper)
# =============================================================================
echo "Creating unified certificate for both ClickHouse and Keeper..."

# Create unified certificate configuration for both ClickHouse and Keeper
cat > "$CERT_DIR/unified-service.conf" <<EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
C = $COUNTRY
ST = $STATE
L = $CITY
O = $ORG
OU = $ORG_UNIT
CN = clickhouse-service

[v3_req]
subjectKeyIdentifier = hash
basicConstraints = CA:FALSE
keyUsage = critical,digitalSignature,keyEncipherment,keyAgreement
extendedKeyUsage = critical,serverAuth,clientAuth
subjectAltName = @unified_alt_names

[unified_alt_names]
# ClickHouse service hostnames
DNS.1 = clickhouse-1
DNS.2 = clickhouse-2
DNS.3 = clickhouse-3
DNS.4 = clickhouse-server

# Keeper service hostnames  
DNS.5 = keeper-1
DNS.6 = keeper-2
DNS.7 = keeper-3
DNS.8 = clickhouse-keeper

# Generic service names
DNS.9 = localhost
DNS.10 = local

# IP addresses
IP.1 = 127.0.0.1
IP.2 = ::1
IP.3 = 10.0.0.1
IP.4 = 172.16.0.1
IP.5 = 192.168.0.1
EOF

# Generate unified private key
openssl genrsa -out "$CERT_DIR/unified-service.key" 4096

# Generate unified certificate signing request
openssl req -new -key "$CERT_DIR/unified-service.key" -out "$CERT_DIR/unified-service.csr" -config "$CERT_DIR/unified-service.conf"

# Generate unified certificate
openssl x509 -req -in "$CERT_DIR/unified-service.csr" -CA "$CERT_DIR/ca.crt" -CAkey "$CERT_DIR/ca.key" -CAcreateserial -out "$CERT_DIR/unified-service.crt" -days 365 -extensions v3_req -extfile "$CERT_DIR/unified-service.conf"

echo "✅ Unified certificate created"

# =============================================================================
# 3. CREATE SYMLINKS FOR BACKWARD COMPATIBILITY
# =============================================================================
echo "Creating symlinks for backward compatibility..."

# Remove old certificates if they exist
rm -f "$CERT_DIR/clickhouse-server.crt" "$CERT_DIR/clickhouse-server.key"
rm -f "$CERT_DIR/keeper.crt" "$CERT_DIR/keeper.key"

# Create symlinks for backward compatibility
ln -sf unified-service.crt "$CERT_DIR/clickhouse-server.crt"
ln -sf unified-service.key "$CERT_DIR/clickhouse-server.key"
ln -sf unified-service.crt "$CERT_DIR/keeper.crt"
ln -sf unified-service.key "$CERT_DIR/keeper.key"

echo "✅ Symlinks created"

# =============================================================================
# 4. CLEANUP AND PERMISSIONS
# =============================================================================
echo "Cleaning up temporary files and setting permissions..."

# Clean up CSR and config files
rm -f "$CERT_DIR"/*.csr "$CERT_DIR"/*.conf

# Set proper permissions
chmod 600 "$CERT_DIR"/*.key
chmod 644 "$CERT_DIR"/*.crt

echo ""
echo "🎉 Unified SSL certificates generated successfully in $CERT_DIR"
echo ""
echo "Generated files:"
echo "  - ca.crt (Certificate Authority)"
echo "  - ca.key (CA Private Key)"
echo "  - unified-service.crt (Unified Certificate for both services)"
echo "  - unified-service.key (Unified Private Key)"
echo "  - clickhouse-server.crt -> unified-service.crt (symlink)"
echo "  - clickhouse-server.key -> unified-service.key (symlink)"
echo "  - keeper.crt -> unified-service.crt (symlink)"
echo "  - keeper.key -> unified-service.key (symlink)"
echo ""

# =============================================================================
# 5. CERTIFICATE VERIFICATION
# =============================================================================
echo "🔍 Verifying certificate quality..."

echo "Unified Certificate Details:"
openssl x509 -in "$CERT_DIR/unified-service.crt" -text -noout | grep -A 15 "Subject Alternative Name" || echo "  ⚠️  No SAN found"

echo ""
echo "Certificate chain verification:"
if openssl verify -CAfile "$CERT_DIR/ca.crt" "$CERT_DIR/unified-service.crt" >/dev/null 2>&1; then
    echo "✅ Unified certificate chain is valid"
else
    echo "❌ Unified certificate chain is invalid"
fi

echo ""
echo "🔒 Unified certificate created successfully!"
echo "   Both ClickHouse and Keeper will use the same certificate"
echo "   This should work with strict SSL validation (AcceptCertificateHandler)"