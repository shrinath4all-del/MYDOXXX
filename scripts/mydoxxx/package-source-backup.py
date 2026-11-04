"""Create a code-only MYDOXXX archive; no cloud calls, uploads or source edits.

Run with --audit first. Final packaging requires clean app/backend Git trees.
An explicit supplemental-file allowlist prevents private workspace data leaking.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[2]
PROJECT = "mydoxxx-dev-261102"
MAX_ZIP = 25_000_000
REPOS = ("experiments/MYDOXXX/app", "experiments/MYDOXXX/backend")
# Only these non-repository files may be included. Add a new reviewed helper
# explicitly; never recursively include the workspace or private-backups.
SUPPLEMENTS = (
    "experiments/MYDOXXX/README.md",
    "docs/mydoxxx-experiment-2026-11-02/STATUS.md",
    "scripts/mydoxxx/TEST-LAB.md",
    "scripts/mydoxxx/test-lab.cjs",
    "scripts/mydoxxx/test-lab-plan.cjs",
    "scripts/mydoxxx/test-lab-local-check.cjs",
    "scripts/mydoxxx/database-readiness.cjs",
    "scripts/mydoxxx/serve-test-lab.py",
    "scripts/mydoxxx/test-console.html",
    "scripts/mydoxxx/test_serve_test_lab.py",
    "scripts/mydoxxx/common.cjs",
    "scripts/mydoxxx/multipart.cjs",
    "scripts/mydoxxx/package-source-backup.py",
    "scripts/mydoxxx/BACKUP-RESTORE.md",
)
FORBIDDEN_PARTS = {
    ".git", "node_modules", "build", ".dart_tool", ".gradle", ".idea",
    "private-backups", ".codex-remote-attachments", "logs", "exports",
    "coverage", "pods", ".symlinks", "ephemeral", "__pycache__",
}
FORBIDDEN_EXTENSIONS = {
    ".jks", ".keystore", ".p12", ".pfx", ".pem", ".key", ".apk",
    ".aab", ".ipa", ".zip", ".7z", ".tar", ".gz", ".log", ".dmp",
    ".sqlite", ".sqlite3", ".db", ".bundle", ".pyc", ".pdf",
}
SAFE_ENV = ".env." + PROJECT
SDK_CONFIGS = {
    "experiments/MYDOXXX/app/lib/firebase_options.dart",
    "experiments/MYDOXXX/app/android/app/google-services.json",
    "experiments/MYDOXXX/app/ios/Runner/GoogleService-Info.plist",
}
PATTERNS = {
    "private key material": re.compile(rb"-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----[\r\n]+[A-Za-z0-9+/=\r\n]{64,}"),
    "GitHub token": re.compile(rb"\b(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,})"),
    "Google OAuth refresh token": re.compile(rb"\b1//[A-Za-z0-9_-]{30,}"),
    "live Razorpay key": re.compile(rb"\brzp_live_[A-Za-z0-9]+"),
    "Google client API key": re.compile(rb"\bAIza[A-Za-z0-9_-]{30,}"),
    "service-account credential JSON": re.compile(rb'"type"\s*:\s*"service_account"'),
    "AWS access key": re.compile(rb"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b"),
    "Twilio API secret identifier": re.compile(rb"\bSK[a-fA-F0-9]{32}\b"),
    "Firebase Storage bearer download URL": re.compile(rb"https://firebasestorage\.googleapis\.com/[^\s\"'<>]{1,2000}[?&]token=[A-Za-z0-9_-]{16,}"),
}


def git(repo: Path, *args: str) -> bytes:
    return subprocess.check_output(["git", "-C", str(repo), *args], stderr=subprocess.PIPE)


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def excluded(rel: str) -> str | None:
    p = PurePosixPath(rel)
    parts = {part.lower() for part in p.parts}
    name = p.name.lower()
    if parts & FORBIDDEN_PARTS:
        return "private, generated, dependency, or repository-internal directory"
    if p.suffix.lower() in FORBIDDEN_EXTENSIONS:
        return "binary document, archive, runtime data, log, or signing material"
    if name in {"key.properties", "local.properties", ".ds_store", ".flutter-plugins", ".flutter-plugins-dependencies"}:
        return "local machine or signing configuration"
    if name.startswith(".env") and name != SAFE_ENV:
        return "environment values not approved for source backup"
    if re.search(r"(?i)(credentials?|service.?account|private.?key|patient.?export|user.?export|auth.?export|restore.?manifest)", p.name):
        return "credential or personal-export filename"
    return None


def scan(rel: str, data: bytes) -> tuple[list[dict], list[dict]]:
    problems, reviewed = [], []
    if PurePosixPath(rel).name == SAFE_ENV and data.strip() != b"MYDOX_RECOVERY_MODE=true":
        problems.append({"path": rel, "kind": "experiment env must contain only MYDOX_RECOVERY_MODE=true"})
    for label, pattern in PATTERNS.items():
        for match in pattern.finditer(data):
            finding = {"path": rel, "kind": label, "line": data[:match.start()].count(b"\n") + 1}
            if label == "Google client API key" and rel in SDK_CONFIGS and PROJECT.encode() in data:
                reviewed.append({**finding, "reason": "Firebase public client configuration for the experiment; not an Admin credential"})
            else:
                problems.append(finding)
    return problems, reviewed


def gather(extra: list[str]) -> tuple[dict[str, bytes], dict]:
    files: dict[str, bytes] = {}
    report = {"projectId": PROJECT, "repositories": [], "exclusions": [], "credentialFindings": [], "reviewedClientConfigs": [], "largeFiles": []}

    def add(rel: str) -> None:
        normalized = PurePosixPath(rel.replace("\\", "/"))
        if normalized.is_absolute() or ".." in normalized.parts:
            raise ValueError("Unsafe relative path in source list")
        rel = normalized.as_posix()
        reason = excluded(rel)
        if reason:
            report["exclusions"].append({"path": rel, "reason": reason})
            return
        path = ROOT / Path(rel)
        if path.is_symlink() or any(parent.is_symlink() for parent in path.parents if parent != ROOT.parent):
            raise ValueError("Symlinks are not allowed in source backup: " + rel)
        if not path.is_file():
            raise ValueError("Tracked/reviewed source file is missing: " + rel)
        if not path.resolve().is_relative_to(ROOT):
            raise ValueError("Source file escaped workspace")
        data = path.read_bytes()
        problems, reviewed = scan(rel, data)
        report["credentialFindings"].extend(problems)
        report["reviewedClientConfigs"].extend(reviewed)
        if len(data) > 1_000_000:
            report["largeFiles"].append({"path": rel, "bytes": len(data)})
        files[rel] = data

    for rel in REPOS:
        repo = ROOT / rel
        tracked = [p for p in git(repo, "ls-files", "-z").decode("utf-8").split("\0") if p]
        status = git(repo, "status", "--porcelain=v1", "--untracked-files=all").decode("utf-8")
        report["repositories"].append({
            "path": rel,
            "branch": git(repo, "branch", "--show-current").decode().strip(),
            "commit": git(repo, "rev-parse", "HEAD").decode().strip(),
            "dirty": bool(status.strip()),
            "pendingPaths": len(status.splitlines()),
            "trackedFiles": len(tracked),
        })
        for path in tracked:
            add(rel + "/" + path)
    for rel in (*SUPPLEMENTS, *extra):
        add(rel)
    report["includedFiles"] = len(files)
    report["uncompressedBytes"] = sum(map(len, files.values()))
    report["largeFiles"].sort(key=lambda x: -x["bytes"])
    return files, report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--audit", action="store_true", help="read-only audit; do not create a ZIP")
    parser.add_argument("--extra-file", action="append", default=[], help="explicit reviewed host/helper path relative to workspace; never a directory")
    parser.add_argument("--output-dir", default="private-backups/" + PROJECT + "/github-source-backup")
    args = parser.parse_args()
    files, report = gather(args.extra_file)
    if args.audit:
        # No secret values are printed: findings contain paths/types/line numbers only.
        print(json.dumps(report, indent=2))
        return 2 if report["credentialFindings"] else 0
    if report["credentialFindings"]:
        print(json.dumps({"blocked": "Credential-pattern review required", "findings": report["credentialFindings"]}, indent=2))
        return 2
    if any(r["dirty"] for r in report["repositories"]):
        print(json.dumps({"blocked": "Commit the finalized app/backend changes first; untracked files must not be silently omitted", "repositories": report["repositories"]}, indent=2))
        return 2
    output = Path(args.output_dir)
    if not output.is_absolute():
        output = ROOT / output
    output = output.resolve()
    if not output.is_relative_to(ROOT / "private-backups" / PROJECT):
        raise ValueError("Output must stay within this experiment's private-backups directory")
    output.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%SZ")
    archive = output / ("MYDOXXX-source-" + stamp + ".zip")
    if archive.exists():
        raise ValueError("Destination already exists")
    manifest = {
        "format": "MYDOXXX source snapshot v1", "createdAt": datetime.now(timezone.utc).isoformat(),
        "projectId": PROJECT, "codeOnly": True, "containsGitHistory": False,
        "repositories": report["repositories"], "exclusions": report["exclusions"],
        "reviewedClientConfigs": report["reviewedClientConfigs"],
        "files": [{"path": path, "bytes": len(data), "sha256": sha(data)} for path, data in sorted(files.items())],
    }
    manifest_bytes = (json.dumps(manifest, indent=2) + "\n").encode()
    # Recheck sources and commit IDs before creating the final snapshot.
    for path, data in files.items():
        if (ROOT / path).read_bytes() != data:
            raise ValueError("Source changed during packaging; rerun after agents finish: " + path)
    for repo in report["repositories"]:
        if git(ROOT / repo["path"], "status", "--porcelain=v1", "--untracked-files=all").strip():
            raise ValueError("Source became dirty during packaging")
        if git(ROOT / repo["path"], "rev-parse", "HEAD").decode().strip() != repo["commit"]:
            raise ValueError("Source commit changed during packaging")
    # Entire ZIP is prepared in memory, so an oversized artifact is never left as a deliverable.
    from io import BytesIO
    memory = BytesIO()
    with zipfile.ZipFile(memory, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for path, data in sorted(files.items()):
            z.writestr("MYDOXXX/" + path, data)
        z.writestr("MYDOXXX/SOURCE-MANIFEST.json", manifest_bytes)
        z.writestr("MYDOXXX/README-BACKUP.md", files["scripts/mydoxxx/BACKUP-RESTORE.md"])
    archive_bytes = memory.getvalue()
    if len(archive_bytes) >= MAX_ZIP:
        print(json.dumps({"blocked": "ZIP exceeds browser upload ceiling", "bytes": len(archive_bytes), "limit": MAX_ZIP, "largeFiles": report["largeFiles"]}, indent=2))
        return 2
    with zipfile.ZipFile(BytesIO(archive_bytes)) as z:
        if z.testzip() is not None:
            raise ValueError("ZIP integrity test failed")
        for item in manifest["files"]:
            if sha(z.read("MYDOXXX/" + item["path"])) != item["sha256"]:
                raise ValueError("Archive file hash mismatch: " + item["path"])
    archive.write_bytes(archive_bytes)
    digest = sha(archive_bytes)
    archive.with_suffix(".zip.sha256").write_text(digest + "  " + archive.name + "\n", encoding="utf-8")
    archive.with_suffix(".manifest.json").write_bytes(manifest_bytes)
    (output / "README-BACKUP.md").write_bytes(files["scripts/mydoxxx/BACKUP-RESTORE.md"])
    (output / "source-backup-audit.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"archive": str(archive), "bytes": len(archive_bytes), "sha256": digest, "includedFiles": len(files), "uploadLimitBytes": MAX_ZIP, "verified": True}, indent=2))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (ValueError, OSError, subprocess.CalledProcessError) as exc:
        print("Backup stopped: " + str(exc), file=sys.stderr)
        raise SystemExit(2)
