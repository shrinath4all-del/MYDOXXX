import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mydox/theme/app_theme.dart';
import 'package:mydox/widgets/doctor_emergency_alert_dialog.dart';
import 'package:mydox/widgets/scrollable_action_dialog.dart';
import 'package:mydox/widgets/sos_tracker_dialog.dart';

Future<void> mountDialog(WidgetTester tester, Size viewport, Widget dialog,
    {double textScale = 1}) async {
  tester.view.physicalSize = viewport;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.lightTheme,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: Scaffold(body: dialog),
  ));
  await tester.pump();
}

void expectReachable(WidgetTester tester, String key, Size viewport) {
  final finder = find.byKey(ValueKey(key));
  expect(finder.hitTestable(), findsOneWidget,
      reason: '$key must be reachable without scrolling');
  final rect = tester.getRect(finder);
  expect(rect.left, greaterThanOrEqualTo(0));
  expect(rect.top, greaterThanOrEqualTo(0));
  expect(rect.right, lessThanOrEqualTo(viewport.width));
  expect(rect.bottom, lessThanOrEqualTo(viewport.height));
}

Future<void> scrollDetailsToEnd(WidgetTester tester) async {
  final scroller = find.descendant(
    of: find.byKey(const ValueKey('action-dialog-details')),
    matching: find.byType(Scrollable),
  );
  final position = tester.state<ScrollableState>(scroller).position;
  expect(position.maxScrollExtent, greaterThan(0));
  position.jumpTo(position.maxScrollExtent);
  await tester.pump();
}

void main() {
  for (final size in [
    const Size(280, 500),
    const Size(280, 360),
    const Size(600, 500)
  ]) {
    for (final scale in [1.0, 1.3]) {
      testWidgets('doctor alert actions remain reachable at $size scale $scale',
          (tester) async {
        await mountDialog(
            tester,
            size,
            DoctorEmergencyAlertDialog(
              appointment: {
                'patientName': 'Synthetic patient with a longer displayed name',
                'patientPhone': '0000000000',
                'emergencyCategory': 'Cardiac / Chest pain',
                'locationName':
                    'Test residence near Wakad, Pimpri Chinchwad, Pune',
                'requiresAmbulance': true,
                'price': 1200,
                'questionAnswers': {
                  for (var n = 0; n < 8; n++)
                    'Question $n with extended wording':
                        'Synthetic patient answer',
                },
              },
            ),
            textScale: scale);
        expect(tester.takeException(), isNull);
        for (final key in [
          'doctor-emergency-accept',
          'doctor-emergency-decline'
        ]) {
          expectReachable(tester, key, size);
        }
        final footer = find.byKey(const ValueKey('action-dialog-footer'));
        final before = tester.getRect(footer);
        await scrollDetailsToEnd(tester);
        expect(find.text('Total Earning:').hitTestable(), findsOneWidget);
        expect(tester.getRect(footer), before);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }

  testWidgets('small-screen response buttons invoke the correct callbacks',
      (tester) async {
    var accepted = 0;
    var declined = 0;
    await mountDialog(
        tester,
        const Size(280, 360),
        ScrollableActionDialog(
          body:
              const SizedBox(height: 1200, child: Text('Long request details')),
          actions: DoctorEmergencyActions(
            responding: false,
            onAccept: () => accepted++,
            onDecline: () => declined++,
          ),
        ));
    await tester.tap(find.byKey(const ValueKey('doctor-emergency-accept')));
    await tester.tap(find.byKey(const ValueKey('doctor-emergency-decline')));
    expect(accepted, 1);
    expect(declined, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('response in progress removes both actionable buttons',
      (tester) async {
    await mountDialog(
        tester,
        const Size(280, 360),
        ScrollableActionDialog(
          body: const SizedBox(height: 1200),
          actions: DoctorEmergencyActions(
            responding: true,
            onAccept: () => fail('Busy acceptance must not be invoked'),
            onDecline: () => fail('Busy decline must not be invoked'),
          ),
        ));
    expect(
        find.byType(CircularProgressIndicator).hitTestable(), findsOneWidget);
    expect(find.byType(ElevatedButton), findsNothing);
    expect(find.byType(OutlinedButton), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final status in [
    'Pending Hospital Acceptance',
    'Pending Ambulance Dispatch',
    'Ambulance Dispatched'
  ]) {
    for (final size in [const Size(280, 360), const Size(280, 500)]) {
      testWidgets('SOS $status remains operable at $size', (tester) async {
        bool? closeComplete;
        final data = <String, dynamic>{
          'status': status,
          'createdAt': DateTime.now().toIso8601String(),
          'patientUid': 'syntheticpatient',
          'requiresAmbulance': true,
          if (status != 'Pending Hospital Acceptance') ...{
            'assignedHospitalUid': 'synthetichospital',
            'assignedHospitalName':
                'Synthetic Hospital with an extended name in Wakad',
            'assignedDoctorName': 'Synthetic Cardiologist',
            'otp': '1234',
          },
          if (status == 'Ambulance Dispatched') ...{
            'assignedAmbulanceUid': 'syntheticambulance',
            'assignedAmbulanceDriver': 'Synthetic Ambulance Driver',
            'assignedVehicleNumber': 'TEST 0001',
          },
        };
        await mountDialog(
            tester,
            size,
            SosTrackerView(
              appointmentId: 'syntheticcase',
              data: data,
              hasData: true,
              onClose: (complete) => closeComplete = complete,
            ),
            textScale: 1.3);
        expect(tester.takeException(), isNull);
        expectReachable(tester, 'sos-tracker-close', size);
        final footer = find.byKey(const ValueKey('action-dialog-footer'));
        final before = tester.getRect(footer);
        await scrollDetailsToEnd(tester);
        expect(tester.getRect(footer), before);
        expectReachable(tester, 'sos-tracker-close', size);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const ValueKey('sos-tracker-close')));
        expect(closeComplete, status == 'Ambulance Dispatched',
            reason: 'Layout must preserve cancel-versus-close semantics');
      });
    }
  }
}
