"""Package approved frontend files only; no network, login, deployment or secrets.

Local mode additionally requires the private 36-password scan reference. CI uses
one-way fingerprints of those 240-bit random values, without reading passwords.
Neither mode publishes credentials, backend code or administrative helpers.
"""
from pathlib import Path
import argparse
import hashlib
import json
import os
import re
import subprocess
from html import escape
from datetime import datetime, timezone, timedelta
ROOT=Path(__file__).resolve().parents[3]
SRC=Path(__file__).resolve().parent
BUILD=ROOT/'experiments/MYDOXXX/app/build/web-cloud-lab'
ORIGIN='https://mydoxxx-live-test.netlify.app'
PROJECT='mydoxxx-dev-261102'
DATABASE='mydoxxx-testing'
# SHA-256 only, of 36 independently generated 30-byte base64url passwords.
# These high-entropy values are not human passwords. Update deliberately after
# test-account password rotation; never replace this with hashes of weak secrets.
KNOWN_PASSWORD_SHA256 = frozenset({
    '057c4c06bf03bf4b7c645a0425f5a97a9c583e939fb2dc58c6b652bd28134863',
    '0a6cd04c4ad0774e7bb392227aaf5527522e18cf3742a773d50ba2ad2f625cc3',
    '0b4e4301fdb5d7f2fb02d2fd65f85c8f14b237bbd8e787f5fc80f8e9dd953b3f',
    '0bf14a110e40cbd00dc2fe23154d835e415b0bfa5dd369b5ba6249c9b3517b47',
    '109c72995a73d7e51fd37b96cdaa8462fa5a79be8e991018586a821c29a5fff1',
    '247db71a93d27aa7b8d614a876a113cdcb1e380d88c41b76725f662e50d405eb',
    '28450dca50fdf155e2c0ff42540dcd165894133bcc7f2d6ad091407444266a77',
    '376bbb2626f61df64950caa1afc4464daf3bc5630cb9db893165306bdd37f3ea',
    '4190035367d41efe6bc6bf91c758b56e9789a059740cba1b5ca3013590a97024',
    '5442b8b0c86cc01e0629353b0fd668fb3d9b3e121173baca0a7eae4f3b2fdb36',
    '54bc6f044931b759b006969a4032e3f5bbdfe907433c75a03e9d64c6778df1cd',
    '58f808e49b8fa3f3c2b4dc8237f1ba5ae7fc24fc0fe1afd42c6e58e9b389524c',
    '5be116d1c2b3a7737cd222cb967be11e76a4beb7620162c692cdd7166cf9a735',
    '5ee037fc2bd5fd50d6ca246971dce6a466944027313463e873c68419b7861735',
    '5fece9142ff711ce0708baa941e6e3f7fc7e73e25c5fa74169c295653feafb8b',
    '6799fb527f708c064cff2bd9867b39d807d10edd33be5e1de3905e6b08aff2fc',
    '6a9f9fc6213d98a8b0e20f39dc48146f6e1b1fb9b0bcbadb12878197267519ce',
    '6ba2e85389d8d68dae84377f3de94509dc1cb69f2e4d050828721f455bd2cd5c',
    '6deacc8fa234e48f81794a257dc5cc27063e4856dbafaf043ee73a1252555209',
    '71860d00c4c4cde17982f8cf387f135547540ce5d05f29118cadb87e9340bb24',
    '815f0bec08c6b83cfe9ae367cf929c8fc940ac19c7b463a6d79533cb921bffaf',
    '93cc920d7cc777c3f88aa317556c54bba75baf0f38877c1fe43d94cc42d98a7d',
    '968032c428489e2bad6b5e40e2143dce3a46e403cfe121a59e04dacc20d89976',
    '97e22a8299cb8124770de7a22188edc84b3b5ebcbf5fe1ce7e219caae69d80fa',
    '99100981f5a77db135ecef0196d8536c56cde09b4ad36e069169eeaef4c30411',
    'a10e36a0fb204e007bb029f196a218fe756534d7b5b04ed9b978e0cf85fb73dc',
    'acc474980f2918f907b9663bb0b970c4df39238704c1eed78c6985e851398dd1',
    'b4b0ad6513cde7c5736feee7efac4700713ecbce0d10439d17d2f3302233b407',
    'bf390aed9a3b1642aa718089d3dcf8f75dd476b9fab570398cba476cfb5bb720',
    'c22ef186faed16aa4cd2cac7a0d58d23a555e7abb298cb2a02fff4d708341f49',
    'c9227c97c2b4f57d5bc8f8982f5cfbabf214cf640f149d3de0d90f253df4aab5',
    'cba29ecc15b8e56a93c325a74ad8a6a6f734b2619587e87568d33dedec321dde',
    'd01940484a3b794a6141e740ca4e0d3e525fe9bba8f7dcb828207714377deedf',
    'eb62858a003a15fb322cbfa4235caaaa97e039bf1095afa408a7d0c88a8a7477',
    'f189da943d6946065e2283ffca6e25e56fbd4863ee3b9617ab934760187f9994',
    'fc3cd9c2b74b7662b2bca21feb516f957542351eaabcc0448af5bd97511de636',
})

# Pinned Flutter release build footprint. A new asset or framework output needs
# explicit review here; copying an entire build directory is intentionally banned.
BUILD_FILES = frozenset('''
assets/AssetManifest.bin
assets/AssetManifest.bin.json
assets/assets/bones.png
assets/assets/ChatGPT%20Image%20Sep%2028,%202026,%2001_58_44%20PM.png
assets/assets/ChatGPT%20Image%20Sep%2028,%202026,%2001_59_35%20PM-1.png
assets/assets/ChatGPT%20Image%20Sep%2028,%202026,%2001_59_36%20PM-2.png
assets/assets/ChatGPT%20Image%20Sep%2028,%202026,%2001_59_38%20PM-3.png
assets/assets/child_specialist.png
assets/assets/doctor.png
assets/assets/doctors.png
assets/assets/fonts/Roboto-Black.ttf
assets/assets/fonts/Roboto-Bold.ttf
assets/assets/fonts/Roboto-Light.ttf
assets/assets/fonts/Roboto-Medium.ttf
assets/assets/fonts/Roboto-OFL.txt
assets/assets/fonts/Roboto-Regular.ttf
assets/assets/general.png
assets/assets/nurses.png
assets/assets/pregnancy.png
assets/assets/skincare.png
assets/assets/technician.png
assets/assets/womens_health.png
assets/FontManifest.json
assets/fonts/MaterialIcons-Regular.otf
assets/NOTICES
assets/packages/cupertino_icons/assets/CupertinoIcons.ttf
assets/packages/pdfrx/assets/pdfium.wasm
assets/packages/pdfrx/assets/pdfium_client.js
assets/packages/pdfrx/assets/pdfium_worker.js
assets/packages/record_web/assets/js/record.worklet.js
assets/shaders/ink_sparkle.frag
assets/shaders/stretch_effect.frag
canvaskit/canvaskit.js
canvaskit/canvaskit.js.symbols
canvaskit/canvaskit.wasm
canvaskit/chromium/canvaskit.js
canvaskit/chromium/canvaskit.js.symbols
canvaskit/chromium/canvaskit.wasm
canvaskit/experimental_webparagraph/canvaskit.js
canvaskit/experimental_webparagraph/canvaskit.js.symbols
canvaskit/experimental_webparagraph/canvaskit.wasm
canvaskit/skwasm.js
canvaskit/skwasm.js.symbols
canvaskit/skwasm.wasm
canvaskit/skwasm_heavy.js
canvaskit/skwasm_heavy.js.symbols
canvaskit/skwasm_heavy.wasm
canvaskit/wimp.js
canvaskit/wimp.js.symbols
canvaskit/wimp.wasm
favicon.png
flutter.js
flutter_bootstrap.js
flutter_service_worker.js
icons/Icon-192.png
icons/Icon-512.png
icons/Icon-maskable-192.png
icons/Icon-maskable-512.png
index.html
main.dart.js
manifest.json
version.json
'''.strip().splitlines())
PORTAL_FILES=('index.html','cloud-config.js','owner-auth.js','login.js','login-support.js','room-auth.js')
GENERATED_FILES=frozenset({'room.html','test-console.js','test-console-state.js',
                         'catalog.json','_headers','robots.txt','panel/panel-bridge.js','panel/panel-startup.js'})
SECRET_PATTERNS=(
    re.compile(rb'-----BEGIN (?:[A-Z ]+)?PRIVATE KEY-----'),
    re.compile(rb'GOCSPX-[A-Za-z0-9_-]{10,}'),
    re.compile(rb'\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})'),
    re.compile(rb'\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{12,}\.[A-Za-z0-9_-]{16,}'),
    re.compile(rb'["\']type["\']\s*:\s*["\']service_account["\']'),
    re.compile(rb'["\']private_key["\']\s*:\s*["\'][^"\']+'),
    re.compile(rb'["\'](?:refresh_token|client_secret|password)["\']\s*:\s*["\'][A-Za-z0-9_+/=-]{12,}["\']'),
    re.compile(rb'1//[A-Za-z0-9_-]{25,}'),
)
PASSWORD_RUN=re.compile(rb'[A-Za-z0-9_-]{40,}')

def require(condition,message):
    if not condition:
        raise ValueError(message)

def reject_links(path,root=ROOT):
    current=path
    while current != root:
        require(current != current.parent,'Path must remain within the workspace')
        require(not current.is_symlink() and not getattr(current,'is_junction',lambda:False)(),
                'Linked paths are not permitted')
        current=current.parent

def output_path(output,ci,root=ROOT):
    if output is None:
        require(not ci,'CI requires --output dist/cloud-test-room')
        relative=Path('private-backups/mydoxxx-dev-261102')/('cloud-site-'+datetime.now(timezone.utc).strftime('%Y%m%d-%H%M%S'))
    else:
        relative=Path(output)
        require(not relative.is_absolute() and '..' not in relative.parts,'Use a safe workspace-relative output')
    if ci:
        require(relative.as_posix()=='dist/cloud-test-room','CI output must be dist/cloud-test-room')
    else:
        require(relative.parts[:2]==('private-backups',PROJECT) and len(relative.parts)>2,
                'Local output must stay inside the private MYDOXXX directory')
    target=root/relative
    reject_links(target,root)
    require(not target.exists(),'Output must be new; existing files are never merged or deleted')
    return target

def known_passwords(ci,root=ROOT):
    require(len(KNOWN_PASSWORD_SHA256)==36 and all(re.fullmatch(r'[a-f0-9]{64}',x) for x in KNOWN_PASSWORD_SHA256),
            'Reviewed password fingerprints are incomplete')
    if ci:
        return ()  # CI never opens private files or asks for account passwords.
    reference=root/'private-backups/mydoxxx-dev-261102/test-lab-credentials.json'
    reject_links(reference,root)
    require(reference.is_file(),'Known-secret scan input is required in local mode')
    account_map=json.loads(reference.read_text(encoding='utf-8-sig')).get('accounts',{})
    passwords=tuple(x['password'].encode() for x in account_map.values())
    require(len(passwords)==36 and all(re.fullmatch(rb'[A-Za-z0-9_-]{40}',x) for x in passwords),
            'Expected exactly 36 high-entropy test-password values')
    require({hashlib.sha256(x).hexdigest() for x in passwords}==KNOWN_PASSWORD_SHA256,
            'Test passwords rotated; update reviewed fingerprints before packaging')
    return passwords

def scan_bytes(data,passwords=(),fingerprints=None):
    hashes=KNOWN_PASSWORD_SHA256 if fingerprints is None else fingerprints
    require(not any(secret in data for secret in passwords),'Credential detected in artifact')
    require(not any(pattern.search(data) for pattern in SECRET_PATTERNS),'Credential signature detected in artifact')
    require(b'/__mydox_test__/login-config' not in data and b'signInWithPassword' not in data,
            'Local/password login endpoint is forbidden in the cloud artifact')
    # All 40-byte windows, including values adjoining other identifier characters.
    for match in PASSWORD_RUN.finditer(data):
        run=match.group()
        for start in range(len(run)-39):
            if hashlib.sha256(run[start:start+40]).hexdigest() in hashes:
                raise ValueError('Known test-password fingerprint detected in artifact')

def check_signature(name,data):
    if name.endswith('.png'):
        require(data.startswith(b'\x89PNG\r\n\x1a\n'),'Expected PNG file signature')
    elif name.endswith('.wasm'):
        require(data.startswith(b'\0asm\x01\0\0\0'),'Expected WebAssembly file signature')
    elif name.endswith('.ttf'):
        require(data[:4] in (b'\0\x01\0\0',b'true',b'ttcf'),'Expected TrueType file signature')
    elif name.endswith('.otf'):
        require(data.startswith(b'OTTO'),'Expected OpenType file signature')
    elif name.endswith(('.js','.json','.html','.txt','.symbols')) or name.endswith('/NOTICES'):
        data.decode('utf-8')

def build_inputs(build=BUILD,root=ROOT):
    reject_links(build,root)
    require(build.is_dir(),'Build the cloud-only Flutter lab first')
    files={}
    for path in sorted(build.rglob('*')):
        reject_links(path,root)
        if not path.is_file():continue
        name=path.relative_to(build).as_posix()
        if name=='.last_build_id':continue  # Build metadata never published.
        require(name in BUILD_FILES,'Unexpected file in Flutter build: '+name)
        files[name]=path.read_bytes()
        check_signature(name,files[name])
    require(set(files)==BUILD_FILES,'Flutter build is missing approved files')
    require(b'<base href="/panel/">' in files['index.html'],'Expected /panel/ base path')
    for marker in (PROJECT,DATABASE,ORIGIN,'mydoxCloudTestLogin','signInWithCustomToken'):
        require(marker.encode() in files['main.dart.js'],'Expected cloud-only compiled guard is missing')
    return files
FAMILIES={'patient':'Patient','doctor':'Cardiologist','nurse':'Nurse','hospital':'Hospital','ambulance':'Ambulance','care_physician':'Care Physician','technician':'Technician','therapist':'Physiotherapist','agency_care':'Care Agency','agency_nurse':'Nursing Agency','agency_technician':'Technician Agency','agency_physio':'Physio Agency'}
def replace_once(source,old,new):
    require(source.count(old)==1, f'Expected one reviewed marker: {old[:60]}')
    return source.replace(old,new,1)

SOURCE_REPOSITORY='shrinath4all-del/MYDOXXX'
SOURCE_URL='https://github.com/'+SOURCE_REPOSITORY
IST=timezone(timedelta(hours=5,minutes=30))

def metadata_git(root,*args):
    return subprocess.check_output(['git','-C',str(root),*args],
                                   stderr=subprocess.PIPE,text=True).strip()

def build_metadata(root=ROOT,environ=None,now=None):
    """Read only public provenance. Never guess a post-build publication time."""
    env=os.environ if environ is None else environ
    netlify=env.get('NETLIFY')=='true'
    prepared=now or datetime.now(timezone.utc)
    require(prepared.tzinfo is not None,'Build timestamp must include a timezone')
    result={'commit':None,'committedAt':None,
            'preparedAt':prepared.astimezone(timezone.utc).isoformat(),
            'deployId':None,'sourceVerified':False}
    # Prepared source inside another checkout must not inherit its Git identity.
    if not (root/'.git').exists():
        require(not netlify,'Netlify source metadata requires its own Git checkout')
        return result
    try:
        require(Path(metadata_git(root,'rev-parse','--show-toplevel')).resolve()==root.resolve(),
                'Git metadata root does not match the packaged source')
        # Netlify may rewrite the local remote with its deploy credential. Its
        # native REPOSITORY_URL is already checked by ci-build.sh; never expose
        # or depend on the credential-bearing remote URL there.
        origin=env.get('REPOSITORY_URL') if netlify else metadata_git(root,'remote','get-url','origin')
        require(origin in (SOURCE_URL,SOURCE_URL+'.git',
                           'git@github.com:'+SOURCE_REPOSITORY,
                           'git@github.com:'+SOURCE_REPOSITORY+'.git'),
                'Git metadata repository does not match the approved source')
        commit=metadata_git(root,'rev-parse','HEAD')
        require(re.fullmatch(r'[a-f0-9]{40}',commit) is not None,
                'Invalid source commit metadata')
        require(not metadata_git(root,'status','--porcelain=v1','--untracked-files=no'),
                'Tracked source has uncommitted changes')
        committed=datetime.fromisoformat(metadata_git(root,'show','-s','--format=%cI',commit))
        require(committed.tzinfo is not None,'Source timestamp must include a timezone')
        if netlify:
            require(env.get('COMMIT_REF')==commit,'Netlify source commit does not match HEAD')
            deploy_id=env.get('DEPLOY_ID','')
            require(re.fullmatch(r'[a-f0-9]{24}',deploy_id) is not None,
                    'Netlify deployment ID metadata is missing or invalid')
            result['deployId']=deploy_id
        result.update(commit=commit,committedAt=committed.astimezone(timezone.utc).isoformat(),
                      sourceVerified=True)
    except (ValueError,OSError,subprocess.CalledProcessError):
        if netlify:
            # Never include Git stderr, remote credentials, or arbitrary env values.
            raise ValueError('Cannot verify source/deployment metadata for Netlify') from None
        # Local/CI snapshots may be unversioned or dirty. Do not claim a revision.
        result.update(commit=None,committedAt=None,deployId=None,sourceVerified=False)
    return result

def metadata_time(value):
    if not value:return 'Not verified in this package'
    moment=datetime.fromisoformat(value).astimezone(IST)
    return moment.strftime('%d %b %Y, %I:%M:%S %p')+' IST'

def source_footer(document,metadata,login=False):
    """Embed provenance with this HTML, never fetch another deployment's metadata."""
    commit=metadata['commit']
    revision=(f'<a href="{SOURCE_URL}/commit/{escape(commit)}" target="_blank" rel="noopener noreferrer"><code>{escape(commit[:12])}</code></a>'
              if metadata['sourceVerified'] and commit else 'Unverified source snapshot')
    deploy=metadata['deployId']
    deployment=(f'<a href="https://app.netlify.com/projects/mydoxxx-live-test/deploys/{escape(deploy)}" target="_blank" rel="noopener noreferrer">Deployment details ↗</a>'
                if deploy else 'Deployment details unavailable for this package')
    note=('This page uses this build. Exact publish time: '+deployment+'.'
          if deploy else 'Build time is when this package was prepared; publication is not verified.')
    footer=f'''<footer class="bfast-build-footer" aria-label="Website source and build details">
<h2>BFAST · Website version</h2>
<dl>
<div><dt>Code repository</dt><dd><a href="{SOURCE_URL}" target="_blank" rel="noopener noreferrer">{SOURCE_REPOSITORY}</a></dd></div>
<div><dt>App source folder</dt><dd><code>experiments/MYDOXXX/app</code></dd></div>
<div><dt>Testing-room source folder</dt><dd><code>scripts/mydoxxx</code></dd></div>
<div><dt>Code version</dt><dd>{revision}</dd></div>
<div><dt>Code committed</dt><dd>{escape(metadata_time(metadata['committedAt']))}</dd></div>
<div><dt>Website build prepared</dt><dd>{escape(metadata_time(metadata['preparedAt']))}</dd></div>
</dl><p>{note}</p>
{('<p class="bfast-deploy-id">Deployment ID: <code>'+escape(deploy)+'</code></p>') if deploy else ''}
</footer>'''
    css='''/* Package-specific provenance; outside the app frames and never sticky. */
.bfast-build-footer{margin:10px 28px 24px;padding:18px 20px;border:1px solid #d4e2e7;border-top:3px solid #c81e32;border-radius:12px;background:#fff;color:#315561;font:12px/1.6 "Segoe UI",Arial,sans-serif;text-align:left}
.bfast-build-footer h2{margin:0 0 12px;font-size:14px;color:#b91c32;font-weight:800}
.bfast-build-footer dl{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:12px 20px;margin:0}
.bfast-build-footer dl>div{min-width:0}.bfast-build-footer dt{font-size:11px;font-weight:700;color:#617985}.bfast-build-footer dd{margin:2px 0 0;overflow-wrap:anywhere}
.bfast-build-footer a{color:#075d7c;text-decoration:underline;text-underline-offset:2px}.bfast-build-footer a:focus-visible{outline:3px solid #efa83c;outline-offset:3px}
.bfast-build-footer code{font:11px/1.6 Consolas,monospace;overflow-wrap:anywhere}.bfast-build-footer p{font-size:11px;margin:12px 0 0;color:#617985}.bfast-build-footer .bfast-deploy-id{margin-top:4px}
.card .bfast-build-footer{margin:25px 0 0;padding:16px 0 0;border:0;border-top:2px solid #c81e32;border-radius:0}.card .bfast-build-footer dl{grid-template-columns:repeat(2,minmax(0,1fr))}
@media(max-width:650px){.bfast-build-footer{margin:10px 15px 20px;padding:16px}.bfast-build-footer dl,.card .bfast-build-footer dl{grid-template-columns:1fr;gap:10px}}
'''
    document=replace_once(document,'</style>',css+'</style>')
    marker='</main>' if login else '</body>'
    return replace_once(document,marker,footer+marker)

def panel_documents(panel,bootstrap):
    panel=replace_once(panel,'<script src="flutter_bootstrap.js" async></script>','<p id="bfast-panel-fallback" role="status" style="padding:28px;color:#173c49;font:18px Arial,sans-serif">Loading BFAST…</p><script src="panel-startup.js"></script><script src="panel-bridge.js"></script><script src="flutter_bootstrap.js" async></script>')
    # Missing feedback code must never prevent the original Flutter loader from
    # using its default engine callback. The access checks remain in Flutter.
    bootstrap=replace_once(bootstrap,'_flutter.loader.load({','_flutter.loader.load({\nconfig:{canvasKitForceCpuOnly:true,canvasKitMaximumSurfaces:1},\nonEntrypointLoaded:window.MyDoxPanelStartup?.startEngine,')
    return panel,bootstrap

def site_headers():
    # Netlify concatenates matching header values. Give each served path exactly
    # one cache rule; do not combine a global no-store with an asset exception.
    names={'panel/'+name for name in BUILD_FILES}|set(PORTAL_FILES)|GENERATED_FILES
    policies={}
    for name in sorted(names-{'_headers'}):
        reusable=name=='panel/main.dart.js' or name.startswith(('panel/assets/','panel/canvaskit/'))
        policies['/'+name]='private, max-age=0, must-revalidate' if reusable else 'no-store'
        if name.endswith('.html'):
            policies['/'+name[:-5]]='no-store'
            policies['/'+name[:-5]+'/']='no-store'
            if name.endswith('index.html'):
                directory='/'+name[:-10]
                policies[directory]='no-store'
                if directory!='/':policies[directory.rstrip('/')]='no-store'
    security="""/*
  X-Content-Type-Options: nosniff
  Referrer-Policy: no-referrer
  X-Frame-Options: SAMEORIGIN
  Content-Security-Policy: frame-ancestors 'self'; object-src 'none'; base-uri 'self'
  Permissions-Policy: camera=(), microphone=(), geolocation=()
  X-Robots-Tag: noindex, nofollow
"""
    return (security+''.join(f'\n{path}\n  Cache-Control: {policy}\n' for path,policy in sorted(policies.items()))).encode()

def main(argv=None):
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ci',action='store_true',help='Use reviewed high-entropy fingerprints; never open private credentials')
    parser.add_argument('--output',help='Fresh workspace-relative destination; CI requires dist/cloud-test-room')
    args=parser.parse_args(argv)
    out=output_path(args.output,args.ci)
    passwords=known_passwords(args.ci)
    build=build_inputs()
    metadata=build_metadata()
    # Assemble in memory so failure cannot leave a partially publishable folder.
    files={'panel/'+name:data for name,data in build.items()}
    for name in PORTAL_FILES:
        reject_links(SRC/name)
        files[name]=(SRC/name).read_bytes()
    for name in ('panel-bridge.js','panel-startup.js'):
        reject_links(SRC/name)
        files['panel/'+name]=(SRC/name).read_bytes()
    for name in ('test-console.html','test-console.js','test-console-state.js'):
        reject_links(ROOT/'scripts/mydoxxx'/name)
    html=(ROOT/'scripts/mydoxxx/test-console.html').read_text(encoding='utf-8')
    html=replace_once(html,'<html lang="en">','<html lang="en" class="checking-owner">')
    html=replace_once(html,'</style>','.checking-owner body{visibility:hidden}.cloud-owner-bar{display:flex;align-items:center;justify-content:space-between;gap:12px;padding:8px 28px;background:#163d49;color:white;font-size:12px}</style>')
    html=replace_once(html,'<script src="/test-console-state.js"></script><script src="/test-console.js"></script>','<script type="module" src="/room-auth.js"></script>')
    html=html.replace('LOCAL TEST MODE','PRIVATE CLOUD TEST MODE').replace('Local dummy bookings only','Synthetic test bookings only')
    files['room.html']=source_footer(html,metadata).encode()
    files['index.html']=source_footer(files['index.html'].decode(),metadata,login=True).encode()
    js=(ROOT/'scripts/mydoxxx/test-console.js').read_text(encoding='utf-8')
    js=replace_once(js,'S.validateCatalog(data)','S.validateCatalog(data,window.MyDoxCloudRoom.origin)')
    js=replace_once(js,'open.href=identity.url;',"open.href='/room.html?solo='+encodeURIComponent(identity.key);")
    js=replace_once(js,"if(restored)columns=restored.columns;","const solo=new URL(location.href).searchParams.get('solo');if(byKey.has(solo))restored={selected:[solo],columns:1};if(restored)columns=restored.columns;")
    js=js.replace('The local role catalogue is unavailable.','The cloud role catalogue is unavailable.').replace('Local host connection required','Cloud connection required').replace('Start the updated MYDOXXX local test host and reload this page.','Check your connection and reload this page.')
    files['test-console.js']=js.encode()
    files['test-console-state.js']=(ROOT/'scripts/mydoxxx/test-console-state.js').read_bytes()
    catalog={'projectId':'mydoxxx-dev-261102','databaseId':'mydoxxx-testing','roles':[]}
    for family,label in FAMILIES.items():
        for person in [1,2,3]:
            key=family if person==1 else f'{family}_{person}'
            catalog['roles'].append(dict(key=key,label=f'{label} {person}',family=family,person=person,uid='mdxtest'+key.replace('_',''),url=f'{ORIGIN}/panel/?role={key}&autologin=1'))
    files['catalog.json']=json.dumps(catalog).encode()
    panel,bootstrap=panel_documents(files['panel/index.html'].decode(),files['panel/flutter_bootstrap.js'].decode())
    files['panel/index.html']=panel.encode()
    files['panel/flutter_bootstrap.js']=bootstrap.encode()
    files['_headers']=site_headers()
    files['robots.txt']=b'User-agent: *\nDisallow: /\n'
    require(set(files)=={'panel/'+name for name in BUILD_FILES}|set(PORTAL_FILES)|GENERATED_FILES,
            'Publish allowlist mismatch')
    for data in files.values():scan_bytes(data,passwords)
    out.mkdir(parents=True,exist_ok=False)
    for name,data in files.items():
        destination=out/name
        destination.parent.mkdir(parents=True,exist_ok=True)
        destination.write_bytes(data)
    report={'publishDirectory':str(out),'files':len(files),'accounts':len(catalog['roles']),
            'credentialScan':'passed','mode':'ci-fingerprints' if args.ci else 'local-known-values-and-fingerprints',
            'fingerprintsChecked':36,'privateCredentialsRead':not args.ci,'cloudCalls':0,
            'mainJsSha256':hashlib.sha256(files['panel/main.dart.js']).hexdigest(),
            'manifest':[{ 'path':name,'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()}
                        for name,data in sorted(files.items())]}
    (out.parent/'cloud-site-package-receipt.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    print(json.dumps(report))
if __name__=='__main__':main()


