"""Exercise the exact claim expression provisioned in Authentik."""

import importlib.util
import contextlib
import io
import json
from pathlib import Path
from types import SimpleNamespace
import unittest
from unittest.mock import MagicMock, patch


SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "reconcile-email-mapping.py"
spec = importlib.util.spec_from_file_location("email_mapping", SCRIPT)
mapping = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mapping)


class VerifiedEmailTests(unittest.TestCase):
    def claims(self, **changes):
        user = dict(pk=7, username="morten", email="morten@olsen.pro", is_active=True)
        user.update(changes)
        namespace = {}
        source = "def evaluate(request):\n" + "\n".join(
            "    " + line for line in mapping.EXPRESSION.splitlines()
        )
        exec(compile(source, "<mealie-email-mapping>", "exec"), namespace)
        return namespace["evaluate"](SimpleNamespace(user=SimpleNamespace(**user)))

    def test_approved_account_and_address_are_verified(self):
        self.assertEqual(
            self.claims(), {"email": "morten@olsen.pro", "email_verified": True}
        )

    def test_other_account_cannot_claim_the_approved_address(self):
        self.assertIs(self.claims(pk=8)["email_verified"], False)

    def test_renamed_or_recreated_account_is_not_verified(self):
        self.assertIs(self.claims(username="someone-else")["email_verified"], False)
        self.assertIs(self.claims(pk=8, username="morten")["email_verified"], False)

    def test_changed_address_is_not_verified(self):
        for address in ("other@example.com", "", None, "Morten@olsen.pro"):
            with self.subTest(address=address):
                claims = self.claims(email=address)
                self.assertEqual(claims["email"], address)
                self.assertIs(claims["email_verified"], False)

    def test_inactive_account_is_not_verified(self):
        self.assertIs(self.claims(is_active=False)["email_verified"], False)


class ScopeCollisionTests(unittest.TestCase):
    """Run the provisioning program against a small in-memory ORM adapter."""

    def provision(self, candidates, apply):
        class Query:
            def __init__(self, **terms):
                self.matches = lambda row: all(
                    getattr(row, key.removesuffix("__iexact")).lower() == value.lower()
                    if key.endswith("__iexact") else getattr(row, key) == value
                    for key, value in terms.items()
                )

            def __or__(self, other):
                combined = Query()
                combined.matches = lambda row: self.matches(row) or other.matches(row)
                return combined

        class Rows(list):
            def select_for_update(self):
                return self

        model = MagicMock()
        model.objects.filter.side_effect = lambda query: Rows(
            row for row in candidates if query.matches(row)
        )
        user = SimpleNamespace(pk=7, username="morten", email="morten@olsen.pro", is_active=True)
        user_model = MagicMock()
        user_model.objects.get.return_value = user
        db = SimpleNamespace(connection=MagicMock(), transaction=SimpleNamespace(atomic=contextlib.nullcontext))
        provider_model = MagicMock()
        provider_model.objects.filter.return_value.exclude.return_value.exists.return_value = False
        modules = {
            "django.db": db,
            "django.db.models": SimpleNamespace(Q=Query),
            "authentik.core.models": SimpleNamespace(User=user_model),
            "authentik.providers.oauth2.models": SimpleNamespace(OAuth2Provider=provider_model, ScopeMapping=model),
        }
        settings = dict(apply=apply, name=mapping.NAME, scope=mapping.SCOPE, expression=mapping.EXPRESSION)
        output = io.StringIO()
        with patch.dict("sys.modules", modules), patch("sys.stdin", io.StringIO(json.dumps(settings))), contextlib.redirect_stdout(output):
            exec(compile(mapping.REMOTE, "<remote-provisioning>", "exec"), {})
        model.assert_not_called()
        for candidate in candidates:
            candidate.save.assert_not_called()
        return json.loads(output.getvalue().removeprefix("MEALIE_MAPPING_RESULT="))

    def test_differently_named_case_variant_blocks_check_and_apply(self):
        for apply in (False, True):
            for scope in ("MEALIE-EMAIL", "Mealie-Email"):
                with self.subTest(apply=apply, scope=scope):
                    candidate = SimpleNamespace(name="conflicting mapping", scope_name=scope, managed=None, save=MagicMock())
                    result = self.provision([candidate], apply)
                    self.assertFalse(result["ok"])
                    self.assertIn("Mapping identity conflicts", result["error"])

    def test_exact_and_case_variant_duplicates_block_check_and_apply(self):
        for apply in (False, True):
            with self.subTest(apply=apply):
                candidates = [
                    SimpleNamespace(name=mapping.NAME, scope_name=mapping.SCOPE, managed=None, expression=mapping.EXPRESSION, save=MagicMock()),
                    SimpleNamespace(name="other mapping", scope_name="MEALIE-EMAIL", managed=None, save=MagicMock()),
                ]
                result = self.provision(candidates, apply)
                self.assertFalse(result["ok"])
                self.assertIn("Duplicate mapping", result["error"])


if __name__ == "__main__":
    unittest.main()
