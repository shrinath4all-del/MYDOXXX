import 'package:flutter_test/flutter_test.dart';
import 'package:mydox/services/physio_agency_service.dart';

void main() {
  final now = DateTime(2026, 10, 3, 10, 0);

  Map<String, dynamic> agency(String id, List<String> areas,
          {bool active = true, int window = 15}) =>
      {
        'id': id,
        'name': 'Agency $id',
        'areas': areas,
        'active': active,
        'acceptWindowMin': window,
      };

  Map<String, dynamic> physio(String uid,
          {String? agencyId,
          String workMode = 'agency',
          bool verified = true,
          bool online = true}) =>
      {
        'uid': uid,
        if (agencyId != null) 'agencyId': agencyId,
        'workMode': workMode,
        'isVerified': verified,
        'isOnline': online,
      };

  group('routeFor', () {
    test('agency serving the area with an on-duty physio gets it first', () {
      final r = PhysioAgencyService.routeFor(
        location: 'Baner, Pune',
        agencies: [agency('a1', ['Baner', 'Balewadi'])],
        physios: [physio('p1', agencyId: 'a1')],
        now: now,
      );
      expect(r['routingStage'], 'team');
      expect(r['agencyId'], 'a1');
      expect(r['agencyOfferExpiresAt'],
          now.add(const Duration(minutes: 15)).toIso8601String());
    });

    test('no agency in the area goes straight to freelancers', () {
      final r = PhysioAgencyService.routeFor(
        location: 'Katraj, Pune',
        agencies: [agency('a1', ['Baner', 'Balewadi'])],
        physios: [physio('p1', agencyId: 'a1')],
        now: now,
      );
      expect(r['routingStage'], 'freelance');
      expect(r['agencyId'], isNull);
    });

    test('agency with nobody on duty does not hold the request', () {
      final r = PhysioAgencyService.routeFor(
        location: 'Baner, Pune',
        agencies: [agency('a1', ['Baner'])],
        physios: [
          physio('p1', agencyId: 'a1', workMode: 'freelance'),
          physio('p2', agencyId: 'a1', online: false),
          physio('p3', agencyId: 'a1', verified: false),
        ],
        now: now,
      );
      expect(r['routingStage'], 'freelance');
    });

    test('paused agency is skipped', () {
      final r = PhysioAgencyService.routeFor(
        location: 'Baner, Pune',
        agencies: [agency('a1', ['Baner'], active: false)],
        physios: [physio('p1', agencyId: 'a1')],
        now: now,
      );
      expect(r['routingStage'], 'freelance');
    });

    test('picks the agency with the most on-duty physios', () {
      final r = PhysioAgencyService.routeFor(
        location: 'Baner, Pune',
        agencies: [agency('a1', ['Baner']), agency('a2', ['Baner'])],
        physios: [
          physio('p1', agencyId: 'a1'),
          physio('p2', agencyId: 'a2'),
          physio('p3', agencyId: 'a2'),
        ],
        now: now,
      );
      expect(r['agencyId'], 'a2');
    });

    test('uses the agency accept time', () {
      final r = PhysioAgencyService.routeFor(
        location: 'Baner, Pune',
        agencies: [agency('a1', ['Baner'], window: 5)],
        physios: [physio('p1', agencyId: 'a1')],
        now: now,
      );
      expect(r['agencyOfferExpiresAt'],
          now.add(const Duration(minutes: 5)).toIso8601String());
    });
  });

  group('time slot availability', () {
    test('free when nothing is booked and no schedule is set', () {
      expect(PhysioAgencyService.isSlotFree(time: '10:00 AM'), isTrue);
    });

    test('busy when another visit is booked at that time', () {
      expect(
          PhysioAgencyService.isSlotFree(
              time: '10:00 AM', bookedSlots: ['10:00 AM']),
          isFalse);
      expect(
          PhysioAgencyService.isSlotFree(
              time: '10:00 am', bookedSlots: ['02:00 PM']),
          isTrue);
    });

    test('schedule: day off or slot not offered means not available', () {
      expect(
          PhysioAgencyService.isSlotFree(
              time: '10:00 AM', schedule: {'isAvailable': false}),
          isFalse);
      expect(
          PhysioAgencyService.isSlotFree(time: '10:00 AM', schedule: {
            'isAvailable': true,
            'timeSlots': ['02:00 PM', '04:00 PM'],
          }),
          isFalse);
      expect(
          PhysioAgencyService.isSlotFree(time: '04:00 PM', schedule: {
            'isAvailable': true,
            'timeSlots': ['02:00 PM', '04:00 PM'],
          }),
          isTrue);
    });

    test('only agency physios free in the slot get Accept / Decline', () {
      final r = PhysioAgencyService.routeFor(
        location: 'Shivajinagar, Pune',
        agencies: [agency('a1', ['Shivajinagar', 'Deccan'])],
        physios: [
          physio('p1', agencyId: 'a1'),
          physio('p2', agencyId: 'a1'), // busy at that time
          physio('p3', agencyId: 'a1'),
        ],
        available: {'p1', 'p3'},
        now: now,
      );
      expect(r['routingStage'], 'team');
      expect(r['agencyOfferedTo'], ['p1', 'p3']);

      final during = now.add(const Duration(minutes: 5));
      expect(
          PhysioAgencyService.isOfferedTo(r, physio('p1', agencyId: 'a1'),
              uid: 'p1', now: during),
          isTrue);
      expect(
          PhysioAgencyService.isOfferedTo(r, physio('p2', agencyId: 'a1'),
              uid: 'p2', now: during),
          isFalse);
    });

    test('agency with nobody free in the slot goes to freelancers', () {
      final r = PhysioAgencyService.routeFor(
        location: 'Shivajinagar, Pune',
        agencies: [agency('a1', ['Shivajinagar'])],
        physios: [physio('p1', agencyId: 'a1')],
        available: const {},
        now: now,
      );
      expect(r['routingStage'], 'freelance');
    });
  });

  group('who is offered the request', () {
    final request = {
      'status': 'Broadcasted',
      'routingStage': 'team',
      'agencyId': 'a1',
      'agencyOfferExpiresAt':
          now.add(const Duration(minutes: 15)).toIso8601String(),
    };

    test('during the window only the agency on-duty team', () {
      final at = now.add(const Duration(minutes: 5));
      expect(
          PhysioAgencyService.isOfferedTo(
              request, physio('p1', agencyId: 'a1'),
              now: at),
          isTrue);
      expect(
          PhysioAgencyService.isOfferedTo(
              request, physio('p2', workMode: 'freelance'),
              now: at),
          isFalse);
      expect(
          PhysioAgencyService.isOfferedTo(
              request, physio('p3', agencyId: 'a2'),
              now: at),
          isFalse);
      // in the agency but off duty (freelancing)
      expect(
          PhysioAgencyService.isOfferedTo(
              request, physio('p4', agencyId: 'a1', workMode: 'freelance'),
              now: at),
          isFalse);
    });

    test('after 15 minutes it opens to every physio', () {
      final at = now.add(const Duration(minutes: 16));
      expect(PhysioAgencyService.isAgencyWindowOpen(request, now: at), isFalse);
      expect(
          PhysioAgencyService.isOfferedTo(
              request, physio('p2', workMode: 'freelance'),
              now: at),
          isTrue);
    });

    test('a physio who left the agency works as a freelancer', () {
      // after leaveAgency: no agencyId, work mode freelance
      final left = physio('p1', workMode: 'freelance');
      final during = now.add(const Duration(minutes: 5));
      expect(PhysioAgencyService.isOfferedTo(request, left, now: during),
          isFalse);
      expect(
          PhysioAgencyService.isOfferedTo(
              {...request, 'routingStage': 'freelance'}, left,
              now: during),
          isTrue);
    });

    test('a physio who joins a new agency gets that agency\'s calls', () {
      final joined = physio('p1', agencyId: 'a2');
      final during = now.add(const Duration(minutes: 5));
      final newAgencyRequest = {...request, 'agencyId': 'a2'};
      expect(
          PhysioAgencyService.isOfferedTo(newAgencyRequest, joined,
              now: during),
          isTrue);
      // no longer gets the old agency's calls
      expect(PhysioAgencyService.isOfferedTo(request, joined, now: during),
          isFalse);
    });

    test('freelance stage is open to everyone', () {
      final freelance = {...request, 'routingStage': 'freelance'};
      expect(
          PhysioAgencyService.isOfferedTo(
              freelance, physio('p2', workMode: 'freelance'),
              now: now),
          isTrue);
    });
  });
}
