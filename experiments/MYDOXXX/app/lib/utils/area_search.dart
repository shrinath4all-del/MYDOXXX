/// Finds the areas for what was typed or spoken in an area search box.
///
/// Typed text matches as before (part of the name). When nothing matches,
/// areas that sound the same are shown: speech often hears "Baner" as
/// "banner" or "Bavdhan" as "bowden", and a word with a trailing full stop.
List<String> searchAreas(List<String> areas, String query) {
  final q = _plain(query);
  if (q.isEmpty) return areas;
  final direct = [
    for (final a in areas)
      if (_plain(a).contains(q)) a
  ];
  if (direct.isNotEmpty) return direct;
  final keys = {
    _sound(q),
    for (final w in q.split(' '))
      if (w.length >= 3) _sound(w),
  }..removeWhere((k) => k.length < 2);
  if (keys.isEmpty) return const [];
  return [
    for (final a in areas)
      if (_soundsLike(a, keys)) a
  ];
}

bool _soundsLike(String area, Set<String> keys) {
  final plain = _plain(area);
  final whole = _sound(plain);
  final words = plain.split(' ').map(_sound).toSet();
  return keys.any((k) =>
      whole == k ||
      words.contains(k) ||
      (k.length >= 3 && whole.startsWith(k)));
}

/// Lower case letters and digits, single spaces.
String _plain(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// A rough "sound" of a name: consonants only, similar sounds merged,
/// doubled letters once ("banner" and "Baner" are both "bnr").
String _sound(String s) {
  var x = s.replaceAll(' ', '');
  const same = [
    ('ck', 'k'),
    ('ph', 'f'),
    ('sh', 's'),
    ('ch', 'c'),
    ('th', 't'),
    ('dh', 'd'),
    ('bh', 'b'),
    ('kh', 'k'),
    ('gh', 'g'),
    ('w', 'v'),
    ('z', 'j'),
    ('q', 'k'),
    ('x', 'ks'),
    ('c', 'k'),
  ];
  for (final (a, b) in same) {
    x = x.replaceAll(a, b);
  }
  x = x.replaceAll(RegExp('[aeiouyh]'), '');
  return x.replaceAllMapped(RegExp(r'(.)\1+'), (m) => m[1]!);
}
