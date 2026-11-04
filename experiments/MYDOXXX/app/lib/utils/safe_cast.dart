/// Reads a number from Firestore data that may have been saved as a number or
/// as text ("1500"). `value as num?` throws on text and crashes the screen;
/// this returns the number, or null if there is none.
num? toNum(Object? value) {
  if (value is num) return value;
  if (value is String) return num.tryParse(value.trim());
  return null;
}
