import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mydox/services/care_agency_service.dart';
import 'package:mydox/services/technician_staffing_service.dart';
import 'package:mydox/utils/lab_test_groups.dart';
import 'package:mydox/widgets/agency_type_picker.dart';

void main() {
  group('technician flow (the care physician flow for technicians)', () {
    test('duties are named for technicians', () {
      expect(TechnicianStaffingService.dutyLabel('ward'), 'Lab duty');
      expect(TechnicianStaffingService.dutyLabel('home'),
          'Home sample collection');
      expect(TechnicianStaffingService.dutyLabel('specialty'),
          'Department duty');
      expect(TechnicianStaffingService.specialtyLabel('radiology'),
          'X-Ray / Imaging');
    });

    test('technician qualifications, not nursing ones', () {
      final q = TechnicianStaffingService.qualifications.keys;
      expect(q, containsAll(['DMLT', 'BMLT', 'DRT']));
      expect(q.any((k) => k.contains('GNM') || k.contains('ANM')), isFalse);
    });

    test('skills are lab tests, keyed by the names patients book', () {
      // until the lab tests are read, the common ones are shown
      final p = TechnicianStaffingService.procedures;
      expect(p.keys, containsAll(['EEG', 'NCS', 'EMG', 'ECG']));
      expect(p['ECG']!.$2, 'ECG');
      expect(p.values.any((v) => v.$3), isFalse,
          reason: 'no test is locked behind verification');
    });

    test('neuro tests come first, under Neuro technician', () {
      final groups = TechnicianStaffingService.groupedProcedures();
      expect(groups.first.$1, LabTestGroups.neuro);
      expect(groups.first.$2, containsAll(['EEG', 'NCS', 'EMG']));
      expect(LabTestGroups.technicianLabels[LabTestGroups.neuro],
          'Neuro technician');
    });

    test('technician partners have their own type and shifts', () {
      expect(CareAgencyService.agencyTypeTechnician, 'technician');
      expect(TechnicianStaffingService.collection, 'technicians');
      expect(TechnicianStaffingService.shiftsCol, 'technician_shifts');
    });
  });

  testWidgets('a technician partner can be chosen', (tester) async {
    String? picked;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: AgencyTypePicker(
              value: CareAgencyService.agencyTypeCare,
              onChanged: (v) => picked = v),
        ),
      ),
    ));
    await tester.tap(find.text('Technician partner'));
    expect(picked, 'technician');
  });
}
