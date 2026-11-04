import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mydox/utils/test_shortcut.dart';
import 'package:mydox/widgets/test_suggestion_ui.dart';

void main() {
  group(r'typing \ in the doctor chat', () {
    test(r'\ opens the list, letters after it filter', () {
      expect(TestShortcut.query(r'\'), '');
      expect(TestShortcut.query(r'\mri'), 'mri');
      expect(TestShortcut.query(r'Please do \ec'), 'ec');
    });

    test(r'only a \ starting a word counts', () {
      expect(TestShortcut.query('hello'), isNull);
      expect(TestShortcut.query(r'a\b'), isNull);
      expect(TestShortcut.query(r'\mri done'), isNull, reason: 'a space closes it');
    });

    test('closing keeps what was typed before the shortcut', () {
      expect(TestShortcut.strip(r'Please do \mri'), 'Please do');
      expect(TestShortcut.strip(r'\'), '');
    });

    test('filter ignores case', () {
      final tests = ['ECG Technician', 'Portable X-Ray', 'Lab - Blood Draw'];
      expect(TestShortcut.filter(tests, 'ecg'), ['ECG Technician']);
      expect(TestShortcut.filter(tests, ''), tests);
    });
  });

  testWidgets('the list ticks several tests and offers to send them',
      (tester) async {
    // a phone screen (the list takes up to a third of its height)
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final picked = <String>{'ECG Technician', 'Portable X-Ray'};
    var sent = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: TestShortcutPanel(
            tests: const ['ECG Technician', 'Portable X-Ray', 'EEG Technician'],
            loading: false,
            picked: picked,
            onToggle: (_) {},
            onSend: () => sent = true,
            onClose: () {},
          ),
        ),
      ),
    ));
    expect(find.byType(CheckboxListTile), findsNWidgets(3));
    await tester.tap(find.text('Send 2 tests to patient'));
    expect(sent, isTrue);
  });
}
