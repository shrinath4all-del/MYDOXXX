import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mydox/models/cp_duty_skills.dart';
import 'package:mydox/screens/care_physician/care_physician_profile_wizard.dart';

void main() {
  test('saved skills are read per duty type, unknown ones dropped', () {
    final p = {
      'dutySkills': {
        'ward': ['IV Cannulation', 'Not a skill'],
        'icu': ['ACLS'],
      }
    };
    expect(cpSkillsOf(p, 'ward'), ['IV Cannulation']);
    expect(cpSkillsOf(p, 'icu'), ['ACLS']);
    expect(cpSkillsOf(p, 'casualty'), isEmpty);
    expect(cpSkillsOf(const {}, 'ward'), isEmpty);
  });

  testWidgets('ticking Ward duty opens its skills to pick', (tester) async {
    tester.view.physicalSize = const Size(390, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(
      home: CarePhysicianProfileWizard(
        profile: {
          'uid': 'cp1',
          'name': 'Asha Rao',
          'dutyTypes': ['ward'],
          'dutySkills': {'ward': ['Wound Dressing']},
        },
        initialStep: 2,
        testAreas: ['Wakad'],
      ),
    ));
    await tester.pump();
    expect(find.text('Ward duty skills · 1 of 21'), findsOneWidget);
    await tester.tap(find.text('IV Cannulation'));
    await tester.pump();
    expect(find.text('Ward duty skills · 2 of 21'), findsOneWidget);
    // ICU is not ticked: no ICU skills shown
    expect(find.textContaining('ICU duty skills'), findsNothing);
    await tester.tap(find.text('ICU duty'));
    await tester.pump();
    expect(find.text('ICU duty skills · 0 of 24'), findsOneWidget);
    expect(find.text('Advanced ICU skills'), findsOneWidget);
  });
}
