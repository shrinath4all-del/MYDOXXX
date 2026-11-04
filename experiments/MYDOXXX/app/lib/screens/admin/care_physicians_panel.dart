import '../../services/app_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../utils/safe_cast.dart';
import 'package:flutter/material.dart';

import '../../services/care_physician_service.dart';
import '../../services/verification_service.dart';
import '../../widgets/admin_verification_review_dialog.dart';
import '../../widgets/document_viewer_screen.dart';
import '../../theme/app_theme.dart';
import '../../utils/error_messages.dart';
import '../../constants/app_colors.dart';

/// Admin: care physicians. Approving checks the medical registration number
/// against the council register and unlocks ICU / procedure-gated shifts.
/// A care physician suspended after repeated no-shows can be cleared here.
class CarePhysiciansPanel extends StatefulWidget {
  const CarePhysiciansPanel({super.key});

  @override
  State<CarePhysiciansPanel> createState() => _CarePhysiciansPanelState();
}

class _CarePhysiciansPanelState extends State<CarePhysiciansPanel> {
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _stream =
      AppDatabase.instance
          .collection(CarePhysicianService.collection)
          .snapshots();
  bool _pendingOnly = true;

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? AppColors.danger : AppColors.successDark,
    ));
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    try {
      await action();
      _snack(done);
    } catch (e) {
      _snack(ErrorMessages.of(e, action: 'update the care physician'),
          error: true);
    }
  }

  /// Approve only when every required document has been approved
  /// (Documents → approve each file first).
  Future<void> _approve(Map<String, dynamic> p) async {
    try {
      final blocking = await VerificationService.approveProvider(
          role: 'care_physician', uid: p['uid'].toString());
      if (blocking.isEmpty) {
        _snack('Care physician verified.');
      } else {
        _snack('Approve these documents first: ${blocking.join(', ')}',
            error: true);
      }
    } catch (e) {
      _snack(ErrorMessages.of(e, action: 'verify the care physician'),
          error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _stream,
      builder: (context, snap) {
        if (snap.hasError) {
          return LoadErrorView(error: snap.error, what: 'care physicians');
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final all = [
          for (final d in snap.data!.docs) {...d.data(), 'uid': d.id}
        ]..sort((a, b) => (a['name'] ?? '')
            .toString()
            .toLowerCase()
            .compareTo((b['name'] ?? '').toString().toLowerCase()));
        final list = _pendingOnly
            ? all.where((p) => p['isVerified'] != true).toList()
            : all;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            Row(children: [
              ChoiceChip(
                label: Text(
                    'Pending (${all.where((p) => p['isVerified'] != true).length})'),
                selected: _pendingOnly,
                onSelected: (_) => setState(() => _pendingOnly = true),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: Text('All (${all.length})'),
                selected: !_pendingOnly,
                onSelected: (_) => setState(() => _pendingOnly = false),
              ),
            ]),
            const SizedBox(height: 6),
            const Text(
                'Check the registration number on the medical council register before approving. Approved care physicians can claim ICU shifts and verified-only services.',
                style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
            const SizedBox(height: 12),
            if (list.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 40),
                child: Center(child: Text('Nobody waiting for verification.')),
              ),
            for (final p in list) _card(p),
          ],
        );
      },
    );
  }

  Widget _card(Map<String, dynamic> p) {
    final verified = p['isVerified'] == true;
    final noShows = toNum(p['noShows'])?.toInt() ?? 0;
    final procedures = CarePhysicianService.listOf(p['procedures']);
    final gated = CarePhysicianService.gatedOf(procedures);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: verified ? AppColors.successLight : AppColors.lineStrong),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text((p['name'] ?? 'Care physician').toString(),
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.darkNavy)),
            ),
            Text(verified ? 'VERIFIED' : 'PENDING',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: verified
                        ? AppColors.successDeep
                        : AppColors.orange)),
          ]),
          const SizedBox(height: 4),
          Text(
              [
                (p['qualification'] ?? '').toString(),
                'Reg ${p['regNo'] ?? '—'}',
                '${p['experienceYears'] ?? 0} yrs',
                (p['phone'] ?? p['mobileNumber'] ?? '').toString(),
              ].where((e) => e.isNotEmpty).join(' · '),
              style: const TextStyle(fontSize: 13)),
          if (gated.isNotEmpty)
            Text(
                'Claims verified-only services: ${CarePhysicianService.procedureLabels(gated)}',
                style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
          if (noShows >= CarePhysicianService.maxNoShows)
            const Text('Claiming paused after repeated no-shows',
                style: TextStyle(fontSize: 12, color: AppColors.danger)),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => AdminVerificationReviewDialog(
                    role: 'care_physician',
                    uid: p['uid'].toString(),
                    providerName: (p['name'] ?? 'Care physician').toString(),
                    onViewFile: (title, url) => DocumentViewerScreen.open(
                        context,
                        url: url,
                        title: title),
                  ),
                ),
                icon: const Icon(Icons.description_outlined, size: 18),
                label: const Text('Documents'),
                style:
                    OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
              ),
              ElevatedButton(
                onPressed: () => verified
                    ? _run(
                        () => CarePhysicianService.setVerified(
                            p['uid'].toString(), false),
                        'Verification revoked.')
                    : _approve(p),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      verified ? AppColors.danger : AppColors.successDark,
                  minimumSize: const Size(100, 40),
                ),
                child: Text(verified ? 'Revoke' : 'Approve'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
