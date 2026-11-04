/// Doctor's chat shortcut: typing `\` (like WhatsApp's `/` menu) opens the
/// list of tests to suggest; the letters after it filter the list, e.g.
/// `\mri`. Only a `\` at the start of a word counts, so "a\b" is just text.
class TestShortcut {
  TestShortcut._();

  static const String trigger = r'\';

  static final RegExp _token = RegExp(r'(^|\s)\\([^\s\\]*)$');

  /// The filter typed after the `\` at the end of [text], or null when the
  /// text does not end in a shortcut.
  static String? query(String text) => _token.firstMatch(text)?.group(2);

  /// [text] without the shortcut at its end (kept: what was typed before).
  static String strip(String text) =>
      text.replaceFirst(_token, '').trimRight();

  /// [tests] whose name contains [query] (any case), in their order.
  static List<String> filter(List<String> tests, String query) {
    final q = query.trim().toLowerCase();
    return [
      for (final t in tests)
        if (q.isEmpty || t.toLowerCase().contains(q)) t
    ];
  }
}
