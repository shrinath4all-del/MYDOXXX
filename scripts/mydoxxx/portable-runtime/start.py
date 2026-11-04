"""Private MYDOXXX runtime launcher. Python stdlib only; no Firebase setup."""
import sys
if sys.version_info < (3, 10):
    print("Python 3.10 or newer is required. Nothing was installed or started.")
    raise SystemExit(2)

import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path, PurePosixPath
import socket
import subprocess
import time
import urllib.request
import webbrowser

sys.dont_write_bytecode = True
PROJECT = "mydoxxx-dev-261102"
DATABASE = "mydoxxx-testing"
ROOT = Path(__file__).resolve().parent
# Long Windows source/workspace paths must not break otherwise portable assets.
if os.name == "nt" and not str(ROOT).startswith("\\\\?\\"):
    value = str(ROOT)
    ROOT = Path("\\\\?\\UNC\\" + value[2:] if value.startswith("\\\\") else "\\\\?\\" + value)


class CheckError(Exception):
    pass


def local_file(root, relative):
    path = PurePosixPath(relative)
    if "\\" in relative or path.is_absolute() or not path.parts or any(x in {".", ".."} or ":" in x for x in path.parts):
        raise CheckError("Unsafe runtime file path in manifest.")
    candidate = root.joinpath(*path.parts)
    if any(p.is_symlink() for p in (candidate, *candidate.parents) if p != root.parent):
        raise CheckError("Runtime files must be extracted as ordinary files, not links.")
    if not candidate.resolve().is_relative_to(root) or not candidate.is_file():
        raise CheckError("Runtime file is missing. Extract the entire ZIP again: " + relative)
    return candidate


def verify_files(root):
    try:
        manifest = json.loads((root / "RUNTIME-MANIFEST.json").read_text(encoding="utf-8"))
    except (OSError, ValueError):
        raise CheckError("Runtime manifest is missing or invalid. Extract the entire private ZIP.") from None
    if (manifest.get("projectId") != PROJECT or manifest.get("databaseId") != DATABASE
            or manifest.get("containsPrivateTestCredentials") is not True):
        raise CheckError("This is not the isolated MYDOXXX runtime kit.")
    entries = manifest.get("files")
    if not isinstance(entries, list) or not entries:
        raise CheckError("The runtime manifest has no files.")
    seen = set()
    for entry in entries:
        if not isinstance(entry, dict) or not isinstance(entry.get("path"), str) or entry["path"] in seen:
            raise CheckError("Invalid or duplicate runtime manifest entry.")
        seen.add(entry["path"])
        path = local_file(root, entry["path"])
        data = path.read_bytes()
        if len(data) != entry.get("bytes") or hashlib.sha256(data).hexdigest() != entry.get("sha256"):
            raise CheckError("Runtime integrity check failed: " + entry["path"])
    required = {"start.py", "server/serve-test-lab.py", "server/test-console.html", "server/test-console.js",
                "server/test-console-state.js", "build/index.html", "build/main.dart.js", "build/flutter_bootstrap.js",
                "private/test-lab-credentials.json"}
    if not required.issubset(seen):
        raise CheckError("Runtime kit is incomplete.")
    for directory in ("build", "server"):
        for file in (root / directory).rglob("*"):
            if file.is_file() and file.relative_to(root).as_posix() not in seen:
                raise CheckError("Unexpected file in served runtime. Restore a clean kit: " + file.relative_to(root).as_posix())
    spec = importlib.util.spec_from_file_location("mydox_portable_host", root / "server/serve-test-lab.py")
    host = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(host)
    if host.PROJECT != PROJECT or host.DATABASE != DATABASE or len(host.ROLE_KEYS) != 36:
        raise CheckError("Unexpected project/database/account catalogue in runtime host.")
    try:
        credentials = host.load_credentials(root / "private/test-lab-credentials.json")
    except Exception:
        raise CheckError("The private 36-account credential file failed validation. Do not print or edit it.") from None
    if str(credentials.get("projectNumber")) != "724915428929":
        raise CheckError("Private credential project number does not match this experiment.")
    del credentials
    try:
        host.lab_flutter_bootstrap((root / "build/flutter_bootstrap.js").read_bytes())
    except ValueError:
        raise CheckError("The Flutter bootstrap is incompatible with the reviewed local host.") from None
    return manifest, len(host.ROLE_KEYS)


def check_ports(console_port, role_port, count):
    ports = [console_port, *range(role_port, role_port + count)]
    if len(set(ports)) != len(ports) or any(p < 1024 or p > 65535 for p in ports):
        raise CheckError("Choose distinct non-privileged ports from 1024 to 65535 for the console and 36 accounts.")
    held = []
    try:
        for port in ports:
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            held.append(sock)
            if os.name == "nt":
                sock.setsockopt(socket.SOL_SOCKET, socket.SO_EXCLUSIVEADDRUSE, 1)
            try:
                sock.bind(("127.0.0.1", port))
            except OSError:
                raise CheckError("Local port " + str(port) + " is unavailable. No existing app was stopped. "
                                 "Use --port 8989 --role-port 8991, or choose another free range.") from None
    finally:
        for sock in held:
            sock.close()


def run_server(root, console_port, role_port, open_browser):
    command = [sys.executable, "-B", str(root / "server/serve-test-lab.py"),
               "--build", str(root / "build"), "--credentials", str(root / "private/test-lab-credentials.json"),
               "--port", str(console_port), "--role-port", str(role_port)]
    url = "http://127.0.0.1:" + str(console_port) + "/"
    process = subprocess.Popen(command, cwd=root)
    try:
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
        deadline = time.monotonic() + 20
        while time.monotonic() < deadline:
            if process.poll() is not None:
                raise CheckError("Local host stopped during startup. Check the selected ports and extracted files.")
            try:
                with opener.open(url + "catalog.json", timeout=1) as response:
                    data = json.load(response)
                if data.get("projectId") == PROJECT and data.get("databaseId") == DATABASE and len(data.get("roles", [])) == 36:
                    break
            except (OSError, ValueError):
                pass
            time.sleep(0.15)
        else:
            raise CheckError("Local host did not become ready. No Firebase setup or account changes were attempted.")
        print("Ready: " + url, flush=True)
        print("Keep this launcher open. Ctrl+C stops only this kit's local server. Internet is required for shared test data.", flush=True)
        if open_browser:
            try:
                webbrowser.open(url)
            except Exception:
                print("Open the local URL above in your browser.", flush=True)
        return process.wait()
    except KeyboardInterrupt:
        print("Stopping this local test-room instance.")
        return 0
    finally:
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=8)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()


def main(argv=None):
    parser = argparse.ArgumentParser(description="Run the private portable MyDox test room; no install or backend setup.")
    parser.add_argument("--check", action="store_true", help="Validate files, private accounts and ports; start nothing and make no cloud calls")
    parser.add_argument("--port", type=int, default=8889, help="Loopback console port (default 8889)")
    parser.add_argument("--role-port", type=int, default=8891, help="First of 36 loopback account ports (default 8891)")
    parser.add_argument("--no-browser", action="store_true", help="Print URL without automatically opening a browser")
    args = parser.parse_args(argv)
    manifest, count = verify_files(ROOT)
    check_ports(args.port, args.role_port, count)
    print("Checks passed: Python, complete release, exact 36 private test accounts and available loopback ports.", flush=True)
    print("Target: " + PROJECT + "/" + DATABASE + "; source commit " + manifest.get("appCommit", "unknown"), flush=True)
    if args.check:
        print("Check only: no server started, no browser opened, no Firebase requests or writes.")
        return 0
    return run_server(ROOT, args.port, args.role_port, not args.no_browser)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except CheckError as error:
        print("Cannot start: " + str(error), file=sys.stderr)
        raise SystemExit(2)
    except (OSError, ValueError, TypeError, KeyError):
        print("Cannot start: a local runtime file or setting is invalid. No credential contents are printed.", file=sys.stderr)
        raise SystemExit(2)
