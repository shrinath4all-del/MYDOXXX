"""Public sample-page isolation and private-room routing, without network access."""
import contextlib
import importlib.util
import io
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

SPEC=importlib.util.spec_from_file_location('public_package',Path(__file__).with_name('package-site.py'))
P=importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(P)
HTML=b'''<!doctype html><html><head><meta charset="utf-8"><link rel="stylesheet" href="/public-demo/demo.css"></head><body><a href="/private.html">Private workspace</a><script src="/public-demo/demo-state.js"></script><script src="/public-demo/demo.js"></script></body></html>'''


class PublicDemoTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name)
        self.src=self.root/'scripts/mydoxxx/cloud-test-room'
        self.demo=self.src/'public-demo'
        self.demo.mkdir(parents=True)
        for name,value in {'index.html':HTML,'demo.css':b'body {color: #173c49}',
                           'demo-state.js':b'const sample = Object.freeze({});',
                           'demo.js':b'"use strict";'}.items():
            (self.demo/name).write_bytes(value)

    def test_only_reviewed_public_assets_are_returned(self):
        files=P.public_demo_inputs(self.src,self.root)
        self.assertEqual(set(files),{'index.html','public-demo/demo.css','public-demo/demo-state.js','public-demo/demo.js'})
        self.assertNotIn('cloud-config.js',files)

    def test_actual_public_sources_pass_isolation_and_secret_scans(self):
        files=P.public_demo_inputs()
        self.assertEqual(set(files),set(P.PUBLIC_DEMO_FILES.values()))
        for data in files.values():P.scan_bytes(data)

    def test_actual_private_portal_has_no_plaintext_email_or_unawaited_owner_check(self):
        import re
        files=P.private_portal_inputs()
        self.assertIn('owner-identity.js',files)
        for name in ('owner-auth.js','room-auth.js','login.js'):
            text=files[name].decode()
            for match in re.finditer(r'\bapproved\s*\(',text):
                self.assertRegex(text[:match.start()],r'\bawait\s*$')

    def test_portal_rejects_plaintext_email_without_changing_server_authorization(self):
        for name in P.PORTAL_FILES:
            source='index.html' if name=='private.html' else name
            (self.src/source).write_bytes(b'"use strict";')
        self.assertIn('private.html',P.private_portal_inputs(self.src,self.root))
        (self.src/'cloud-config.js').write_bytes(b'const owner="fictional@example.test";')
        with self.assertRaisesRegex(ValueError,'Personal email'):
            P.private_portal_inputs(self.src,self.root)

    def test_public_page_cannot_load_private_or_remote_scripts(self):
        for replacement in (b'/owner-auth.js',b'/panel/flutter.js',b'https://example.test/library.js',b'data:text/javascript,1'):
            with self.subTest(source=replacement):
                (self.demo/'index.html').write_bytes(HTML.replace(b'/public-demo/demo.js',replacement))
                with self.assertRaises(ValueError):P.public_demo_inputs(self.src,self.root)

    def test_network_storage_and_backend_access_fail_packaging(self):
        for source in (b'fetch("/catalog.json")',b'new WebSocket("wss://example.test")',
                       b'navigator.sendBeacon("/send")',b'new Worker("/worker.js")',
                       b'import("/owner-auth.js")',b'window.localStorage.getItem("state")',
                       b'document.cookie',b'const database = "mydoxxx-testing";',b'firebase.initializeApp({})'):
            with self.subTest(source=source):
                (self.demo/'demo.js').write_bytes(source)
                with self.assertRaises(ValueError):P.public_demo_inputs(self.src,self.root)

    def test_iframe_form_inline_script_styles_and_redirects_fail(self):
        for addition in (b'<iframe src="/room.html"></iframe>',b'<form action="/submit"></form>',
                         b'<script>alert(1)</script>',b'<button onclick="alert(1)">Go</button>',
                         b'<div style="color:red">x</div>',b'<meta http-equiv="refresh" content="0;/room.html">',
                         b'<link rel="preconnect" href="https://example.test">'):
            with self.subTest(addition=addition):
                (self.demo/'index.html').write_bytes(HTML.replace(b'</body>',addition+b'</body>'))
                with self.assertRaises(ValueError):P.public_demo_inputs(self.src,self.root)

    def test_public_csp_blocks_connections_and_frames_without_restricting_private_login(self):
        headers=P.site_headers().decode()
        for path in ('/','/index','/index.html'):
            self.assertIn('\n'+path+'\n  Content-Security-Policy: '+P.PUBLIC_CSP+'\n',headers)
        self.assertIn("connect-src 'none'",P.PUBLIC_CSP)
        self.assertIn("frame-src 'none'",P.PUBLIC_CSP)
        self.assertIn("style-src 'self'",P.PUBLIC_CSP)
        self.assertNotIn("'unsafe-inline'",P.PUBLIC_CSP)
        global_policy=headers.split('\n\n/')[0]
        self.assertNotIn('connect-src',global_policy)
        self.assertNotIn('/private.html',headers)
        self.assertNotIn('/panel/',headers)

    def test_private_redirects_and_broker_authorization_are_retained(self):
        room=Path(__file__).with_name('room-auth.js').read_text(encoding='utf-8')
        owner=Path(__file__).with_name('owner-auth.js').read_text(encoding='utf-8')
        login=Path(__file__).with_name('login.js').read_text(encoding='utf-8')
        self.assertEqual(room.count("location.replace('/private.html')"),2)
        self.assertNotIn("location.replace('/')",room)
        self.assertIn('if(!await approved(user))',room)
        self.assertIn('const ownerApproved=await approved(currentUser)',room)
        self.assertIn('ownerApproved&&auth.currentUser?.uid===ownerUid',room)
        self.assertIn('await approved(user)',owner)
        self.assertIn("Authorization:'Bearer '+ownerToken",owner)
        self.assertIn("location.replace('/room.html')",login)

    def test_complete_package_keeps_private_entry_and_public_sample_page_separate(self):
        for name in P.PORTAL_FILES:
            source='index.html' if name=='private.html' else name
            (self.src/source).write_bytes(b'<p>Private operator sign-in</p>' if source=='index.html' else b'"use strict";')
        (self.src/'panel-bridge.js').write_bytes(b'"use strict";')
        viewer=self.root/'scripts/mydoxxx'
        for name in ('test-console.html','test-console.js','test-console-state.js'):
            (viewer/name).write_bytes((P.ROOT/'scripts/mydoxxx'/name).read_bytes())
        build={name:b'fixture' for name in P.BUILD_FILES}
        build['index.html']=b'<script src="flutter_bootstrap.js" async></script>'
        build['flutter_bootstrap.js']=b'_flutter.loader.load({});'
        build['main.dart.js']=b'compiled private panel placeholder'
        out=self.root/'dist/cloud-test-room'
        original_reject=P.reject_links
        with patch.object(P,'ROOT',self.root),patch.object(P,'SRC',self.src),\
             patch.object(P,'output_path',return_value=out),patch.object(P,'known_passwords',return_value=()),\
             patch.object(P,'build_inputs',return_value=build),\
             patch.object(P,'reject_links',side_effect=lambda path,root=None:original_reject(path,self.root)),\
             contextlib.redirect_stdout(io.StringIO()):
            P.main(['--ci','--output','dist/cloud-test-room'])
        self.assertEqual((out/'index.html').read_bytes(),HTML)
        self.assertEqual((out/'private.html').read_bytes(),b'<p>Private operator sign-in</p>')
        self.assertIn('room-auth.js',(out/'room.html').read_text())
        self.assertTrue((out/'panel/main.dart.js').is_file())
        self.assertEqual(set(p.relative_to(out).as_posix() for p in out.rglob('*') if p.is_file()),
                         {'panel/'+name for name in P.BUILD_FILES}|set(P.PORTAL_FILES)|P.GENERATED_FILES|set(P.PUBLIC_DEMO_FILES.values()))


if __name__=='__main__':unittest.main()
