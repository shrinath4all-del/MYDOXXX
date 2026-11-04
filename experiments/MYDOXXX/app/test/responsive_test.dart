import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mydox/theme/app_theme.dart';
import 'package:mydox/utils/responsive.dart';

Future<void> pumpAt(WidgetTester tester, Size size, Widget child,
    {double textScale = 1}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(MaterialApp(
    key: UniqueKey(),
    theme: AppTheme.lightTheme,
    builder: (context, c) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
          textScaler: Responsive.appTextScaler(MediaQuery.of(context))),
      child: c!,
    ),
    home: child,
  ));
}

/// A booking-style grid: icon, two-line name, price chip.
class _Grid extends StatelessWidget {
  const _Grid();
  @override
  Widget build(BuildContext context) => ResponsiveCenter(
        child: Scaffold(
          body: GridView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: 6,
            gridDelegate: Responsive.grid(context,
                minTileWidth: 150, tileHeight: 190),
            itemBuilder: (_, i) => Container(
              padding: const EdgeInsets.all(14),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(width: 82, height: 82),
                  SizedBox(height: 8),
                  Text('Pediatric Physiotherapy and Rehabilitation',
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  SizedBox(height: 4),
                  Text('₹1,200', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ),
        ),
      );
}

void main() {
  testWidgets('screen size classes', (tester) async {
    late BuildContext ctx;
    for (final (w, phone, tablet, desktop) in [
      (320.0, true, false, false),
      (599.0, true, false, false),
      (768.0, false, true, false),
      (1280.0, false, false, true),
    ]) {
      await pumpAt(tester, Size(w, 800), Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      }));
      expect(Responsive.isPhone(ctx), phone, reason: '$w');
      expect(Responsive.isTablet(ctx), tablet, reason: '$w');
      expect(Responsive.isDesktop(ctx), desktop, reason: '$w');
      expect(Responsive.dialogWidth(ctx), w * 0.9 < 420 ? w * 0.9 : 420);
    }
  });

  testWidgets('phone-style screens are centred on wide screens',
      (tester) async {
    await pumpAt(tester, const Size(1280, 800),
        const ResponsiveCenter(child: Scaffold(body: Text('x'))));
    expect(tester.getSize(find.byType(Scaffold)).width,
        Responsive.phoneMaxWidth);
    await pumpAt(tester, const Size(390, 800),
        const ResponsiveCenter(child: Scaffold(body: Text('x'))));
    expect(tester.getSize(find.byType(Scaffold)).width, 390);
  });

  testWidgets('system font size is kept within 85–130%', (tester) async {
    late BuildContext ctx;
    await pumpAt(tester, const Size(390, 800), Builder(builder: (c) {
      ctx = c;
      return const SizedBox();
    }), textScale: 2.0);
    expect(Responsive.textScale(ctx), closeTo(1.3, 0.01));
  });

  testWidgets('text and pictures scale with the screen width', (tester) async {
    late BuildContext ctx;
    Future<void> at(double w) => pumpAt(tester, Size(w, 800), Builder(builder: (c) {
          ctx = c;
          return const SizedBox();
        }));
    await at(390);
    expect(Responsive.textScale(ctx), closeTo(1.0, 0.01));
    expect(Responsive.scale(ctx, 100), closeTo(100, 0.5));
    await at(320);
    expect(Responsive.textScale(ctx), closeTo(0.88, 0.01));
    expect(Responsive.scale(ctx, 100), closeTo(88, 0.5));
    await at(1280);
    expect(Responsive.textScale(ctx), closeTo(1.12, 0.01));
    expect(Responsive.scale(ctx, 100), closeTo(112, 0.5));
  });

  for (final w in [320.0, 360.0, 412.0, 768.0, 1280.0]) {
    for (final scale in [1.0, 1.3]) {
      testWidgets('booking grid fits at ${w.toInt()} px, font x$scale',
          (tester) async {
        await pumpAt(tester, Size(w, 1400), const _Grid(), textScale: scale);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
