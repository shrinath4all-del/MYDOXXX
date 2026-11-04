"""Loopback-only host for the actual Flutter multi-role Firebase test build.

Each role has a different port. Credentials are supplied only to that role's
same-origin Flutter client and are never placed in compiled assets or logs.
"""
from __future__ import annotations

import argparse
import functools
import json
import mimetypes
import re
import signal
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote, urlsplit

PROJECT = "mydoxxx-dev-261102"
DATABASE = "mydoxxx-testing"
FAMILY_LABELS = {
    "patient": "Patient", "doctor": "Cardiologist", "nurse": "Nurse",
    "hospital": "Hospital", "ambulance": "Ambulance", "care_physician": "Care Physician",
    "technician": "Technician", "therapist": "Physiotherapist", "agency_care": "Care Agency",
    "agency_nurse": "Nursing Agency", "agency_technician": "Technician Agency", "agency_physio": "Physio Agency",
}
# Never reorder these: already-used role origins must retain their identities.
LEGACY_ROLE_KEYS = (
    "patient", "doctor", "nurse", "hospital", "ambulance", "care_physician",
    "care_physician_2", "care_physician_3", "technician", "therapist",
    "agency_care", "agency_nurse", "agency_technician", "agency_physio",
)
ROLE_KEYS = LEGACY_ROLE_KEYS + tuple(
    f"{family}_{person}" for family in FAMILY_LABELS for person in (2, 3)
    if f"{family}_{person}" not in LEGACY_ROLE_KEYS
)


def identity_of(key: str) -> tuple[str, int]:
    family = re.sub(r"_[23]$", "", key)
    return family, int(key[-1]) if family != key else 1


ROLE_LABELS = {key: f"{FAMILY_LABELS[identity_of(key)[0]]} {identity_of(key)[1]}" for key in ROLE_KEYS}


def allowed_host(host: str, port: int) -> bool:
    return host in {f"127.0.0.1:{port}", f"localhost:{port}"}


def allowed_origin(origin: str | None, host: str) -> bool:
    return origin is None or origin == f"http://{host}"


def resolve_asset(root: Path, request_path: str) -> Path | None:
    decoded = unquote(urlsplit(request_path).path)
    if "\x00" in decoded or "\\" in decoded:
        return None
    parts = Path(decoded.lstrip("/")).parts
    if any(part.startswith(".") or ":" in part for part in parts):
        return None
    candidate = (root / (decoded.lstrip("/") or "index.html")).resolve()
    if not candidate.is_relative_to(root):
        return None
    return candidate if candidate.is_file() else None


def public_catalog(base_port: int) -> list[dict]:
    return [dict(key=k, label=v, family=identity_of(k)[0], person=identity_of(k)[1],
                 uid="mdxtest" + k.replace("_", ""),
                 url=f"http://127.0.0.1:{base_port+i}/?role={k}&autologin=1")
            for i, (k, v) in enumerate(ROLE_LABELS.items())]


def lab_flutter_bootstrap(data: bytes) -> bytes:
    """Serve CPU CanvasKit for concurrent local panels without editing builds.

    Only the observed generated loader call is accepted. A changed bootstrap
    or existing config requires review instead of silently overriding settings.
    """
    marker = b"_flutter.loader.load({"
    if data.count(marker) != 1:
        raise ValueError("Expected exactly one generated Flutter loader call")
    before, arguments = data.split(marker, 1)
    if not re.search(rb"\}\);\s*\Z", arguments) or re.search(rb"\bconfig\b", arguments):
        raise ValueError("Unexpected Flutter bootstrap shape or existing loader config")
    config = b"\n  config: {canvasKitForceCpuOnly: true, canvasKitMaximumSurfaces: 1},"
    return before + marker + config + arguments


class Handler(BaseHTTPRequestHandler):
    server_version = "MyDoxLocalLab/1.0"

    def __init__(self, *args, build: Path, credentials: dict, role: str | None,
                 catalog: list[dict], **kwargs):
        self.build, self.credentials, self.role, self.catalog = build, credentials, role, catalog
        super().__init__(*args, **kwargs)

    def log_message(self, *_args):
        # Request paths and credential responses are deliberately never logged.
        pass

    def respond(self, code: int, data: bytes, content_type="text/plain; charset=utf-8"):
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "no-referrer")
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(data)

    def do_OPTIONS(self):
        self.respond(403, b"Cross-origin requests are not supported.")

    def do_POST(self):
        self.respond(405, b"Read-only local host.")

    def do_HEAD(self):
        self.do_GET()

    def do_GET(self):
        host = self.headers.get("Host", "")
        port = self.server.server_port
        if len(self.headers.get_all("Host", [])) != 1 or not allowed_host(host, port):
            self.respond(403, b"Loopback host required.")
            return
        try:
            target = urlsplit(self.path)
        except ValueError:
            self.respond(400, b"Invalid request target.")
            return
        if target.scheme or target.netloc:
            self.respond(400, b"Origin-form request target required.")
            return
        request_path = target.path
        if request_path == "/__mydox_test__/login-config":
            if (not self.role or self.command != "GET" or
                len(self.headers.get_all("X-MyDox-Test-Client", [])) != 1 or
                len(self.headers.get_all("Origin", [])) > 1 or
                len(self.headers.get_all("Sec-Fetch-Site", [])) > 1 or
                self.headers.get("X-MyDox-Test-Client") != "1" or
                not allowed_origin(self.headers.get("Origin"), host) or
                self.headers.get("Sec-Fetch-Site") == "cross-site"):
                self.respond(403, b"Same-origin test client required.")
                return
            a = self.credentials["accounts"][self.role]
            payload = {"projectId": PROJECT, "databaseId": DATABASE,
                       "roleKey": self.role, "role": a["role"],
                       "uid": a["uid"], "email": a["email"], "password": a["password"]}
            self.respond(200, json.dumps(payload).encode(), "application/json")
            return
        if request_path.startswith("/__mydox_test__/"):
            self.respond(404, b"Not found.")
            return
        if self.role is None:
            if request_path == "/catalog.json":
                self.respond(200, json.dumps({"projectId": PROJECT, "databaseId": DATABASE,
                                             "roles": self.catalog}).encode(), "application/json")
            elif request_path in {"/", "/index.html"}:
                self.respond(200, Path(__file__).with_name("test-console.html").read_bytes(),
                             "text/html; charset=utf-8")
            elif request_path in {"/test-console.js", "/test-console-state.js"}:
                self.respond(200, Path(__file__).with_name(request_path[1:]).read_bytes(),
                             "text/javascript; charset=utf-8")
            else:
                self.respond(404, b"Not found.")
            return
        asset = resolve_asset(self.build, self.path)
        if asset is None:
            self.respond(404, b"Not found.")
            return
        kind = mimetypes.guess_type(asset.name)[0] or "application/octet-stream"
        if asset.suffix == ".wasm":
            kind = "application/wasm"
        data = asset.read_bytes()
        if request_path == "/flutter_bootstrap.js":
            try:
                data = lab_flutter_bootstrap(data)
            except ValueError:
                self.respond(503, b"Local Flutter bootstrap needs review before the test panels can start.")
                return
        self.respond(200, data, kind)


def load_credentials(path: Path) -> dict:
    c = json.loads(path.read_text(encoding="utf-8-sig"))
    if not isinstance(c, dict) or c.get("projectId") != PROJECT or c.get("databaseId") != DATABASE:
        raise ValueError("Credential configuration must target the isolated MYDOXXX test database")
    if not isinstance(c.get("accounts"), dict) or set(c["accounts"]) != set(ROLE_LABELS):
        raise ValueError("Expected exactly the thirty-six synthetic accounts")
    emails = set()
    for key, account in c["accounts"].items():
        expected_uid = "mdxtest" + key.replace("_", "")
        family, _ = identity_of(key)
        expected_role = "agency" if family.startswith("agency_") else family
        if (not isinstance(account, dict) or account.get("roleKey") != key or
            account.get("uid") != expected_uid or account.get("role") != expected_role):
            raise ValueError("Synthetic account does not match its assigned role")
        email, password = account.get("email"), account.get("password")
        if (not isinstance(email, str) or not email.endswith("@mydoxxx-test.invalid") or
            email in emails or not isinstance(password, str) or len(password) < 35):
            raise ValueError("Synthetic account has invalid local test credentials")
        emails.add(email)
    return c


def main():
    root = Path(__file__).resolve().parents[2]
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8889)
    parser.add_argument("--role-port", type=int, default=8891)
    parser.add_argument("--build", type=Path, default=root / "experiments/MYDOXXX/app/build/web-lab")
    parser.add_argument("--credentials", type=Path,
                        default=root / "private-backups/mydoxxx-dev-261102/test-lab-credentials.json")
    args = parser.parse_args()
    build = args.build.resolve()
    if not (build / "index.html").is_file():
        raise ValueError("Build the MYDOXXX_TEST_LAB Flutter target first")
    if not (build / "main.dart.js").is_file():
        raise ValueError("Missing Flutter web JavaScript")
    creds = load_credentials(args.credentials)
    catalog = public_catalog(args.role_port)
    servers = []
    try:
        targets = [(args.port, None)] + [(args.role_port+i, key) for i, key in enumerate(ROLE_LABELS)]
        if len({port for port, _ in targets}) != len(targets):
            raise ValueError("The console and role ports must be distinct")
        if any(not 1 <= port <= 65535 for port, _ in targets):
            raise ValueError("All local test ports must be between 1 and 65535")
        for port, role in targets:
            handler = functools.partial(Handler, build=build, credentials=creds, role=role, catalog=catalog)
            servers.append(ThreadingHTTPServer(("127.0.0.1", port), handler))
        for server in servers:
            threading.Thread(target=server.serve_forever, daemon=True).start()
        print(f"MyDox live test room: http://127.0.0.1:{args.port}/", flush=True)
        print(f"{len(ROLE_LABELS)} isolated role origins; Firebase {PROJECT}/{DATABASE}; loopback only.", flush=True)
        stop = threading.Event()
        signal.signal(signal.SIGINT, lambda *_: stop.set())
        signal.signal(signal.SIGTERM, lambda *_: stop.set())
        stop.wait()
    finally:
        for server in servers:
            server.server_close()


if __name__ == "__main__":
    main()
