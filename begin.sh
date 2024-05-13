
#!/bin/bash

#----# Configure script #----#

# Stops the execution of the script on any error encountered.
set -e

# Prints each command to stdout before execution; useful for debugging.
set -x

#----# Generate certs #----#

## Generate cert & key pairs to enable SSL for Keycloak

# Ensure the SSL certificates directory exists, create if missing
CERT_DIR="./certs"
if [ ! -d "$CERT_DIR" ]; then
    mkdir -p "$CERT_DIR"
fi

# Check and generate SSL certificates for Keycloak if they don't exist
if [ ! -f "$CERT_DIR/keycloak.crt" ] || [ ! -f "$CERT_DIR/keycloak.key" ]; then
    echo "Generating SSL certificates for Keycloak..."
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout "$CERT_DIR/keycloak.key" -out "$CERT_DIR/keycloak.crt" -subj "/CN=keycloak.local"
fi

# Set permissions for certificate files to ensure they are readable (too much permissions given for certs, adjust later)
chmod 644 "$CERT_DIR/keycloak.crt"
chmod 644 "$CERT_DIR/keycloak.key"

#----# Build and deploy Keycloak #----#

# Deploy Keycloak DB

echo "Starting the detahced Keycloak database container..."
docker compose up -d keycloak-db

echo "Waiting for Keycloak database to be ready..." # Uses a simple delay
until docker compose exec keycloak-db pg_isready --timeout=0 --dbname=${KEYCLOAK_DB}; do
    sleep 10
done

# Deploy Keycloak

echo "Starting the detached Keycloak service..."
docker compose up -d keycloak

# Configure Keycloak

# Call the Keycloak setup script to configure Keycloak
echo "Configuring Keycloak..."
./configure-keycloak.sh

echo "Keycloak is configured and running!"
