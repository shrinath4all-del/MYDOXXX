import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mydox/services/agency_invite_service.dart';

/// Agency invite codes: an agency shares a link / code; staff who sign up with
/// it join that agency at once. Picking an agency from the list is a request.
void main() {
  group('invite codes', () {
    test('three letters of the name, a dash and four easy characters', () {
      final code = AgencyInviteService.newCode('Sai Care Services', Random(1));
      expect(code, matches(RegExp(r'^SAI-[A-HJ-NP-Z2-9]{4}$')));
    });

    test('short or non-letter names still give a full prefix', () {
      expect(AgencyInviteService.newCode('Jo', Random(2)), startsWith('JOX-'));
      expect(AgencyInviteService.newCode('123 !', Random(3)), startsWith('AGY-'));
    });

    test('codes never use characters that are easy to mix up', () {
      final r = Random(4);
      for (var i = 0; i < 500; i++) {
        final tail = AgencyInviteService.newCode('Nursing Bureau', r).split('-')[1];
        expect(tail, isNot(matches(RegExp('[01OIL]'))));
      }
    });

    test('many codes for one agency are different', () {
      final r = Random(5);
      final codes = {
        for (var i = 0; i < 200; i++) AgencyInviteService.newCode('Sai', r)
      };
      expect(codes.length, greaterThan(190));
    });
  });

  group('reading a typed or pasted code', () {
    test('case, spaces and the dash do not matter', () {
      for (final typed in ['SAI-7K3Q', 'sai-7k3q', ' sai 7k3q ', 'SAI7K3Q']) {
        expect(AgencyInviteService.keyOf(typed), 'SAI7K3Q', reason: typed);
      }
    });

    test('a whole pasted invite link works too', () {
      expect(
          AgencyInviteService.keyOf(
              'https://app.example.com/?invite=SAI-7K3Q'),
          'SAI7K3Q');
    });

    test('empty or silly text is no code', () {
      for (final typed in ['', '  ', 'ab', 'X' * 30]) {
        expect(AgencyInviteService.keyOf(typed), '', reason: typed);
      }
    });
  });

  test('the link carries the code on the page the app runs from', () {
    expect(
        AgencyInviteService.linkFor(
            Uri.parse('https://app.example.com/start?x=1'), 'SAI-7K3Q'),
        'https://app.example.com/start?invite=SAI-7K3Q');
    expect(
        AgencyInviteService.linkFor(Uri.parse('http://localhost:8080'), 'A-1'),
        'http://localhost:8080/?invite=A-1');
  });

  group('which agency may take whom', () {
    final nursing = {'agencyType': 'nurse', 'active': true};
    final doctors = {'agencyType': 'care_physician', 'active': true};
    final physio = {'agencyType': 'physio', 'active': true};
    final legacyPhysio = {'active': true}; // older physio agencies had no type
    final lab = {'agencyType': 'technician', 'active': true};

    test('each role only joins its own kind of agency', () {
      expect(AgencyInviteService.inviteProblem(nursing, InviteRole.nurse), isNull);
      expect(AgencyInviteService.inviteProblem(doctors, InviteRole.carePhysician),
          isNull);
      expect(AgencyInviteService.inviteProblem(physio, InviteRole.therapist), isNull);
      expect(AgencyInviteService.inviteProblem(legacyPhysio, InviteRole.therapist),
          isNull);
      expect(AgencyInviteService.inviteProblem(nursing, InviteRole.carePhysician),
          contains('not for care physicians'));
      expect(AgencyInviteService.inviteProblem(doctors, InviteRole.nurse),
          contains('not for nurses'));
      expect(AgencyInviteService.inviteProblem(lab, InviteRole.therapist),
          contains('not for physiotherapists'));
    });

    test('unknown, switched-off code or paused agency is refused', () {
      expect(AgencyInviteService.inviteProblem(null, InviteRole.nurse),
          contains('not found'));
      expect(
          AgencyInviteService.inviteProblem(
              {...nursing, 'inviteActive': false}, InviteRole.nurse),
          contains('switched off'));
      expect(
          AgencyInviteService.inviteProblem(
              {...nursing, 'active': false}, InviteRole.nurse),
          contains('switched off'));
    });
  });

  test('roles by their sign-up key', () {
    expect(AgencyInviteService.roleFromKey('nurse'), InviteRole.nurse);
    expect(AgencyInviteService.roleFromKey('care_physician'),
        InviteRole.carePhysician);
    expect(AgencyInviteService.roleFromKey('therapist'), InviteRole.therapist);
    expect(AgencyInviteService.roleFromKey('technician'), InviteRole.technician);
    // only staff who work with agencies have invite links
    expect(AgencyInviteService.roleFromKey('doctor'), isNull);
    expect(AgencyInviteService.roleFromKey('patient'), isNull);
    expect(AgencyInviteService.collectionOf(InviteRole.therapist), 'therapists');
  });

  test('a waiting request is read from the profile', () {
    expect(AgencyInviteService.requestOf(null), isNull);
    expect(AgencyInviteService.requestOf({'agencyRequest': 'x'}), isNull);
    expect(AgencyInviteService.requestOf({'agencyRequest': {'agencyId': ''}}),
        isNull);
    expect(
        AgencyInviteService.requestOf({
          'agencyRequest': {'agencyId': 'a1', 'agencyName': 'Sai'}
        })?['agencyName'],
        'Sai');
  });
}
