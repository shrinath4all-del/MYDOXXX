import 'package:flutter/material.dart';

import '../../../services/care_physician_service.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/error_messages.dart';
import '../../../utils/responsive.dart';
import 'physician_photo.dart';

typedef _Cp = CarePhysicianService;

/// A care physician's profile, as the agency sees it (read only).
class CareDoctorProfileScreen extends StatelessWidget {
  final String uid;
  final String name;
  const CareDoctorProfileScreen({super.key, required this.uid, this.name = ''});

  /// Opens the profile; does nothing if the physician is not known.
  static void open(BuildContext context, String? uid, {String name = ''}) {
    if (uid == null || uid.isEmpty) return;
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => CareDoctorProfileScreen(uid: uid, name: name)));
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveCenter(
      child: Scaffold(
        backgroundColor: AppTheme.bgLight,
        appBar: AppBar(title: Text(name.isEmpty ? 'Care physician' : name)),
        body: StreamBuilder<Map<String, dynamic>>(
          stream: _Cp.profileStream(uid),
          builder: (context, snap) {
            if (snap.hasError) {
              return Center(
                  child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(ErrorMessages.of(snap.error!,
                    action: 'load the profile')),
              ));
            }
            if (!snap.hasData) {
              return const Center(
                  child:
                      CircularProgressIndicator(color: AppTheme.primaryTeal));
            }
            final p = snap.data!;
            if (p['name'] == null && p['firstName'] == null) {
              return const Center(
                  child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('This care physician has no profile yet.',
                    style: TextStyle(color: AppTheme.textMuted)),
              ));
            }
            return _body(p);
          },
        ),
      ),
    );
  }

  static String _text(dynamic v) => (v ?? '').toString().trim();

  Widget _body(Map<String, dynamic> p) {
    final full = _text(p['name']).isNotEmpty
        ? _text(p['name'])
        : '${_text(p['firstName'])} ${_text(p['lastName'])}'.trim();
    final verified = p['isVerified'] == true;
    final exp = _text(p['experienceYears']).isNotEmpty
        ? '${_text(p['experienceYears'])} years'
        : _text(p['experience']);
    final procedures = _Cp.listOf(p['procedureNames']).isNotEmpty
        ? _Cp.listOf(p['procedureNames'])
        : _Cp.listOf(p['procedures']);
    final rows = <(String, String)>[
      ('Phone', _text(p['phone'] ?? p['mobileNumber'])),
      ('Qualification', _text(p['qualification'])),
      ('Registration no.', _text(p['regNo'])),
      ('Experience', exp),
      ('Agency', _text(p['agencyName']).isEmpty ? 'Freelancer' : _text(p['agencyName'])),
      ('Areas', _Cp.listOf(p['areas']).join(', ')),
      ('Duty types',
          _Cp.listOf(p['dutyTypes']).map(_Cp.dutyLabel).join(', ')),
      ('Specialties', _Cp.listOf(p['specialties']).join(', ')),
      ('Procedures', procedures.join(', ')),
      ('Preferred hospitals', _Cp.listOf(p['preferredHospitals']).join(', ')),
    ].where((r) => r.$2.isNotEmpty).toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Center(
          child: Column(children: [
            PhysicianPhoto(uid: uid, name: name, radius: 40),
            const SizedBox(height: 10),
            Text(full.isEmpty ? name : full,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                    color: AppTheme.darkNavy)),
            const SizedBox(height: 6),
            Chip(
              avatar: Icon(
                  verified ? Icons.verified_rounded : Icons.hourglass_top_rounded,
                  size: 18,
                  color: verified ? Colors.green : Colors.orange),
              label: Text(verified ? 'Verified' : 'Verification pending'),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) Divider(height: 1, color: Colors.grey.shade200),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 130,
                        child: Text(rows[i].$1,
                            style: const TextStyle(
                                color: AppTheme.textMuted, fontSize: 13)),
                      ),
                      Expanded(
                        child: Text(rows[i].$2,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 14)),
                      ),
                    ]),
              ),
            ],
          ]),
        ),
      ],
    );
  }
}
