import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mydox/screens/agency/control_room_widgets.dart';
import 'package:mydox/screens/care_physician/care_physician_profile_wizard.dart';
import 'package:mydox/services/care_agency_service.dart';
import 'package:mydox/services/pricing_service.dart';
import 'package:mydox/theme/app_theme.dart';

void main() {
  test('emergency locum duties are billed 20% more (from Firestore)', () {
    const pricing = PricingSettings(emergencyLocumHikePct: 20);
    expect(pricing.billedRate('emergency', 3000), 3600);
    expect(pricing.billedRate('locum', 3000), 3000);
    expect(const PricingSettings().billedRate('emergency', 3000), 3000,
        reason: 'no % in Firestore: no hike');
    expect(CareAgencyService.rateFields('emergency', 3000, pricing), {
      'baseRate': 3000,
      'hospitalRate': 3600,
      'emergencyHikePct': 20,
    });
  });

  testWidgets('lists show the first 10 rows, then "View all"', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: SingleChildScrollView(
          child: ListPanel(
            rows: [for (var i = 1; i <= 14; i++) Text('Duty $i')],
            emptyText: 'none',
            initialRows: 10,
          ),
        ),
      ),
    ));
    expect(find.text('Duty 10'), findsOneWidget);
    expect(find.text('Duty 11'), findsNothing);
    await tester.tap(find.text('View all (14)'));
    await tester.pump();
    expect(find.text('Duty 14'), findsOneWidget);
    expect(find.text('Show first 10'), findsOneWidget);
  });

  for (final width in [320.0, 412.0, 1280.0]) {
    testWidgets('profile progress shows each step at ${width.toInt()}',
        (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: CarePhysicianProfileWizard(
          profile: const {
            'uid': 'u1',
            'name': 'Dr Nikhil',
            'qualification': 'MBBS',
            'regNo': 'MMC-1',
            'experienceYears': 4,
            'dutyTypes': ['home'],
          },
          testAreas: const ['Wakad'],
        ),
      ));
      expect(tester.takeException(), isNull);
      // credentials, role and (passed-later) procedures: 2 of 4 now
      expect(find.text('50% complete'), findsOneWidget);
      for (final t in ['Credentials', 'Procedures', 'Where you work']) {
        expect(find.text(t), findsWidgets);
      }
    });
  }
}
