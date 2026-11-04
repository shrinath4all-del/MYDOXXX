import 'care_physician_service.dart';
import '../utils/display_names.dart';

/// Notifications for logins without patient bookings (hospital, ambulance,
/// care physician). Each item is {kind, title, body, at}, newest first, the
/// same shape the bell shows for bookings.
class RoleNotifications {
  RoleNotifications._();

  static String _s(Object? v) => (v ?? '').toString();

  static void _add(List<Map<String, String>> out, String kind, String title,
      String body, Object? at) {
    final when = _s(at);
    if (when.isEmpty) return;
    out.add({'kind': kind, 'title': title, 'body': body, 'at': when});
  }

  static List<Map<String, String>> _newestFirst(
          List<Map<String, String>> list) =>
      list..sort((a, b) => b['at']!.compareTo(a['at']!));

  /// SOS emergencies this hospital accepted.
  static List<Map<String, String>> hospitalSos(
      List<Map<String, dynamic>> sos, String hospitalUid) {
    final out = <Map<String, String>>[];
    for (final a in sos) {
      if (a['assignedHospitalUid'] != hospitalUid) continue;
      final patient = _s(a['patientName']).isEmpty ? 'Patient' : _s(a['patientName']);
      final what = _s(a['emergencyCategory'] ?? a['doctorCategory']);
      _add(out, 'accepted', 'Emergency accepted', '$patient · $what',
          a['hospitalAcceptedAt']);
      _add(out, 'request', 'Ambulance on the way', patient,
          a['ambulanceDispatchedAt']);
      _add(out, 'started', 'Patient picked up', '$patient is coming in',
          a['ambulancePickedUpAt']);
      _add(out, 'completed', 'Patient arrived', patient, a['hospitalReachedAt']);
      if (a['status'] == 'Completed') {
        _add(out, 'completed', 'Emergency closed', patient, a['completedAt']);
      }
    }
    return _newestFirst(out);
  }

  /// Dispatches given to this ambulance.
  static List<Map<String, String>> ambulanceSos(
      List<Map<String, dynamic>> sos, String ambulanceUid) {
    final out = <Map<String, String>>[];
    for (final a in sos) {
      if (a['assignedAmbulanceUid'] != ambulanceUid) continue;
      final patient = _s(a['patientName']).isEmpty ? 'Patient' : _s(a['patientName']);
      final area = _s(a['locationName']);
      _add(out, 'request', 'New dispatch',
          area.isEmpty ? patient : '$patient · $area', a['ambulanceDispatchedAt']);
      _add(out, 'started', 'Patient picked up', patient, a['ambulancePickedUpAt']);
      _add(out, 'completed', 'Patient handed over',
          _s(a['assignedHospitalName']).isEmpty
              ? patient
              : '$patient · ${a['assignedHospitalName']}',
          a['hospitalReachedAt']);
    }
    return _newestFirst(out);
  }

  /// Care physicians booked for the hospital's posted shifts.
  static List<Map<String, String>> hospitalShifts(
      List<Map<String, dynamic>> shifts, DateTime now) {
    final out = <Map<String, String>>[];
    for (final s in shifts) {
      final doctor = DisplayNames.doctor(_s(s['claimedByName']));
      final when = '${CarePhysicianService.dayLabel(s, now)} · '
          '${CarePhysicianService.timeRange(s)}';
      _add(out, 'booked', 'Care physician booked', '$doctor · $when',
          s['claimedAt']);
      _add(out, 'started', '$doctor is on duty', when, s['checkInAt']);
      if (s['status'] == 'cancelled') {
        _add(out, 'declined', 'Shift cancelled', when, s['cancelledAt']);
      }
    }
    return _newestFirst(out);
  }

  /// Shifts the care physician booked.
  static List<Map<String, String>> carePhysicianShifts(
      List<Map<String, dynamic>> shifts, DateTime now) {
    final out = <Map<String, String>>[];
    for (final s in shifts) {
      final hospital = _s(s['posterName']).isEmpty ? 'Hospital' : _s(s['posterName']);
      final when = '${CarePhysicianService.dayLabel(s, now)} · '
          '${CarePhysicianService.timeRange(s)}';
      _add(out, 'booked', 'Shift booked at $hospital', when, s['claimedAt']);
      _add(out, 'started', 'Checked in at $hospital', when, s['checkInAt']);
      if (s['status'] == 'cancelled') {
        _add(out, 'declined', 'Shift at $hospital cancelled', when,
            s['cancelledAt']);
      }
    }
    return _newestFirst(out);
  }
}
