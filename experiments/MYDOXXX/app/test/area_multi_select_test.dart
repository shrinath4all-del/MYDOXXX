import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mydox/theme/app_theme.dart';
import 'package:mydox/widgets/area_multi_select_field.dart';

void main() {
  final areas = [for (var i = 0; i < 150; i++) 'Area $i', 'Wakad', 'Baner'];

  test('closed field summary', () {
    expect(AreaMultiSelectField.summary({}, 'Select areas'), 'Select areas');
    expect(AreaMultiSelectField.summary({'Wakad'}, ''), 'Wakad');
    expect(AreaMultiSelectField.summary({'Wakad', 'Baner', 'Aundh', 'Pashan'}, ''),
        'Wakad, Baner +2 more');
  });

  for (final size in [const Size(320, 640), const Size(412, 915)]) {
    testWidgets('area dropdown: pick, search, remove at ${size.width.toInt()}',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var selected = <String>{'Wakad'};
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: AreaMultiSelectField(
                areas: areas,
                selected: selected,
                onChanged: (v) => setState(() => selected = v),
              ),
            ),
          ),
        ),
      ));
      // closed: one compact field, not 150 chips
      expect(find.text('Area 10'), findsNothing);
      expect(find.text('Wakad'), findsNWidgets(2)); // field + removable chip

      await tester.tap(find.byIcon(Icons.arrow_drop_down_rounded));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Select areas (1)'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'baner');
      await tester.pump();
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Baner'));
      await tester.pump();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(selected, {'Wakad', 'Baner'});

      // remove from the chip below the field
      await tester.tap(find.byTooltip('Delete').first);
      await tester.pump();
      expect(selected.length, 1);
      expect(tester.takeException(), isNull);
    });
  }
}
