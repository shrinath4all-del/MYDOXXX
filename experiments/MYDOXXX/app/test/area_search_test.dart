import 'package:flutter_test/flutter_test.dart';
import 'package:mydox/utils/area_search.dart';

void main() {
  const areas = [
    'Anand Nagar', 'Aundh', 'Baner', 'Bavdhan', 'Bhosari', 'Wakad', 'Balewadi', 'Kothrud',
  ];

  test('typed text matches part of the name, as before', () {
    expect(searchAreas(areas, 'ba'), ['Baner', 'Bavdhan', 'Balewadi']);
    expect(searchAreas(areas, ''), areas);
  });

  test('spoken words find the area that sounds the same', () {
    expect(searchAreas(areas, 'Banner'), ['Baner']);
    expect(searchAreas(areas, 'Baner.'), ['Baner']);
    expect(searchAreas(areas, 'bowden'), ['Bavdhan']);
    expect(searchAreas(areas, 'Bosari'), ['Bhosari']);
    expect(searchAreas(areas, 'ond'), contains('Aundh'));
    expect(searchAreas(areas, 'kothrood'), ['Kothrud']);
    expect(searchAreas(areas, 'waakad'), ['Wakad']);
  });

  test('nothing alike: no result', () {
    expect(searchAreas(areas, 'zzzz'), isEmpty);
  });
}
