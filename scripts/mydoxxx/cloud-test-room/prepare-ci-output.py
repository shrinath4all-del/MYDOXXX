"""Preserve a prior generated publish folder before a repeated Linux CI build.

No files are deleted. The exact untracked output and its validated receipt move
into a unique workspace-local cache slot. The packager still requires new output.
"""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import subprocess
import sys
import uuid

ROOT = Path(__file__).absolute().parents[3]
OUTPUT = 'dist/cloud-test-room'
RECEIPT = 'dist/cloud-site-package-receipt.json'
ARCHIVES = '.cache/mydoxxx-ci/previous-publish'


def require(condition, message):
    if not condition:
        raise ValueError(message)


def reject_links(path):
    for part in (path, *path.parents):
        require(not part.is_symlink() and not getattr(part, 'is_junction', lambda: False)(),
                'Linked paths are not permitted')


def git(root, *args):
    return subprocess.run(['git', '-C', str(root), *args], check=True,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE).stdout


def validate_previous_output(root):
    root = Path(root).absolute()
    reject_links(root)
    require(root.is_dir() and root.resolve() == root, 'Expected a real absolute workspace')
    actual_root = Path(os.fsdecode(git(root, 'rev-parse', '--show-toplevel')).strip()).resolve()
    require(actual_root == root, 'Expected the actual Git root, not a nested or different path')
    out, receipt, archives = root / OUTPUT, root / RECEIPT, root / ARCHIVES
    for path in (out, receipt, archives):
        reject_links(path)
        require(path.resolve().is_relative_to(root), 'Output/cache must remain within the Git root')
    require(not git(root, 'ls-files', '-z', '--', OUTPUT, RECEIPT, ARCHIVES),
            'Tracked publish output, receipt or quarantine content is forbidden')
    if not out.exists() and not receipt.exists():
        return root, out, receipt, archives, 'fresh'
    if out.exists():
        require(out.is_dir(), 'Publish output must be a directory')
        for path in out.rglob('*'):
            reject_links(path)
            mode = path.lstat().st_mode
            require(stat.S_ISREG(mode) or stat.S_ISDIR(mode), 'Unexpected special file in publish output')
    require(receipt.is_file() and stat.S_ISREG(receipt.lstat().st_mode),
            'Previous generated output needs its regular package receipt')
    require(receipt.stat().st_size <= 1_048_576, 'Unexpected package receipt size')
    report = json.loads(receipt.read_text(encoding='utf-8'))
    require(Path(report.get('publishDirectory', '')).absolute() == out,
            'Previous receipt belongs to a different publish directory')
    require(report.get('mode') == 'ci-fingerprints' and report.get('credentialScan') == 'passed'
            and report.get('privateCredentialsRead') is False and report.get('cloudCalls') == 0
            and report.get('accounts') == 36, 'Expected a prior CI-generated package receipt')
    manifest = report.get('manifest')
    require(isinstance(manifest, list) and 0 < len(manifest) <= 1000
            and report.get('files') == len(manifest), 'Invalid package manifest')
    names = set()
    for item in manifest:
        require(isinstance(item, dict), 'Invalid package manifest item')
        name = item.get('path')
        require(isinstance(name, str) and name and '\\' not in name and ':' not in name,
                'Unsafe package manifest path')
        relative = PurePosixPath(name)
        require(relative.parts and '\x00' not in name and not relative.is_absolute() and '..' not in relative.parts
                and relative.as_posix() == name and name not in names,
                'Unsafe or duplicate package manifest path')
        require(type(item.get('bytes')) is int and item['bytes'] >= 0
                and isinstance(item.get('sha256'), str)
                and re.fullmatch('[a-f0-9]{64}', item['sha256']), 'Invalid package manifest metadata')
        names.add(name)
    require({'index.html', 'catalog.json', 'panel/main.dart.js'} <= names,
            'Expected generated portal and Flutter package manifest')
    # Preserve all actual contents, including Netlify additions or hash mismatches.
    # The old receipt is provenance, never permission to delete an arbitrary file.
    return root, out, receipt, archives, 'output' if out.exists() else 'orphan-receipt'


def prepare_output(root, check_only=False):
    root, out, receipt, archives, state = validate_previous_output(root)
    if state == 'fresh' or check_only:
        return {'status': 'fresh' if state == 'fresh' else 'validated', 'output': OUTPUT, 'deletedFiles': 0}
    archives.mkdir(parents=True, exist_ok=True)
    reject_links(archives)
    slot = archives / (datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ-') + uuid.uuid4().hex)
    require(slot.parent.resolve() == archives.resolve() and not slot.exists(),
            'Quarantine destination must be a new contained slot')
    slot.mkdir(exist_ok=False)
    # Revalidate immediately before rename; never merge into or overwrite a slot.
    require(validate_previous_output(root)[-1] == state, 'Previous output changed during preparation')
    destination = slot / 'cloud-test-room'
    require(not destination.exists() and not (slot / receipt.name).exists(),
            'Quarantine destination is occupied')
    if state == 'output':
        out.rename(destination)
    receipt.rename(slot / receipt.name)
    return {'status': 'quarantined' if state == 'output' else 'quarantined-receipt', 'output': OUTPUT,
            'preservedAt': slot.relative_to(root).as_posix(), 'deletedFiles': 0}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', help='Validate without moving anything')
    args = parser.parse_args()
    require(sys.platform == 'linux' and os.environ.get('CI') == 'true',
            'This fixed-path preparation is only for Linux CI')
    print(json.dumps(prepare_output(ROOT, check_only=args.check)))


if __name__ == '__main__':
    main()
