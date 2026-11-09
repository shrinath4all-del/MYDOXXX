/// India time everywhere in the app, whatever zone the phone or browser is in.
///
/// ONE RULE: a [DateTime] in this app that is NOT UTC-flagged is an India
/// wall-clock time: its year ... millisecond fields are what a clock in India
/// shows. A UTC-flagged [DateTime] (`isUtc == true`) is a real instant.
///
/// Why: `DateTime.now()`, `DateTime.parse('...Z')`, `Timestamp.toDate()` and
/// `TimeOfDay.now()` all answer in the DEVICE's zone. Shift times, slot times and
/// duty rosters are India times, so on a device set to another zone "now" was
/// compared with the wrong hour. Reading the clock only through this class
/// removes that whole class of bugs. On a device already set to India time every
/// value is identical to what `DateTime.now()` gave before.
///
/// Only this file may use the raw device clock APIs; `test/ist_clock_guard_test.dart`
/// fails the build if another file in `lib/` does.
///
/// Limits, by design "for now": the zone is fixed to India Standard Time
/// (UTC+05:30, no daylight saving). A plain wall-clock value is stored in a
/// `DateTime` flagged "local", so on a device whose own zone has daylight saving,
/// the single India hour that does not exist locally on the changeover night
/// cannot be represented exactly. Changing the app zone later means changing
/// [offset] here (and the roster text), nothing else.
library;

class IstClock {
  IstClock._();

  /// India Standard Time, UTC+05:30. India has no daylight saving.
  static const Duration offset = Duration(hours: 5, minutes: 30);

  static DateTime Function() _deviceNow = DateTime.now;

  /// Tests only: replace the device clock with a fixed instant, or pass null to
  /// restore the real clock. Never call this from app code.
  static void debugSetInstantSource(DateTime Function()? source) {
    _deviceNow = source ?? DateTime.now;
  }

  /// The current India wall-clock time. This is what almost all code needs:
  /// compare it with shift times, slot times and dates, build date keys from it,
  /// store `now().toIso8601String()` as "created at".
  static DateTime now() => fromInstant(_deviceNow());

  /// The current real instant (UTC-flagged). Use ONLY where an absolute moment
  /// matters: comparing with server-issued epoch times (the cloud session expiry),
  /// unique ids, cache-busting numbers.
  static DateTime instant() => _deviceNow().toUtc();

  /// The India wall-clock time of the real instant [instant].
  static DateTime fromInstant(DateTime instant) {
    final w = instant.toUtc().add(offset);
    return DateTime(w.year, w.month, w.day, w.hour, w.minute, w.second,
        w.millisecond, w.microsecond);
  }

  /// Reads [t]'s date and time FIELDS as India time and returns the real instant
  /// (UTC-flagged), ignoring whether [t] is flagged UTC or local. For values that
  /// are known to be India wall-clock times (shift times, slot times).
  static DateTime fieldsToInstant(DateTime t) => DateTime.utc(t.year, t.month,
          t.day, t.hour, t.minute, t.second, t.millisecond, t.microsecond)
      .subtract(offset);

  /// The real instant of [t]: a UTC-flagged value already is one; a plain value is
  /// an India wall-clock time. Use before writing a Firestore `Timestamp` or
  /// comparing with real instants.
  static DateTime toInstant(DateTime t) => t.isUtc ? t : fieldsToInstant(t);

  /// [toInstant] that passes null through.
  static DateTime? maybeToInstant(DateTime? t) => t == null ? null : toInstant(t);

  /// A real instant given in any form (UTC-flagged or the device-local flag that
  /// `Timestamp.toDate()` returns) as a UTC-flagged instant.
  static DateTime instantOf(DateTime realInstant) => realInstant.toUtc();

  /// [t] as an India wall-clock time: a UTC-flagged instant is converted; a plain
  /// value is returned unchanged. Do NOT use this on a value that came from
  /// `Timestamp.toDate()` (that is a plain-looking real instant): use
  /// [fromInstant] for those.
  static DateTime wall(DateTime t) => t.isUtc ? fromInstant(t) : t;

  /// Parses an ISO-8601 string. A string with a zone marker (`Z` or `+hh:mm`) is
  /// a real instant and becomes India wall-clock time; a string with none is
  /// already India wall-clock time and is returned as written. Throws on bad input.
  static DateTime parse(String source) => wall(DateTime.parse(source));

  /// Like [parse], but null for text that is not a date.
  static DateTime? tryParse(String source) {
    final t = DateTime.tryParse(source);
    return t == null ? null : wall(t);
  }

  /// The India wall-clock time of [milliseconds] since the Unix epoch.
  static DateTime fromEpochMs(int milliseconds) => fromInstant(
      DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true));
}
