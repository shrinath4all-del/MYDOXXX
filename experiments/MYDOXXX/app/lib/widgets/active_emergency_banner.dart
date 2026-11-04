import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_strings.dart';

/// Blinking red "Emergency in progress" button on the patient home while an
/// SOS is still running (after its tracker window was closed). Tapping it
/// opens the raised emergency again.
class ActiveEmergencyBanner extends StatefulWidget {
  final String status;
  final VoidCallback onTap;

  const ActiveEmergencyBanner(
      {super.key, required this.status, required this.onTap});

  @override
  State<ActiveEmergencyBanner> createState() => _ActiveEmergencyBannerState();
}

class _ActiveEmergencyBannerState extends State<ActiveEmergencyBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _blink = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${AppStrings.emergencyActive}. ${AppStrings.emergencyActiveHint}',
      child: AnimatedBuilder(
        animation: _blink,
        builder: (context, child) => Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            // the glow pulses so it catches the eye
            boxShadow: [
              BoxShadow(
                color: AppColors.danger
                    .withValues(alpha: 0.25 + 0.35 * _blink.value),
                blurRadius: 8 + 10 * _blink.value,
                spreadRadius: 1 + 2 * _blink.value,
              ),
            ],
          ),
          child: child,
        ),
        child: Material(
          color: AppColors.danger,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: widget.onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  FadeTransition(
                    opacity: Tween(begin: 0.35, end: 1.0).animate(_blink),
                    child: const Icon(Icons.emergency_rounded,
                        color: Colors.white, size: 28),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(AppStrings.emergencyActive,
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 15)),
                        const SizedBox(height: 2),
                        Text(
                          widget.status.isEmpty
                              ? AppStrings.emergencyActiveHint
                              : '${widget.status} · ${AppStrings.emergencyActiveHint}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: Colors.white),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
