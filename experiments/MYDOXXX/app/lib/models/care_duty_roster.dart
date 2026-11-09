/// Weekly rotation roster for a team of three care physicians (A, B, C) at one
/// hospital unit. Pure Dart: no Firestore, so it can be tested and reused by
/// the server rules.
///
/// Shifts (hospital local time, Asia/Kolkata):
///   Morning 08:00-15:00, Evening 15:00-22:00, Night 22:00-08:00 (next day).
/// One weekly rotation (7 days from the start date), repeating every three weeks:
///   week 1  Morning A, Evening B, Night C
///   week 2  Morning B, Evening C, Night A
///   week 3  Morning C, Evening A, Night B
/// so each physician's own cycle is Morning, then Night, then Evening.
library;

import '../utils/ist_clock.dart';

/// India time (UTC+05:30, no daylight saving) to and from real instants.
class CareDutyClock {
  CareDutyClock._();
  static const Duration offset = IstClock.offset;

  /// The instant for [hour]:00 India time on the civil date [y]-[m]-[d].
  static DateTime istToUtc(int y, int m, int d, int hour) =>
      DateTime.utc(y, m, d, hour).subtract(offset);

  /// The instant of a shift time typed as India wall-clock time. Shift
  /// dates and hours are entered in India time, whatever the device zone, so
  /// only the date and time fields of [wall] are used, never its zone.
  static DateTime wallToUtc(DateTime wall) => IstClock.fieldsToInstant(wall);

  /// The India civil time of an instant (fields read as local India time).
  static DateTime utcToIst(DateTime instant) =>
      IstClock.instantOf(instant).add(offset);

  /// The India calendar day (as a UTC-flagged date) of [now]. [now] is either an
  /// India wall-clock time (a plain DateTime, as everywhere in the app) or a real
  /// instant (UTC-flagged); a wall-clock value is never converted a second time.
  static DateTime today(DateTime now) {
    final i = IstClock.wall(now);
    return DateTime.utc(i.year, i.month, i.day);
  }
}

enum DutyShift { morning, evening, night }

extension DutyShiftInfo on DutyShift {
  String get key => name;
  String get label => switch (this) {
        DutyShift.morning => 'Morning',
        DutyShift.evening => 'Evening',
        DutyShift.night => 'Night',
      };
  int get startHour => switch (this) {
        DutyShift.morning => 8,
        DutyShift.evening => 15,
        DutyShift.night => 22,
      };
  int get hours => switch (this) {
        DutyShift.morning => 7,
        DutyShift.evening => 7,
        DutyShift.night => 10,
      };
  String get timeText => switch (this) {
        DutyShift.morning => '08:00 to 15:00',
        DutyShift.evening => '15:00 to 22:00',
        DutyShift.night => '22:00 to 08:00 (next day)',
      };

  /// Position in the weekly table: who holds this shift in week 1.
  int get _offset => switch (this) {
        DutyShift.morning => 0,
        DutyShift.evening => 1,
        DutyShift.night => 2,
      };
}

DutyShift? dutyShiftFromKey(String key) {
  for (final s in DutyShift.values) {
    if (s.key == key) return s;
  }
  return null;
}

/// One duty: a shift on a civil date. Its [key] ("2026-10-20|night") is how
/// requests and overrides refer to it.
class DutySlot {
  final DateTime date; // civil date, UTC midnight
  final DutyShift shift;
  const DutySlot(this.date, this.shift);

  static String dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static DateTime? parseDate(String? s) {
    final p = (s ?? '').split('-');
    if (p.length != 3) return null;
    final y = int.tryParse(p[0]), m = int.tryParse(p[1]), d = int.tryParse(p[2]);
    if (y == null || m == null || d == null) return null;
    return DateTime.utc(y, m, d);
  }

  static DutySlot? parse(String key) {
    final p = key.split('|');
    if (p.length != 2) return null;
    final d = parseDate(p[0]);
    final s = dutyShiftFromKey(p[1]);
    return d == null || s == null ? null : DutySlot(d, s);
  }

  String get key => '${dateKey(date)}|${shift.key}';

  /// Real start / end instants. Intervals are half-open [start, end).
  DateTime get start =>
      CareDutyClock.istToUtc(date.year, date.month, date.day, shift.startHour);
  DateTime get end => start.add(Duration(hours: shift.hours));

  bool overlaps(DutySlot other) =>
      start.isBefore(other.end) && other.start.isBefore(end);

  @override
  bool operator ==(Object other) => other is DutySlot && other.key == key;
  @override
  int get hashCode => key.hashCode;
}

/// Another commitment of a physician (a locum shift, a home visit ...).
class BusyInterval {
  final DateTime start;
  final DateTime end;
  final String label; // where, for a message ("Kush Hospital")
  const BusyInterval(this.start, this.end, [this.label = '']);
}

class DutyCheck {
  final String? problem; // null: allowed
  const DutyCheck.ok() : problem = null;
  const DutyCheck.no(String this.problem);
  bool get ok => problem == null;
}

/// A roster: the first Monday, the three physicians in the order A, B, C,
/// and the accepted changes (key -> physician who actually works that duty).
class CareDutyRoster {
  final DateTime anchorMonday;
  final List<String> members; // uids of A, B, C
  final Map<String, String> overrides;

  /// A one-shift placement: a single physician (members[0]) works only this
  /// shift, every day. Null for the three-physician weekly rotation.
  final DutyShift? fixed;

  CareDutyRoster({
    required DateTime anchorMonday,
    required this.members,
    this.overrides = const {},
    this.fixed,
  }) : anchorMonday = DateTime.utc(
            anchorMonday.year, anchorMonday.month, anchorMonday.day) {
    assert(members.length == 3);
  }

  static const letters = ['A', 'B', 'C'];

  String letterOf(String uid) {
    final i = members.indexOf(uid);
    return i < 0 ? 'R' : letters[i]; // R: relief
  }

  /// Monday-to-Sunday week number counted from the anchor (can be negative).
  int weekIndex(DateTime date) {
    final d = DateTime.utc(date.year, date.month, date.day);
    final days = d.difference(anchorMonday).inDays;
    return (days / 7).floor();
  }

  /// The physician the rotation gives this duty to (before any change).
  String plannedFor(DutySlot slot) {
    if (fixed != null) return slot.shift == fixed ? members[0] : '';
    final w = weekIndex(slot.date);
    final i = ((w + slot.shift._offset) % 3 + 3) % 3;
    return members[i];
  }

  /// Who works this duty now (an accepted change wins).
  String assigneeOf(DutySlot slot) => overrides[slot.key] ?? plannedFor(slot);

  List<DutySlot> slotsOn(DateTime date) =>
      DateTime.utc(date.year, date.month, date.day).isBefore(anchorMonday)
          // nothing is rostered before the job's start date
          ? const []
          : [
        for (final s in DutyShift.values)
          if (fixed == null || s == fixed)
          DutySlot(DateTime.utc(date.year, date.month, date.day), s)
      ];

  /// Every duty [uid] works on dates [from] to [to] (inclusive), earliest
  /// first, using [withOverrides] instead of the stored changes if given.
  List<DutySlot> dutiesOf(String uid, DateTime from, DateTime to,
      {Map<String, String>? withOverrides}) {
    final ov = withOverrides ?? overrides;
    final out = <DutySlot>[];
    for (var d = DateTime.utc(from.year, from.month, from.day);
        !d.isAfter(to);
        d = d.add(const Duration(days: 1))) {
      for (final slot in slotsOn(d)) {
        if ((ov[slot.key] ?? plannedFor(slot)) == uid) out.add(slot);
      }
    }
    return out..sort((a, b) => a.start.compareTo(b.start));
  }

  /// All the rules for [uid] working the duties in [slots] after a change:
  /// no overlap with any other duty or commitment, no chain of three duties
  /// touching end to start, and the last Sunday night must not run into that
  /// Monday morning.
  DutyCheck checkWorking(
    String uid,
    DutySlot changed, {
    required Map<String, String> after,
    List<BusyInterval> others = const [],
  }) {
    final from = changed.date.subtract(const Duration(days: 3));
    final to = changed.date.add(const Duration(days: 3));
    final mine = dutiesOf(uid, from, to, withOverrides: after);
    if (!mine.any((s) => s == changed)) return const DutyCheck.ok();

    final spans = <(DateTime, DateTime, String)>[
      for (final s in mine) (s.start, s.end, s.key),
      for (final o in others) (o.start, o.end, 'other'),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    for (var i = 0; i < spans.length; i++) {
      for (var j = i + 1; j < spans.length; j++) {
        if (spans[j].$1.isBefore(spans[i].$2)) {
          return const DutyCheck.no(
              'That overlaps another duty or booking of the same physician.');
        }
      }
    }

    // the last night of a week, then the first morning of the next week
    for (final s in mine) {
      final next = s.date.add(const Duration(days: 1));
      if (s.shift == DutyShift.night && weekIndex(next) != weekIndex(s.date)) {
        final monday = DutySlot(next, DutyShift.morning);
        if (mine.contains(monday) && (s == changed || monday == changed)) {
          return const DutyCheck.no(
              'The last night of a week cannot be followed by the morning of the next week.');
        }
      }
    }
    // three duties touching: end of one is exactly the start of the next
    var chain = 1;
    for (var i = 1; i < mine.length; i++) {
      chain = mine[i].start == mine[i - 1].end ? chain + 1 : 1;
      if (chain >= 3) {
        final touching = mine.sublist(i - 2, i + 1);
        if (touching.any((s) => s == changed)) {
          return const DutyCheck.no(
              'That would be three duties in a row without a break.');
        }
      }
    }

    return const DutyCheck.ok();
  }

  /// [uid] takes over [slot] (leave cover). [now] is India wall-clock time (a
  /// plain DateTime) or a real instant (UTC-flagged); duty times are real instants.
  DutyCheck checkTakeOver(String uid, DutySlot slot, DateTime now,
      {List<BusyInterval> others = const []}) {
    if (!slot.start.isAfter(IstClock.toInstant(now))) {
      return const DutyCheck.no('That duty has already started.');
    }
    final after = {...overrides, slot.key: uid};
    return checkWorking(uid, slot, after: after, others: others);
  }

  /// [a] and [b] exchange the duties [slotA] (now [a]'s) and [slotB] (now
  /// [b]'s). Both new assignments are checked before either is applied.
  DutyCheck checkSwap(
    String a,
    DutySlot slotA,
    String b,
    DutySlot slotB,
    DateTime now, {
    List<BusyInterval> othersA = const [],
    List<BusyInterval> othersB = const [],
  }) {
    if (a == b) return const DutyCheck.no('Pick another physician.');
    if (slotA == slotB) return const DutyCheck.no('Pick a different duty.');
    final nowInstant = IstClock.toInstant(now);
    if (!slotA.start.isAfter(nowInstant) || !slotB.start.isAfter(nowInstant)) {
      return const DutyCheck.no('A duty in the swap has already started.');
    }
    if (assigneeOf(slotA) != a || assigneeOf(slotB) != b) {
      return const DutyCheck.no('The duties have changed. Please start again.');
    }
    final after = {...overrides, slotA.key: b, slotB.key: a};
    final forB = checkWorking(b, slotA, after: after, others: othersB);
    if (!forB.ok) return forB;
    return checkWorking(a, slotB, after: after, others: othersA);
  }

  /// Hours a physician is scheduled in the month of [monthStart].
  int hoursIn(String uid, DateTime monthStart) {
    final last = DateTime.utc(monthStart.year, monthStart.month + 1, 0);
    return dutiesOf(uid, monthStart, last)
        .fold(0, (t, s) => t + s.shift.hours);
  }
}
