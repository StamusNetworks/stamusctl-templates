#!/bin/bash
# Create Scirius API token for LibreChat MCP access

set -e
set -o pipefail

export PYTHONUNBUFFERED=1

SCIRIUS_URL="${SCIRIUS_URL:-http://scirius:8000}"
SCIRIUS_USER="${SCIRIUS_USER:-selks-user}"
TOKEN_FILE="${TOKEN_FILE:-/shared/scirius-token}"

echo "======================================="
echo "Scirius API Token Generation"
echo "======================================="

# Wait for Scirius to be ready
echo "Waiting for Scirius to be available..."
max_retries=60
retry_count=0
while [ $retry_count -lt $max_retries ]; do
    if curl -s -f "$SCIRIUS_URL" > /dev/null 2>&1; then
        echo "Scirius is ready!"
        break
    fi
    retry_count=$((retry_count + 1))
    if [ $retry_count -eq $max_retries ]; then
        echo "ERROR: Scirius did not become ready in time"
        exit 1
    fi
    echo "Waiting for Scirius... ($retry_count/$max_retries)"
    sleep 5
done

# Find where manage.py is located
if [ -f "/opt/scirius/manage.py" ]; then
    SCIRIUS_DIR="/opt/scirius"
elif [ -f "/code/manage.py" ]; then
    SCIRIUS_DIR="/code"
else
    echo "ERROR: Could not find manage.py"
    exit 1
fi

echo "Found Scirius at: $SCIRIUS_DIR"
cd "$SCIRIUS_DIR"

# Create Python script to get/create token
echo "Getting or creating API token for user: $SCIRIUS_USER"

cat > /tmp/get_token.py << 'PYEOF'
from django.contrib.auth.models import User
from rest_framework.authtoken.models import Token
import sys

try:
    user = User.objects.get(username='__USERNAME__')
    token, created = Token.objects.get_or_create(user=user)
    if created:
        print(f"Created new token for user: __USERNAME__", file=sys.stderr)
    else:
        print(f"Retrieved existing token for user: __USERNAME__", file=sys.stderr)
    print(token.key)
    sys.exit(0)
except User.DoesNotExist:
    print("ERROR: User '__USERNAME__' does not exist", file=sys.stderr)
    sys.exit(1)
except Exception as e:
    print(f"ERROR: {type(e).__name__}: {e}", file=sys.stderr)
    import traceback
    traceback.print_exc()
    sys.exit(1)
PYEOF

# Replace username placeholder
sed -i "s/__USERNAME__/$SCIRIUS_USER/g" /tmp/get_token.py

# Execute and capture token
set +e
TOKEN_OUTPUT=$(python manage.py shell < /tmp/get_token.py 2>&1)
TOKEN_EXIT_CODE=$?
set -e

rm -f /tmp/get_token.py

if [ $TOKEN_EXIT_CODE -ne 0 ]; then
    echo "ERROR: Failed to get API token (exit code: $TOKEN_EXIT_CODE)"
    echo "Output:"
    echo "$TOKEN_OUTPUT"
    exit 1
fi

TOKEN=$(echo "$TOKEN_OUTPUT" | tail -n 1)

if [ -z "$TOKEN" ]; then
    echo "ERROR: Failed to get API token - empty token returned"
    exit 1
fi

# Write token to shared volume
mkdir -p "$(dirname "$TOKEN_FILE")"
echo -n "$TOKEN" > "$TOKEN_FILE"
chmod 644 "$TOKEN_FILE"

echo "======================================="
echo "✅ Token created successfully!"
echo "Token file: $TOKEN_FILE"
echo "Token: ${TOKEN:0:8}...${TOKEN: -8}"
echo "======================================="
echo ""
echo "LibreChat can now access Scirius MCP with this token"
