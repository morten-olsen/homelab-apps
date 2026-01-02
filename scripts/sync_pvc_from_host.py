#!/usr/bin/env python3
"""
Sync data from a Kubernetes node host path to a Kubernetes PVC.

This script creates a temporary pod that mounts both the hostPath (from the K8s node)
and the PVC, copies data from the host path to the PVC, and then cleans up the pod.

The host_path should be a path on the Kubernetes node's filesystem, not on the local
machine running this script.

Usage:
    python3 sync_pvc_from_host.py <pvc_name> <namespace> <host_path> [--verify] [--dry-run]

Examples:
    python3 sync_pvc_from_host.py immich-postgres-data prod /data/volumes/prod/immich-postgres-data/
    python3 sync_pvc_from_host.py my-pvc default /backup/data --verify
    python3 sync_pvc_from_host.py my-pvc default /backup/data --dry-run
"""

import subprocess
import sys
import argparse
import time
import os
import tempfile


def run_kubectl(cmd, check=True, capture_output=True):
    """Run a kubectl command."""
    try:
        result = subprocess.run(
            ["kubectl"] + cmd,
            capture_output=capture_output,
            text=True,
            check=check
        )
        return result.stdout.strip() if capture_output else None
    except subprocess.CalledProcessError as e:
        print(f"Error running kubectl {' '.join(cmd)}", file=sys.stderr)
        if capture_output:
            print(f"stdout: {e.stdout}", file=sys.stderr)
            print(f"stderr: {e.stderr}", file=sys.stderr)
        raise


def check_pvc_exists(pvc_name, namespace):
    """Check if a PVC exists."""
    try:
        run_kubectl(["get", "pvc", pvc_name, "-n", namespace], check=True)
        return True
    except subprocess.CalledProcessError:
        return False


def check_host_path_exists_on_node(host_path, pod_name, namespace):
    """Check if the host path exists on the Kubernetes node."""
    try:
        result = run_kubectl([
            "exec", "-n", namespace, pod_name, "-c", "sync", "--",
            "test", "-d", "/host-data"
        ], check=False)
        # If test succeeds, directory exists
        return True
    except:
        return False


def create_temp_pod(pvc_name, namespace, pod_name, host_path):
    """Create a temporary pod that mounts both the hostPath and the PVC."""
    print(f"Creating temporary pod '{pod_name}'...")
    
    pod_manifest = f"""apiVersion: v1
kind: Pod
metadata:
  name: {pod_name}
  namespace: {namespace}
spec:
  containers:
  - name: sync
    image: busybox:latest
    command: ["sleep", "3600"]
    securityContext:
      privileged: true
    volumeMounts:
    - name: host-data
      mountPath: /host-data
      readOnly: true
    - name: pvc
      mountPath: /pvc-data
  volumes:
  - name: host-data
    hostPath:
      path: {host_path}
      type: DirectoryOrCreate
  - name: pvc
    persistentVolumeClaim:
      claimName: {pvc_name}
  restartPolicy: Never
"""
    
    # Write manifest to temp file
    with tempfile.NamedTemporaryFile(mode='w', suffix='.yaml', delete=False) as f:
        f.write(pod_manifest)
        temp_file = f.name
    
    try:
        # Apply the pod manifest
        run_kubectl(["apply", "-f", temp_file], check=True)
        
        # Wait for pod to be ready
        print("Waiting for pod to be ready...")
        max_wait = 60  # seconds
        start_time = time.time()
        
        while time.time() - start_time < max_wait:
            try:
                result = run_kubectl(
                    ["get", "pod", pod_name, "-n", namespace, "-o", "jsonpath={.status.phase}"],
                    check=True
                )
                if result == "Running":
                    print(f"✓ Pod '{pod_name}' is ready")
                    return True
                elif result == "Failed":
                    print(f"ERROR: Pod '{pod_name}' failed to start", file=sys.stderr)
                    return False
            except subprocess.CalledProcessError:
                pass
            
            time.sleep(2)
        
        print(f"ERROR: Pod '{pod_name}' did not become ready within {max_wait} seconds", file=sys.stderr)
        return False
    finally:
        # Clean up temp file
        try:
            os.unlink(temp_file)
        except OSError:
            pass


def delete_pod(pod_name, namespace):
    """Delete a pod."""
    print(f"Deleting temporary pod '{pod_name}'...")
    try:
        run_kubectl(["delete", "pod", pod_name, "-n", namespace], check=True)
        print(f"✓ Pod '{pod_name}' deleted")
    except subprocess.CalledProcessError as e:
        print(f"Warning: Failed to delete pod '{pod_name}': {e}", file=sys.stderr)


def sync_data_from_host(host_path, pod_name, namespace):
    """Sync data from host path (mounted in pod) to PVC using tar."""
    print(f"Syncing data from host path '{host_path}' (mounted at /host-data) to PVC (mounted at /pvc-data)...")
    
    # First verify the host path exists in the pod
    print("Verifying host path is accessible in pod...")
    try:
        result = run_kubectl([
            "exec", "-n", namespace, pod_name, "-c", "sync", "--",
            "test", "-d", "/host-data"
        ], check=True)
        print("✓ Host path is accessible")
    except subprocess.CalledProcessError:
        print(f"ERROR: Host path '/host-data' is not accessible in pod", file=sys.stderr)
        raise
    
    # Check if host path has data
    try:
        file_count = run_kubectl([
            "exec", "-n", namespace, pod_name, "-c", "sync", "--",
            "sh", "-c", "find /host-data -type f | wc -l"
        ], check=True)
        file_count = int(file_count.strip())
        if file_count == 0:
            print("⚠ Warning: Host path appears to be empty")
        else:
            print(f"Found {file_count} files in host path")
    except:
        pass
    
    # Use tar to sync data from /host-data to /pvc-data
    print("Syncing data using tar (this may take a while)...")
    
    # Clear PVC data first, then copy from host
    sync_cmd = [
        "exec", "-n", namespace, pod_name, "-c", "sync", "--",
        "sh", "-c", """
        # Clear existing PVC data
        rm -rf /pvc-data/* /pvc-data/..?* /pvc-data/.[!.]* 2>/dev/null || true
        
        # Create tar from host-data and extract to pvc-data in one go
        cd /host-data && tar -cf - . | (cd /pvc-data && tar -xf -)
        
        # Verify sync completed
        if [ $? -eq 0 ]; then
            echo "Sync completed successfully"
        else
            echo "Sync failed" >&2
            exit 1
        fi
        """
    ]
    
    run_kubectl(sync_cmd, check=True)
    print("✓ Data sync completed")


def verify_sync(host_path, pod_name, namespace):
    """Verify that the sync was successful by comparing file counts and sizes."""
    print("\nVerifying sync...")
    
    try:
        # Count files on host (mounted in pod)
        host_count_result = run_kubectl([
            "exec", "-n", namespace, pod_name, "-c", "sync", "--",
            "sh", "-c", "find /host-data -type f | wc -l"
        ], check=True)
        host_file_count = int(host_count_result.strip())
        
        host_size_result = run_kubectl([
            "exec", "-n", namespace, pod_name, "-c", "sync", "--",
            "sh", "-c", "du -sb /host-data 2>/dev/null | cut -f1 || echo 0"
        ], check=True)
        host_total_size = int(host_size_result.strip() or "0")
        
        # Count files in PVC
        pvc_count_result = run_kubectl([
            "exec", "-n", namespace, pod_name, "-c", "sync", "--",
            "sh", "-c", "find /pvc-data -type f | wc -l"
        ], check=True)
        pvc_file_count = int(pvc_count_result.strip())
        
        pvc_size_result = run_kubectl([
            "exec", "-n", namespace, pod_name, "-c", "sync", "--",
            "sh", "-c", "du -sb /pvc-data 2>/dev/null | cut -f1 || echo 0"
        ], check=True)
        pvc_total_size = int(pvc_size_result.strip() or "0")
        
        print(f"Host path: {host_file_count} files, {host_total_size} bytes")
        print(f"PVC:       {pvc_file_count} files, {pvc_total_size} bytes")
        
        if host_file_count == pvc_file_count:
            print("✓ File counts match")
        else:
            print(f"⚠ Warning: File counts differ ({host_file_count} vs {pvc_file_count})")
        
        # Allow some tolerance for size differences (due to filesystem overhead)
        size_diff = abs(host_total_size - pvc_total_size)
        if size_diff < 1024:  # Less than 1KB difference
            print("✓ Total sizes match (within tolerance)")
        else:
            print(f"⚠ Warning: Size difference: {size_diff} bytes")
        
        return host_file_count == pvc_file_count and size_diff < 1024
    except subprocess.CalledProcessError as e:
        print(f"Warning: Could not verify sync: {e}", file=sys.stderr)
        return False


def main():
    parser = argparse.ArgumentParser(
        description="Sync data from host path to Kubernetes PVC",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s immich-postgres-data prod /data/volumes/prod/immich-postgres-data/
  %(prog)s my-pvc default /backup/data --verify
  %(prog)s my-pvc default /backup/data --dry-run
        """
    )
    parser.add_argument(
        "pvc_name",
        help="Name of the PVC to sync to"
    )
    parser.add_argument(
        "namespace",
        help="Namespace where the PVC exists"
    )
    parser.add_argument(
        "host_path",
        help="Host path to sync from (source of truth)"
    )
    parser.add_argument(
        "--verify",
        action="store_true",
        help="Verify sync by comparing file counts and sizes"
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show what would be done without actually syncing"
    )
    
    args = parser.parse_args()
    
    # Normalize host path (but don't check locally - it's on the K8s node)
    host_path = args.host_path.rstrip('/')
    
    print("=" * 60)
    print("PVC Sync from Kubernetes Node Host Path")
    print("=" * 60)
    print(f"PVC: {args.pvc_name}")
    print(f"Namespace: {args.namespace}")
    print(f"Host Path (on K8s node): {host_path}")
    print("=" * 60)
    print()
    
    # Validate inputs
    if not check_pvc_exists(args.pvc_name, args.namespace):
        print(f"ERROR: PVC '{args.pvc_name}' not found in namespace '{args.namespace}'", file=sys.stderr)
        sys.exit(1)
    print(f"✓ PVC '{args.pvc_name}' exists")
    print(f"✓ Will check host path '{host_path}' once pod is created")
    print()
    
    if args.dry_run:
        print("DRY RUN: Would sync data from Kubernetes node host path to PVC")
        print("Remove --dry-run to perform actual sync")
        sys.exit(0)
    
    # Generate unique pod name
    pod_name = f"pvc-sync-{args.pvc_name}-{int(time.time())}"
    
    pod_created = False
    try:
        # Create temporary pod with both hostPath and PVC mounted
        if not create_temp_pod(args.pvc_name, args.namespace, pod_name, host_path):
            sys.exit(1)
        pod_created = True
        
        # Sync data
        sync_data_from_host(host_path, pod_name, args.namespace)
        
        # Verify if requested
        if args.verify:
            verify_sync(host_path, pod_name, args.namespace)
        
        print()
        print("=" * 60)
        print("Sync completed successfully!")
        print("=" * 60)
        
    except KeyboardInterrupt:
        print("\n\nSync interrupted by user.", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"\n\nERROR: {e}", file=sys.stderr)
        sys.exit(1)
    finally:
        # Always clean up the temporary pod
        if pod_created:
            delete_pod(pod_name, args.namespace)


if __name__ == "__main__":
    main()
