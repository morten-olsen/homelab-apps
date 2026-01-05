#!/bin/bash
set -e

# Script to sync Kubernetes PVC content with a host path
# Creates a temporary Job with both PVC and host path mounted, then ensures they're identical

usage() {
    echo "Usage: $0 <host-path> <namespace> <pvc-name> [--dry-run] [--verify-only]"
    echo ""
    echo "Arguments:"
    echo "  host-path    Path on the Kubernetes node filesystem"
    echo "  namespace    Kubernetes namespace where the PVC exists"
    echo "  pvc-name     Name of the PersistentVolumeClaim to sync"
    echo ""
    echo "Options:"
    echo "  --dry-run    Show what would be done without actually syncing"
    echo "  --verify-only  Only verify if paths are identical, don't sync"
    echo ""
    echo "Examples:"
    echo "  $0 /data/volumes/prod/my-app-data prod my-app-data"
    echo "  $0 /backup/data default my-pvc --dry-run"
    echo "  $0 /data/volumes/prod/my-app-data prod my-app-data --verify-only"
    exit 1
}

# Parse arguments
if [ $# -lt 3 ]; then
    usage
fi

HOST_PATH="$1"
NAMESPACE="$2"
PVC_NAME="$3"
DRY_RUN=false
VERIFY_ONLY=false

# Parse optional flags
shift 3
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --verify-only)
            VERIFY_ONLY=true
            shift
            ;;
        *)
            echo "ERROR: Unknown option: $1"
            usage
            ;;
    esac
done

# Normalize host path (remove trailing slash)
HOST_PATH="${HOST_PATH%/}"

# Generate unique job name
JOB_NAME="pvc-sync-${PVC_NAME}-$(date +%s)"

echo "============================================================"
echo "PVC Sync with Host Path"
echo "============================================================"
echo "Host Path:  $HOST_PATH"
echo "Namespace:  $NAMESPACE"
echo "PVC Name:   $PVC_NAME"
echo "Job Name:   $JOB_NAME"
if [ "$DRY_RUN" = true ]; then
    echo "Mode:       DRY RUN"
elif [ "$VERIFY_ONLY" = true ]; then
    echo "Mode:       VERIFY ONLY"
else
    echo "Mode:       SYNC (will DELETE extra files in PVC)"
fi
echo "============================================================"
if [ "$VERIFY_ONLY" != true ] && [ "$DRY_RUN" != true ]; then
    echo ""
    echo "⚠ WARNING: This operation will make the PVC identical to the host path"
    echo "   by DELETING any files in the PVC that don't exist in the host path."
    echo ""
fi
echo ""

# Check if PVC exists
echo "Step 1: Checking if PVC exists..."
if ! kubectl get pvc "$PVC_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "ERROR: PVC '$PVC_NAME' not found in namespace '$NAMESPACE'"
    exit 1
fi
echo "✓ PVC '$PVC_NAME' exists"

# Get PVC details
PVC_ACCESS_MODE=$(kubectl get pvc "$PVC_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.accessModes[0]}' 2>/dev/null || echo "Unknown")
echo "  Access Mode: $PVC_ACCESS_MODE"
echo ""

if [ "$DRY_RUN" = true ]; then
    echo "DRY RUN: Would create job and sync data"
    echo "WARNING: Sync will DELETE any files in the PVC that don't exist in the host path"
    echo "Remove --dry-run to perform actual sync"
    exit 0
fi

# Build the sync script that will run inside the container
SYNC_SCRIPT=$(cat <<'SCRIPT_EOF'
#!/bin/sh
set -e

MODE="$1"
HOST_PATH="/host-data"
PVC_PATH="/pvc-data"

echo "Installing rsync..."
apk add --no-cache rsync >/dev/null 2>&1 || {
    echo "WARNING: Failed to install rsync, will use tar instead"
    USE_RSYNC=false
}

if command -v rsync >/dev/null 2>&1; then
    USE_RSYNC=true
else
    USE_RSYNC=false
fi

verify_sync() {
    echo "Verifying sync..."
    
    if [ "$USE_RSYNC" = true ]; then
        # Run rsync dry-run and capture output
        DIFF_OUTPUT=$(rsync -avn --delete "$HOST_PATH/" "$PVC_PATH/" 2>&1)
        RSYNC_EXIT=$?
        
        if [ $RSYNC_EXIT -ne 0 ]; then
            echo "ERROR: Failed to verify sync (rsync exit code: $RSYNC_EXIT)"
            echo "$DIFF_OUTPUT"
            return 1
        fi
        
        # When paths are identical, rsync only shows "./" and summary lines
        # Filter out all known summary lines and "./", then check if anything remains
        # Summary lines: "sending incremental file list", "sent X", "received X", "total size is X", "speedup is X"
        # Also filter out "deleting X" lines and empty lines
        FILTERED=$(echo "$DIFF_OUTPUT" | \
            grep -v "^sending incremental file list$" | \
            grep -v "^\./$" | \
            grep -v "^sent " | \
            grep -v "^received " | \
            grep -v "^total size is " | \
            grep -v "^speedup is " | \
            grep -v "^deleting " | \
            grep -v "^$")
        
        # If FILTERED is empty, paths are identical
        if [ -z "$FILTERED" ]; then
            echo "✓ Paths are identical (no differences found)"
            return 0
        else
            echo "⚠ Paths differ:"
            echo "$DIFF_OUTPUT" | head -20
            return 1
        fi
    else
        HOST_COUNT=$(find "$HOST_PATH" -type f 2>/dev/null | wc -l | tr -d ' ')
        PVC_COUNT=$(find "$PVC_PATH" -type f 2>/dev/null | wc -l | tr -d ' ')
        
        HOST_SIZE=$(du -sb "$HOST_PATH" 2>/dev/null | cut -f1 | tr -d ' ' || echo "0")
        PVC_SIZE=$(du -sb "$PVC_PATH" 2>/dev/null | cut -f1 | tr -d ' ' || echo "0")
        
        echo "Host path: $HOST_COUNT files, $HOST_SIZE bytes"
        echo "PVC:       $PVC_COUNT files, $PVC_SIZE bytes"
        
        if [ "$HOST_COUNT" = "$PVC_COUNT" ] && [ "$HOST_SIZE" = "$PVC_SIZE" ]; then
            echo "✓ Paths appear identical"
            return 0
        else
            echo "⚠ Paths differ"
            return 1
        fi
    fi
}

sync_data() {
    echo "Syncing data from host path to PVC..."
    echo "WARNING: This will DELETE any files in the PVC that don't exist in the host path"
    echo "to ensure they are identical."
    
    if [ "$USE_RSYNC" = true ]; then
        echo "Using rsync to sync data (with --delete to remove extra files)..."
        rsync -av --delete "$HOST_PATH/" "$PVC_PATH/" || {
            echo "ERROR: Rsync failed"
            return 1
        }
        echo "✓ Sync completed using rsync (PVC now matches host path exactly)"
        return 0
    else
        echo "Using tar to sync data (clearing PVC first)..."
        echo "Clearing existing PVC data..."
        rm -rf "$PVC_PATH"/* "$PVC_PATH"/..?* "$PVC_PATH"/.[!.]* 2>/dev/null || true
        echo "Copying data from host path to PVC..."
        cd "$HOST_PATH" && tar -cf - . | (cd "$PVC_PATH" && tar -xf -) || {
            echo "ERROR: Tar sync failed"
            return 1
        }
        echo "✓ Sync completed using tar (PVC now matches host path exactly)"
        return 0
    fi
}

if [ "$MODE" = "verify" ]; then
    verify_sync
    exit $?
elif [ "$MODE" = "sync" ]; then
    sync_data || exit 1
    echo "✓ Sync completed successfully (rsync ensures paths are identical)"
    exit 0
else
    echo "ERROR: Unknown mode: $MODE"
    exit 1
fi
SCRIPT_EOF
)

# Base64 encode the script
SYNC_SCRIPT_B64=$(echo "$SYNC_SCRIPT" | base64 | tr -d '\n')

# Determine job mode
if [ "$VERIFY_ONLY" = true ]; then
    JOB_MODE="verify"
else
    JOB_MODE="sync"
fi

# Create temporary job manifest
echo "Step 2: Creating temporary job..."
JOB_MANIFEST=$(cat <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: ${JOB_NAME}
  namespace: ${NAMESPACE}
spec:
  ttlSecondsAfterFinished: 300
  template:
    metadata:
      annotations:
        sidecar.istio.io/inject: "false"
    spec:
      containers:
      - name: sync
        image: alpine:latest
        command:
        - /bin/sh
        - -c
        - |
          echo '${SYNC_SCRIPT_B64}' | base64 -d > /tmp/sync.sh
          chmod +x /tmp/sync.sh
          /tmp/sync.sh ${JOB_MODE}
        securityContext:
          privileged: true
        volumeMounts:
        - name: host-data
          mountPath: /host-data
          readOnly: false
        - name: pvc-data
          mountPath: /pvc-data
      volumes:
      - name: host-data
        hostPath:
          path: ${HOST_PATH}
          type: DirectoryOrCreate
      - name: pvc-data
        persistentVolumeClaim:
          claimName: ${PVC_NAME}
      restartPolicy: Never
EOF
)

# Apply job manifest
echo "$JOB_MANIFEST" | kubectl apply -f - >/dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to create job"
    exit 1
fi
echo "✓ Job created"

# Wait for job to complete
echo "Step 3: Waiting for job to complete..."
MAX_WAIT=600  # 10 minutes for large syncs
ELAPSED=0
while [ $ELAPSED -lt $MAX_WAIT ]; do
    # Get job status (ensure we always have numeric values)
    SUCCEEDED=$(kubectl get job "$JOB_NAME" -n "$NAMESPACE" -o jsonpath='{.status.succeeded}' 2>/dev/null || echo "0")
    FAILED=$(kubectl get job "$JOB_NAME" -n "$NAMESPACE" -o jsonpath='{.status.failed}' 2>/dev/null || echo "0")
    
    # Ensure they're numeric (default to 0 if empty)
    SUCCEEDED=${SUCCEEDED:-0}
    FAILED=${FAILED:-0}
    
    # Convert to integers (handle empty strings)
    SUCCEEDED=$((SUCCEEDED + 0))
    FAILED=$((FAILED + 0))
    
    # Check if succeeded
    if [ "$SUCCEEDED" -ge 1 ]; then
        echo "✓ Job completed successfully"
        break
    fi
    
    # Check if failed
    if [ "$FAILED" -ge 1 ]; then
        echo "ERROR: Job failed"
        echo "Job logs:"
        # Get the pod name from the job
        POD_NAME=$(kubectl get pods -n "$NAMESPACE" -l job-name="$JOB_NAME" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
        if [ -n "$POD_NAME" ]; then
            kubectl logs "$POD_NAME" -n "$NAMESPACE" 2>&1 || true
        fi
        exit 1
    fi
    
    # Show progress every 10 seconds
    if [ $((ELAPSED % 10)) -eq 0 ] && [ $ELAPSED -gt 0 ]; then
        echo "  Still running... (${ELAPSED}s elapsed)"
    fi
    
    sleep 2
    ELAPSED=$((ELAPSED + 2))
done

if [ $ELAPSED -ge $MAX_WAIT ]; then
    echo "ERROR: Job did not complete within $MAX_WAIT seconds"
    echo "Job status:"
    kubectl get job "$JOB_NAME" -n "$NAMESPACE" 2>&1 || true
    exit 1
fi

# Get job logs
echo ""
echo "Step 4: Job output:"
echo "----------------------------------------"
POD_NAME=$(kubectl get pods -n "$NAMESPACE" -l job-name="$JOB_NAME" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$POD_NAME" ]; then
    kubectl logs "$POD_NAME" -n "$NAMESPACE" 2>&1 || true
else
    echo "WARNING: Could not find pod for job"
fi
echo "----------------------------------------"
echo ""

# Check job exit status
JOB_EXIT_CODE=0
if [ -n "$POD_NAME" ]; then
    # Get the exit code from the container
    CONTAINER_STATUS=$(kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.status.containerStatuses[0].state.terminated.exitCode}' 2>/dev/null || echo "")
    if [ -n "$CONTAINER_STATUS" ]; then
        JOB_EXIT_CODE=$CONTAINER_STATUS
    fi
fi

# Cleanup function
cleanup() {
    echo ""
    echo "Step 5: Cleaning up job..."
    kubectl delete job "$JOB_NAME" -n "$NAMESPACE" >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo "✓ Job deleted (pods will be cleaned up automatically)"
    else
        echo "WARNING: Failed to delete job (you may need to delete it manually: kubectl delete job $JOB_NAME -n $NAMESPACE)"
    fi
}

# Set trap to ensure cleanup on exit
trap cleanup EXIT

# Determine final status based on job exit code
if [ "$JOB_EXIT_CODE" = "0" ]; then
    echo ""
    echo "============================================================"
    if [ "$VERIFY_ONLY" = true ]; then
        echo "✓ Verification passed: Paths are identical"
    else
        echo "✓ Sync completed successfully!"
    fi
    echo "============================================================"
    exit 0
else
    echo ""
    echo "============================================================"
    if [ "$VERIFY_ONLY" = true ]; then
        echo "⚠ Verification failed: Paths differ"
    else
        echo "⚠ Sync completed but verification shows differences"
    fi
    echo "============================================================"
    exit $JOB_EXIT_CODE
fi
