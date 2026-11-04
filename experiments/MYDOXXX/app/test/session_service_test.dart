import 'package:flutter_test/flutter_test.dart';
import 'package:mydox/services/session_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('the single-device check can be paused while logging in and resumed', () {
    SessionService.resume();
    expect(SessionService.paused, isFalse);
    SessionService.pause();
    expect(SessionService.paused, isTrue);
    SessionService.resume();
    expect(SessionService.paused, isFalse);
  });

  test('this device remembers its own session id until it signs out', () async {
    SharedPreferences.setMockInitialValues({'mydox_session_id': 'abc123'});
    expect(await SessionService.localId(), 'abc123');
    await SessionService.clearLocal();
    expect(await SessionService.localId(), isNull);
  });
}
