import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mydox/constants/app_colors.dart';
import 'package:mydox/constants/app_strings.dart';
import 'package:mydox/services/app_search.dart';
import 'package:mydox/services/role_notifications.dart';
import 'package:mydox/theme/app_theme.dart';
import 'package:mydox/utils/appointment_rules.dart';
import 'package:mydox/utils/display_names.dart';
import 'package:mydox/widgets/active_emergency_banner.dart';
import 'package:mydox/widgets/app_bottom_nav.dart';
import 'package:mydox/widgets/app_dialog.dart';
import 'package:mydox/widgets/chat_button.dart';

void main() {
  group('names', () {
    test('Dr. is added once', () {
      expect(DisplayNames.doctor('Kunal Jadhav'), 'Dr. Kunal Jadhav');
      expect(DisplayNames.doctor('Dr Kunal Jadhav'), 'Dr. Kunal Jadhav');
      expect(DisplayNames.doctor('dr. Kunal Jadhav'), 'Dr. Kunal Jadhav');
      expect(DisplayNames.doctor(''), 'Doctor');
    });
    test('plurals', () {
      expect(DisplayNames.count(1, 'doctor'), '1 doctor');
      expect(DisplayNames.count(3, 'doctor'), '3 doctors');
    });
    test('every role has a login label', () {
      for (final r in ['patient', 'hospital', 'doctor', 'ambulance',
        'technician', 'therapist', 'nurse', 'care_physician', 'agency',
        'admin']) {
        expect(AppStrings.loginAs(r), isNot('Login as Patient'),
            skip: r == 'patient');
      }
      expect(AppStrings.loginAs('hospital'), 'Login as Hospital');
      expect(AppStrings.loginAs('ambulance'), 'Login as Ambulance');
      expect(AppStrings.roleName('technician'), 'Technician');
    });
  });

  group('chat', () {
    final now = DateTime(2026, 10, 19, 12);
    test('locked until the consultation ENDS (also while it runs)', () {
      expect(AppointmentRules.chatState({'status': 'Confirmed'}, now: now),
          ChatState.notStarted);
      expect(AppointmentRules.chatState({'status': 'In Progress'}, now: now),
          ChatState.notStarted);
    });
    test('open for 24 h after it ends, then expired (recharge)', () {
      expect(
          AppointmentRules.chatState({
            'status': 'Completed',
            'completedAt': now.subtract(const Duration(hours: 23)).toIso8601String(),
          }, now: now),
          ChatState.open);
      expect(
          AppointmentRules.chatState({
            'status': 'Completed',
            'completedAt': now.subtract(const Duration(hours: 25)).toIso8601String(),
          }, now: now),
          ChatState.expired);
    });

    testWidgets('chat button is greyed out and says why before the start',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: ChatButton(booking: const {'status': 'Confirmed'}, onChat: () {}),
        ),
      ));
      expect(find.text(AppStrings.chat), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
      await tester.tap(find.text(AppStrings.chat));
      await tester.pump();
      expect(find.text(AppStrings.chatLocked), findsOneWidget);
    });
  });

  group('search', () {
    const items = [
      SearchItem(SearchKind.specialty, 'Cardiologist'),
      SearchItem(SearchKind.doctor, 'Dr. Kunal Jadhav',
          subtitle: 'General Physician · MIG Hospital',
          target: 'General Physician'),
      SearchItem(SearchKind.labTest, 'ECG Technician'),
      ...AppSearch.services,
    ];
    test('finds by name, speciality, hospital and synonyms', () {
      expect(AppSearch.filter('cardio', items).first.title, 'Cardiologist');
      expect(AppSearch.filter('kunal', items).single.kind, SearchKind.doctor);
      expect(AppSearch.filter('mig', items).single.title, 'Dr. Kunal Jadhav');
      expect(AppSearch.filter('ecg', items).first.title, 'ECG Technician');
      expect(AppSearch.filter('ambulance', items).single.target, 'sos');
      expect(AppSearch.filter('', items), isEmpty);
    });
  });

  group('notifications for hospital / ambulance / care physician', () {
    test('hospital: accepted emergency and booked care physician', () {
      final now = DateTime(2026, 10, 19, 12);
      final sos = RoleNotifications.hospitalSos([
        {
          'assignedHospitalUid': 'h1',
          'patientName': 'Asha',
          'emergencyCategory': 'Cardiac',
          'hospitalAcceptedAt': '2026-10-19T10:00:00',
        },
        {'assignedHospitalUid': 'h2', 'hospitalAcceptedAt': '2026-10-19T11:00:00'},
      ], 'h1');
      expect(sos.single['title'], 'Emergency accepted');
      final shifts = RoleNotifications.hospitalShifts([
        {
          'claimedByName': 'Dr Rao',
          'claimedAt': '2026-10-19T09:00:00',
          'date': '2026-10-20',
          'start': '20:00',
          'end': '08:00',
        },
      ], now);
      expect(shifts.single['body'], startsWith('Dr. Rao'));
    });
    test('ambulance: only its own dispatches', () {
      final list = RoleNotifications.ambulanceSos([
        {'assignedAmbulanceUid': 'a1', 'ambulanceDispatchedAt': '2026-10-19T10:00:00'},
        {'assignedAmbulanceUid': 'a2', 'ambulanceDispatchedAt': '2026-10-19T10:00:00'},
      ], 'a1');
      expect(list.single['title'], 'New dispatch');
    });
  });

  for (final width in [320.0, 412.0]) {
    testWidgets('dialog with a long title and fees fits at ${width.toInt()}',
        (tester) async {
      tester.view.physicalSize = Size(width, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => AppDialog.confirm(
                  context,
                  icon: Icons.warning_amber_rounded,
                  color: AppColors.danger,
                  title: 'Confirm urgent request for a very long speciality name?',
                  message:
                      'Send an urgent same-day request to Dr. Venkatanarasimharajuvaripeta Subramanian?',
                  content: const PriceBreakdown(
                    base: 520,
                    extras: [(AppStrings.urgentSurcharge, 104)],
                    total: 624,
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('+₹104'), findsOneWidget);
      expect(find.text('₹624'), findsOneWidget);
      expect(find.text(AppStrings.confirm), findsOneWidget);
    });

    testWidgets('bottom bar marks the selected tab at ${width.toInt()}',
        (tester) async {
      tester.view.physicalSize = Size(width, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          bottomNavigationBar: AppBottomNav(
            currentIndex: 1,
            onTap: (_) {},
            items: const [
              AppNavItem(Icons.home_rounded, 'Home'),
              AppNavItem(Icons.calendar_month_rounded, 'Bookings'),
              AppNavItem(Icons.chat_bubble_rounded, 'Chat'),
              AppNavItem(Icons.person_rounded, 'Profile'),
            ],
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
      // icons only: the selected tab's icon is white in its raised circle
      final selected =
          tester.widget<Icon>(find.byIcon(Icons.calendar_month_rounded));
      expect(selected.color, Colors.white);
      final other = tester.widget<Icon>(find.byIcon(Icons.chat_bubble_rounded));
      expect(other.color, AppColors.muted);
      expect(find.byTooltip('Bookings'), findsOneWidget);
    });

    testWidgets('emergency banner fits at ${width.toInt()}', (tester) async {
      tester.view.physicalSize = Size(width, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var opened = false;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: ActiveEmergencyBanner(
              status: 'Pending Hospital Acceptance',
              onTap: () => opened = true,
            ),
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      await tester.tap(find.text(AppStrings.emergencyActive));
      expect(opened, isTrue);
    });
  }

  testWidgets('snackbar text is white on its blue / red background',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Saved'),
                      backgroundColor: AppColors.danger)),
              child: const Text('show'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('show'));
    await tester.pumpAndSettle();
    final style = DefaultTextStyle.of(tester.element(find.text('Saved'))).style;
    expect(style.color, Colors.white);
  });
}

