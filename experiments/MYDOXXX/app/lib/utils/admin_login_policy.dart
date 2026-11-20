/// Client admission check for an already provisioned administrator account.
/// The caller must read the role from the authenticated UID's account record.
/// Backend security rules must independently enforce administrator privileges.
bool canUseProvisionedAdminPortal({
  required String authenticatedEmail,
  required String configuredAdminEmail,
  required Object? storedRole,
}) {
  final allowedEmail = configuredAdminEmail.trim().toLowerCase();
  return storedRole == 'admin' &&
      allowedEmail.isNotEmpty &&
      authenticatedEmail.trim().toLowerCase() == allowedEmail;
}
