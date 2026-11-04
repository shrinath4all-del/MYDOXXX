import 'package:flutter_test/flutter_test.dart';
import 'package:mydox/services/staffing_claim_agency.dart';

void main() {
  const physician = {'agencyId': 'sai', 'isVerified': true};
  const hospital = {'postedBy': 'hospital', 'hospitalId': 'hospital1'};
  test(
      'hospital locum inherits accepting physician partner when hospital left agency blank',
      () {
    expect(StaffingClaimAgency.select(shift: hospital, provider: physician),
        'sai');
  });
  test('existing explicitly routed hospital agency is preserved', () {
    expect(
        StaffingClaimAgency.select(
            shift: {...hospital, 'agencyId': 'partner'}, provider: physician),
        'partner');
  });
  test('agency coordinator assignment has priority', () {
    expect(
        StaffingClaimAgency.select(
            assignedByAgency: 'coordinator',
            shift: {...hospital, 'agencyId': 'partner'},
            provider: physician),
        'coordinator');
  });
  test('independent patient home visit does not acquire agency margin', () {
    expect(
        StaffingClaimAgency.select(
            shift: const {'postedBy': 'patient', 'hospitalId': ''},
            provider: physician),
        '');
  });
  test('physician who left agency does not retain stale agency routing', () {
    expect(StaffingClaimAgency.select(shift: hospital, provider: const {}), '');
  });
  const activeAgency = {'agencyType': 'care_physician', 'active': true};
  bool valid(Map<String, dynamic>? provider, Map<String, dynamic>? agency) =>
      StaffingClaimAgency.membershipValid(
          agencyId: 'sai',
          provider: provider,
          agency: agency,
          agencyType: 'care_physician');
  test('verified current membership is valid',
      () => expect(valid(physician, activeAgency), isTrue));
  test('transaction must reject membership removed during acceptance',
      () => expect(valid(const {'isVerified': true}, activeAgency), isFalse));
  test(
      'transaction must reject inactive partner',
      () => expect(
          valid(physician, {...activeAgency, 'active': false}), isFalse));
  test(
      'transaction must reject wrong agency type',
      () => expect(
          valid(physician, {...activeAgency, 'agencyType': 'nurse'}), isFalse));
  test('transaction must reject missing or unverified profile',
      () => expect(valid(const {'agencyId': 'sai'}, activeAgency), isFalse));
  test('transaction must reject deleted agency',
      () => expect(valid(physician, null), isFalse));
}
