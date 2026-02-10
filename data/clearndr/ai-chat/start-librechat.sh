#!/bin/sh
# LibreChat startup wrapper - waits for Scirius token, generates config, and starts LibreChat

set -e

TOKEN_FILE="/shared/scirius-token"
CONFIG_TEMPLATE="/app/librechat.yaml.template"
CONFIG_OUTPUT="/app/librechat.yaml"

echo "LibreChat starting..."
echo "Waiting for Scirius API token..."

# Wait for token file to be created
timeout=60
count=0
while [ ! -f "$TOKEN_FILE" ]; do
    count=$((count + 1))
    if [ $count -ge $timeout ]; then
        echo "WARNING: Scirius token not found after ${timeout}s"
        echo "Scirius MCP will use placeholder token"
        break
    fi
    sleep 1
done

# Read token or use placeholder
if [ -f "$TOKEN_FILE" ]; then
    SCIRIUS_TOKEN=$(cat "$TOKEN_FILE")
    echo "✅ Scirius token loaded"
    echo "Token: ${SCIRIUS_TOKEN:0:8}...${SCIRIUS_TOKEN: -8}"
else
    echo "⚠️  Scirius token not available, using placeholder"
    SCIRIUS_TOKEN="PLACEHOLDER_TOKEN"
fi

# Generate librechat.yaml from template
echo "Generating librechat.yaml from template..."
if [ -f "$CONFIG_TEMPLATE" ]; then
    # Use sed to replace __SCIRIUS_TOKEN__ with actual token
    sed "s/__SCIRIUS_TOKEN__/$SCIRIUS_TOKEN/g" "$CONFIG_TEMPLATE" > "$CONFIG_OUTPUT"
    echo "✅ Config generated successfully"
else
    echo "ERROR: Template file not found: $CONFIG_TEMPLATE"
    exit 1
fi

# Verify config was created
if [ ! -f "$CONFIG_OUTPUT" ]; then
    echo "ERROR: Failed to generate config file"
    exit 1
fi

# Start LibreChat with original entrypoint
echo "Starting LibreChat..."
exec /usr/local/bin/docker-entrypoint.sh npm run backend
