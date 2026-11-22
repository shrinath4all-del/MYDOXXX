import '../models/care_duty_roster.dart';
import 'nurse_duty_service.dart';

/// One nurse working one duty on one day, as the agency's calendar
/// shows it.
class NurseAgencyDuty {
  final String uid;
  final String name;
  final String hospital;

  /// 'locum' (a hospital shift) or 'full' (a full-time team duty).
  final String kind;

  /// ward, icu, casualty or specialty ('' for a full-time team duty).
  final String dutyType;

  /// morning, afternoon or night.
  final String part;
  const NurseAgencyDuty({
    required this.uid,
    required this.name,
    required this.hospital,
    required this.kind,
    required this.dutyType,
    required this.part,
  });
}

/// One nurse on leave from one duty.
class NurseAgencyLeave {
  final String uid;
  final String name;
  final String hospital;
  final String shiftLabel;

  /// Who covers the duty ('' while a relief physician is being found).
  final String coveredBy;
  const NurseAgencyLeave({
    required this.uid,
    required this.name,
    required this.hospital,
    required this.shiftLabel,
    required this.coveredBy,
  });
}

/// Which duties fall on a day, for the agency's Bookings and Calendar.
class NurseAgencyDayDuties {
  NurseAgencyDayDuties._();

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

  /// The locum shifts on [day] that a nurse took.
  static List<NurseAgencyDuty> locums(
      Iterable<Map<String, dynamic>> shifts, DateTime day) {
    final key = DutySlot.dateKey(day);
    return [
      for (final s in shifts)
        if (s['date'] == key &&
            const {'claimed', 'on_duty', 'completed'}.contains(s['status']) &&
            (s['claimedBy'] ?? '').toString().isNotEmpty)
          NurseAgencyDuty(
            uid: s['claimedBy'].toString(),
            name: (s['claimedByName'] ?? 'Nurse').toString(),
            hospital: (s['hospitalName'] ?? '').toString(),
            kind: 'locum',
            dutyType: (s['dutyType'] ?? '').toString(),
            part: partOf(s['slot']?.toString()),
          )
    ];
  }

  /// The full-time team duties on [day].
  static List<NurseAgencyDuty> fullTime(
      Iterable<Map<String, dynamic>> teams, DateTime day) {
    final out = <NurseAgencyDuty>[];
    for (final t in teams) {
      if (t['status'] != 'active') continue;
      final roster = NurseDutyService.rosterOf(t);
      for (final slot in roster.slotsOn(day)) {
        final uid = roster.assigneeOf(slot);
        if (uid.isEmpty) continue;
        out.add(NurseAgencyDuty(
          uid: uid,
          name: NurseDutyService.assigneeName(t, slot),
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
  static List<NurseAgencyDuty> all(Iterable<Map<String, dynamic>> shifts,
          Iterable<Map<String, dynamic>> teams, DateTime day) =>
      [...locums(shifts, day), ...fullTime(teams, day)];

  /// The nurses on leave on [day]: leave the hospital has approved
  /// (or that was covered), from a duty on that date. A request still waiting
  /// for the hospital, declined or withdrawn is not leave.
  static List<NurseAgencyLeave> leaves(
      Iterable<Map<String, dynamic>> requests, DateTime day) {
    final key = DutySlot.dateKey(day);
    final out = <NurseAgencyLeave>[];
    for (final r in requests) {
      if (r['type'] != 'leave') continue;
      final status = (r['status'] ?? '').toString();
      if (status != 'accepted' && status != 'pending') continue;
      final slot = DutySlot.parse((r['sourceKey'] ?? '').toString());
      if (slot == null || DutySlot.dateKey(slot.date) != key) continue;
      out.add(NurseAgencyLeave(
        uid: (r['requesterUid'] ?? '').toString(),
        name: (r['requesterName'] ?? 'Nurse').toString(),
        hospital: (r['hospitalName'] ?? '').toString(),
        shiftLabel: '${slot.shift.label} duty',
        coveredBy:
            status == 'accepted' ? (r['acceptedByName'] ?? '').toString() : '',
      ));
    }
    return out;
  }

  /// How many different nurses work.
  static int people(Iterable<NurseAgencyDuty> duties) =>
      duties.map((d) => d.uid).toSet().length;
}
