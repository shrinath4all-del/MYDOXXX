"""Apply already-downloaded SDK config to this isolated copy; no cloud operations."""
from pathlib import Path
import argparse, json, plistlib, shutil

PROJECT = 'mydoxxx-dev-261102'
APP = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser()
parser.add_argument('--config-root', required=True)
args = parser.parse_args()
config_root = Path(args.config_root).resolve()
assert APP.name == 'app' and APP.parent.name == 'MYDOXXX'
record = json.loads((config_root / 'app-registration-restore-status.json').read_text())
assert record['target'] == PROJECT
apps = record['apps']
android = next(a for a in apps if a['platform'] == 'ANDROID' and a.get('packageName') == 'com.mydox.app')
ios = next(a for a in apps if a['platform'] == 'IOS' and a.get('bundleId') == 'com.mydox.app')
web = next(a for a in apps if a['platform'] == 'WEB' and a['displayName'] == 'mydox (web)')
windows = next(a for a in apps if a['platform'] == 'WEB' and a['displayName'] == 'mydox (windows)')

def filename(app):
    result = (config_root / app['config']).resolve()
    assert result.is_relative_to(config_root)
    return result

android_json = json.loads(filename(android).read_text())
client = next(c for c in android_json['client'] if c['client_info']['android_client_info']['package_name'] == 'com.mydox.app')
apple = plistlib.loads(filename(ios).read_bytes())
web_json = json.loads(filename(web).read_text())
windows_json = json.loads(filename(windows).read_text())
assert android_json['project_info']['project_id'] == apple['PROJECT_ID'] == web_json['projectId'] == windows_json['projectId'] == PROJECT
shutil.copyfile(filename(android), APP / 'android/app/google-services.json')
shutil.copyfile(filename(ios), APP / 'ios/Runner/GoogleService-Info.plist')
platforms = {
    'web': web_json,
    'android': {'apiKey': client['api_key'][0]['current_key'], 'appId': client['client_info']['mobilesdk_app_id'], 'messagingSenderId': android_json['project_info']['project_number'], 'projectId': PROJECT, 'storageBucket': android_json['project_info']['storage_bucket']},
    'ios': {'apiKey': apple['API_KEY'], 'appId': apple['GOOGLE_APP_ID'], 'messagingSenderId': apple['GCM_SENDER_ID'], 'projectId': PROJECT, 'storageBucket': apple['STORAGE_BUCKET'], 'iosBundleId': 'com.mydox.app'},
    'windows': windows_json,
}
platforms['macos'] = platforms['ios'].copy()
content = '''// MYDOXXX configuration from its independent Firebase app registrations.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android: return android;
      case TargetPlatform.iOS: return ios;
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
        throw UnsupportedError('MYDOXXX desktop setup is pending.');
      default:
        throw UnsupportedError('MYDOXXX Firebase is not configured on this platform.');
    }
  }
'''
keys = ['apiKey', 'appId', 'messagingSenderId', 'projectId', 'authDomain', 'storageBucket', 'measurementId', 'iosClientId', 'iosBundleId']
for platform in ['web', 'android', 'ios', 'macos', 'windows']:
    content += '\n  static const FirebaseOptions ' + platform + ' = FirebaseOptions(\n'
    for key in keys:
        if key in platforms[platform]:
            content += '    ' + key + ': ' + repr(str(platforms[platform][key])) + ',\n'
    content += '  );\n'
content += '}\n'
(APP / 'lib/firebase_options.dart').write_text(content, encoding='utf8')
firebase_json = json.loads((APP / 'firebase.json').read_text())
firebase_json['flutter']['platforms']['android']['default'].update(projectId=PROJECT, appId=android['targetAppId'])
dart = firebase_json['flutter']['platforms']['dart']['lib/firebase_options.dart']
dart['projectId'] = PROJECT
dart['configurations'] = {'android': android['targetAppId'], 'ios': ios['targetAppId'], 'macos': ios['targetAppId'], 'web': web['targetAppId'], 'windows': windows['targetAppId']}
assert 'functions' not in firebase_json
(APP / 'firebase.json').write_text(json.dumps(firebase_json, indent=2) + '\n', encoding='utf8')
assert json.loads((APP / '.firebaserc').read_text())['projects']['default'] == PROJECT
assert ("projectId = '" + PROJECT + "'") in (APP / 'lib/config/experiment_environment.dart').read_text()
print(json.dumps({'project': PROJECT, 'androidPackage': 'com.mydox.app', 'appleBundle': 'com.mydox.app', 'platformConfigs': len(platforms), 'desktopActivation': False}))
