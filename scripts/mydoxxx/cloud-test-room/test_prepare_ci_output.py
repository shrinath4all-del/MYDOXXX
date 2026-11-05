"""Offline repeat-build tests; temporary Git repositories, no cloud or credentials."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location('prepare_ci_output', Path(__file__).with_name('prepare-ci-output.py'))
P = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(P)


class PrepareOutputTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        subprocess.run(['git', 'init', '-q', str(self.root)], check=True, capture_output=True)
        self.out = self.root / P.OUTPUT
        self.receipt = self.root / P.RECEIPT
        self.sentinel = self.root / 'keep-source.txt'
        self.sentinel.write_bytes(b'untouched source')

    def previous(self):
        files = {'index.html': b'old portal', 'catalog.json': b'{}', 'panel/main.dart.js': b'old app'}
        for name, data in files.items():
            path = self.out / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
        report = {'publishDirectory': str(self.out), 'mode': 'ci-fingerprints',
                  'credentialScan': 'passed', 'privateCredentialsRead': False,
                  'cloudCalls': 0, 'accounts': 36, 'files': len(files),
                  'manifest': [{'path': name, 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()}
                               for name, data in files.items()]}
        self.receipt.write_text(json.dumps(report), encoding='utf-8')
        return report

    def assert_unchanged(self):
        self.assertEqual(self.sentinel.read_bytes(), b'untouched source')
        self.assertEqual((self.out / 'index.html').read_bytes(), b'old portal')
        self.assertTrue(self.receipt.exists())

    def symlink(self, path, target, directory=False):
        try:
            path.symlink_to(target, target_is_directory=directory)
        except (OSError, NotImplementedError):
            self.skipTest('OS does not permit unprivileged symlinks; Linux CI runs this test')

    def test_absent_output_is_noop_and_creates_no_quarantine(self):
        self.assertEqual(P.prepare_output(self.root)['status'], 'fresh')
        self.assertFalse((self.root / P.ARCHIVES).exists())
        self.assertEqual(self.sentinel.read_bytes(), b'untouched source')

    def test_three_repeated_builds_preserve_each_distinct_output_and_receipt(self):
        slots = []
        for i in range(3):
            self.previous()
            (self.out / 'panel/main.dart.js').write_bytes(f'app build {i}'.encode())
            receipt = self.receipt.read_bytes()
            result = P.prepare_output(self.root)
            self.assertEqual(result['status'], 'quarantined')
            self.assertEqual(result['deletedFiles'], 0)
            slot = self.root / result['preservedAt']
            self.assertEqual((slot / 'cloud-test-room/panel/main.dart.js').read_bytes(), f'app build {i}'.encode())
            self.assertEqual((slot / self.receipt.name).read_bytes(), receipt)
            self.assertFalse(self.out.exists())
            self.assertFalse(self.receipt.exists())
            slots.append(slot)
        self.assertEqual(len(set(slots)), 3)
        self.assertTrue(all(slot.exists() for slot in slots))
        self.assertEqual(self.sentinel.read_bytes(), b'untouched source')

    def test_injected_config_extra_files_and_hash_mismatch_are_preserved_not_deleted(self):
        self.previous()
        extras = {'netlify.toml': b'netlify-generated config', 'unknown.txt': b'preserve this too'}
        for name, data in extras.items():
            (self.out / name).write_bytes(data)
        (self.out / 'index.html').write_bytes(b'postprocessed old portal')
        result = P.prepare_output(self.root)
        archived = self.root / result['preservedAt'] / 'cloud-test-room'
        for name, data in extras.items():
            self.assertEqual((archived / name).read_bytes(), data)
        self.assertEqual((archived / 'index.html').read_bytes(), b'postprocessed old portal')
        self.assertFalse(self.out.exists())

    def test_check_mode_validates_but_never_moves(self):
        self.previous()
        self.assertEqual(P.prepare_output(self.root, check_only=True)['status'], 'validated')
        self.assert_unchanged()
        self.assertFalse((self.root / P.ARCHIVES).exists())

    def test_tracked_output_or_receipt_is_refused_before_any_move(self):
        self.previous()
        for path in [P.OUTPUT + '/index.html', P.RECEIPT]:
            with self.subTest(path=path):
                subprocess.run(['git', '-C', str(self.root), 'add', '--', path], check=True, capture_output=True)
                with self.assertRaisesRegex(ValueError, 'Tracked'):
                    P.prepare_output(self.root)
                self.assert_unchanged()
                subprocess.run(['git', '-C', str(self.root), 'rm', '--cached', '--', path], check=True, capture_output=True)

    def test_nested_git_path_is_not_accepted_as_checkout_root(self):
        self.previous()
        with self.assertRaisesRegex(ValueError, 'actual Git root'):
            P.prepare_output(self.root / 'dist')
        self.assert_unchanged()

    def test_tracked_quarantine_or_occupied_slot_is_not_overwritten(self):
        self.previous()
        archives = self.root / P.ARCHIVES
        archives.mkdir(parents=True)
        old = archives / 'preserve.txt'
        old.write_bytes(b'previous quarantine')
        subprocess.run(['git', '-C', str(self.root), 'add', '--', str(old.relative_to(self.root))],
                       check=True, capture_output=True)
        with self.assertRaisesRegex(ValueError, 'Tracked'):
            P.prepare_output(self.root)
        subprocess.run(['git', '-C', str(self.root), 'rm', '--cached', '--', str(old.relative_to(self.root))],
                       check=True, capture_output=True)
        (archives / 'fixed-collision').mkdir()
        with patch.object(P, 'datetime') as clock, patch.object(P.uuid, 'uuid4') as unique:
            clock.now.return_value.strftime.return_value = 'fixed-'
            unique.return_value.hex = 'collision'
            with self.assertRaisesRegex(ValueError, 'new contained slot'):
                P.prepare_output(self.root)
        self.assertEqual(old.read_bytes(), b'previous quarantine')
        self.assert_unchanged()

    def test_receipt_is_required_and_malformed_receipt_does_not_move_output(self):
        self.previous()
        original = self.receipt.read_bytes()
        self.receipt.unlink()
        with self.assertRaisesRegex(ValueError, 'receipt'):
            P.prepare_output(self.root)
        self.receipt.write_text('not json')
        with self.assertRaises(json.JSONDecodeError):
            P.prepare_output(self.root)
        self.receipt.write_bytes(original)
        self.assert_unchanged()

    def test_wrong_directory_and_manifest_paths_are_rejected_without_touching_sentinel(self):
        original = self.previous()
        variants = []
        for directory in [str(self.root), str(self.root.parent / 'outside')]:
            report = dict(original, publishDirectory=directory)
            variants.append(report)
        for name in ['../keep-source.txt', '/outside', 'C:/outside', 'panel\\main.dart.js']:
            report = json.loads(json.dumps(original))
            report['manifest'][0]['path'] = name
            variants.append(report)
        duplicate = json.loads(json.dumps(original))
        duplicate['manifest'][1]['path'] = duplicate['manifest'][0]['path']
        variants.append(duplicate)
        for report in variants:
            with self.subTest(report=report.get('publishDirectory')):
                self.receipt.write_text(json.dumps(report))
                with self.assertRaises(ValueError):
                    P.prepare_output(self.root)
                self.assert_unchanged()
        self.assertFalse((self.root / P.ARCHIVES).exists())

    def test_output_parent_symlink_is_refused_and_outside_target_survives(self):
        outside = self.root / 'outside'
        outside.mkdir()
        (outside / 'sentinel').write_bytes(b'outside')
        self.symlink(self.root / 'dist', outside, True)
        with self.assertRaisesRegex(ValueError, 'Linked'):
            P.prepare_output(self.root)
        self.assertEqual((outside / 'sentinel').read_bytes(), b'outside')

    def test_checkout_root_symlink_is_refused(self):
        self.previous()
        alias = self.root / 'checkout-alias'
        self.symlink(alias, self.root, True)
        with self.assertRaisesRegex(ValueError, 'Linked'):
            P.prepare_output(alias)
        self.assert_unchanged()

    def test_dangling_output_symlink_is_refused(self):
        self.out.parent.mkdir()
        self.symlink(self.out, self.root / 'missing', True)
        with self.assertRaisesRegex(ValueError, 'Linked'):
            P.prepare_output(self.root)
        self.assertTrue(self.out.is_symlink())

    def test_nested_symlink_is_refused_and_target_survives(self):
        self.previous()
        self.symlink(self.out / 'linked.txt', self.sentinel)
        with self.assertRaisesRegex(ValueError, 'Linked'):
            P.prepare_output(self.root)
        self.assert_unchanged()

    def test_destination_parent_symlink_is_refused(self):
        self.previous()
        cache = self.root / '.cache'
        self.symlink(cache, self.root / 'dist', True)
        with self.assertRaisesRegex(ValueError, 'Linked'):
            P.prepare_output(self.root)
        self.assert_unchanged()

    def test_receipt_symlink_is_refused(self):
        self.previous()
        data = self.receipt.read_bytes()
        self.receipt.unlink()
        reference = self.root / 'receipt-copy.json'
        reference.write_bytes(data)
        self.symlink(self.receipt, reference)
        with self.assertRaisesRegex(ValueError, 'Linked'):
            P.prepare_output(self.root)
        self.assertEqual(reference.read_bytes(), data)
        self.assert_unchanged()

    def test_cli_refuses_non_linux_or_non_ci_before_touching_files(self):
        for platform, ci in [('win32', 'true'), ('linux', ''), ('linux', 'false')]:
            with self.subTest(platform=platform, ci=ci), patch.object(sys, 'argv', ['prepare-ci-output.py']), \
                 patch.object(sys, 'platform', platform), patch.dict(os.environ, {'CI': ci}), \
                 patch.object(P, 'prepare_output', side_effect=AssertionError('Must not touch files')):
                with self.assertRaisesRegex(ValueError, 'Linux CI'):
                    P.main()

    @unittest.skipUnless(sys.platform == 'linux', 'Real Linux CI entrypoint test')
    def test_linux_cli_handles_two_reused_workspaces_with_fixed_root(self):
        script = self.root / 'scripts/mydoxxx/cloud-test-room/prepare-ci-output.py'
        script.parent.mkdir(parents=True)
        script.write_bytes(Path(P.__file__).read_bytes())
        for _ in range(2):
            self.previous()
            result = subprocess.run([sys.executable, str(script)], check=True, capture_output=True,
                                    text=True, env={**os.environ, 'CI': 'true'})
            report = json.loads(result.stdout)
            self.assertEqual(report['status'], 'quarantined')
            self.assertEqual(report['deletedFiles'], 0)
            self.assertFalse(self.out.exists())
        self.assertEqual(self.sentinel.read_bytes(), b'untouched source')


if __name__ == '__main__':
    unittest.main()
