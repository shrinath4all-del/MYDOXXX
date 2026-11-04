/// Native builds cannot obtain a portal's ephemeral web login.
Future<String> requestCloudLogin(String roleKey) async {
  throw StateError('Cloud test logins require the approved web test portal.');
}
