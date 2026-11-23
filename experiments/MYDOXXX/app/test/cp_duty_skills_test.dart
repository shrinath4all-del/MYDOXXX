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

  testWidgets('duty cards: tap opens skills, home visit is chosen by tap', (tester) async {
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
    // no checkboxes on the duty cards
    expect(find.byIcon(Icons.check_box_rounded), findsNothing);
    expect(find.byIcon(Icons.check_box_outline_blank_rounded), findsNothing);
    expect(find.text('1 of 21 skills chosen'), findsOneWidget);
    // tapping Ward opens its skills
    await tester.tap(find.text('Ward duty'));
    await tester.pump();
    expect(find.text('Ward duty skills · 1 of 21'), findsOneWidget);
    await tester.tap(find.text('IV Cannulation'));
    await tester.pump();
    expect(find.text('Ward duty skills · 2 of 21'), findsOneWidget);
    // ICU opens (Ward closes); it is chosen once a skill is picked
    await tester.tap(find.text('ICU duty'));
    await tester.pump();
    expect(find.textContaining('Ward duty skills'), findsNothing);
    expect(find.text('ICU duty skills · 0 of 24'), findsOneWidget);
    expect(find.text('Advanced ICU skills'), findsOneWidget);
    await tester.tap(find.text('ACLS'));
    await tester.pump();
    expect(find.text('1 of 24 skills chosen'), findsOneWidget);
    // home care visit has no skills: tapping the card chooses it
    await tester.tap(find.text('Home care visit'));
    await tester.pump();
    final card = tester.widget<Material>(find
        .ancestor(of: find.text('Home care visit'), matching: find.byType(Material))
        .first);
    expect(card.color, isNot(Colors.white));
  });
}
