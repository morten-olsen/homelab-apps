#!/bin/bash
set -e

NAMESPACE="shared"
RELEASE_NAME="immich"

echo "=== Fixing immich database password issue ==="
echo "Namespace: $NAMESPACE"
echo ""

# Step 1: Get the password from secret
echo "Step 1: Getting password from secret..."
SECRET_B64=$(kubectl get secret "${RELEASE_NAME}-postgres-secret" -n "$NAMESPACE" -o jsonpath='{.data.password}' 2>&1)

if [ -z "$SECRET_B64" ] || [[ "$SECRET_B64" == *"Error"* ]] || [[ "$SECRET_B64" == *"NotFound"* ]]; then
  echo "ERROR: Could not find secret ${RELEASE_NAME}-postgres-secret"
  echo "Secret output: $SECRET_B64"
  exit 1
fi

echo "✓ Secret found"

# Step 2: Decode password (double base64 decode)
echo "Step 2: Decoding password..."
EXTERNAL_SECRETS_B64=$(echo "$SECRET_B64" | base64 -d 2>&1)
if [ $? -ne 0 ]; then
  echo "ERROR: Failed to decode secret (first level)"
  exit 1
fi

PASSWORD=$(echo "$EXTERNAL_SECRETS_B64" | base64 -d 2>&1)
if [ $? -ne 0 ]; then
  echo "ERROR: Failed to decode secret (second level)"
  exit 1
fi

if [ -z "$PASSWORD" ]; then
  echo "ERROR: Password is empty after decoding"
  exit 1
fi

echo "✓ Password decoded successfully"

# Step 3: URL encode the password
echo "Step 3: URL encoding password..."
ENCODED_PASSWORD=$(python3 -c "import urllib.parse; import sys; print(urllib.parse.quote(sys.stdin.read().strip(), safe=''))" <<< "$PASSWORD" 2>&1)
if [ $? -ne 0 ] || [ -z "$ENCODED_PASSWORD" ]; then
  echo "ERROR: Failed to URL encode password"
  echo "Python output: $ENCODED_PASSWORD"
  exit 1
fi

echo "✓ Password URL encoded"

# Step 4: Create DB URL
echo "Step 4: Creating database URL..."
DB_URL="postgresql://immich:${ENCODED_PASSWORD}@${RELEASE_NAME}-postgres.${NAMESPACE}.svc.cluster.local:5432/immich"
echo "✓ Database URL created"

# Step 5: Update ConfigMap
echo "Step 5: Updating ConfigMap..."
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

# Step 6: Restart deployment
echo "Step 6: Restarting immich-server deployment..."
kubectl rollout restart deployment "${RELEASE_NAME}-server" -n "$NAMESPACE" 2>&1

if [ $? -eq 0 ]; then
  echo "✓ Deployment restart initiated"
else
  echo "ERROR: Failed to restart deployment"
  exit 1
fi

echo ""
echo "=== Done ==="
echo "The immich-server pod should restart with the correct database password."
echo "Check status with: kubectl get pods -n $NAMESPACE | grep immich-server"
