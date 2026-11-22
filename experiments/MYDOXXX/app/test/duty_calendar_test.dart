import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mydox/screens/care_physician/my_duties_view.dart';

void main() {
  // 17 Nov 2026, noon in India
  final now = DateTime.utc(2026, 11, 17, 6, 30);

  Future<void> show(WidgetTester tester, List<Map<String, dynamic>> shifts) async {
    tester.view.physicalSize = const Size(412, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MyDutiesView(
          uid: 'cp1',
          myShifts: shifts,
          now: now,
          cardFor: (_) => const SizedBox.shrink(),
        ),
      ),
    ));
    await tester.pump();
  }

  IconButton back(WidgetTester tester) => tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.chevron_left_rounded));

  testWidgets('before any duty: no going back, past days are not "free"',
      (tester) async {
    await show(tester, const []);
    expect(find.text('November 2026'), findsOneWidget);
    expect(back(tester).onPressed, isNull);

    await tester.tap(find.text('10')); // a past day
    await tester.pump();
    expect(find.textContaining('No duties assigned'), findsNothing);

    await tester.tap(find.text('20')); // a coming day
    await tester.pump();
    expect(find.text('20 November: No duties assigned'), findsOneWidget);
  });

  testWidgets('earlier months with duties can still be opened', (tester) async {
    await show(tester, [
      {
        'id': 's1',
        'status': 'completed',
        'date': '2026-10-05',
        'start': '08:00',
        'end': '14:00',
        'slot': 'morning',
        'hospitalName': 'City Hospital',
      },
    ]);
    expect(back(tester).onPressed, isNotNull);
    await tester.tap(find.widgetWithIcon(IconButton, Icons.chevron_left_rounded));
    await tester.pump();
    expect(find.text('October 2026'), findsOneWidget);
    // October is the first month with a duty: no further back
    expect(back(tester).onPressed, isNull);
  });
}
