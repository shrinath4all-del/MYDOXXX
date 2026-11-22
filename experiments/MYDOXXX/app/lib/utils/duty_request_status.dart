/// Compatibility for existing leave requests while new requests use agency
/// approval. No records are migrated merely by reading a list.
class DutyRequestStatus {
  DutyRequestStatus._();

  static const platformId = 'platform';
  static const pending = ['pending', 'awaiting_agency', 'awaiting_hospital'];

  static bool awaitingApproval(Object? status) =>
      status == 'awaiting_agency' || status == 'awaiting_hospital';

  static bool isPending(Object? status) => pending.contains(status);

  /// Legacy records always persisted the team's agencyId (empty for platform
  /// work). Explicit new approvers take precedence over that legacy scope.
  static String approverOf(Map<String, dynamic> request) {
    final explicit = (request['approverId'] ?? '').toString();
    if (explicit.isNotEmpty) return explicit;
    final agency = (request['agencyId'] ?? '').toString();
    return agency.isEmpty ? platformId : agency;
  }

  /// Include the old agency's complete leave history. Decision eligibility is
  /// checked separately, so covered or closed requests cannot be approved again.
  static bool legacyForApprover(
    Map<String, dynamic> request,
    String approverId,
  ) =>
      request['type'] == 'leave' &&
      (request['approverId'] ?? '').toString().isEmpty &&
      approverOf(request) == approverId;

  static bool canDecide(Map<String, dynamic> request, String approverId) =>
      request['type'] == 'leave' &&
      awaitingApproval(request['status']) &&
      approverOf(request) == approverId;

  static bool canWithdraw(Map<String, dynamic> request, String uid) =>
      isPending(request['status']) && request['requesterUid'] == uid;

  static bool blocksDuty(Map<String, dynamic> request, List<String> keys) =>
      isPending(request['status']) &&
      (keys.contains(request['sourceKey']) ||
          keys.contains(request['targetKey']));
}
