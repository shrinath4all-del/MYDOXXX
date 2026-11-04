/// Select the existing staffing partner without attributing independent home
/// visits to an agency. The caller verifies membership inside its transaction.
class StaffingClaimAgency {
  static String select(
      {String? assignedByAgency,
      required Map<String, dynamic> shift,
      required Map<String, dynamic> provider}) {
    if ((assignedByAgency ?? '').isNotEmpty) return assignedByAgency!;
    final assigned = (shift['agencyId'] ?? '').toString();
    if (assigned.isNotEmpty) return assigned;
    final hospitalRequest = shift['postedBy'] == 'hospital' ||
        ((shift['hospitalId'] ?? '').toString().isNotEmpty &&
            shift['postedBy'] != 'patient');
    return hospitalRequest ? (provider['agencyId'] ?? '').toString() : '';
  }

  static bool membershipValid(
          {required String agencyId,
          required Map<String, dynamic>? provider,
          required Map<String, dynamic>? agency,
          required String agencyType}) =>
      agencyId.isNotEmpty &&
      provider != null &&
      provider['isVerified'] == true &&
      provider['agencyId'] == agencyId &&
      agency != null &&
      agency['active'] != false &&
      agency['agencyType'] == agencyType;
}
