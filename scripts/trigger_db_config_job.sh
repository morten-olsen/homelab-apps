#!/bin/bash
set -e

RELEASE_NAME="immich"
NAMESPACE="${1:-immich}"  # Default to immich namespace, or pass as first argument

echo "Triggering db-config job in namespace: $NAMESPACE"

# Create a temporary job based on the Helm hook job
kubectl create job --from=cronjob/immich-db-config-generator "${RELEASE_NAME}-db-config-manual-$(date +%s)" -n "$NAMESPACE" 2>/dev/null || \
kubectl create job "${RELEASE_NAME}-db-config-manual-$(date +%s)" \
  --image=python:3.11-slim \
  -n "$NAMESPACE" \
  -- /bin/bash -c "
    set -e
    apt-get update -qq && apt-get install -y -qq curl > /dev/null 2>&1 && \
    curl -sSL \"https://dl.k8s.io/release/\$(curl -sL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl\" -o /tmp/kubectl && \
    chmod +x /tmp/kubectl && mv /tmp/kubectl /usr/local/bin/kubectl
    
    PASSWORD_B64=\$(cat /secrets/password)
    PASSWORD=\$(python3 -c \"import base64; import sys; print(base64.b64decode(sys.stdin.read().strip()).decode('utf-8'))\" <<< \"\$PASSWORD_B64\")
    ENCODED_PASSWORD=\$(python3 -c \"import urllib.parse; import sys; print(urllib.parse.quote(sys.stdin.read().strip(), safe=''))\" <<< \"\$PASSWORD\")
    DB_URL=\"postgresql://immich:\${ENCODED_PASSWORD}@${RELEASE_NAME}-postgres.${NAMESPACE}.svc.cluster.local:5432/immich\"
    kubectl create configmap ${RELEASE_NAME}-db-config --from-literal=url=\"\${DB_URL}\" --dry-run=client -o yaml | kubectl apply -f -
    echo \"ConfigMap ${RELEASE_NAME}-db-config updated successfully\"
  " \
  --overrides='
{
  "spec": {
    "serviceAccountName": "'"${RELEASE_NAME}"'-db-config-sa",
    "volumes": [
      {
        "name": "postgres-secret",
        "secret": {
          "secretName": "'"${RELEASE_NAME}"'-postgres-secret"
        }
      }
    ],
    "containers": [{
      "name": "generator",
      "volumeMounts": [
        {
          "name": "postgres-secret",
          "mountPath": "/secrets",
          "readOnly": true
        }
      ]
    }]
  }
}'

echo "Job created. Waiting for completion..."
kubectl wait --for=condition=complete --timeout=60s job -l job-name="${RELEASE_NAME}-db-config-manual" -n "$NAMESPACE" || true

echo "Restarting immich-server..."
kubectl rollout restart deployment "${RELEASE_NAME}-server" -n "$NAMESPACE"

echo "Done!"
