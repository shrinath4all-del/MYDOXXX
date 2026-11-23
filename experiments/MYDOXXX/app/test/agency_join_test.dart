import 'package:flutter_test/flutter_test.dart';
import 'package:mydox/services/agency_join_service.dart';
import 'package:mydox/services/care_physician_service.dart';

void main() {
  test('only an approved agency member may apply for full-time jobs', () {
    expect(AgencyJoinService.fullTimeBlockReason({'agencyId': 'a1'}), isNull);
    expect(AgencyJoinService.fullTimeBlockReason({}),
        contains('Join an agency first'));
    expect(
        AgencyJoinService.fullTimeBlockReason(
            {'joinStatus': 'pending', 'joinAgencyName': 'Apex'}),
        contains('waiting for the agency'));
  });

  test('pending and rejected requests are read from the profile', () {
    final waiting = {'joinStatus': 'pending', 'joinAgencyName': 'Apex'};
    expect(AgencyJoinService.pendingAgencyName(waiting), 'Apex');
    expect(AgencyJoinService.rejectedBy(waiting), '');
    final no = {'joinStatus': 'rejected', 'joinAgencyName': 'Apex'};
    expect(AgencyJoinService.rejectedBy(no), 'Apex');
    expect(AgencyJoinService.pendingAgencyName(no), '');
  });

  test('the agency sees the details of the request', () {
    final d = AgencyJoinService.details({
      'name': 'Asha Rao',
      'experienceYears': 4,
      'qualification': 'mbbs',
      'regNo': 'MMC201908421',
      'phone': '+919876543210',
      'email': 'asha@example.com',
      'areas': ['Baner'],
    }, CarePhysicianService.collection);
    expect(d['name'], 'Asha Rao');
    expect(d['experienceYears'], 4);
    expect(d['regNo'], 'MMC201908421');
    expect(d['role'], 'Care physician');
  });

  test('a freelancer cannot apply; the agency list leaves freelancers out', () {
    final me = {
      'uid': 'cp1',
      'isVerified': true,
      'available': true,
    };
    expect(CarePhysicianService.applyBlockReason(me), contains('Join an agency'));
    expect(CarePhysicianService.applyBlockReason({...me, 'agencyId': 'a1'}), isNull);
    final request = {
      'applicants': {
        'free': {'name': 'Freelancer', 'experienceYears': 9, 'agencyId': ''},
        'member': {'name': 'Member', 'experienceYears': 2, 'agencyId': 'a1'},
      },
    };
    expect(CarePhysicianService.shortlist(request).map((e) => e.uid), ['member']);
  });
}
