"""Offline provenance checks: no credentials, cloud API calls, or Git mutations."""
from datetime import datetime, timezone
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

SPEC=importlib.util.spec_from_file_location('package_site',Path(__file__).with_name('package-site.py'))
P=importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(P)
COMMIT='a'*40
DEPLOY='b'*24
PREPARED=datetime(2026,11,20,18,35,0,tzinfo=timezone.utc)


class BuildMetadataTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name)
        (self.root/'.git').mkdir()
        self.values={
            ('rev-parse','--show-toplevel'):str(self.root),
            ('remote','get-url','origin'):P.SOURCE_URL+'.git',
            ('rev-parse','HEAD'):COMMIT,
            ('status','--porcelain=v1','--untracked-files=no'):'',
            ('show','-s','--format=%cI',COMMIT):'2026-11-20T16:01:02+00:00',
        }
        self.env={'NETLIFY':'true','COMMIT_REF':COMMIT,'DEPLOY_ID':DEPLOY,
                  'REPOSITORY_URL':P.SOURCE_URL,
                  'PRIVATE_PASSWORD':'DO_NOT_PUBLISH_THIS_VALUE'}

    def metadata(self,env=None):
        with patch.object(P,'metadata_git',side_effect=lambda root,*args:self.values[args]):
            return P.build_metadata(self.root,self.env if env is None else env,PREPARED)

    def test_netlify_commit_and_deployment_are_tied_to_own_clean_git_root(self):
        data=self.metadata()
        self.assertTrue(data['sourceVerified'])
        self.assertEqual(data['commit'],COMMIT)
        self.assertEqual(data['deployId'],DEPLOY)
        self.assertEqual(data['committedAt'],'2026-11-20T16:01:02+00:00')
        self.assertEqual(set(data),{'commit','committedAt','preparedAt','deployId','sourceVerified'})

    def test_snapshot_cannot_inherit_parent_repository_metadata(self):
        (self.root/'.git').rmdir()
        with patch.object(P,'metadata_git',side_effect=AssertionError('Do not query parent Git')):
            data=P.build_metadata(self.root,{},PREPARED)
            self.assertFalse(data['sourceVerified'])
            self.assertIsNone(data['commit'])
            with self.assertRaisesRegex(ValueError,'own Git checkout'):
                P.build_metadata(self.root,self.env,PREPARED)

    def test_wrong_repository_root_and_dirty_checkout_stop_netlify(self):
        changes=[
            (('rev-parse','--show-toplevel'),str(self.root.parent)),
            (('status','--porcelain=v1','--untracked-files=no'),' M source.dart'),
            (('show','-s','--format=%cI',COMMIT),'2026-11-20T16:01:02'),
        ]
        for key,value in changes:
            with self.subTest(key=key),patch.dict(self.values,{key:value}):
                with self.assertRaisesRegex(ValueError,'Cannot verify source/deployment metadata') as caught:
                    self.metadata()
                self.assertNotIn(value,str(caught.exception))
                data=self.metadata({})
                self.assertFalse(data['sourceVerified'])
                self.assertIsNone(data['commit'])

    def test_netlify_commit_mismatch_or_bad_deployment_id_cannot_be_published(self):
        for changes in ({'COMMIT_REF':'c'*40},{'COMMIT_REF':''},
                        {'REPOSITORY_URL':'https://example.test/other/repo'},
                        {'DEPLOY_ID':''},{'DEPLOY_ID':'<img src=x onerror=alert(1)>'}):
            with self.subTest(changes=changes):
                with self.assertRaisesRegex(ValueError,'Cannot verify'):
                    self.metadata({**self.env,**changes})

    def test_netlify_does_not_read_a_credential_bearing_git_remote(self):
        self.values.pop(('remote','get-url','origin'))
        self.assertTrue(self.metadata()['sourceVerified'])

    def test_local_checkout_requires_the_approved_repository(self):
        self.values[('remote','get-url','origin')]='https://credential@example.test/other/repo'
        data=self.metadata({})
        self.assertFalse(data['sourceVerified'])
        self.assertIsNone(data['commit'])

    def test_ist_dates_include_midnight_rollover_and_explicit_timezone(self):
        self.assertEqual(P.metadata_time(self.metadata()['preparedAt']),'21 Nov 2026, 12:05:00 AM IST')
        self.assertEqual(P.metadata_time(self.metadata()['committedAt']),'20 Nov 2026, 09:31:02 PM IST')
        self.assertEqual(P.metadata_time(None),'Not verified in this package')

    def test_footer_is_embedded_with_page_and_does_not_claim_publish_timestamp(self):
        data=self.metadata()
        result=P.source_footer('<style></style><body><main>APP</main></body>',data)
        self.assertIn('Website build prepared',result)
        self.assertIn('Exact publish time:',result)
        self.assertIn('/deploys/'+DEPLOY,result)
        self.assertIn('/commit/'+COMMIT,result)
        self.assertIn('experiments/MYDOXXX/app',result)
        self.assertIn('scripts/mydoxxx',result)
        self.assertLess(result.index('</main>'),result.index('<footer'))
        for forbidden in ('fetch(',str(self.root),'DO_NOT_PUBLISH_THIS_VALUE','Published at','Live at'):
            self.assertNotIn(forbidden,result)

    def test_login_footer_stays_inside_existing_centered_card(self):
        data=self.metadata()
        result=P.source_footer('<style></style><body><main class="card">LOGIN</main><script></script></body>',data,login=True)
        self.assertLess(result.index('<footer'),result.index('</main>'))
        self.assertIn('.card .bfast-build-footer',result)
        self.assertEqual(result.count('<footer'),1)

    def test_local_unknown_metadata_is_explicit_and_not_a_deployment_claim(self):
        data={'commit':None,'committedAt':None,'preparedAt':PREPARED.isoformat(),
              'deployId':None,'sourceVerified':False}
        result=P.source_footer('<style></style><body></body>',data)
        self.assertIn('Unverified source snapshot',result)
        self.assertIn('publication is not verified',result)
        self.assertNotIn('/commit/',result)
        self.assertNotIn('/deploys/',result)

    def test_missing_html_marker_is_a_build_failure_not_silent_footer_omission(self):
        with self.assertRaisesRegex(ValueError,'Expected one reviewed marker'):
            P.source_footer('<body></body>',self.metadata())


if __name__=='__main__':unittest.main()
