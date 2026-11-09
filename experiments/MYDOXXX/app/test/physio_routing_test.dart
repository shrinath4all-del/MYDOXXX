import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter_test/flutter_test.dart';
import 'package:mydox/services/physio_agency_service.dart';

void main() {
  final now = DateTime(2026, 10, 3, 10, 0);

  Map<String, dynamic> agency(String id, List<String> areas,
          {bool active = true,
          int window = 15,
          Object? createdAt,
          num? priority}) =>
      {
        'id': id,
        'name': 'Agency $id',
        'areas': areas,
        'active': active,
        'acceptWindowMin': window,
        if (createdAt != null) 'createdAt': createdAt,
        if (priority != null) 'priority': priority,
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

    group('Agency 1 comes first', () {
      const area = ['Baner'];
      Map<String, dynamic> route(List<Map<String, dynamic>> agencies,
              List<Map<String, dynamic>> physios,
              {Set<String>? available}) =>
          PhysioAgencyService.routeFor(
              location: 'Baner, Pune',
              agencies: agencies,
              physios: physios,
              available: available,
              now: now);

      test('the oldest agency is offered first even if another has more free', () {
        final r = route([
          agency('a2', area, createdAt: '2026-03-01T10:00:00'),
          agency('a1', area, createdAt: '2026-01-01T10:00:00'),
        ], [
          physio('p1', agencyId: 'a1'),
          physio('p2', agencyId: 'a2'),
          physio('p3', agencyId: 'a2'),
        ]);
        expect(r['routingStage'], 'team');
        expect(r['agencyId'], 'a1');
        expect(r['agencyOfferedTo'], ['p1']);
      });

      test('a priority number decides before age (lower first)', () {
        final r = route([
          agency('a1', area, createdAt: '2026-01-01T10:00:00', priority: 2),
          agency('a2', area, createdAt: '2026-03-01T10:00:00', priority: 1),
        ], [
          physio('p1', agencyId: 'a1'),
          physio('p2', agencyId: 'a2'),
        ]);
        expect(r['agencyId'], 'a2');
      });

      test('an agency with a priority comes before one without', () {
        final r = route([
          agency('a1', area, createdAt: '2026-01-01T10:00:00'),
          agency('a2', area, createdAt: '2026-03-01T10:00:00', priority: 5),
        ], [
          physio('p1', agencyId: 'a1'),
          physio('p2', agencyId: 'a2'),
        ]);
        expect(r['agencyId'], 'a2');
      });

      test('the answer does not depend on the order the list was read in', () {
        final a1 = agency('a1', area, createdAt: '2026-01-01T10:00:00');
        final a2 = agency('a2', area, createdAt: '2026-02-01T10:00:00');
        final team = [physio('p1', agencyId: 'a1'), physio('p2', agencyId: 'a2')];
        expect(route([a1, a2], team)['agencyId'], 'a1');
        expect(route([a2, a1], team)['agencyId'], 'a1');
      });

      test('with no dates or priorities the name decides', () {
        final team = [physio('p1', agencyId: 'a1'), physio('p2', agencyId: 'a2')];
        expect(route([agency('a2', area), agency('a1', area)], team)['agencyId'],
            'a1');
      });

      test('createdAt may be a Firestore Timestamp or text', () {
        final r = route([
          agency('a2', area, createdAt: '2026-02-01T10:00:00'),
          agency('a1', area,
              createdAt: Timestamp.fromDate(DateTime.utc(2026, 1, 1, 4, 30))),
        ], [
          physio('p1', agencyId: 'a1'),
          physio('p2', agencyId: 'a2'),
        ]);
        expect(r['agencyId'], 'a1');
      });

      test('if Agency 1 has nobody on duty the next agency is offered it', () {
        final r = route([
          agency('a1', area, createdAt: '2026-01-01T10:00:00'),
          agency('a2', area, createdAt: '2026-02-01T10:00:00'),
        ], [
          physio('p1', agencyId: 'a1', online: false),
          physio('p2', agencyId: 'a2'),
        ]);
        expect(r['agencyId'], 'a2');
      });

      test('if Agency 1 has nobody free in that slot the next agency is offered it', () {
        final r = route([
          agency('a1', area, createdAt: '2026-01-01T10:00:00'),
          agency('a2', area, createdAt: '2026-02-01T10:00:00'),
        ], [
          physio('p1', agencyId: 'a1'),
          physio('p2', agencyId: 'a2'),
        ], available: {'p2'});
        expect(r['agencyId'], 'a2');
        expect(r['agencyOfferedTo'], ['p2']);
      });

      test('if Agency 1 does not serve the area the next one that does is offered it', () {
        final r = route([
          agency('a1', ['Katraj'], createdAt: '2026-01-01T10:00:00'),
          agency('a2', area, createdAt: '2026-02-01T10:00:00'),
        ], [
          physio('p1', agencyId: 'a1'),
          physio('p2', agencyId: 'a2'),
        ]);
        expect(r['agencyId'], 'a2');
      });

      test('a paused Agency 1 is skipped', () {
        final r = route([
          agency('a1', area, active: false, createdAt: '2026-01-01T10:00:00'),
          agency('a2', area, createdAt: '2026-02-01T10:00:00'),
        ], [
          physio('p1', agencyId: 'a1'),
          physio('p2', agencyId: 'a2'),
        ]);
        expect(r['agencyId'], 'a2');
      });

      test('nobody free at any agency goes to freelancers', () {
        final r = route([
          agency('a1', area, createdAt: '2026-01-01T10:00:00'),
          agency('a2', area, createdAt: '2026-02-01T10:00:00'),
        ], [
          physio('p1', agencyId: 'a1', online: false),
          physio('p2', agencyId: 'a2', workMode: 'freelance'),
        ]);
        expect(r['routingStage'], 'freelance');
        expect(r['agencyId'], isNull);
      });

      test('Agency 1 holds the request for its own accept time', () {
        final r = route([
          agency('a1', area, window: 5, createdAt: '2026-01-01T10:00:00'),
          agency('a2', area, window: 30, createdAt: '2026-02-01T10:00:00'),
        ], [
          physio('p1', agencyId: 'a1'),
          physio('p2', agencyId: 'a2'),
        ]);
        expect(r['agencyOfferExpiresAt'],
            now.add(const Duration(minutes: 5)).toIso8601String());
      });

      test('a physio with no agency is a freelancer, never offered the team stage', () {
        final r = route([
          agency('a1', area, createdAt: '2026-01-01T10:00:00'),
        ], [
          physio('p9'), // chose no agency
        ]);
        expect(r['routingStage'], 'freelance');
      });
    });

    test('compareAgencyOrder sorts priority, then oldest, then name, then id', () {
      final list = [
        agency('d', const [], createdAt: '2026-05-01T10:00:00'),
        agency('c', const [], priority: 2),
        agency('b', const [], createdAt: '2026-01-01T10:00:00'),
        agency('a', const [], priority: 1),
        agency('e', const []),
      ]..sort(PhysioAgencyService.compareAgencyOrder);
      expect([for (final a in list) a['id']], ['a', 'c', 'b', 'd', 'e']);
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
