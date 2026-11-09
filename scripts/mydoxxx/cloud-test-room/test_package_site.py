"""Offline publish-boundary tests. No credentials, Firebase or network required."""
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

SPEC=importlib.util.spec_from_file_location('package_site',Path(__file__).with_name('package-site.py'))
P=importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(P)


class PackageSafetyTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name)

    def fixture_build(self):
        build=self.root/'build'
        for name in P.BUILD_FILES:
            data=b'{}'
            if name.endswith('.png'):data=b'\x89PNG\r\n\x1a\nfixture'
            elif name.endswith('.wasm'):data=b'\0asm\x01\0\0\0'
            elif name.endswith('.ttf'):data=b'\0\x01\0\0fixture'
            elif name.endswith('.otf'):data=b'OTTOfixture'
            if name=='index.html':data=b'<base href="/panel/">'
            if name=='main.dart.js':data=' '.join((P.PROJECT,P.DATABASE,P.ORIGIN,'mydoxCloudTestLogin','signInWithCustomToken')).encode()
            file=build/name;file.parent.mkdir(parents=True,exist_ok=True);file.write_bytes(data)
        return build

    def test_fingerprint_contract_has_36_hashes_not_plaintext(self):
        self.assertEqual(len(P.KNOWN_PASSWORD_SHA256),36)
        self.assertTrue(all(len(h)==64 and all(c in '0123456789abcdef' for c in h) for h in P.KNOWN_PASSWORD_SHA256))

    def test_ci_does_not_read_private_files(self):
        with patch.object(Path,'read_text',side_effect=AssertionError('Unexpected private read')):
            self.assertEqual(P.known_passwords(True,self.root),())

    def test_local_mode_requires_reference(self):
        with self.assertRaisesRegex(ValueError,'scan input'):
            P.known_passwords(False,self.root)

    def test_local_mode_detects_rotated_reference(self):
        reference=self.root/'private-backups/mydoxxx-dev-261102/test-lab-credentials.json'
        reference.parent.mkdir(parents=True)
        # Deliberately fake test values; never real credentials or CI fingerprints.
        records={str(i):{'password':f'{i:040x}'} for i in range(36)}
        reference.write_text(json.dumps({'accounts':records}))
        with self.assertRaisesRegex(ValueError,'rotated'):
            P.known_passwords(False,self.root)

    def test_ci_output_is_exact_and_fresh(self):
        self.assertEqual(P.output_path('dist/cloud-test-room',True,self.root),self.root/'dist/cloud-test-room')
        for value in [None,'dist/other','../dist/cloud-test-room','private-backups/mydoxxx-dev-261102/x',str(self.root/'dist/cloud-test-room')]:
            with self.subTest(value=value),self.assertRaises(ValueError):P.output_path(value,True,self.root)
        target=self.root/'dist/cloud-test-room';target.mkdir(parents=True)
        with self.assertRaisesRegex(ValueError,'never merged'):P.output_path('dist/cloud-test-room',True,self.root)

    def test_local_output_stays_private(self):
        self.assertEqual(P.output_path('private-backups/mydoxxx-dev-261102/cloud-test',False,self.root),self.root/'private-backups/mydoxxx-dev-261102/cloud-test')
        with self.assertRaises(ValueError):P.output_path('dist/cloud-test-room',False,self.root)

    def test_candidate_scanner_detects_every_adjoining_window(self):
        value=b'0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ_-ab'
        self.assertEqual(len(value),40)
        fingerprints={hashlib.sha256(value).hexdigest()}
        for offset in range(20):
            with self.subTest(offset=offset),self.assertRaisesRegex(ValueError,'fingerprint'):
                P.scan_bytes(b'x'*offset+value+b'_adjacentIdentifier',fingerprints=fingerprints)
        P.scan_bytes(value[:-1]+b'c',fingerprints=fingerprints)

    def test_local_raw_scanner_handles_any_boundary(self):
        with self.assertRaisesRegex(ValueError,'Credential detected'):
            P.scan_bytes(b'prefix'+b'fake-local-reference'+b'suffix',passwords=(b'fake-local-reference',),fingerprints=set())

    def test_unknown_credentials_are_rejected(self):
        cases=[b'-----BEGIN PRIVATE KEY-----',b'-----BEGIN RSA PRIVATE KEY-----',
               b'-----BEGIN EC PRIVATE KEY-----',b'-----BEGIN OPENSSH PRIVATE KEY-----',
               b'{"type":"service_account"}',b'{"private_key":"unexpected value"}',
               b'{"refresh_token":"abcdefghijklmnopqrstuvwxyz"}',
               b'GOCSPX-abcdefghijklmnopqrstuv',b'ghp_' + b'a'*36,
               b'eyJ' + b'a'*20+b'.'+b'b'*20+b'.'+b'c'*25]
        for value in cases:
            with self.subTest(signature=value[:15]),self.assertRaisesRegex(ValueError,'signature'):
                P.scan_bytes(value,fingerprints=set())

    def test_local_password_endpoints_are_forbidden(self):
        for value in (b'/__mydox_test__/login-config',b'https://example.test/signInWithPassword'):
            with self.subTest(value=value),self.assertRaisesRegex(ValueError,'endpoint'):
                P.scan_bytes(value,fingerprints=set())

    def test_public_firebase_configuration_is_allowed(self):
        P.scan_bytes(b'{"apiKey":"public-client-config-placeholder", "projectId":"mydoxxx-dev-261102"}',fingerprints=set())

    def test_reviewed_complete_build_is_accepted(self):
        build=self.fixture_build()
        (build/'.last_build_id').write_text('unused-build-metadata')
        self.assertEqual(set(P.build_inputs(build,self.root)),P.BUILD_FILES)

    def test_extra_build_file_and_missing_file_fail(self):
        build=self.fixture_build();(build/'credentials.json').write_text('{}')
        with self.assertRaisesRegex(ValueError,'Unexpected file'):P.build_inputs(build,self.root)
        (build/'credentials.json').unlink();(build/'main.dart.js').unlink()
        with self.assertRaisesRegex(ValueError,'missing approved'):P.build_inputs(build,self.root)

    def test_spoofed_asset_extension_is_rejected(self):
        build=self.fixture_build();(build/'favicon.png').write_bytes(b'{"private_key":"x"}')
        with self.assertRaisesRegex(ValueError,'PNG'):P.build_inputs(build,self.root)

    def test_wrong_build_base_and_cloud_mode_fail(self):
        build=self.fixture_build();(build/'index.html').write_text('<base href="/">')
        with self.assertRaisesRegex(ValueError,'base path'):P.build_inputs(build,self.root)
        (build/'index.html').write_text('<base href="/panel/">');(build/'main.dart.js').write_text(P.PROJECT)
        with self.assertRaisesRegex(ValueError,'compiled guard'):P.build_inputs(build,self.root)

    def test_symlink_output_parent_is_rejected(self):
        outside=self.root/'outside';outside.mkdir()
        try:(self.root/'dist').symlink_to(outside,target_is_directory=True)
        except (OSError,NotImplementedError):self.skipTest('OS does not permit unprivileged symlinks')
        with self.assertRaisesRegex(ValueError,'Linked'):P.output_path('dist/cloud-test-room',True,self.root)


if __name__=='__main__':unittest.main()
