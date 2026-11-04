import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mydox/constants/app_colors.dart';
import 'package:mydox/theme/app_theme.dart';

/// Button icons must be visible: they follow the button's text colour, not
/// Material 3's primary blue.
void main() {
  Color? iconColor(WidgetTester tester, IconData icon) =>
      IconTheme.of(tester.element(find.byIcon(icon))).color;

  testWidgets('filled and outlined button icons match their text',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: Column(children: [
          ElevatedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.sync_rounded),
            label: const Text('Replace Document'),
          ),
          ElevatedButton.icon(
            onPressed: () {},
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            icon: const Icon(Icons.payments_rounded),
            label: const Text('Cash collected'),
          ),
          OutlinedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.visibility_rounded),
            label: const Text('View Document'),
          ),
        ]),
      ),
    ));
    expect(iconColor(tester, Icons.sync_rounded), Colors.white);
    expect(iconColor(tester, Icons.payments_rounded), Colors.white);
    expect(iconColor(tester, Icons.visibility_rounded), AppColors.brand);
  });
}
