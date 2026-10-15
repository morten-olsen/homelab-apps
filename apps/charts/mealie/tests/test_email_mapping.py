"""Exercise the exact claim expression provisioned in Authentik."""

import importlib.util
from pathlib import Path
from types import SimpleNamespace
import unittest


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


if __name__ == "__main__":
    unittest.main()
