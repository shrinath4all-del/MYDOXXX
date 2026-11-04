import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mydox/theme/app_theme.dart';

// The real app starts on SplashScreen, which needs a live Firebase project, so
// it can't be pumped in a plain widget test. This checks the app theme builds
// and renders; Firebase flows need integration tests on a device/emulator.
void main() {
  testWidgets('App theme renders', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const Scaffold(body: Text('MyDox')),
      ),
    );
    expect(find.text('MyDox'), findsOneWidget);
  });
}
