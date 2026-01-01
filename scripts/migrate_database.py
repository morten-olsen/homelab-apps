#!/usr/bin/env python3
"""
Database migration script for PostgreSQL databases in Kubernetes.

Migrates a database from the old PostgreSQL server (prod-postgres-cluster-0 in homelab namespace)
to the new PostgreSQL server (postgres-statefulset-0 in shared namespace).

Usage:
    python3 migrate_database.py <source_db_name> <dest_db_name> [--clean]

Examples:
    python3 migrate_database.py myapp myapp
    python3 migrate_database.py oldname newname
    python3 migrate_database.py prod_blinko prod_blinko --clean  # Drop existing data first

WARNING: Without --clean flag, pg_restore will attempt to restore objects. If objects already
exist, it may fail with errors or cause data conflicts (duplicate key violations, etc.).
Use --clean to drop existing objects before restoring (this will DELETE all existing data).
"""

import subprocess
import sys
import argparse
import base64
import tempfile
import os


# Configuration
SOURCE_POD = "prod-postgres-cluster-0"
SOURCE_NAMESPACE = "homelab"
SOURCE_CONTAINER = "prod-postgres-cluster"
SOURCE_DEFAULT_USER = "homelab"  # Default user for old server

DEST_POD = "postgres-statefulset-0"
DEST_NAMESPACE = "shared"
DEST_CONTAINER = "postgres"
DEST_DEFAULT_USER = "postgres"  # Default user for new server


def run_kubectl_exec(pod, namespace, container, command, stdin=None, binary=False):
    """Execute a command in a Kubernetes pod using kubectl exec."""
    cmd = [
        "kubectl", "exec", "-n", namespace, pod,
        "-c", container, "--"
    ] + command
    
    try:
        if stdin:
            result = subprocess.run(
                cmd,
                input=stdin,
                capture_output=True,
                text=not binary,
                check=True
            )
        else:
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=not binary,
                check=True
            )
        return result.stdout, result.stderr
    except subprocess.CalledProcessError as e:
        print(f"Error executing command: {' '.join(cmd)}", file=sys.stderr)
        print(f"Exit code: {e.returncode}", file=sys.stderr)
        if not binary:
            print(f"stdout: {e.stdout}", file=sys.stderr)
            print(f"stderr: {e.stderr}", file=sys.stderr)
        raise


def check_pod_exists(pod, namespace):
    """Check if a pod exists and is running."""
    try:
        result = subprocess.run(
            ["kubectl", "get", "pod", pod, "-n", namespace],
            capture_output=True,
            text=True,
            check=True
        )
        # Check if pod is running
        if "Running" in result.stdout:
            return True
        return False
    except subprocess.CalledProcessError:
        return False


def check_database_exists(pod, namespace, container, db_name, pg_user):
    """Check if a database exists on a PostgreSQL server."""
    psql_cmd = [
        "psql", "-U", pg_user, "-tAc",
        f"SELECT 1 FROM pg_database WHERE datname='{db_name}'"
    ]
    
    try:
        stdout, _ = run_kubectl_exec(pod, namespace, container, psql_cmd)
        return stdout.strip() == "1"
    except subprocess.CalledProcessError:
        return False


def dump_database(pod, namespace, container, db_name, pg_user):
    """Dump a database from the source server."""
    print(f"Dumping database '{db_name}' from source server...")
    
    # Use pg_dump with stdout to avoid file I/O issues
    dump_cmd = [
        "pg_dump",
        "-U", pg_user,
        "-F", "c",  # Custom format (compressed)
        db_name
    ]
    
    # Get the dump directly from stdout
    dump_data, _ = run_kubectl_exec(pod, namespace, container, dump_cmd, binary=True)
    
    if not dump_data or len(dump_data) == 0:
        raise RuntimeError(f"Failed to dump database '{db_name}': dump is empty")
    
    print(f"Successfully dumped database '{db_name}' ({len(dump_data)} bytes).")
    
    return dump_data  # Return as bytes for binary data


def fix_database_permissions(pod, namespace, container, db_name, db_user, pg_user):
    """Fix permissions for the database user after migration."""
    print(f"Fixing permissions for user '{db_user}' on database '{db_name}'...")
    
    # Get all schemas owned by the database user or that need permissions
    fix_perms_cmd = [
        "psql", "-U", pg_user, "-d", db_name, "-tAc",
        f"""
        DO $$
        DECLARE
            schema_rec RECORD;
        BEGIN
            -- Grant permissions on all schemas to the database user
            FOR schema_rec IN 
                SELECT nspname 
                FROM pg_namespace 
                WHERE nspname NOT IN ('pg_catalog', 'information_schema', 'pg_toast', 'pg_toast_temp_1')
            LOOP
                -- Grant usage and create on schema
                EXECUTE format('GRANT USAGE ON SCHEMA %I TO %I', schema_rec.nspname, '{db_user}');
                EXECUTE format('GRANT CREATE ON SCHEMA %I TO %I', schema_rec.nspname, '{db_user}');
                
                -- Grant privileges on all existing tables
                EXECUTE format('GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA %I TO %I', schema_rec.nspname, '{db_user}');
                
                -- Grant privileges on all existing sequences
                EXECUTE format('GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA %I TO %I', schema_rec.nspname, '{db_user}');
                
                -- Set default privileges for future objects
                EXECUTE format('ALTER DEFAULT PRIVILEGES IN SCHEMA %I GRANT ALL ON TABLES TO %I', schema_rec.nspname, '{db_user}');
                EXECUTE format('ALTER DEFAULT PRIVILEGES IN SCHEMA %I GRANT ALL ON SEQUENCES TO %I', schema_rec.nspname, '{db_user}');
                
                -- Change ownership to database user if schema is not system-owned
                IF schema_rec.nspname != 'public' THEN
                    EXECUTE format('ALTER SCHEMA %I OWNER TO %I', schema_rec.nspname, '{db_user}');
                END IF;
            END LOOP;
            
            -- Grant database connection privilege
            EXECUTE format('GRANT CONNECT ON DATABASE %I TO %I', '{db_name}', '{db_user}');
        END $$;
        """
    ]
    
    try:
        run_kubectl_exec(pod, namespace, container, fix_perms_cmd)
        print(f"Successfully fixed permissions for user '{db_user}'.")
    except subprocess.CalledProcessError as e:
        print(f"Warning: Could not fix all permissions automatically. You may need to fix them manually.", file=sys.stderr)
        print(f"Error: {e.stderr}", file=sys.stderr)


def restore_database(pod, namespace, container, db_name, dump_data, pg_user, clean=False):
    """Restore a database dump to the destination server."""
    print(f"Restoring database '{db_name}' to destination server...")
    
    # For large dumps, use kubectl cp instead of base64 encoding to avoid command line length limits
    # Write dump to a temporary file locally, then copy it to the pod
    with tempfile.NamedTemporaryFile(delete=False, suffix='.dump') as tmp_file:
        tmp_path = tmp_file.name
        tmp_file.write(dump_data)
    
    try:
        # Copy dump file to pod using kubectl cp
        print("Copying dump file to destination pod...")
        cp_cmd = [
            "kubectl", "cp", tmp_path,
            f"{namespace}/{pod}:/tmp/dump.dump",
            "-c", container
        ]
        subprocess.run(cp_cmd, check=True, capture_output=True)
        print("Dump file copied successfully.")
    finally:
        # Clean up local temporary file
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
    
    # Restore the dump
    restore_cmd = [
        "pg_restore",
        "-U", pg_user,
        "-d", db_name,
        "-v",  # Verbose
        "--no-owner",  # Don't restore ownership
        "--no-acl",  # Don't restore access privileges
    ]
    
    # Add --clean flag if requested (drops existing objects before restoring)
    if clean:
        restore_cmd.append("--clean")
        print("WARNING: Using --clean flag. This will drop all existing objects in the destination database!")
    
    restore_cmd.append("/tmp/dump.dump")
    
    try:
        run_kubectl_exec(pod, namespace, container, restore_cmd)
        print(f"Successfully restored database '{db_name}'.")
    finally:
        # Clean up remote dump file
        rm_cmd = ["rm", "/tmp/dump.dump"]
        try:
            run_kubectl_exec(pod, namespace, container, rm_cmd)
        except subprocess.CalledProcessError:
            pass  # Ignore cleanup errors


def main():
    parser = argparse.ArgumentParser(
        description="Migrate PostgreSQL database between Kubernetes pods",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s myapp myapp
  %(prog)s oldname newname
  %(prog)s source_db dest_db
        """
    )
    parser.add_argument(
        "source_db",
        help="Name of the source database (on old server: prod-postgres-cluster-0)"
    )
    parser.add_argument(
        "dest_db",
        help="Name of the destination database (on new server: postgres-statefulset-0)"
    )
    parser.add_argument(
        "--source-user",
        default=SOURCE_DEFAULT_USER,
        help=f"PostgreSQL user for source server (default: {SOURCE_DEFAULT_USER})"
    )
    parser.add_argument(
        "--dest-user",
        default=DEST_DEFAULT_USER,
        help=f"PostgreSQL user for destination server (default: {DEST_DEFAULT_USER})"
    )
    parser.add_argument(
        "--clean",
        action="store_true",
        help="Drop existing objects before restoring (WARNING: This will delete all existing data in the destination database)"
    )
    args = parser.parse_args()
    
    print("=" * 60)
    print("PostgreSQL Database Migration Script")
    print("=" * 60)
    print(f"Source: {SOURCE_POD} ({SOURCE_NAMESPACE}) - Database: {args.source_db}")
    print(f"Destination: {DEST_POD} ({DEST_NAMESPACE}) - Database: {args.dest_db}")
    print("=" * 60)
    print()
    
    # Check if pods exist and are running
    print("Checking source pod...")
    if not check_pod_exists(SOURCE_POD, SOURCE_NAMESPACE):
        print(f"ERROR: Source pod '{SOURCE_POD}' not found or not running in namespace '{SOURCE_NAMESPACE}'", file=sys.stderr)
        sys.exit(1)
    print(f"✓ Source pod '{SOURCE_POD}' is running")
    
    print("Checking destination pod...")
    if not check_pod_exists(DEST_POD, DEST_NAMESPACE):
        print(f"ERROR: Destination pod '{DEST_POD}' not found or not running in namespace '{DEST_NAMESPACE}'", file=sys.stderr)
        sys.exit(1)
    print(f"✓ Destination pod '{DEST_POD}' is running")
    print()
    
    # Check if source database exists
    print(f"Checking if source database '{args.source_db}' exists...")
    if not check_database_exists(SOURCE_POD, SOURCE_NAMESPACE, SOURCE_CONTAINER, args.source_db, args.source_user):
        print(f"ERROR: Source database '{args.source_db}' does not exist", file=sys.stderr)
        sys.exit(1)
    print(f"✓ Source database '{args.source_db}' exists")
    
    # Check if destination database exists
    print(f"Checking if destination database '{args.dest_db}' exists...")
    if not check_database_exists(DEST_POD, DEST_NAMESPACE, DEST_CONTAINER, args.dest_db, args.dest_user):
        print(f"ERROR: Destination database '{args.dest_db}' does not exist. Please create it first.", file=sys.stderr)
        sys.exit(1)
    print(f"✓ Destination database '{args.dest_db}' exists")
    print()
    
    # Dump source database
    dump_data = dump_database(SOURCE_POD, SOURCE_NAMESPACE, SOURCE_CONTAINER, args.source_db, args.source_user)
    print()
    
    # Restore to destination database
    restore_database(DEST_POD, DEST_NAMESPACE, DEST_CONTAINER, args.dest_db, dump_data, args.dest_user, clean=args.clean)
    print()
    
    # Fix permissions for the database user (assuming db user name matches db name)
    # This fixes schema ownership and permissions that were lost due to --no-owner and --no-acl
    fix_database_permissions(DEST_POD, DEST_NAMESPACE, DEST_CONTAINER, args.dest_db, args.dest_db, args.dest_user)
    print()
    
    print("=" * 60)
    print("Migration completed successfully!")
    print("=" * 60)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n\nMigration interrupted by user.", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"\n\nERROR: {e}", file=sys.stderr)
        sys.exit(1)
