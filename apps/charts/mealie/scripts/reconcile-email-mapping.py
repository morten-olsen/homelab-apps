#!/usr/bin/env python3
"""Check (default) or provision the approved Mealie-only Authentik scope.

Uses the existing Authentik server's configuration interface through ak shell;
no API token, user password, or Kubernetes Secret is read or printed.
"""

import argparse
import json
import subprocess
import sys


NAME = "prod-mealie verified email"
SCOPE = "mealie-email"
EXPRESSION = '''return {
    "email": request.user.email,
    "email_verified": bool(
        request.user.is_active
        and request.user.pk == 7
        and request.user.username == "morten"
        and request.user.email == "morten@olsen.pro"
    ),
}'''

# This code runs inside Authentik. In check mode PostgreSQL also enforces that
# the transaction is read-only. Provider bindings remain the operator's job.
REMOTE = '''
import json
import sys
from django.db import connection, transaction
from django.db.models import Q
from authentik.core.models import User
from authentik.providers.oauth2.models import OAuth2Provider, ScopeMapping

settings = json.load(sys.stdin)
try:
    with transaction.atomic():
        if not settings["apply"]:
            with connection.cursor() as cursor:
                cursor.execute("SET TRANSACTION READ ONLY")
        user = User.objects.get(pk=7)
        if not (user.is_active and user.username == "morten" and user.email == "morten@olsen.pro"):
            raise ValueError("Approved Authentik identity no longer matches; stop for a new decision")
        OAuth2Provider.objects.get(name="prod-mealie")
        candidates = ScopeMapping.objects.filter(
            Q(scope_name=settings["scope"]) | Q(name=settings["name"])
        )
        if settings["apply"]:
            candidates = candidates.select_for_update()
        matches = list(candidates)
        if len(matches) > 1:
            raise ValueError("Duplicate mapping name or scope; refusing to select by ordering")
        mapping = matches[0] if matches else None
        if mapping:
            if mapping.name != settings["name"] or mapping.scope_name != settings["scope"] or mapping.managed:
                raise ValueError("Mapping identity conflicts with another scope or managed mapping")
            if OAuth2Provider.objects.filter(property_mappings=mapping).exclude(name="prod-mealie").exists():
                raise ValueError("Mapping is attached to another provider; refusing to change its policy")
        state = "present" if mapping and mapping.expression == settings["expression"] else "drift" if mapping else "missing"
        if settings["apply"] and state != "present":
            if mapping is None:
                mapping = ScopeMapping(name=settings["name"], scope_name=settings["scope"])
            mapping.expression = settings["expression"]
            mapping.description = "Morten approved user 7/morten and exact address in task 842a05bd-9c04-4b06-a390-acf65155ebe2"
            mapping.save()
            state = "present"
        result = {"ok": state == "present", "state": state, "scope": settings["scope"], "mode": "apply" if settings["apply"] else "check"}
except ValueError as error:
    result = {"ok": False, "error": str(error)}
except Exception as error:
    result = {"ok": False, "error": "Authentik configuration check failed", "error_type": type(error).__name__}
print("MEALIE_MAPPING_RESULT=" + json.dumps(result))
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true", help="Provision the reviewed mapping (requires approved authentication change)")
    args = parser.parse_args()
    completed = subprocess.run(
        ["kubectl", "exec", "-i", "-n", "shared", "deploy/authentik-server", "-c", "authentik", "--", "ak", "shell", "-c", REMOTE],
        input=json.dumps({"apply": args.apply, "name": NAME, "scope": SCOPE, "expression": EXPRESSION}),
        text=True,
        capture_output=True,
        timeout=60,
        check=False,
    )
    # Authentik startup logs are deliberately omitted. Only our narrow result
    # reaches the caller, including when remote configuration validation fails.
    results = [line.removeprefix("MEALIE_MAPPING_RESULT=") for line in completed.stdout.splitlines() if line.startswith("MEALIE_MAPPING_RESULT=")]
    if completed.returncode or len(results) != 1:
        print("Authentik command failed without a safe result; no credentials/log payloads printed", file=sys.stderr)
        return 1
    result = json.loads(results[0])
    print(json.dumps(result, indent=2))
    return 0 if result["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
