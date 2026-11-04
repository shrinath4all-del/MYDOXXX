"""Assemble a strictly static, credential-free Netlify cloud lab artifact."""
from pathlib import Path
import json
import shutil
import re
from datetime import datetime, timezone
ROOT=Path(__file__).resolve().parents[3]
SRC=Path(__file__).resolve().parent
OUT=ROOT/('private-backups/mydoxxx-dev-261102/cloud-site-'+datetime.now(timezone.utc).strftime('%Y%m%d-%H%M%S'))
BUILD=ROOT/'experiments/MYDOXXX/app/build/web-cloud-lab'
ORIGIN='https://mydoxxx-live-test.netlify.app'
FAMILIES={'patient':'Patient','doctor':'Cardiologist','nurse':'Nurse','hospital':'Hospital','ambulance':'Ambulance','care_physician':'Care Physician','technician':'Technician','therapist':'Physiotherapist','agency_care':'Care Agency','agency_nurse':'Nursing Agency','agency_technician':'Technician Agency','agency_physio':'Physio Agency'}
def replace_once(source,old,new):
    assert source.count(old)==1, f'Expected one reviewed marker: {old[:60]}'
    return source.replace(old,new,1)
def main():
    assert (BUILD/'main.dart.js').is_file(),'Build the cloud-only Flutter lab first.'
    OUT.mkdir(parents=True,exist_ok=False)
    # This output directory is task-owned, never an arbitrary cleanup target.
    assert OUT.resolve().is_relative_to((ROOT/'private-backups/mydoxxx-dev-261102').resolve())
    shutil.copytree(BUILD,OUT/'panel')
    for name in ['index.html','cloud-config.js','owner-auth.js','login.js','login-support.js','room-auth.js']:
        shutil.copyfile(SRC/name,OUT/name)
    shutil.copyfile(SRC/'panel-bridge.js',OUT/'panel/panel-bridge.js')
    html=(ROOT/'scripts/mydoxxx/test-console.html').read_text(encoding='utf-8')
    html=replace_once(html,'<html lang="en">','<html lang="en" class="checking-owner">')
    html=replace_once(html,'</style>','.checking-owner body{visibility:hidden}.cloud-owner-bar{display:flex;align-items:center;justify-content:space-between;gap:12px;padding:8px 28px;background:#163d49;color:white;font-size:12px}</style>')
    html=replace_once(html,'<script src="/test-console-state.js"></script><script src="/test-console.js"></script>','<script type="module" src="/room-auth.js"></script>')
    html=html.replace('LOCAL TEST MODE','PRIVATE CLOUD TEST MODE').replace('Local dummy bookings only','Synthetic test bookings only')
    (OUT/'room.html').write_text(html,encoding='utf-8')
    js=(ROOT/'scripts/mydoxxx/test-console.js').read_text(encoding='utf-8')
    js=replace_once(js,'S.validateCatalog(data)','S.validateCatalog(data,window.MyDoxCloudRoom.origin)')
    js=replace_once(js,'open.href=identity.url;',"open.href='/room.html?solo='+encodeURIComponent(identity.key);")
    js=replace_once(js,"if(restored)columns=restored.columns;","const solo=new URL(location.href).searchParams.get('solo');if(byKey.has(solo))restored={selected:[solo],columns:1};if(restored)columns=restored.columns;")
    js=js.replace('The local role catalogue is unavailable.','The cloud role catalogue is unavailable.').replace('Local host connection required','Cloud connection required').replace('Start the updated MYDOXXX local test host and reload this page.','Check your connection and reload this page.')
    (OUT/'test-console.js').write_text(js,encoding='utf-8')
    shutil.copyfile(ROOT/'scripts/mydoxxx/test-console-state.js',OUT/'test-console-state.js')
    catalog={'projectId':'mydoxxx-dev-261102','databaseId':'mydoxxx-testing','roles':[]}
    for family,label in FAMILIES.items():
        for person in [1,2,3]:
            key=family if person==1 else f'{family}_{person}'
            catalog['roles'].append(dict(key=key,label=f'{label} {person}',family=family,person=person,uid='mdxtest'+key.replace('_',''),url=f'{ORIGIN}/panel/?role={key}&autologin=1'))
    (OUT/'catalog.json').write_text(json.dumps(catalog),encoding='utf-8')
    panel=(OUT/'panel/index.html').read_text(encoding='utf-8')
    panel=replace_once(panel,'<script src="flutter_bootstrap.js" async></script>','<script src="panel-bridge.js"></script><script src="flutter_bootstrap.js" async></script>')
    (OUT/'panel/index.html').write_text(panel,encoding='utf-8')
    bootstrap=(OUT/'panel/flutter_bootstrap.js').read_text(encoding='utf-8')
    bootstrap=replace_once(bootstrap,'_flutter.loader.load({','_flutter.loader.load({\nconfig:{canvasKitForceCpuOnly:true,canvasKitMaximumSurfaces:1},')
    (OUT/'panel/flutter_bootstrap.js').write_text(bootstrap,encoding='utf-8')
    (OUT/'_headers').write_text('''/*
  X-Content-Type-Options: nosniff
  Referrer-Policy: no-referrer
  X-Frame-Options: SAMEORIGIN
  Content-Security-Policy: frame-ancestors 'self'; object-src 'none'; base-uri 'self'
  Permissions-Policy: camera=(), microphone=(), geolocation=()
  Cache-Control: no-store
  X-Robots-Tag: noindex, nofollow
''',encoding='utf-8')
    (OUT/'robots.txt').write_text('User-agent: *\nDisallow: /\n',encoding='utf-8')
    # Scan the publish artifact for private credentials without emitting any.
    creds=ROOT/'private-backups/mydoxxx-dev-261102/test-lab-credentials.json'
    secrets=[]
    assert creds.is_file(),'Known-secret scan input is required before publication'
    secrets=[x['password'].encode() for x in json.loads(creds.read_text(encoding='utf-8-sig'))['accounts'].values()]
    assert len(secrets)==36
    count=0
    for path in OUT.rglob('*'):
        if not path.is_file():continue
        assert path.suffix.lower() not in {'.jks','.keystore','.pem','.p12'}, 'Private artifact in publish folder'
        data=path.read_bytes();count+=1
        assert b'-----BEGIN PRIVATE KEY-----' not in data and all(secret not in data for secret in secrets),'Credential detected in publish artifact'
    report={'publishDirectory':str(OUT),'files':count,'accounts':len(catalog['roles']),'credentialScan':'passed'}
    (OUT.parent/'cloud-site-package-receipt.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    print(json.dumps(report))
if __name__=='__main__':main()
