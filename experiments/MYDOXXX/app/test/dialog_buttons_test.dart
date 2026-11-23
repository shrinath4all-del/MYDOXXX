import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mydox/theme/app_theme.dart';
import 'package:mydox/widgets/app_alert_dialog.dart';

void main() {
  for (final width in [360.0, 412.0, 1280.0]) {
    testWidgets('dialog buttons: one row, same size, at $width px', (t) async {
      t.view.physicalSize = Size(width, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: AppAlertDialog(
            title: const Text('Accept this team opportunity?'),
            content: const Text('Golden Care requires 3 full-time care physicians.'),
            actions: [
              TextButton(onPressed: () {}, child: const Text('Not now')),
              ElevatedButton(onPressed: () {}, child: const Text('Accept')),
            ],
          ),
        ),
      ));
      expect(t.takeException(), isNull);
      final a = t.getRect(find.widgetWithText(TextButton, 'Not now'));
      final b = t.getRect(find.widgetWithText(ElevatedButton, 'Accept'));
      expect((a.center.dy - b.center.dy).abs(), lessThan(1));
      expect(b.left, greaterThan(a.right));
      expect((a.width - b.width).abs(), lessThan(1));
      expect((a.height - b.height).abs(), lessThan(1));
    });
  }

  Future<void> open(WidgetTester t, {required bool dismissible}) async {
    await t.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              barrierDismissible: dismissible,
              builder: (_) => AppAlertDialog(
                title: const Text('Leave the agency?'),
                content: const Text('You will work as a freelancer.'),
                actions: [
                  TextButton(onPressed: () {}, child: const Text('Cancel')),
                  ElevatedButton(onPressed: () {}, child: const Text('Leave')),
                ],
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
  }

  testWidgets('a popup has a close button that closes it', (t) async {
    await open(t, dismissible: true);
    expect(find.byTooltip('Close'), findsOneWidget);
    await t.tap(find.byTooltip('Close'));
    await t.pumpAndSettle();
    expect(find.text('Leave the agency?'), findsNothing);
  });

  testWidgets('a popup that must be answered has no close button', (t) async {
    await open(t, dismissible: false);
    expect(find.text('Leave the agency?'), findsOneWidget);
    expect(find.byTooltip('Close'), findsNothing);
  });
}
