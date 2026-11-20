import '../models/care_duty_roster.dart';
import 'care_duty_service.dart';

/// One care physician working one duty on one day, as the agency's calendar
/// shows it.
class AgencyDuty {
  final String uid;
  final String name;
  final String hospital;

  /// 'locum' (a hospital shift) or 'full' (a full-time team duty).
  final String kind;

  /// ward, icu, casualty or specialty ('' for a full-time team duty).
  final String dutyType;

  /// morning, afternoon or night.
  final String part;
  const AgencyDuty({
    required this.uid,
    required this.name,
    required this.hospital,
    required this.kind,
    required this.dutyType,
    required this.part,
  });
}

/// One care physician on leave from one duty.
class AgencyLeave {
  final String uid;
  final String name;
  final String hospital;
  final String shiftLabel;

  /// Who covers the duty ('' while a relief physician is being found).
  final String coveredBy;
  const AgencyLeave({
    required this.uid,
    required this.name,
    required this.hospital,
    required this.shiftLabel,
    required this.coveredBy,
  });
}

/// Which duties fall on a day, for the agency's Bookings and Calendar.
class AgencyDayDuties {
  AgencyDayDuties._();

  static const List<String> parts = ['morning', 'afternoon', 'night'];
  static const List<String> dutyTypes = ['icu', 'ward', 'casualty', 'specialty'];

  static String partLabel(String p) => switch (p) {
        'morning' => 'Morning',
        'afternoon' => 'Afternoon',
        _ => 'Night',
      };

  static String dutyLabel(String d) => switch (d) {
        'icu' => 'ICU duty',
        'ward' => 'Ward duty',
        'casualty' => 'Casualty',
        _ => 'Speciality',
      };

  /// A shift's slot key (morning, evening, night) as the day part.
  static String partOf(String? slot) => switch (slot) {
        'morning' => 'morning',
        'evening' => 'afternoon',
        _ => 'night',
      };

  /// The locum shifts on [day] that a care physician took.
  static List<AgencyDuty> locums(
      Iterable<Map<String, dynamic>> shifts, DateTime day) {
    final key = DutySlot.dateKey(day);
    return [
      for (final s in shifts)
        if (s['date'] == key &&
            const {'claimed', 'on_duty', 'completed'}.contains(s['status']) &&
            (s['claimedBy'] ?? '').toString().isNotEmpty)
          AgencyDuty(
            uid: s['claimedBy'].toString(),
            name: (s['claimedByName'] ?? 'Care physician').toString(),
            hospital: (s['hospitalName'] ?? '').toString(),
            kind: 'locum',
            dutyType: (s['dutyType'] ?? '').toString(),
            part: partOf(s['slot']?.toString()),
          )
    ];
  }

  /// The full-time team duties on [day].
  static List<AgencyDuty> fullTime(
      Iterable<Map<String, dynamic>> teams, DateTime day) {
    final out = <AgencyDuty>[];
    for (final t in teams) {
      if (t['status'] != 'active') continue;
      final roster = CareDutyService.rosterOf(t);
      for (final slot in roster.slotsOn(day)) {
        final uid = roster.assigneeOf(slot);
        if (uid.isEmpty) continue;
        out.add(AgencyDuty(
          uid: uid,
          name: CareDutyService.assigneeName(t, slot),
          hospital: (t['hospitalName'] ?? '').toString(),
          kind: 'full',
          dutyType: (t['dutyType'] ?? '').toString(),
          part: switch (slot.shift) {
            DutyShift.morning => 'morning',
            DutyShift.evening => 'afternoon',
            DutyShift.night => 'night',
          },
        ));
      }
    }
    return out;
  }

  /// Everything on [day].
  static List<AgencyDuty> all(Iterable<Map<String, dynamic>> shifts,
          Iterable<Map<String, dynamic>> teams, DateTime day) =>
      [...locums(shifts, day), ...fullTime(teams, day)];

  /// The care physicians on leave on [day]: leave the hospital has approved
  /// (or that was covered), from a duty on that date. A request still waiting
  /// for the hospital, declined or withdrawn is not leave.
  static List<AgencyLeave> leaves(
      Iterable<Map<String, dynamic>> requests, DateTime day) {
    final key = DutySlot.dateKey(day);
    final out = <AgencyLeave>[];
    for (final r in requests) {
      if (r['type'] != 'leave') continue;
      final status = (r['status'] ?? '').toString();
      if (status != 'accepted' && status != 'pending') continue;
      final slot = DutySlot.parse((r['sourceKey'] ?? '').toString());
      if (slot == null || DutySlot.dateKey(slot.date) != key) continue;
      out.add(AgencyLeave(
        uid: (r['requesterUid'] ?? '').toString(),
        name: (r['requesterName'] ?? 'Care physician').toString(),
        hospital: (r['hospitalName'] ?? '').toString(),
        shiftLabel: '${slot.shift.label} duty',
        coveredBy:
            status == 'accepted' ? (r['acceptedByName'] ?? '').toString() : '',
      ));
    }
    return out;
  }

  /// How many different care physicians work.
  static int people(Iterable<AgencyDuty> duties) =>
      duties.map((d) => d.uid).toSet().length;
}
