#!/bin/bash
set -e

RELEASE_NAME="immich"
NAMESPACE=""

# Try to find the namespace
for ns in immich default apps; do
  if kubectl get configmap "${RELEASE_NAME}-db-config" -n "$ns" &>/dev/null; then
    NAMESPACE="$ns"
    break
  fi
done

if [ -z "$NAMESPACE" ]; then
  # Try to find from pod
  POD_NAME="immich-server-6759ddb46c-c2cmq"
  for ns in immich default apps; do
    if kubectl get pod "$POD_NAME" -n "$ns" &>/dev/null; then
      NAMESPACE="$ns"
      break
    fi
  done
fi

if [ -z "$NAMESPACE" ]; then
  echo "Error: Could not find immich resources. Please specify namespace manually."
  echo "Usage: $0 <namespace>"
  exit 1
fi

# Allow manual namespace override
if [ -n "$1" ]; then
  NAMESPACE="$1"
fi

echo "Using namespace: $NAMESPACE"

# Get the password from the secret (double base64 decode)
echo "Getting password from secret..."
SECRET_B64=$(kubectl get secret "${RELEASE_NAME}-postgres-secret" -n "$NAMESPACE" -o jsonpath='{.data.password}')

if [ -z "$SECRET_B64" ]; then
  echo "Error: Could not find secret ${RELEASE_NAME}-postgres-secret in namespace $NAMESPACE"
  exit 1
fi

# Decode twice: Kubernetes base64 -> External Secrets base64 -> actual password
EXTERNAL_SECRETS_B64=$(echo "$SECRET_B64" | base64 -d)
PASSWORD=$(echo "$EXTERNAL_SECRETS_B64" | base64 -d)

if [ -z "$PASSWORD" ]; then
  echo "Error: Failed to decode password"
  exit 1
fi

echo "Password retrieved successfully"

# URL encode the password using Python (same as the Helm hook job does)
ENCODED_PASSWORD=$(python3 -c "import urllib.parse; import sys; print(urllib.parse.quote(sys.stdin.read().strip(), safe=''))" <<< "$PASSWORD")

# Construct the DB URL
DB_URL="postgresql://immich:${ENCODED_PASSWORD}@${RELEASE_NAME}-postgres.${NAMESPACE}.svc.cluster.local:5432/immich"

echo "Updating ConfigMap ${RELEASE_NAME}-db-config..."

# Update the ConfigMap
kubectl create configmap "${RELEASE_NAME}-db-config" \
  --from-literal=url="${DB_URL}" \
  --namespace="$NAMESPACE" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "ConfigMap updated successfully!"

# Restart the immich-server deployment to pick up the new ConfigMap
echo "Restarting immich-server deployment..."
kubectl rollout restart deployment "${RELEASE_NAME}-server" -n "$NAMESPACE"

echo "Done! The immich-server pod will restart with the correct database password."
