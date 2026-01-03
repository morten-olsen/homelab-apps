#!/bin/bash
set -e

# Find the pod namespace
POD_NAME="immich-postgres-544f467fd8-2k84c"
NAMESPACE=""

# Try to find the namespace
for ns in immich default apps; do
  if kubectl get pod "$POD_NAME" -n "$ns" &>/dev/null; then
    NAMESPACE="$ns"
    break
  fi
done

if [ -z "$NAMESPACE" ]; then
  # Try without namespace specification
  if kubectl get pod "$POD_NAME" -A &>/dev/null; then
    NAMESPACE=$(kubectl get pod "$POD_NAME" -A -o jsonpath='{.items[0].metadata.namespace}' 2>/dev/null || \
                kubectl get pod "$POD_NAME" -A -o jsonpath='{.metadata.namespace}' 2>/dev/null)
  fi
fi

if [ -z "$NAMESPACE" ]; then
  echo "Error: Could not find pod $POD_NAME in any namespace"
  exit 1
fi

echo "Found pod in namespace: $NAMESPACE"

# Get the password from the secret
# The secret is stored as base64 in Kubernetes, and External Secrets uses base64 encoding
# So we need to decode twice: Kubernetes base64 -> External Secrets base64 -> actual password
SECRET_B64=$(kubectl get secret "immich-postgres-secret" -n "$NAMESPACE" -o jsonpath='{.data.password}')

if [ -z "$SECRET_B64" ]; then
  echo "Error: Could not find secret immich-postgres-secret in namespace $NAMESPACE"
  exit 1
fi

# Decode the password (double base64 decode: Kubernetes -> External Secrets -> actual password)
# First decode: Kubernetes base64 to get External Secrets base64 value
EXTERNAL_SECRETS_B64=$(echo "$SECRET_B64" | base64 -d)
# Second decode: External Secrets base64 to get actual password
PASSWORD=$(echo "$EXTERNAL_SECRETS_B64" | base64 -d)

if [ -z "$PASSWORD" ]; then
  echo "Error: Failed to decode password"
  exit 1
fi

echo "Updating PostgreSQL password for user 'immich'..."

# Update the password in PostgreSQL
# Escape single quotes in password for SQL by doubling them
ESCAPED_PASSWORD=$(echo "$PASSWORD" | sed "s/'/''/g")

# Use psql to update the password
kubectl exec "$POD_NAME" -n "$NAMESPACE" -- psql -U immich -d immich -c "ALTER USER immich WITH PASSWORD '${ESCAPED_PASSWORD}';"

echo "Password updated successfully!"
