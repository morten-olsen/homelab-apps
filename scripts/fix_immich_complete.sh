#!/bin/bash
set -e

NAMESPACE="shared"
RELEASE_NAME="immich"

echo "=== Complete immich database password fix ==="
echo ""

# Step 1: Get PostgreSQL pod name
echo "Step 1: Finding PostgreSQL pod..."
POSTGRES_POD=$(kubectl get pods -n "$NAMESPACE" -l app="${RELEASE_NAME}-postgres" -o jsonpath='{.items[0].metadata.name}' 2>&1)
if [ -z "$POSTGRES_POD" ] || [[ "$POSTGRES_POD" == *"Error"* ]]; then
  echo "ERROR: Could not find PostgreSQL pod"
  echo "Output: $POSTGRES_POD"
  exit 1
fi
echo "✓ Found PostgreSQL pod: $POSTGRES_POD"

# Step 2: Get the password from secret
echo "Step 2: Getting password from secret..."
SECRET_B64=$(kubectl get secret "${RELEASE_NAME}-postgres-secret" -n "$NAMESPACE" -o jsonpath='{.data.password}' 2>&1)
if [ -z "$SECRET_B64" ] || [[ "$SECRET_B64" == *"Error"* ]] || [[ "$SECRET_B64" == *"NotFound"* ]]; then
  echo "ERROR: Could not find secret ${RELEASE_NAME}-postgres-secret"
  echo "Output: $SECRET_B64"
  exit 1
fi

# Decode password (double base64 decode)
EXTERNAL_SECRETS_B64=$(echo "$SECRET_B64" | base64 -d 2>&1)
PASSWORD=$(echo "$EXTERNAL_SECRETS_B64" | base64 -d 2>&1)
if [ -z "$PASSWORD" ]; then
  echo "ERROR: Failed to decode password"
  exit 1
fi
echo "✓ Password retrieved and decoded"

# Step 3: Update PostgreSQL database password
echo "Step 3: Updating PostgreSQL password in database..."
# Escape single quotes in password for SQL
ESCAPED_PASSWORD=$(echo "$PASSWORD" | sed "s/'/''/g")
kubectl exec "$POSTGRES_POD" -n "$NAMESPACE" -- psql -U immich -d immich -c "ALTER USER immich WITH PASSWORD '${ESCAPED_PASSWORD}';" 2>&1
if [ $? -eq 0 ]; then
  echo "✓ PostgreSQL password updated"
else
  echo "WARNING: Failed to update PostgreSQL password (might already be correct)"
fi

# Step 4: URL encode the password for ConfigMap
echo "Step 4: URL encoding password for ConfigMap..."
ENCODED_PASSWORD=$(python3 -c "import urllib.parse; import sys; print(urllib.parse.quote(sys.stdin.read().strip(), safe=''))" <<< "$PASSWORD" 2>&1)
if [ $? -ne 0 ] || [ -z "$ENCODED_PASSWORD" ]; then
  echo "ERROR: Failed to URL encode password"
  exit 1
fi
echo "✓ Password URL encoded"

# Step 5: Create DB URL and update ConfigMap
echo "Step 5: Updating ConfigMap..."
DB_URL="postgresql://immich:${ENCODED_PASSWORD}@${RELEASE_NAME}-postgres.${NAMESPACE}.svc.cluster.local:5432/immich"
kubectl create configmap "${RELEASE_NAME}-db-config" \
  --from-literal=url="${DB_URL}" \
  --namespace="$NAMESPACE" \
  --dry-run=client -o yaml 2>&1 | kubectl apply -f - 2>&1

if [ $? -eq 0 ]; then
  echo "✓ ConfigMap updated successfully"
else
  echo "ERROR: Failed to update ConfigMap"
  exit 1
fi

# Step 6: Verify ConfigMap
echo "Step 6: Verifying ConfigMap..."
CM_URL=$(kubectl get configmap "${RELEASE_NAME}-db-config" -n "$NAMESPACE" -o jsonpath='{.data.url}' 2>&1)
if [[ "$CM_URL" == postgresql://immich:* ]]; then
  echo "✓ ConfigMap verified: URL starts with postgresql://immich:"
else
  echo "WARNING: ConfigMap URL doesn't look correct: $CM_URL"
fi

# Step 7: Restart deployment
echo "Step 7: Restarting immich-server deployment..."
kubectl rollout restart deployment "${RELEASE_NAME}-server" -n "$NAMESPACE" 2>&1
if [ $? -eq 0 ]; then
  echo "✓ Deployment restart initiated"
else
  echo "ERROR: Failed to restart deployment"
  exit 1
fi

echo ""
echo "=== Fix completed ==="
echo "Waiting for pod to restart..."
sleep 5
echo ""
echo "Current pod status:"
kubectl get pods -n "$NAMESPACE" | grep "${RELEASE_NAME}-server" || true
echo ""
echo "Check logs with: kubectl logs -n $NAMESPACE -l app=${RELEASE_NAME}-server --tail=50"
