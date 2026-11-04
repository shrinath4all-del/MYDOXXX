import 'package:flutter/material.dart';

import '../services/care_agency_service.dart';
import '../theme/app_theme.dart';
import '../constants/app_colors.dart';

/// Admin, add agency: care physician agency or physio agency. Two option cards
/// stacked vertically, so they fit any screen width.
class AgencyTypePicker extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const AgencyTypePicker(
      {super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => Column(
        children: [
          _option(
            CareAgencyService.agencyTypeCare,
            Icons.medical_services_outlined,
            'Care physician agency',
            'You place doctors in hospitals (permanent, locum, emergency locum) and run duties, attendance and payouts from the Control Room.',
          ),
          const SizedBox(height: 8),
          _option(
            CareAgencyService.agencyTypeNurse,
            Icons.local_hospital_outlined,
            'Nurse agency',
            'You place nurses in hospitals (locum shifts and full-time teams) and see their duties, attendance and earnings.',
          ),
          const SizedBox(height: 8),
          _option(
            CareAgencyService.agencyTypeTechnician,
            Icons.biotech_outlined,
            'Technician partner',
            'You place lab, X-Ray, ECG, EEG and OT technicians in hospitals (locum shifts and full-time teams) and see their duties, attendance and earnings.',
          ),
          const SizedBox(height: 8),
          _option(
            CareAgencyService.agencyTypePhysio,
            Icons.self_improvement_rounded,
            'Physio agency',
            'Your physios get home-visit requests in your areas first. The admin sets your areas.',
          ),
        ],
      );

  Widget _option(String type, IconData icon, String title, String text) {
    final selected = value == type;
    return Material(
      color: selected ? AppTheme.pastelBlue : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
            color: selected ? AppTheme.primaryTeal : AppColors.lineStrong,
            width: selected ? 1.6 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => onChanged(type),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon,
                  color: selected ? AppTheme.primaryTeal : AppTheme.textMuted),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: selected
                                ? AppTheme.primaryTeal
                                : AppTheme.darkNavy)),
                    const SizedBox(height: 2),
                    Text(text,
                        style: const TextStyle(
                            fontSize: 12, color: AppTheme.textMuted)),
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.check_box_rounded
                    : Icons.check_box_outline_blank_rounded,
                color: selected ? AppTheme.primaryTeal : AppColors.muted,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
