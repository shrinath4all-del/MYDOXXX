"""Offline/loopback tests using temporary fake credentials and assets only.

Run: python scripts/mydoxxx/test_serve_test_lab.py
No Firebase/Google calls and no real credential or app-build files are read.
"""
from __future__ import annotations

from copy import deepcopy
import functools
import http.client
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import unittest
from http.server import ThreadingHTTPServer

MODULE_PATH = Path(__file__).with_name("serve-test-lab.py")
SPEC = importlib.util.spec_from_file_location("mydox_test_host", MODULE_PATH)
HOST = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(HOST)


def fake_credentials():
    accounts = {}
    for key in HOST.ROLE_LABELS:
        family, _ = HOST.identity_of(key)
        role = "agency" if family.startswith("agency_") else family
        accounts[key] = {
            "roleKey": key, "role": role,
            "uid": "mdxtest" + key.replace("_", ""),
            "email": key + "@mydoxxx-test.invalid",
            "password": "fixture-only-not-a-real-password-" + key + "-0000000000",
        }
    return {"projectId": HOST.PROJECT, "databaseId": HOST.DATABASE, "accounts": accounts}


class CredentialValidationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="mydox-host-test-")
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name) / "fixture.json"

    def load(self, data):
        self.path.write_text(json.dumps(data), encoding="utf-8")
        return HOST.load_credentials(self.path)

    def test_accepts_exact_thirty_six_synthetic_accounts(self):
        data = fake_credentials()
        self.assertEqual(len(data["accounts"]), 36)
        self.assertEqual(self.load(data), data)

    def test_each_family_has_three_unique_exact_identities(self):
        data = self.load(fake_credentials())
        for family in HOST.FAMILY_LABELS:
            for person in (1, 2, 3):
                key = family if person == 1 else f"{family}_{person}"
                a = data["accounts"][key]
                self.assertEqual(a["uid"], "mdxtest" + key.replace("_", ""))
                self.assertEqual(a["role"], "agency" if family.startswith("agency_") else family)

    def test_rejects_numbered_account_with_base_uid_or_wrong_role(self):
        for key, field, value in (("doctor_2", "uid", "mdxtestdoctor"),
                                  ("agency_care_3", "role", "agency_care"),
                                  ("nurse_3", "role", "nurse_3")):
            data = fake_credentials(); data["accounts"][key][field] = value
            with self.assertRaises(ValueError): self.load(data)

    def test_rejects_wrong_project_database_and_role_set(self):
        for field, value in (("projectId", "protected-project"), ("databaseId", "(default)")):
            with self.subTest(field=field):
                data = fake_credentials(); data[field] = value
                with self.assertRaises(ValueError): self.load(data)
        for extra in (False, True):
            data = fake_credentials()
            if extra: data["accounts"]["unlisted"] = deepcopy(data["accounts"]["patient"])
            else: del data["accounts"]["patient"]
            with self.assertRaises(ValueError): self.load(data)

    def test_rejects_wrong_uid_role_email_and_password(self):
        for field, value in (("uid", "mdxtestdifferent"), ("role", "admin"),
                             ("roleKey", "doctor"), ("email", "someone@example.com"),
                             ("password", "short"), ("password", None)):
            with self.subTest(field=field):
                data = fake_credentials(); data["accounts"]["patient"][field] = value
                with self.assertRaises(ValueError): self.load(data)

    def test_rejects_duplicate_email(self):
        data = fake_credentials()
        data["accounts"]["doctor"]["email"] = data["accounts"]["patient"]["email"]
        with self.assertRaises(ValueError): self.load(data)

    def test_validation_survives_python_optimized_mode(self):
        data = fake_credentials(); data["projectId"] = "protected-project"
        self.path.write_text(json.dumps(data), encoding="utf-8")
        code = ("import importlib.util,pathlib,sys;"
                "s=importlib.util.spec_from_file_location('host',sys.argv[1]);"
                "m=importlib.util.module_from_spec(s);s.loader.exec_module(m);"
                "m.load_credentials(pathlib.Path(sys.argv[2]))")
        result = subprocess.run([sys.executable, "-O", "-c", code, str(MODULE_PATH), str(self.path)], capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b"ValueError", result.stderr)


class PathBoundaryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="mydox-host-path-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve() / "web"
        self.root.mkdir()
        (self.root / "index.html").write_text("fixture home")
        (self.root / "main.dart.js").write_text("fixture javascript")
        self.outside = self.root.parent / "outside.txt"
        self.outside.write_text("OUTSIDE-FIXTURE-CANARY")

    def test_serves_only_real_files_within_build_root(self):
        self.assertEqual(HOST.resolve_asset(self.root, "/?role=patient"), self.root / "index.html")
        self.assertEqual(HOST.resolve_asset(self.root, "/main.dart.js?v=1"), self.root / "main.dart.js")
        self.assertIsNone(HOST.resolve_asset(self.root, "/not-here.txt"))

    def test_rejects_traversal_hidden_windows_and_nul_paths(self):
        for path in ("/../outside.txt", "/%2e%2e/outside.txt", "/%2E%2E%2foutside.txt",
                     "/%5c..%5coutside.txt", "/C:/outside.txt", "/.git/config", "/%00.txt"):
            with self.subTest(path=path): self.assertIsNone(HOST.resolve_asset(self.root, path))

    def test_refuses_symlink_escape_where_supported(self):
        link = self.root / "escape.txt"
        try: link.symlink_to(self.outside)
        except (OSError, NotImplementedError): self.skipTest("Creating symlinks is not permitted on this test host")
        self.assertIsNone(HOST.resolve_asset(self.root, "/escape.txt"))


class BootstrapTests(unittest.TestCase):
    def test_adds_cpu_canvas_configuration_and_preserves_every_original_byte(self):
        original = (b"/* generated loader */\n_flutter.loader.load({\n"
                    b"  serviceWorkerSettings: {serviceWorkerVersion: 'fixture'},\n"
                    b"  onEntrypointLoaded: function(engine) { return engine; }\n});\n")
        patched = HOST.lab_flutter_bootstrap(original)
        inserted = b"\n  config: {canvasKitForceCpuOnly: true, canvasKitMaximumSurfaces: 1},"
        self.assertEqual(patched.count(inserted), 1)
        self.assertEqual(patched.replace(inserted, b"", 1), original)

    def test_refuses_unknown_duplicate_existing_or_incomplete_loader(self):
        for data in (b"unknown generated bootstrap", b"_flutter.loader.load ({ });",
                     b"_flutter.loader.load({});_flutter.loader.load({});",
                     b"_flutter.loader.load({config: {renderer: 'html'}});",
                     b"_flutter.loader.load({'config': {}});",
                     b"_flutter.loader.load({config});",
                     b"_flutter.loader.load({serviceWorkerSettings: {}"):
            with self.subTest(data=data):
                with self.assertRaises(ValueError): HOST.lab_flutter_bootstrap(data)


class HttpIsolationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix="mydox-host-http-")
        cls.root = Path(cls.temp.name).resolve() / "web"
        cls.root.mkdir()
        (cls.root / "index.html").write_text("fixture app shell")
        (cls.root / "main.dart.js").write_text("fixture javascript")
        cls.bootstrap = b"_flutter.loader.load({\n serviceWorkerSettings: {serviceWorkerVersion: 'fixture'}\n});\n"
        (cls.root / "flutter_bootstrap.js").write_bytes(cls.bootstrap)
        (cls.root / "other.js").write_bytes(cls.bootstrap)
        (cls.root / "test.wasm").write_bytes(b"\0asm")
        (cls.root.parent / "outside.txt").write_text("OUTSIDE-FIXTURE-CANARY")
        cls.creds = fake_credentials()
        cls.servers = {}
        cls.threads = []
        for role in ("patient", "doctor", "doctor_2", "agency_care_3", None):
            handler = functools.partial(HOST.Handler, build=cls.root, credentials=cls.creds,
                                        role=role, catalog=HOST.public_catalog(12000))
            server = ThreadingHTTPServer(("127.0.0.1", 0), handler)
            cls.servers[role] = server
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start(); cls.threads.append(thread)

    @classmethod
    def tearDownClass(cls):
        for server in cls.servers.values(): server.shutdown(); server.server_close()
        for thread in cls.threads: thread.join(timeout=2)
        cls.temp.cleanup()

    def request(self, role="patient", path="/__mydox_test__/login-config", *, method="GET", headers=None):
        server = self.servers[role]
        connection = http.client.HTTPConnection("127.0.0.1", server.server_port, timeout=3)
        connection.putrequest(method, path, skip_host=True)
        items = list(headers or [])
        if not any(k.lower() == "host" for k, _ in items):
            items.insert(0, ("Host", f"127.0.0.1:{server.server_port}"))
        for name, value in items: connection.putheader(name, value)
        connection.endheaders()
        response = connection.getresponse()
        result = response.status, dict(response.getheaders()), response.read()
        connection.close()
        return result

    def assert_no_password(self, body):
        for account in self.creds["accounts"].values():
            self.assertNotIn(account["password"].encode(), body)

    def test_per_role_credentials_exact_fields_and_no_cache(self):
        for role in ("patient", "doctor", "doctor_2", "agency_care_3"):
            port = self.servers[role].server_port
            status, headers, body = self.request(role, headers=[("X-MyDox-Test-Client", "1"), ("Origin", f"http://127.0.0.1:{port}")])
            self.assertEqual(status, 200)
            data = json.loads(body)
            self.assertEqual(set(data), {"projectId", "databaseId", "roleKey", "role", "uid", "email", "password"})
            self.assertEqual(data["roleKey"], role)
            self.assertEqual(data["uid"], self.creds["accounts"][role]["uid"])
            self.assertNotIn("accounts", data)
            self.assertEqual(headers["Cache-Control"], "no-store")
            self.assertEqual(headers["X-Content-Type-Options"], "nosniff")
            self.assertEqual(headers["Referrer-Policy"], "no-referrer")
            self.assertNotIn("Access-Control-Allow-Origin", headers)
            for other, a in self.creds["accounts"].items():
                if other != role: self.assertNotIn(a["password"].encode(), body)

    def test_query_cannot_choose_another_roles_credentials(self):
        status, _, body = self.request(path="/__mydox_test__/login-config?role=doctor", headers=[("X-MyDox-Test-Client", "1")])
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(body)["roleKey"], "patient")

    def test_rejects_missing_header_cross_origin_cross_site_and_null_origin(self):
        port = self.servers["doctor"].server_port
        cases = [[], [("X-MyDox-Test-Client", "0")],
                 [("X-MyDox-Test-Client", "1"), ("Origin", "https://example.com")],
                 [("X-MyDox-Test-Client", "1"), ("Origin", f"http://127.0.0.1:{port}")],
                 [("X-MyDox-Test-Client", "1"), ("Origin", "null")],
                 [("X-MyDox-Test-Client", "1"), ("Sec-Fetch-Site", "cross-site")]]
        for headers in cases:
            with self.subTest(headers=headers):
                status, _, body = self.request(headers=headers)
                self.assertEqual(status, 403); self.assert_no_password(body)

    def test_rejects_wrong_or_duplicate_host_and_security_headers(self):
        port = self.servers["patient"].server_port
        cases = [[("Host", "evil.example"), ("X-MyDox-Test-Client", "1")],
                 [("Host", f"127.0.0.1:{port+1}"), ("X-MyDox-Test-Client", "1")],
                 [("Host", f"127.0.0.1:{port}"), ("Host", "evil.example"), ("X-MyDox-Test-Client", "1")],
                 [("X-MyDox-Test-Client", "1"), ("X-MyDox-Test-Client", "1")],
                 [("X-MyDox-Test-Client", "1"), ("Origin", f"http://127.0.0.1:{port}"), ("Origin", "https://example.com")]]
        for headers in cases:
            with self.subTest(headers=headers):
                status, _, body = self.request(headers=headers)
                self.assertEqual(status, 403); self.assert_no_password(body)

    def test_no_credentials_for_console_head_post_or_preflight(self):
        for role, method, expected in ((None, "GET", 403), ("patient", "HEAD", 403),
                                        ("patient", "POST", 405), ("patient", "OPTIONS", 403)):
            with self.subTest(role=role, method=method):
                status, headers, body = self.request(role, method=method, headers=[("X-MyDox-Test-Client", "1")])
                self.assertEqual(status, expected); self.assert_no_password(body)
                self.assertNotIn("Access-Control-Allow-Origin", headers)

    def test_console_catalog_has_only_public_role_metadata(self):
        status, _, body = self.request(None, "/catalog.json")
        self.assertEqual(status, 200)
        catalog = json.loads(body)
        self.assertEqual(catalog["projectId"], HOST.PROJECT)
        self.assertEqual(len(catalog["roles"]), 36)
        self.assertEqual(set(catalog["roles"][0]), {"key", "label", "family", "person", "uid", "url"})
        self.assert_no_password(body)

    def test_legacy_ports_are_stable_and_new_accounts_append(self):
        legacy = ("patient", "doctor", "nurse", "hospital", "ambulance", "care_physician",
                  "care_physician_2", "care_physician_3", "technician", "therapist",
                  "agency_care", "agency_nurse", "agency_technician", "agency_physio")
        catalog = HOST.public_catalog(8891)
        self.assertEqual(tuple(r["key"] for r in catalog[:14]), legacy)
        self.assertEqual(len({r["uid"] for r in catalog}), 36)
        self.assertEqual(len({r["url"] for r in catalog}), 36)
        for i, key in enumerate(legacy):
            self.assertEqual(catalog[i]["url"], f"http://127.0.0.1:{8891+i}/?role={key}&autologin=1")

    def test_console_serves_only_whitelisted_public_scripts(self):
        for path in ("/test-console.js", "/test-console-state.js"):
            status, headers, body = self.request(None, path)
            self.assertEqual(status, 200)
            self.assertIn("javascript", headers["Content-Type"])
            self.assert_no_password(body)
        for path in ("/serve-test-lab.py", "/test-lab-credentials.json", "/../common.cjs"):
            status, _, body = self.request(None, path)
            self.assertEqual(status, 404); self.assert_no_password(body)

    def test_assets_and_wasm_mime_but_no_outside_or_hidden_files(self):
        status, headers, body = self.request(path="/test.wasm")
        self.assertEqual((status, body), (200, b"\0asm"))
        self.assertEqual(headers["Content-Type"], "application/wasm")
        for path in ("/%2e%2e/outside.txt", "/.git/config", "/%5c..%5coutside.txt", "/__mydox_test__/anything"):
            with self.subTest(path=path):
                status, _, body = self.request(path=path)
                self.assertEqual(status, 404)
                self.assertNotIn(b"OUTSIDE-FIXTURE-CANARY", body)
                self.assert_no_password(body)

    def test_rejects_absolute_proxy_request_target(self):
        status, _, body = self.request(path="http://evil.example/__mydox_test__/login-config", headers=[("X-MyDox-Test-Client", "1")])
        self.assertEqual(status, 400); self.assert_no_password(body)

    def test_bootstrap_patch_is_response_only_and_exact_path_only(self):
        status, _, body = self.request(path="/flutter_bootstrap.js")
        self.assertEqual(status, 200)
        self.assertIn(b"canvasKitForceCpuOnly: true", body)
        self.assertIn(b"canvasKitMaximumSurfaces: 1", body)
        self.assertIn(b"serviceWorkerVersion: 'fixture'", body)
        self.assertEqual((self.root / "flutter_bootstrap.js").read_bytes(), self.bootstrap)
        status, _, other = self.request(path="/other.js")
        self.assertEqual(status, 200)
        self.assertEqual(other, self.bootstrap)

    def test_bootstrap_unexpected_shape_returns_unavailable_without_mutating_file(self):
        asset = self.root / "flutter_bootstrap.js"
        bad = b"_flutter.loader.load({config: {}});"
        try:
            asset.write_bytes(bad)
            status, _, body = self.request(path="/flutter_bootstrap.js")
            self.assertEqual(status, 503)
            self.assertNotIn(b"canvasKitForceCpuOnly", body)
            self.assertEqual(asset.read_bytes(), bad)
        finally:
            asset.write_bytes(self.bootstrap)


if __name__ == "__main__":
    unittest.main(verbosity=2)
