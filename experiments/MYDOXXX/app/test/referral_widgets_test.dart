import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mydox/services/agency_invite_service.dart';
import 'package:mydox/widgets/referral_widgets.dart';

/// The sign-up code field and the "Referred by" line, without a database.
void main() {
  Widget page(Widget child) =>
      MaterialApp(home: Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: child)));

  testWidgets('an empty field offers the code, with nothing checked',
      (tester) async {
    final c = TextEditingController();
    addTearDown(c.dispose);
    await tester.pumpWidget(
        page(ReferralCodeField(controller: c, role: InviteRole.technician)));
    expect(find.text('Referral or agency invite code (optional)'), findsOneWidget);
    expect(find.textContaining('Got a link or code'), findsOneWidget);
    expect(find.textContaining('Referred by'), findsNothing);
    expect(find.byIcon(Icons.lock_outline_rounded), findsNothing);
  });

  testWidgets('a code from a link is filled in; when it cannot be looked up '
      'yet, sign-up is not blocked', (tester) async {
    final c = TextEditingController(text: 'SAI-7K3Q');
    addTearDown(c.dispose);
    var changed = 0;
    await tester.pumpWidget(page(ReferralCodeField(
        controller: c,
        role: InviteRole.nurse,
        fromLink: true,
        onChanged: () => changed++)));
    await tester.pumpAndSettle();
    expect(find.text('SAI-7K3Q'), findsOneWidget);
    // no database in this test: the code is checked when the account is made
    expect(find.textContaining('will be checked when your account is created'),
        findsOneWidget);
    // not recognised, so not locked: the person can still correct it
    expect(find.byIcon(Icons.lock_outline_rounded), findsNothing);
    expect(tester.takeException(), isNull);
    expect(changed, 0);
  });

  testWidgets('text that is not a code says so without a look-up',
      (tester) async {
    final c = TextEditingController();
    addTearDown(c.dispose);
    await tester.pumpWidget(
        page(ReferralCodeField(controller: c, role: InviteRole.carePhysician)));
    await tester.enterText(find.byType(TextField), 'ab');
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.textContaining('not found'), findsOneWidget);
  });

  testWidgets('the profile line shows only when there is a referral',
      (tester) async {
    await tester.pumpWidget(page(const Column(children: [
      ReferredByLine({'name': 'Asha'}),
    ])));
    expect(find.textContaining('Referred by'), findsNothing);
    await tester.pumpWidget(page(const Column(children: [
      ReferredByLine({
        'referredBy': {
          'type': 'marketing',
          'id': 'm1',
          'name': 'Ravi Kumar',
          'at': '2026-11-23T10:00:00.000'
        }
      }),
    ])));
    expect(find.text('Referred by Ravi Kumar (BFAST team) · 23/11/2026'),
        findsOneWidget);
  });
}
