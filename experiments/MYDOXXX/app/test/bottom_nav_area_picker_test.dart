import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mydox/theme/app_theme.dart';
import 'package:mydox/widgets/app_bottom_nav.dart';
import 'package:mydox/widgets/area_picker_sheet.dart';

void main() {
  const items = [
    AppNavItem(Icons.home_rounded, 'Home'),
    AppNavItem(Icons.calendar_month_rounded, 'Bookings'),
    AppNavItem(Icons.assignment_rounded, 'Records'),
    AppNavItem(Icons.person_rounded, 'Profile'),
  ];

  for (final size in const [Size(320, 640), Size(412, 915), Size(1280, 800)]) {
    for (final gestureBar in [0.0, 34.0]) {
      testWidgets(
          'bottom bar fits at ${size.width.toInt()} (gesture bar $gestureBar)',
          (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        tester.view.padding = FakeViewPadding(bottom: gestureBar);
        addTearDown(tester.view.reset);
        var tapped = -1;
        await tester.pumpWidget(MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            extendBody: true,
            body: const SizedBox.expand(),
            bottomNavigationBar: AppBottomNav(
              items: items,
              currentIndex: 0,
              onTap: (i) => tapped = i,
            ),
          ),
        ));
        expect(tester.takeException(), isNull);
        for (final i in items) {
          expect(find.byTooltip(i.label), findsOneWidget);
        }
        // labels stay above the phone's gesture bar
        final profile = tester.getRect(find.byTooltip('Profile'));
        expect(profile.bottom, lessThanOrEqualTo(size.height - gestureBar));
        await tester.tap(find.byTooltip('Records'));
        expect(tapped, 2);
      });
    }
  }

  testWidgets('area picker: 150 areas never take the full screen',
      (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final areas = [for (var i = 1; i <= 150; i++) 'Area $i'];
    String? picked;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async =>
                  picked = await AreaPickerSheet.show(context, areas: areas),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final sheet = tester.getRect(find.byType(AreaPickerSheet));
    expect(sheet.height, lessThanOrEqualTo(915 * 0.7 + 1));
    // search narrows the list
    await tester.enterText(find.byType(TextField), 'Area 14');
    await tester.pump();
    expect(find.text('Area 140'), findsOneWidget);
    expect(find.text('Area 2'), findsNothing);
    await tester.tap(find.text('Area 145'));
    await tester.pumpAndSettle();
    expect(picked, 'Area 145');
  });
}
