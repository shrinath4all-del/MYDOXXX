import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mydox/screens/care_physician/care_physician_home_screen.dart';
import 'package:mydox/screens/patient/book_care_physician_screen.dart';
import 'package:mydox/services/care_physician_service.dart';
import 'package:mydox/services/location_service.dart';
import 'package:mydox/theme/app_theme.dart';
import 'package:mydox/utils/responsive.dart';

typedef Cp = CarePhysicianService;

final now = DateTime(2026, 10, 8, 10);

Map<String, dynamic> visit(String status, {String? doctor}) => {
      'id': 'v-$status',
      'postedBy': 'patient',
      'posterId': 'p1',
      'posterName': 'Ravindranath Venkataraman Iyer',
      'patientPhone': '9876543210',
      'serviceName': 'IV Line Insertion',
      'hospitalName': 'IV Line Insertion',
      'area': 'Wakad',
      'address': 'Flat 1204, Rohan Leher Phase 2, Near Shivar Chowk, Pimple Saudagar',
      'notes': 'Patient is diabetic; please bring a 22G cannula.',
      'dutyType': 'home',
      'procedures': ['iv_cannulation'],
      'date': '2026-10-08',
      'slot': 'visit',
      'start': '18:00',
      'end': '19:00',
      'pay': 850,
      'status': status,
      if (doctor != null) 'claimedByName': doctor,
      if (doctor != null) 'claimedByPhone': '9123456780',
    };

const services = [
  {'id': 'a', 'name': 'Catheter Change', 'price': 900, 'icon': 'add'},
  {'id': 'b', 'name': 'Wound Dressing', 'price': 800, 'icon': 'shield'},
  {'id': 'c', 'name': 'Stitch Removal', 'price': 700, 'icon': 'check'},
  {'id': 'd', 'name': 'IV Line Insertion', 'price': 850, 'icon': 'drop'},
  {'id': 'e', 'name': 'Suctioning', 'price': 900, 'icon': 'air'},
  {
    'id': 'f',
    'name': 'Bed-sore Care and Pressure Ulcer Management',
    'price': 1000,
    'icon': 'heart',
    'description': 'Cleaning, dressing and repositioning advice for bed-bound patients.'
  },
];

void main() {
  test('no Dubai: location messages are not areas, the map falls back to Pune', () {
    expect(LocationService.isError(LocationService.notFound), isTrue);
    expect(LocationService.isError('Location Permission Denied'), isTrue);
    expect(LocationService.isError('Location Disabled in Settings'), isTrue);
    expect(LocationService.isError('Baner, Pune'), isFalse);
    expect(LocationService.defaultLat, closeTo(18.52, 0.01));
    expect(LocationService.defaultLng, closeTo(73.86, 0.01));
  });

  test('home visits reach care physicians who do home visits in the area', () {
    final me = {
      'dutyTypes': ['home'],
      'areas': ['Wakad'],
    };
    expect(Cp.shiftFits(visit('open'), me, now), isTrue);
    expect(Cp.shiftFits(visit('open'), {...me, 'dutyTypes': ['icu']}, now),
        isFalse);
    expect(Cp.shiftFits(visit('open'), {...me, 'areas': ['Aundh']}, now),
        isFalse);
    expect(Cp.slotLabel(visit('open')), 'Home visit');
    expect(Cp.timeRange(visit('open')), '6 PM – 7 PM');
    expect(Cp.isHomeVisit(visit('open')), isTrue);
  });

  test('visit slots are two hours and cover the whole day', () {
    expect(Cp.visitTimes().first, '00:00');
    expect(Cp.visitTimes().last, '22:00');
    expect(Cp.visitTimes().length, 12);
    expect(Cp.slotLabel2h('08:00'), '8 AM – 10 AM');
    expect(Cp.slotLabel2h('22:00'), '10 PM – 12 AM');
  });

  test('service icons from the database key', () {
    expect(serviceIcon('drop'), Icons.water_drop_outlined);
    expect(serviceIcon('unknown'), Icons.medical_services_outlined);
  });

  const sizes = [
    Size(320, 640),
    Size(360, 780),
    Size(412, 915),
    Size(768, 1024),
    Size(1280, 800),
  ];

  Future<void> pumpAt(WidgetTester tester, Size size, Widget child) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      key: UniqueKey(),
      theme: AppTheme.lightTheme,
      home: ResponsiveCenter(child: Scaffold(body: child)),
    ));
  }

  for (final size in sizes) {
    final label = '${size.width.toInt()}×${size.height.toInt()}';
    testWidgets('services, visits and home-visit duty fit at $label',
        (tester) async {
      await pumpAt(
        tester,
        size,
        ListView(padding: const EdgeInsets.all(16), children: [
          Builder(
            builder: (context) => GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: services.length,
              gridDelegate: Responsive.grid(context,
                  minTileWidth: 150, tileHeight: 246),
              itemBuilder: (_, i) =>
                  ServiceGridTile(service: services[i], onTap: () {}),
            ),
          ),
          for (final v in [
            visit('open'),
            visit('claimed', doctor: 'Dr. Nikhil Bhosale'),
            visit('on_duty', doctor: 'Dr. Nikhil Bhosale'),
            visit('completed', doctor: 'Dr. Nikhil Bhosale'),
            visit('absent', doctor: 'Dr. Nikhil Bhosale'),
            visit('cancelled'),
          ])
            VisitCard(visit: v, now: now, onCancel: () {}, onCall: (_) {}),
          DutyCard(
            shift: visit('claimed', doctor: 'Dr. Nikhil Bhosale'),
            now: DateTime(2026, 10, 8, 17, 30),
            onCheckIn: () {},
            onCheckOut: () {},
          ),
          ShiftCard(shift: visit('open'), now: now, onClaim: () {}),
        ]),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('services show as grid tiles with live prices', (tester) async {
    var tapped = '';
    await pumpAt(
      tester,
      const Size(412, 1200),
      Builder(
        builder: (context) => GridView.builder(
          itemCount: services.length,
          gridDelegate:
              Responsive.grid(context, minTileWidth: 150, tileHeight: 246),
          itemBuilder: (_, i) => ServiceGridTile(
              service: services[i],
              onTap: () => tapped = services[i]['name'] as String),
        ),
      ),
    );
    expect(find.text('₹850 onwards'), findsOneWidget);
    expect(find.text('IV Line Insertion'), findsOneWidget);
    await tester.tap(find.text('Wound Dressing'));
    expect(tapped, 'Wound Dressing');
  });

  testWidgets('the claimed doctor sees patient, address and a call button',
      (tester) async {
    await pumpAt(
      tester,
      const Size(412, 900),
      DutyCard(
        shift: visit('claimed', doctor: 'Dr. Nikhil Bhosale'),
        now: DateTime(2026, 10, 8, 17, 30),
        onCheckIn: () {},
        onCheckOut: () {},
      ),
    );
    expect(find.textContaining('Ravindranath'), findsOneWidget);
    expect(find.textContaining('Rohan Leher'), findsOneWidget);
    expect(find.text('Call 9876543210'), findsOneWidget);
    expect(find.text('Check in'), findsOneWidget);
  });

  test("a declined visit leaves only that doctor's list", () {
    final me = {
      'uid': 'd1',
      'dutyTypes': ['home'],
      'areas': ['Wakad'],
    };
    final declined = {
      ...visit('open'),
      'declinedBy': ['d1'],
    };
    expect(Cp.shiftFits(declined, me, now), isFalse);
    expect(Cp.shiftFits(declined, {...me, 'uid': 'd2'}, now), isTrue);
  });

  for (final size in sizes) {
    testWidgets('visit card Accept / Decline fit at ${size.width.toInt()}',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var accepted = false, declined = false;
      await tester.pumpWidget(MaterialApp(
        key: UniqueKey(),
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(children: [
              ShiftCard(
                shift: visit('open'),
                now: now,
                onClaim: () => accepted = true,
                onDecline: () => declined = true,
              ),
              ShiftCard(shift: visit('open'), now: now, onClaim: () {}),
            ]),
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
      expect(find.text('Accept'), findsNWidgets(2));
      expect(find.text('Decline'), findsOneWidget);
      expect(find.text('per visit'), findsNWidgets(2));
      await tester.tap(find.text('Decline'));
      await tester.tap(find.text('Accept').first);
      expect(declined, isTrue);
      expect(accepted, isTrue);
    });
  }

  group('agency first, live area, travel buffer', () {
    test("my area covers the patient's live location", () {
      expect(Cp.inMyAreas(['Wakad'], 'Wakad, Pimpri-Chinchwad, Pune'), isTrue);
      expect(Cp.inMyAreas(['Aundh'], 'Wakad, Pune'), isFalse);
      expect(Cp.inMyAreas([], 'Wakad, Pune'), isTrue);
    });

    test("an agency's doctors see the visit first for 15 min", () {
      final v = {
        ...visit('open'),
        'offerAgencyIds': ['ag1'],
        'agencyOfferUntil':
            now.add(const Duration(minutes: 15)).toIso8601String(),
      };
      final freelancer = {
        'dutyTypes': ['home'],
        'areas': ['Wakad']
      };
      final agencyDoc = {...freelancer, 'agencyId': 'ag1'};
      final otherAgency = {...freelancer, 'agencyId': 'ag2'};
      expect(Cp.shiftFits(v, agencyDoc, now), isTrue);
      expect(Cp.shiftFits(v, freelancer, now), isFalse);
      expect(Cp.shiftFits(v, otherAgency, now), isFalse);
      final later = now.add(const Duration(minutes: 16));
      expect(Cp.shiftFits(v, freelancer, later), isTrue,
          reason: 'after 15 min everyone in the area gets it');
      expect(
          Cp.shiftFits({...v, 'offerAgencyIds': []}, freelancer, now), isTrue,
          reason: 'no agency in the area: straight to everyone');
    });

    test('45 min to reach after the booked time', () {
      expect(Cp.reachBy(visit('claimed')), DateTime(2026, 10, 8, 18, 45));
      expect(Cp.clock(Cp.reachBy(visit('claimed'))), '6:45 PM');
      expect(Cp.lateAfterMinutes, 45);
    });
  });

  // The agency console no longer shows patients' home visits (the agency's
  // doctors still get them first: see 'agency first, live area, travel buffer').
}
