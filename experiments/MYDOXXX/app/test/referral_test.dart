import 'package:flutter_test/flutter_test.dart';
import 'package:mydox/services/agency_invite_service.dart';
import 'package:mydox/services/referral_service.dart';
import 'package:mydox/widgets/referral_widgets.dart';

/// Referral links: one link for care physicians, nurses, technicians and
/// physiotherapists. An agency's link joins its agency at once; whoever sent
/// the first link a person used stays on record as who referred them.
void main() {
  const nursing = {'name': 'Sai Nursing', 'agencyType': 'nurse', 'inviteCode': 'SAI-7K3Q'};
  const lab = {'name': 'City Lab Staff', 'agencyType': 'technician', 'inviteCode': 'CIT-2222'};
  final nurseAgency = ReferralService.referrerFrom('agencies', 'a1', nursing);
  final labAgency = ReferralService.referrerFrom('agencies', 'a2', lab);
  final marketer = ReferralService.referrerFrom(
      AgencyInviteService.referrersCollection,
      'm1',
      const {'name': 'Ravi Kumar', 'inviteCode': 'RAV-9999'});

  group('all four kinds of staff use the same link', () {
    test('technicians are invited like the others', () {
      expect(AgencyInviteService.roleFromKey('technician'), InviteRole.technician);
      expect(AgencyInviteService.collectionOf(InviteRole.technician), 'technicians');
      expect(AgencyInviteService.staffWord(InviteRole.technician), 'technicians');
      expect(AgencyInviteService.inviteProblem(lab, InviteRole.technician), isNull);
    });

    test('a technician agency takes technicians only', () {
      for (final other in [
        InviteRole.nurse,
        InviteRole.carePhysician,
        InviteRole.therapist
      ]) {
        expect(AgencyInviteService.agencyServes(lab, other), isFalse);
        expect(AgencyInviteService.inviteProblem(lab, other),
            contains('different kind of agency'));
      }
      expect(AgencyInviteService.inviteProblem(nursing, InviteRole.technician),
          contains('different kind of agency'));
    });

    test('every role has a stored name that reads back', () {
      for (final role in InviteRole.values) {
        expect(AgencyInviteService.roleFromKey(AgencyInviteService.roleKey(role)),
            role);
      }
      expect(InviteRole.values.length, 4);
    });

    test('an agency link opens the form of the staff it takes', () {
      expect(AgencyInviteService.roleOfAgency(nursing), InviteRole.nurse);
      expect(AgencyInviteService.roleOfAgency(lab), InviteRole.technician);
      expect(
          AgencyInviteService.roleOfAgency(const {'agencyType': 'care_physician'}),
          InviteRole.carePhysician);
      expect(AgencyInviteService.roleOfAgency(const {'agencyType': 'physio'}),
          InviteRole.therapist);
      expect(AgencyInviteService.roleOfAgency(const {}), InviteRole.therapist);
      for (final a in [nursing, lab]) {
        expect(
            AgencyInviteService.agencyServes(
                a, AgencyInviteService.roleOfAgency(a)),
            isTrue);
      }
    });
  });

  group('who a code belongs to', () {
    test('an agency or a marketing person', () {
      expect(nurseAgency.type, Referrer.agency);
      expect(nurseAgency.isAgency, isTrue);
      expect(nurseAgency.name, 'Sai Nursing');
      expect(nurseAgency.code, 'SAI-7K3Q');
      expect(nurseAgency.data['id'], 'a1');
      expect(marketer.type, Referrer.marketing);
      expect(marketer.isAgency, isFalse);
      expect(marketer.active, isTrue);
    });

    test('a closed agency or a switched-off code cannot be used', () {
      final off = ReferralService.referrerFrom(
          'agencies', 'a1', {...nursing, 'inviteActive': false});
      final closed = ReferralService.referrerFrom(
          'agencies', 'a1', {...nursing, 'active': false});
      expect(ReferralService.problem(off), contains('switched off'));
      expect(ReferralService.problem(closed), contains('switched off'));
      expect(ReferralService.problem(null), contains('not found'));
      expect(ReferralService.problem(nurseAgency), isNull);
      expect(ReferralService.problem(marketer), isNull);
    });
  });

  group('the referral is written once', () {
    final at = DateTime(2026, 11, 23, 18, 5);
    final tag = ReferralService.tagFor(nurseAgency,
        via: ReferralService.atSignUp, at: at);

    test('the tag names who, with which code, where and when', () {
      expect(tag, {
        'type': 'agency',
        'id': 'a1',
        'name': 'Sai Nursing',
        'code': 'SAI-7K3Q',
        'via': 'signup',
        'at': '2026-11-23T18:05:00.000',
      });
      expect(ReferralService.referralOf({'referredBy': tag}), tag);
    });

    test('a profile without a referral has none', () {
      expect(ReferralService.referralOf(null), isNull);
      expect(ReferralService.referralOf(const {}), isNull);
      expect(ReferralService.referralOf(const {'referredBy': 'x'}), isNull);
      expect(ReferralService.referralOf(const {'referredBy': {'name': 'x'}}),
          isNull);
    });

    test('nothing on record: a referral may be written', () {
      expect(ReferralService.existing(const {'name': 'Asha'}, null), isNull);
      expect(ReferralService.existing(null, const {}), isNull);
    });

    test('a referral on the profile blocks a new one', () {
      expect(ReferralService.existing({'referredBy': tag}, null), tag);
    });

    test('leaving the agency does not remove it', () {
      // leaving clears the agency fields only
      final afterLeaving = {'agencyId': '', 'agencyName': '', 'referredBy': tag};
      expect(ReferralService.existing(afterLeaving, null)!['name'], 'Sai Nursing');
    });

    test('the back-office record outlives a profile that lost its tag', () {
      final record = ReferralService.recordFor(InviteRole.nurse, 'u1', tag,
          const {'name': 'Asha Patil', 'mobileNumber': '9000000001'});
      expect(record['uid'], 'u1');
      expect(record['role'], 'nurse');
      expect(record['staffName'], 'Asha Patil');
      expect(record['phone'], '9000000001');
      expect(record['referrerId'], 'a1');
      expect(record['referrerType'], 'agency');
      expect(ReferralService.existing(const {'name': 'Asha Patil'}, record), tag);
    });
  });

  group('what the person is told', () {
    test('an agency code for their kind of staff joins at once', () {
      expect(
          ReferralService.outcome(nurseAgency, InviteRole.nurse,
              joined: true, recorded: true),
          'You joined Sai Nursing.');
      // joining again later with a new agency's code: still joins
      expect(
          ReferralService.outcome(nurseAgency, InviteRole.nurse,
              joined: true, recorded: false, earlier: 'Ravi Kumar'),
          'You joined Sai Nursing.');
    });

    test('a marketing code is noted, without joining anything', () {
      expect(
          ReferralService.outcome(marketer, InviteRole.technician,
              joined: false, recorded: true),
          'Ravi Kumar is noted as the one who referred you.');
    });

    test('a second marketing code changes nothing and says so', () {
      expect(
          () => ReferralService.outcome(marketer, InviteRole.technician,
              joined: false, recorded: false, earlier: 'Sai Nursing'),
          throwsA(predicate((e) =>
              e.toString().contains('already noted (Sai Nursing)') &&
              e.toString().contains('cannot be changed'))));
    });

    test('another kind of agency is noted but not joined', () {
      final text = ReferralService.outcome(labAgency, InviteRole.nurse,
          joined: false, recorded: true);
      expect(text, contains('City Lab Staff is noted'));
      expect(text, contains('agency for technicians'));
      expect(text, contains('not added'));
      expect(
          () => ReferralService.outcome(labAgency, InviteRole.nurse,
              joined: false, recorded: false, earlier: 'Ravi Kumar'),
          throwsA(predicate(
              (e) => e.toString().contains('different kind of agency'))));
    });
  });

  group('sign-up form', () {
    test('an agency link says the person joins it', () {
      final note = ReferralService.signUpNote(nurseAgency, InviteRole.nurse);
      expect(note.problem, isFalse);
      expect(note.text, contains('You join Sai Nursing'));
      expect(note.text, contains('leave the agency later'));
    });

    test('a marketing link is kept for the record', () {
      final note = ReferralService.signUpNote(marketer, InviteRole.carePhysician);
      expect(note.problem, isFalse);
      expect(note.text, contains('who brought you'));
    });

    test('an agency for other staff is noted, not joined', () {
      final note = ReferralService.signUpNote(labAgency, InviteRole.therapist);
      expect(note.problem, isFalse);
      expect(note.text, contains('agency for technicians'));
      expect(note.text, contains('still kept as who referred you'));
    });

    test('an unknown code is a problem', () {
      final note = ReferralService.signUpNote(null, InviteRole.nurse);
      expect(note.problem, isTrue);
      expect(note.text, contains('not found'));
    });
  });

  group('how it is shown', () {
    test('the profile line names who and when (India date)', () {
      expect(
          ReferredByLine.textOf({
            'referredBy': {
              'type': 'agency',
              'id': 'a1',
              'name': 'Sai Nursing',
              'at': '2026-11-23T18:05:00.000'
            }
          }),
          'Referred by Sai Nursing (agency) · 23/11/2026');
      expect(
          ReferredByLine.textOf({
            'referredBy': {'type': 'marketing', 'id': 'm1', 'name': 'Ravi Kumar'}
          }),
          'Referred by Ravi Kumar (BFAST team)');
      expect(ReferredByLine.textOf(const {}), '');
    });

    test('a UTC-stamped time shows the India date', () {
      // 20:00 UTC on the 23rd is 01:30 on the 24th in India
      expect(
          ReferredByLine.textOf({
            'referredBy': {
              'type': 'agency',
              'id': 'a1',
              'name': 'Sai Nursing',
              'at': '2026-11-23T20:00:00.000Z'
            }
          }),
          endsWith('24/11/2026'));
    });

    test('the back-office line says the role, how and when', () {
      expect(
          ReferralService.summaryOf(const {
            'role': 'care_physician',
            'via': 'signup',
            'at': '2026-11-23T18:05:00.000'
          }),
          'Care physician · at sign-up · 23/11/2026');
      expect(
          ReferralService.summaryOf(const {'role': 'technician', 'via': 'profile'}),
          'Technician · code entered later');
    });

    test('the list is newest first', () {
      final sorted = ReferralService.newestFirst([
        {'uid': 'old', 'at': '2026-11-01T09:00:00.000'},
        {'uid': 'new', 'at': '2026-11-23T09:00:00.000'},
        {'uid': 'mid', 'at': '2026-11-10T09:00:00.000'},
      ]);
      expect([for (final r in sorted) r['uid']], ['new', 'mid', 'old']);
    });
  });
}
