"""Read-only local version and public-target check for the MYDOXXX shared repo.

Does not read credentials, contact Firebase, fetch, install, commit or push.
"""
from __future__ import annotations

import json
from pathlib import Path
import re
import subprocess
import sys

PROJECT = "mydoxxx-dev-261102"
DATABASE = "mydoxxx-testing"
ROOT = Path(__file__).resolve().parents[2]


def git(*args: str) -> str:
    return subprocess.check_output(
        ["git", "-C", str(ROOT), *args], stderr=subprocess.PIPE, text=True
    ).strip()


def main() -> int:
    app = ROOT / "experiments/MYDOXXX/app"
    backend = ROOT / "experiments/MYDOXXX/backend"
    for source in (app, backend):
        if (source / ".git").exists():
            raise ValueError("Nested Git repository found; use one shared MYDOXXX root.")
        config = json.loads((source / ".firebaserc").read_text(encoding="utf-8"))
        if config.get("projects") != {"default": PROJECT}:
            raise ValueError("Unexpected public Firebase project configuration.")
    env = (app / "lib/config/experiment_environment.dart").read_text(encoding="utf-8")
    lab = (app / "lib/config/test_lab_config.dart").read_text(encoding="utf-8")
    if not re.search(r"projectId\s*=\s*['\"]" + re.escape(PROJECT) + r"['\"]", env):
        raise ValueError("Flutter project guard does not match the shared experiment.")
    if not re.search(r"databaseId\s*=\s*['\"]" + re.escape(DATABASE) + r"['\"]", lab):
        raise ValueError("Flutter named-database guard does not match the shared lab.")
    result = {
        "projectId": PROJECT,
        "databaseId": DATABASE,
        "publicConfigChecks": "passed",
        "cloudRequests": 0,
    }
    # A staging folder may sit inside another workspace. Never report that
    # ancestor repository's version as if it were this prepared shared source.
    if not (ROOT / ".git").exists():
        result.update(gitState="prepared source; not a Git checkout", branch=None, commit=None, dirty=None)
    else:
        if Path(git("rev-parse", "--show-toplevel")).resolve() != ROOT:
            raise ValueError("Git root does not match this shared source folder.")
        status = git("status", "--porcelain=v1", "--untracked-files=all")
        result.update(gitState="local checkout", branch=git("branch", "--show-current") or "detached HEAD",
                      commit=git("rev-parse", "HEAD"), dirty=bool(status), changedPaths=len(status.splitlines()))
    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        message = str(error) if isinstance(error, ValueError) else type(error).__name__
        print("Version check stopped: " + message, file=sys.stderr)
        raise SystemExit(2)
