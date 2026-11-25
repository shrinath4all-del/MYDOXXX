import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mydox/services/auth_service.dart';

/// New accounts confirm their email (Firebase's link) before they can log in.
/// The links the app hands to Firebase must come back to THIS project's site,
/// never to the original or a preserved project.
void main() {
  const preserved = ['mydox-be432', 'clinigo-77808', 'mydox-shrinath-backup-261102'];

  test('new accounts must verify their email', () {
    expect(AuthService.requireVerifiedEmail, isTrue);
  });

  test('the verification and password links return to this project', () {
    for (final link in [AuthService.verifyContinueUrl, AuthService.resetPageUrl]) {
      final uri = Uri.parse(link);
      expect(uri.scheme, 'https', reason: link);
      expect(uri.host, 'mydoxxx-dev-261102.web.app', reason: link);
    }
  });

  test('no file in the app links to a preserved project\'s site', () {
    final hosts = RegExp(
        '(${preserved.join('|')})\\.(web\\.app|firebaseapp\\.com)');
    final hits = <String>[];
    for (final e in Directory('lib').listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      final lines = e.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (hosts.hasMatch(lines[i])) hits.add('${e.path}:${i + 1}');
      }
    }
    expect(hits, isEmpty, reason: hits.join('\n'));
  });
}
