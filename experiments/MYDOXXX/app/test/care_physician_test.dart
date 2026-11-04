import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mydox/screens/care_physician/care_physician_home_screen.dart';
import 'package:mydox/screens/care_physician/care_physician_profile_wizard.dart';
import 'package:mydox/screens/shifts/shift_board_screen.dart';
import 'package:mydox/models/care_duty_roster.dart';
import 'package:mydox/services/care_physician_service.dart';
import 'package:mydox/theme/app_theme.dart';
import 'package:mydox/utils/responsive.dart';

typedef Cp = CarePhysicianService;

final now = DateTime(2026, 10, 8, 10, 0);
String key(DateTime d) => Cp.dateKey(d);
final today = key(now);
final tomorrow = key(now.add(const Duration(days: 1)));

Map<String, dynamic> shift(String id,
        {String date = '',
        String start = '20:00',
        String end = '08:00',
        String slot = 'night',
        String type = 'icu',
        String area = 'Wakad',
        String status = 'open',
        bool urgent = false,
        List<String> procedures = const [],
        String hospital = 'Kush Neuro Cardiac Hospital',
        int pay = 4500,
        String? claimedBy}) =>
    {
      'id': id,
      'hospitalName': hospital,
      'area': area,
      'dutyType': type,
      'specialty': 'cardiology',
      'procedures': procedures,
      'date': date.isEmpty ? today : date,
      'slot': slot,
      'start': start,
      'end': end,
      'pay': pay,
      'urgent': urgent,
      'status': status,
      if (claimedBy != null) 'claimedBy': claimedBy,
    };

final me = <String, dynamic>{
  'uid': 'u1',
  'name': 'Dr. Nikhil Bhosale',
  'qualification': 'MBBS',
  'experienceYears': 4,
  'regNo': 'MMC-2019-08421',
  'isVerified': true,
  'available': true,
  'procedures': ['intubation', 'ventilator', 'iv_cannulation'],
  'dutyTypes': ['icu', 'ward', 'specialty', 'casualty'],
  'ageGroups': ['adult'],
  'specialties': ['cardiology', 'general_med'],
  'areas': ['Wakad', 'Pimpri'],
  'preferredHospitals': ['Sahyadri Hospital, Wakad'],
  'noShows': 0,
};

void main() {
  group('shift times', () {
    test('a night shift ends the next morning', () {
      final s = shift('a');
      expect(Cp.shiftStart(s), DateTime(2026, 10, 8, 20));
      expect(Cp.shiftEnd(s), DateTime(2026, 10, 9, 8));
      expect(Cp.timeRange(s), '8 PM – 8 AM');
      expect(Cp.dayLabel(s, now), 'Tonight');
    });
    test('day labels', () {
      expect(
          Cp.dayLabel(shift('a', date: tomorrow, start: '08:00', end: '14:00'),
              now),
          'Tomorrow');
      expect(Cp.dayLabel(shift('a', date: '2026-10-11'), now), 'Sun, 11 Oct');
    });
  });

  group('hospital shifts: agency doctors first for 5 minutes', () {
    final hospitalShift = {
      ...shift('h1'),
      'agencyFirst': true,
      'agencyOfferUntil': now.add(const Duration(minutes: 3)).toIso8601String(),
    };
    test('freelancers wait, agency doctors see it at once', () {
      expect(Cp.shiftFits(hospitalShift, {...me, 'agencyId': 'ag1'}, now), isTrue);
      expect(Cp.shiftFits(hospitalShift, {...me, 'agencyId': ''}, now), isFalse);
    });
    test('after the window everyone it fits sees it', () {
      final later = now.add(const Duration(minutes: 6));
      expect(Cp.shiftFits(hospitalShift, {...me, 'agencyId': ''}, later), isTrue);
    });
  });

  group('home visit requests', () {
    final p = {
      'isVerified': true,
      'available': true,
      'areas': ['Wakad'],
      'procedures': ['svc1'],
    };

    test('a care physician is offered a visit for his area and service', () {
      expect(Cp.canOfferVisit(p, 'svc1', 'Wakad'), isTrue);
      expect(Cp.canOfferVisit(p, 'svc1', 'Wakad, Pune'), isTrue);
      expect(Cp.canOfferVisit(p, 'other', 'Wakad'), isFalse,
          reason: 'he does not do that service');
      expect(Cp.canOfferVisit(p, 'svc1', 'Baner'), isFalse,
          reason: 'not his area');
      expect(Cp.canOfferVisit({...p, 'isVerified': false}, 'svc1', 'Wakad'), isFalse);
      expect(Cp.canOfferVisit({...p, 'available': false}, 'svc1', 'Wakad'), isFalse);
      expect(Cp.canOfferVisit({...p, 'noShows': 3}, 'svc1', 'Wakad'), isFalse);
    });

    test('a duty at that time means no request: no overlap', () {
      final a = Cp.shiftStart({'date': '2099-01-05', 'start': '08:00'})!;
      final locum = [BusyInterval(a.toUtc(), a.add(const Duration(hours: 6)).toUtc())]; // 8 to 2
      final v10 = Cp.shiftStart({'date': '2099-01-05', 'start': '10:00'})!;
      final v14 = Cp.shiftStart({'date': '2099-01-05', 'start': '14:00'})!;
      expect(Cp.clashesWith(locum, v10, v10.add(const Duration(hours: 2))), isTrue);
      expect(Cp.clashesWith(locum, v14, v14.add(const Duration(hours: 2))), isFalse,
          reason: 'a visit that starts when the shift ends is fine');
    });

    test('he cannot accept a 10 to 12 visit over a morning locum', () {
      final visit = {
        ...shift('v', date: '2099-01-05', start: '10:00', end: '12:00', type: 'home'),
        'postedBy': 'patient',
      };
      final locum = shift('l', date: '2099-01-05', start: '08:00', end: '14:00', status: 'claimed');
      final reason = Cp.claimBlockReason(visit, me, [locum], now);
      expect(reason, contains('already have a shift'));
    });

    test('slots are two hours and the whole day', () {
      expect(Cp.homeHours.first, 0);
      expect(Cp.homeHours.last, 22);
      expect(Cp.slotLabel2h('10:00'), '10 AM – 12 PM');
    });
  });

  group('arrival OTP', () {
    final claimed = {...shift('o1', status: 'claimed'), 'postedBy': 'hospital'};
    test('only a hospital locum uses it', () {
      expect(Cp.usesArrivalOtp(claimed), isTrue);
      expect(Cp.usesArrivalOtp({...claimed, 'postedBy': 'agency'}), isFalse);
    });
    test('valid for 10 minutes only', () {
      final at = now.subtract(const Duration(minutes: 4)).toIso8601String();
      final withOtp = {...claimed, 'arrivalOtp': '1234', 'arrivalOtpAt': at};
      expect(Cp.activeArrivalOtp(withOtp, now), '1234');
      final old = now.subtract(const Duration(minutes: 11)).toIso8601String();
      expect(Cp.activeArrivalOtp({...withOtp, 'arrivalOtpAt': old}, now), isNull);
      expect(Cp.activeArrivalOtp({...withOtp, 'status': 'on_duty'}, now), isNull);
    });
  });

  group('team requests', () {
    final team = {
      ...shift('t1'),
      'isTeam': true,
      'teamSize': 3,
      'applicantUids': <String>[],
      'allocatedUids': <String>[],
    };
    test('every care physician sees it, agency or not', () {
      expect(Cp.shiftFits(team, {...me, 'agencyId': 'ag1'}, now), isTrue);
      expect(Cp.shiftFits(team, {...me, 'agencyId': ''}, now), isTrue);
    });
    test('hidden once the doctor accepted or the team is full', () {
      final mine = {...me, 'uid': 'u1', 'agencyId': 'ag1'};
      expect(Cp.shiftFits({...team, 'applicantUids': ['u1']}, mine, now), isFalse);
      expect(Cp.shiftFits({...team, 'allocatedUids': ['a', 'b', 'c']}, mine, now), isFalse);
    });
  });

  setUpAll(() {
    Cp.procedures = {
      'intubation': ('🩺', 'Intubation', true),
      'ventilator': ('🩺', 'Ventilator management', true),
      'iv_cannulation': ('🩺', 'IV cannulation', false),
      'suturing': ('🩺', 'Suturing', false),
    };
  });

  group('which shifts a care physician sees', () {
    test('open, not started, own duty types and areas', () {
      expect(Cp.shiftFits(shift('a'), me, now), isTrue);
      expect(Cp.shiftFits(shift('a', type: 'home'), me, now), isFalse);
      expect(Cp.shiftFits(shift('a', area: 'Aundh'), me, now), isFalse);
      expect(Cp.shiftFits(shift('a', status: 'claimed'), me, now), isFalse);
      expect(
          Cp.shiftFits(shift('a', start: '08:00', end: '14:00'), me, now),
          isFalse,
          reason: 'already started');
    });
    test('an empty profile sees every open shift', () {
      final empty = {...me, 'dutyTypes': [], 'areas': []};
      expect(Cp.shiftFits(shift('a', type: 'home', area: 'Aundh'), empty, now),
          isTrue);
    });
    test('urgent first, then preferred hospitals, then soonest', () {
      final sorted = Cp.sortShifts([
        shift('later', date: '2026-10-12'),
        shift('pref', date: '2026-10-13', hospital: 'Sahyadri Hospital, Wakad'),
        shift('urgent', date: '2026-10-14', urgent: true),
        shift('soon', date: tomorrow),
      ], me);
      expect([for (final s in sorted) s['id']],
          ['urgent', 'pref', 'soon', 'later']);
    });
  });

  group('claiming', () {
    test('a verified, available doctor with the procedures can claim', () {
      expect(
          Cp.claimBlockReason(
              shift('a', procedures: ['intubation']), me, const [], now),
          isNull);
    });
    test('Off cannot claim', () {
      expect(Cp.claimBlockReason(shift('a'), {...me, 'available': false},
          const [], now), contains('Available'));
    });
    test('locked procedures need verified credentials', () {
      expect(
          Cp.claimBlockReason(shift('a', procedures: ['intubation']),
              {...me, 'isVerified': false}, const [], now),
          contains('verified credentials'));
    });
    test('missing procedures are named', () {
      expect(
          Cp.claimBlockReason(
              shift('a', procedures: ['suturing']), me, const [], now),
          contains('Suturing'));
    });
    test('no two shifts at the same time', () {
      final mine = [
        shift('m', start: '22:00', end: '06:00', status: 'claimed')
      ];
      expect(Cp.claimBlockReason(shift('a'), me, mine, now),
          contains('already have a shift'));
      expect(
          Cp.claimBlockReason(
              shift('a', date: tomorrow, start: '08:00', end: '14:00'),
              me,
              mine,
              now),
          isNull,
          reason: 'next morning after the night shift ends is fine');
    });
    test('every ICU duty needs verified credentials', () {
      expect(
          Cp.claimBlockReason(
              shift('a'), {...me, 'isVerified': false}, const [], now),
          contains('ICU duties need verified credentials'));
      expect(
          Cp.claimBlockReason(shift('a', type: 'ward'),
              {...me, 'isVerified': false}, const [], now),
          contains('pending verification'),
          reason: 'an unverified care physician cannot claim any duty');
    });
    test('the booked-times record blocks a clashing claim', () {
      final start = Cp.shiftStart(shift('m', start: '22:00', end: '06:00'))!;
      final schedule = {
        'slots': {
          'm': {
            'start': start.toIso8601String(),
            'end': start.add(const Duration(hours: 8)).toIso8601String(),
            'label': 'Ruby Hall, 10 PM – 6 AM',
          },
        },
      };
      expect(Cp.scheduleClash(schedule, shift('a'), 'a', now),
          contains('Ruby Hall'));
      expect(Cp.scheduleClash(schedule, shift('m'), 'm', now), isNull,
          reason: 'the same shift is not a clash');
      expect(
          Cp.scheduleClash(schedule,
              shift('b', date: tomorrow, start: '08:00', end: '14:00'), 'b', now),
          isNull);
    });
    test('on an agency shift the doctor sees their share', () {
      final agencyShift = {...shift('a', pay: 3200), 'doctorPay': 2560};
      expect(Cp.doctorPayOf(agencyShift), 2560);
      expect(Cp.isAgencySplit(agencyShift), isTrue);
      expect(Cp.doctorPayOf(shift('b', pay: 3200)), 3200);
      expect(
          Cp.confirmedEarnings([
            {...agencyShift, 'status': 'claimed'},
            shift('c', pay: 1000, status: 'completed'),
          ]),
          3560);
    });
    test('3 no-shows pause claiming', () {
      expect(
          Cp.claimBlockReason(shift('a'), {...me, 'noShows': 3}, const [], now),
          contains('no-shows'));
    });
  });

  group('my duties', () {
    test('check-in opens 1 h before the start, until the end', () {
      final s = shift('a', status: 'claimed', claimedBy: 'u1');
      expect(Cp.canCheckIn(s, DateTime(2026, 10, 8, 18, 59)), isFalse);
      expect(Cp.canCheckIn(s, DateTime(2026, 10, 8, 19, 0)), isTrue);
      expect(Cp.canCheckIn(s, DateTime(2026, 10, 9, 7, 59)), isTrue);
      expect(Cp.canCheckIn(s, DateTime(2026, 10, 9, 8, 0)), isFalse);
    });
    test('4 h after the start without check-in is a no-show', () {
      final s = shift('a', status: 'claimed');
      expect(Cp.isNoShow(s, DateTime(2026, 10, 8, 23, 59)), isFalse);
      expect(Cp.isNoShow(s, DateTime(2026, 10, 9, 0, 1)), isTrue);
      expect(Cp.isNoShow({...s, 'checkInAt': 'x'}, DateTime(2026, 10, 9, 1)),
          isFalse);
    });
    test('earnings count claimed, on duty and completed shifts', () {
      expect(
          Cp.confirmedEarnings([
            shift('a', status: 'claimed', pay: 2600),
            shift('b', status: 'completed', pay: 2200),
            shift('c', status: 'absent', pay: 4500),
            shift('d', status: 'cancelled', pay: 1000),
          ]),
          4800);
    });
  });

  group('jobs', () {
    test('matching by area and qualification', () {
      final job = {
        'active': true,
        'area': 'Wakad',
        'qualifications': ['MBBS', 'MD / MS'],
      };
      expect(Cp.jobFits(job, me), isTrue);
      expect(Cp.jobFits({...job, 'qualifications': ['BAMS']}, me), isFalse);
      expect(Cp.jobFits({...job, 'area': 'Aundh'}, me), isFalse);
      expect(Cp.jobFits({...job, 'active': false}, me), isFalse);
    });
    test('salary label', () {
      expect(Cp.salaryLabel({'salaryMin': 60000, 'salaryMax': 80000}),
          '₹60–80k');
      expect(Cp.salaryLabel({'salaryMin': 45000, 'salaryMax': 45000}),
          '₹45k');
      expect(Cp.salaryLabel({}), 'Salary on request');
    });
  });

  // ------------------------------------------------------------- layouts

  const sizes = <Size>[
    Size(320, 640),
    Size(360, 780),
    Size(412, 915),
    Size(768, 1024),
    Size(1280, 800),
    Size(1920, 1080),
  ];

  final open = [
    shift('s1', urgent: true, procedures: ['intubation', 'ventilator']),
    shift('s2',
        date: tomorrow,
        start: '08:00',
        end: '14:00',
        slot: 'morning',
        type: 'ward',
        hospital: 'Sahyadri Hospital, Wakad',
        pay: 2200,
        procedures: ['iv_cannulation']),
    shift('s3',
        date: '2026-10-11',
        start: '14:00',
        end: '20:00',
        slot: 'evening',
        type: 'specialty',
        area: 'Pimpri',
        hospital: 'Lokmanya Hospital, Pimpri Chinchwad Super Speciality',
        pay: 2600),
  ];
  final mine = [
    shift('m1', status: 'claimed', claimedBy: 'u1', pay: 2600),
    {...shift('m2', status: 'on_duty', claimedBy: 'u1'), 'lateMinutes': 25},
    shift('m3', status: 'absent', claimedBy: 'u1'),
  ];
  final jobs = [
    {
      'id': 'j1',
      'title': 'Resident Medical Officer (RMO) – Cardiac Intensive Care Unit',
      'hospitalName': 'Kush Neuro Cardiac Hospital',
      'area': 'Wakad',
      'unit': 'ICU / Cardiac Care',
      'dutyType': 'icu',
      'timing': 'full_time',
      'salaryMin': 60000,
      'salaryMax': 80000,
      'openings': 2,
      'urgent': true,
      'active': true,
      'interestedUids': ['u1'],
    },
    {
      'id': 'j2',
      'title': 'Care Physician – General Ward',
      'hospitalName': 'Sahyadri Hospital, Wakad',
      'area': 'Wakad',
      'unit': 'General Medicine Ward',
      'dutyType': 'ward',
      'timing': 'morning',
      'salaryMin': 40000,
      'salaryMax': 55000,
      'openings': 1,
      'active': true,
    },
  ];

  Future<void> pumpAt(WidgetTester tester, Size size, Widget child) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      key: UniqueKey(),
      theme: AppTheme.lightTheme,
      home: ResponsiveCenter(child: child),
    ));
    await tester.pump();
  }

  void noOverflow(WidgetTester tester, String what) {
    final e = tester.takeException();
    expect(e, isNull, reason: '$what: $e');
  }

  for (final size in sizes) {
    final label = '${size.width.toInt()}×${size.height.toInt()}';
    testWidgets('care physician tabs fit at $label', (tester) async {
      for (final tab in ['shifts', 'jobs', 'duties', 'profile']) {
        await pumpAt(
          tester,
          size,
          CarePhysicianView(
            me: me,
            openShifts: open,
            myShifts: mine,
            jobs: jobs,
            now: now,
            tab: tab,
            shiftFilter: 'all',
            jobFilter: 'all',
            onTab: (_) {},
            onShiftFilter: (_) {},
            onJobFilter: (_) {},
            onClaim: (_) {},
            onCheckIn: (_) {},
            onCheckOut: (_) {},
            onJob: (_) {},
            onEditProfile: () {},
            onToggleAvailable: () {},
            onLogout: () {},
          ),
        );
        noOverflow(tester, tab);
      }
    });

    testWidgets('profile wizard fits at $label', (tester) async {
      for (var step = 0; step < 4; step++) {
        await pumpAt(
          tester,
          size,
          CarePhysicianProfileWizard(
            profile: me,
            initialStep: step,
            testAreas: const ['Wakad', 'Pimpri', 'Chinchwad', 'Bhosari', 'Aundh', 'Hinjewadi'],
            testHospitals: const [
              'Kush Neuro Cardiac Hospital',
              'DPU Private Super Speciality Hospital and Research Centre',
            ],
          ),
        );
        noOverflow(tester, 'step ${step + 1}');
      }
    });

    testWidgets('posted shift and job cards fit at $label', (tester) async {
      await pumpAt(
        tester,
        size,
        Scaffold(
          body: ListView(children: [
            for (final s in [
              ...open,
              {...mine[0], 'claimedByName': 'Dr. Nikhil Bhosale', 'claimedByPhone': '9876543210'},
              {...mine[1], 'claimedByName': 'Dr. Venkatanarasimharajuvaripeta', 'claimedByPhone': '9876543210'},
            ])
              PostedShiftCard(shift: s, now: now, onCancel: () {}),
            for (final j in jobs)
              PostedJobCard(
                  job: j, onInterests: () {}, onEdit: () {}, onActive: (_) {}),
          ]),
        ),
      );
      noOverflow(tester, 'board cards');
    });
  }

  testWidgets('empty profile shows the complete-profile banner',
      (tester) async {
    await pumpAt(
      tester,
      const Size(390, 844),
      CarePhysicianView(
        me: {...me, 'dutyTypes': [], 'areas': []},
        openShifts: const [],
        myShifts: const [],
        jobs: const [],
        now: now,
        tab: 'shifts',
        shiftFilter: 'all',
        jobFilter: 'all',
        onTab: (_) {},
        onShiftFilter: (_) {},
        onJobFilter: (_) {},
        onClaim: (_) {},
        onCheckIn: (_) {},
        onCheckOut: (_) {},
        onJob: (_) {},
        onEditProfile: () {},
        onToggleAvailable: () {},
        onLogout: () {},
      ),
    );
    expect(find.textContaining('Add your duty types and areas'), findsOneWidget);
    expect(find.textContaining('No matching shifts'), findsOneWidget);
  });

  testWidgets('Off: no open shifts or home visits are listed', (tester) async {
    await pumpAt(
      tester,
      const Size(412, 1600),
      CarePhysicianView(
        me: {...me, 'available': false},
        openShifts: open,
        myShifts: const [],
        jobs: const [],
        now: now,
        tab: 'shifts',
        shiftFilter: 'all',
        jobFilter: 'all',
        onTab: (_) {},
        onShiftFilter: (_) {},
        onJobFilter: (_) {},
        onClaim: (_) {},
        onCheckIn: (_) {},
        onCheckOut: (_) {},
        onJob: (_) {},
        onEditProfile: () {},
        onToggleAvailable: () {},
        onLogout: () {},
      ),
    );
    expect(find.textContaining('You are Off'), findsOneWidget);
    expect(find.text('Shifts (0)'), findsOneWidget);
    expect(find.text('Claim this shift'), findsNothing);
  });

  testWidgets('shift list shows counts, urgent tag and claim buttons',
      (tester) async {
    await pumpAt(
      tester,
      const Size(412, 1600),
      CarePhysicianView(
        me: me,
        openShifts: open,
        myShifts: mine,
        jobs: jobs,
        now: now,
        tab: 'shifts',
        shiftFilter: 'all',
        jobFilter: 'all',
        onTab: (_) {},
        onShiftFilter: (_) {},
        onJobFilter: (_) {},
        onClaim: (_) {},
        onCheckIn: (_) {},
        onCheckOut: (_) {},
        onJob: (_) {},
        onEditProfile: () {},
        onToggleAvailable: () {},
        onLogout: () {},
      ),
    );
    expect(find.text('Shifts (3)'), findsOneWidget);
    expect(find.text('Jobs (2)'), findsOneWidget);
    expect(find.text('URGENT'), findsOneWidget);
    expect(find.text('Claim this shift'), findsNWidgets(3));
  });
}
