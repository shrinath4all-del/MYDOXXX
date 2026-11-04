import 'dart:js_interop';

/// Implemented by the portal's frame bridge before Flutter starts. The bridge
/// validates parent origin, source window and request ID. It returns JSON only
/// to this frame; it must never persist or log credentials.
@JS('mydoxCloudTestLogin')
external JSPromise<JSString> _requestCloudLogin(JSString roleKey);

Future<String> requestCloudLogin(String roleKey) async {
  try {
    return (await _requestCloudLogin(roleKey.toJS).toDart).toDart;
  } catch (_) {
    // Do not surface a JS rejection that might contain a token or response.
    throw StateError(
        'Cloud test sign-in is unavailable. Reopen this panel from the test portal.');
  }
}
