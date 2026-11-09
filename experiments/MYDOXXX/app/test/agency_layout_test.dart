// Renders the agency screens with sample data at phone, tablet and desktop
// sizes. Any layout overflow ("RenderFlex overflowed") fails the test.
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mydox/screens/agency/care/care_forms.dart';
import 'package:mydox/screens/agency/care/control_room_screen.dart';
import 'package:mydox/screens/agency/physio/physio_control_room_screen.dart';
import 'package:mydox/screens/payouts/payout_setup_screen.dart';
import 'package:mydox/widgets/agency_duties_card.dart';
import 'package:mydox/widgets/agency_type_picker.dart';
import 'package:mydox/theme/app_theme.dart';
import 'package:mydox/utils/ist_clock.dart';
import 'package:mydox/utils/ist_timestamp.dart';

const sizes = <Size>[
  Size(320, 640), // small phone
  Size(360, 780),
  Size(412, 915),
  Size(768, 1024), // tablet
  Size(1280, 800), // laptop
  Size(1920, 1080), // desktop
];

final now = IstClock.now();
Timestamp at(int h, int m) =>
    timestampOf(DateTime(now.year, now.month, now.day, h, m));
String key(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
final today = key(now);

final agency = <String, dynamic>{
  'id': 'ag1',
  'name': 'Pune Care Physicians and Emergency Locum Services Private Limited',
  'splitDoctorPct': 80,
  'splitAgencyPct': 15,
  'splitAppPct': 5,
  'commissionPct': 20,
  'active': true,
  'areas': ['Shivajinagar', 'Deccan Gymkhana', 'Model Colony', 'Kothrud'],
};

final doctors = [
  for (var i = 0; i < 8; i++)
    {
      'id': 'd$i',
      'name': 'Dr. Venkatanarasimharajuvaripeta Subramanian $i',
      'phone': '98765432$i$i',
      'qualification': 'MBBS',
      'placementType': i == 0 ? 'permanent' : 'pool',
      'permanentHospitalName': 'Deenanath Mangeshkar Hospital and Research Centre',
      'active': true,
      if (i == 7) 'leaveFrom': today,
      if (i == 7) 'leaveTo': today,
      if (i.isEven) 'userUid': 'u$i',
    }
];

Map<String, dynamic> duty(String id, String doctor, String type,
        {String status = 'scheduled',
        int h = 8,
        Timestamp? checkIn,
        Timestamp? checkOut,
        String payout = 'due'}) =>
    {
      'id': id,
      'doctorId': doctor,
      'doctorName': 'Dr. Venkatanarasimharajuvaripeta Subramanian',
      'hospitalId': 'h1',
      'hospitalName': 'Sahyadri Super Speciality Hospital, Kothrud',
      'type': type,
      'unit': 'icu',
      'date': today,
      'shiftStart': at(h, 0),
      'shiftEnd': at((h + 12) % 24, 0),
      'status': status,
      if (checkIn != null) 'checkInAt': checkIn,
      if (checkOut != null) 'checkOutAt': checkOut,
      'hospitalRate': 128000,
      'doctorPay': 102400,
      'agencyShare': 19200,
      'appShare': 6400,
      'payoutStatus': payout,
    };

final duties = [
  duty('a', 'd0', 'permanent', checkIn: at(0, 5)),
  duty('b', 'd1', 'locum', status: 'absent'),
  duty('c', 'd2', 'locum', h: 0), // late
  duty('e', 'd3', 'emergency', h: 0, checkIn: at(0, 40)),
  duty('f', 'd4', 'locum', h: 0, checkIn: at(0, 1), checkOut: at(0, 2), payout: 'paid'),
  duty('g', 'd5', 'locum', status: 'cancelled'),
];

final hospitals = [
  {
    'id': 'h1',
    'name': 'Sahyadri Super Speciality Hospital',
    'area': 'Kothrud, Pune',
    'contactName': 'Dr. Meenakshi Raghunathan',
    'contactPhone': '+91 20 2616 3391',
  }
];

final team = [
  for (var i = 0; i < 4; i++)
    {
      'uid': 'p$i',
      'name': 'Kavita Deshmukh-Kulkarni Physiotherapist $i',
      'qualification': 'MPT (Musculoskeletal and Sports Physiotherapy)',
      'phone': '+91 98765 4321$i',
      'agencyId': 'ag1',
      'workMode': ['agency', 'freelance', 'offline', 'agency'][i],
      'isOnline': i != 2,
      'isVerified': i != 3,
      'rating': 4.5,
      'totalRatings': 12,
    }
];

final visits = [
  {
    'id': 'v1',
    'status': 'Broadcasted',
    'routingStage': 'team',
    'agencyId': 'ag1',
    'agencyOfferExpiresAt':
        now.add(const Duration(minutes: 10)).toIso8601String(),
    'therapyName': 'Post-surgery knee and hip replacement rehabilitation',
    'locationName': 'Shivajinagar, Pune, Maharashtra 411005',
    'date': '${now.day}/${now.month}/${now.year}',
    'time': '06:00 PM',
    'price': 1200,
  },
  for (final status in ['Confirmed', 'In Progress', 'Completed', 'Provider Absent'])
    {
      'id': 'v$status',
      'status': status,
      'agencyId': 'ag1',
      'patientName': 'Ravindranath Venkataraman Iyer',
      'doctorName': 'Kavita Deshmukh-Kulkarni',
      'therapyName': 'Neuro rehabilitation',
      'locationName': 'Deccan Gymkhana, Pune',
      'date': '${now.day}/${now.month}/${now.year}',
      'time': '07:00 AM',
      'price': 1500,
      'lateArrival': status == 'In Progress',
      'lateByMinutes': 35,
    },
];

Future<void> pumpAt(WidgetTester tester, Size size, Widget child) async {
  // Tall surface so every row of the lists is laid out
  tester.view.physicalSize = Size(size.width, size.height * 4);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(key: UniqueKey(), theme: AppTheme.lightTheme, home: child));
  await tester.pump(const Duration(milliseconds: 50));
}

void expectNoOverflow(WidgetTester tester, String what, Size size) {
  final e = tester.takeException();
  expect(e, isNull, reason: '$what at ${size.width.toInt()}×${size.height.toInt()}: $e');
}

void main() {
  for (final size in sizes) {
    final label = '${size.width.toInt()}×${size.height.toInt()}';

    testWidgets('care Control Room fits at $label', (tester) async {
      for (final period in ['today', 'week', 'month']) {
        for (final filter in ['all', 'on_duty', 'late', 'absent', 'no_job', 'emergency']) {
          await pumpAt(
            tester,
            size,
            Scaffold(
              body: CareControlRoomView(
                agency: agency,
                doctors: doctors,
                duties: duties,
                now: now,
                period: period,
                filter: filter,
                onPeriod: (_) {},
                onFilter: (_) {},
                onDoctors: () {},
                onHospitals: () {},
                onPayouts: () {},
                onDuty: (_, __) {},
              ),
            ),
          );
          expectNoOverflow(tester, 'care $period/$filter', size);
        }
      }
    });

    testWidgets('physio Control Room fits at $label', (tester) async {
      for (final filter in ['all', 'offered', 'accepted', 'in_progress', 'late', 'absent']) {
        await pumpAt(
          tester,
          size,
          Scaffold(
            body: PhysioControlRoomView(
              agencyId: 'ag1',
              agency: agency,
              team: team,
              visits: visits,
              now: now,
              period: 'month',
              filter: filter,
              teamFilter: 'all',
              onPeriod: (_) {},
              onFilter: (_) {},
              onTeamFilter: (_) {},
              onEditProfile: () {},
            ),
          ),
        );
        expectNoOverflow(tester, 'physio $filter', size);
      }
      // empty agency: no areas, no team, no visits
      await pumpAt(
        tester,
        size,
        Scaffold(
          body: PhysioControlRoomView(
            agencyId: 'ag2',
            agency: const {'id': 'ag2', 'name': 'New Physio Agency'},
            team: const [],
            visits: const [],
            now: now,
            period: 'today',
            filter: 'all',
            teamFilter: 'all',
            onPeriod: (_) {},
            onFilter: (_) {},
            onTeamFilter: (_) {},
            onEditProfile: () {},
          ),
        ),
      );
      expectNoOverflow(tester, 'physio empty', size);
    });

    testWidgets('agency forms and lists fit at $label', (tester) async {
      await pumpAt(
          tester,
          size,
          DutyFormScreen(
            agency: agency,
            copyFrom: duties[1],
            doctorId: 'd2',
            testDoctors: Stream.value(doctors),
            testHospitals: Stream.value(hospitals),
          ));
      await tester.pump();
      expectNoOverflow(tester, 'duty form', size);

      await pumpAt(
          tester,
          size,
          AgencyDoctorsScreen(
            agency: agency,
            testDoctors: Stream.value(doctors),
            testHospitals: Stream.value(hospitals),
          ));
      await tester.pump();
      expectNoOverflow(tester, 'doctor list', size);
      // edit doctor form (partners no longer add doctors)
      await tester.tap(find.text('Dr. Venkatanarasimharajuvaripeta Subramanian 1'));
      await tester.pumpAndSettle();
      expectNoOverflow(tester, 'doctor form', size);
      await tester.tap(find.text('Permanent'));
      await tester.pumpAndSettle();
      expectNoOverflow(tester, 'doctor form (permanent)', size);

      await pumpAt(
          tester,
          size,
          AgencyHospitalsScreen(
              agency: agency, testHospitals: Stream.value(hospitals)));
      await tester.pump();
      expectNoOverflow(tester, 'hospital list', size);
      await tester.tap(find.text('Sahyadri Super Speciality Hospital'));
      await tester.pumpAndSettle();
      expectNoOverflow(tester, 'hospital dialog', size);

      final paidDuties = [
        for (final d in duties)
          {...d, 'date': today}
      ];
      await pumpAt(
          tester,
          size,
          AgencyPayoutsScreen(
              agency: agency, testDuties: Stream.value(paidDuties)));
      await tester.pump();
      expectNoOverflow(tester, 'payouts', size);

      await pumpAt(
          tester,
          size,
          Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showAgencySettingsDialog(context, agency),
                  child: const Text('settings'),
                ),
              ),
            ),
          ));
      await tester.tap(find.text('settings'));
      await tester.pumpAndSettle();
      expectNoOverflow(tester, 'agency settings dialog', size);

      await pumpAt(
          tester,
          size,
          const PayoutSetupScreen(
            provider: {
              'payoutStatus': 'needs_clarification',
              'payoutBankLast4': '9012',
              'payoutIfsc': 'HDFC0001234',
              'city': 'Pune',
            },
            defaultName: 'Kavita Deshmukh-Kulkarni',
          ));
      expectNoOverflow(tester, 'payout setup', size);

      for (final type in ['care_physician', 'physio']) {
        await pumpAt(
            tester,
            size,
            Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: AgencyTypePicker(value: type, onChanged: (_) {}),
              ),
            ));
        expectNoOverflow(tester, 'agency type picker', size);
      }

      // doctor app: today's agency duties with Check in / Check out
      final soon = IstClock.now().add(const Duration(minutes: 30));
      await pumpAt(
          tester,
          size,
          Scaffold(
            body: ListView(padding: const EdgeInsets.all(16), children: [
              AgencyDutiesCard(
                uid: 'u1',
                phone: '9876543210',
                testDuties: Stream.value([
                  {...duties[0], 'shiftStart': timestampOf(soon),
                   'shiftEnd': timestampOf(soon.add(const Duration(hours: 8)))},
                  {...duties[2], 'checkInAt': null},
                  duties[4],
                  {...duties[3], 'lateMinutes': 40},
                ]),
              ),
            ]),
          ));
      await tester.pump();
      expectNoOverflow(tester, 'doctor duties card', size);
    });
  }
}
