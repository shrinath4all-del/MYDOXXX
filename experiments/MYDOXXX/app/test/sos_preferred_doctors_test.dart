import 'package:flutter_test/flutter_test.dart';
import 'package:mydox/services/firestore_service.dart';

void main() {
  test('urgent Cardiologist specialty matches itself after normalization', () {
    expect(
        FirestoreService.isDoctorSpecialtyMatching(
            'Cardiologist', 'Cardiologist'),
        isTrue);
    expect(
        FirestoreService.isDoctorSpecialtyMatching(
            ' CARDIOLOGIST ', 'cardiologist'),
        isTrue);
  });

  test('cardiology preference follows cardiac SOS without widening other SOS',
      () {
    expect(
        FirestoreService.preferredDoctorsForEmergency({
          'Cardiologist': ['cardio1'],
          'Orthopedic': ['unrelated']
        }, 'Cardiac / Chest pain'),
        ['cardio1']);
    for (final emergency in [
      'Something else',
      'Chest / Breathing',
      'Ortho / Trauma',
      'Pregnancy / Obstetrics'
    ]) {
      expect(
          FirestoreService.isDoctorSpecialtyMatching('Cardiologist', emergency),
          isFalse,
          reason: emergency);
    }
    expect(
        FirestoreService.isDoctorSpecialtyMatching(
            'General Physician', 'Cardiac / Chest pain'),
        isTrue,
        reason: 'The existing SOS category rule is unchanged.');
  });

  test('Something else resolves General Physician hospital preference', () {
    expect(
        FirestoreService.preferredDoctorsForEmergency({
          'General Physician': ['doctor1'],
          'Orthopedic': ['unrelated']
        }, 'Something else'),
        ['doctor1']);
  });

  test('symptom labels preserve exact preferences and remove duplicates', () {
    expect(
        FirestoreService.preferredDoctorsForEmergency({
          ' SOMETHING ELSE ': ['doctor1', ''],
          'general physician': ['doctor1', 'doctor2']
        }, 'Something else'),
        ['doctor1', 'doctor2']);
  });

  test('trauma uses same specialty mapping as candidate eligibility', () {
    final preferences = {
      'General Physician': ['general'],
      'Bones & Joints - Orthopedic': ['ortho'],
      'Trauma Specialist': ['trauma'],
      'Gynecologist': ['gynae']
    };
    expect(
        FirestoreService.preferredDoctorsForEmergency(
            preferences, 'Ortho / Trauma'),
        ['ortho', 'trauma']);
    for (final entry in preferences.entries) {
      final matches = FirestoreService.isDoctorSpecialtyMatching(
          entry.key, 'Ortho / Trauma');
      expect(
          FirestoreService.preferredDoctorsForEmergency(
                  preferences, 'Ortho / Trauma')
              .contains(entry.value.single),
          matches);
    }
  });

  test('empty or absent preference does not widen eligibility', () {
    expect(
        FirestoreService.preferredDoctorsForEmergency(null, 'Something else'),
        isEmpty);
    expect(
        FirestoreService.preferredDoctorsForEmergency({
          '': ['unknown'],
          'Orthopedic': ['unrelated']
        }, 'Something else'),
        isEmpty);
    expect(
        FirestoreService.preferredDoctorsForEmergency({
          'General Physician': ['doctor1']
        }, ''),
        isEmpty);
  });
}
