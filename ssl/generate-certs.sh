#!/bin/bash
# SSL Certificate Generator for VerneMQ MQTT TLS
# This script generates self-signed certificates for development/testing
# For production, use certificates from a trusted CA (e.g., Let's Encrypt)

set -e

SSL_DIR="$(dirname "$0")"
cd "$SSL_DIR"

# Configuration
DAYS=365
COUNTRY="ID"
STATE="DKI Jakarta"
LOCALITY="Jakarta"
ORGANIZATION="VerneMQ Development"
COMMON_NAME="vernemq.local"

echo "========================================="
echo "VerneMQ SSL Certificate Generator"
echo "========================================="
echo ""

# Create CA (Certificate Authority)
echo "1. Creating CA private key..."
openssl genrsa -out ca.key 4096

echo "2. Creating CA certificate..."
openssl req -new -x509 -days $DAYS -key ca.key -out ca.crt \
    -subj "/C=$COUNTRY/ST=$STATE/L=$LOCALITY/O=$ORGANIZATION/CN=VerneMQ CA"

# Create Server Certificate
echo "3. Creating server private key..."
openssl genrsa -out server.key 4096

echo "4. Creating server certificate signing request..."
openssl req -new -key server.key -out server.csr \
    -subj "/C=$COUNTRY/ST=$STATE/L=$LOCALITY/O=$ORGANIZATION/CN=$COMMON_NAME"

# Create extensions file for SAN (Subject Alternative Names)
cat > server_ext.cnf << EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = vernemq.local
DNS.2 = vernemq
DNS.3 = localhost
IP.1 = 127.0.0.1
IP.2 = ::1
EOF

echo "5. Creating server certificate..."
openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
    -out server.crt -days $DAYS -extfile server_ext.cnf

# Clean up temporary files
rm -f server.csr server_ext.cnf ca.srl

# Set appropriate permissions
chmod 644 ca.crt server.crt
chmod 600 ca.key server.key

echo ""
echo "========================================="
echo "SSL Certificates Generated Successfully!"
echo "========================================="
echo ""
echo "Files created:"
echo "  - ca.crt      : CA certificate (share with clients)"
echo "  - ca.key      : CA private key (keep secure)"
echo "  - server.crt  : Server certificate"
echo "  - server.key  : Server private key"
echo ""
echo "Next steps:"
echo "1. In docker-compose.yml, uncomment the SSL configuration lines"
echo "2. Restart the containers: docker-compose up -d"
echo "3. Test TLS connection: mosquitto_pub -h localhost -p 8883 --cafile ssl/ca.crt -t test -m 'hello' --tls-version tlsv1.2"
echo ""
echo "For production, use certificates from a trusted CA!"
echo ""
