import '../services/app_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/verification_service.dart';
import '../theme/app_theme.dart';
import '../utils/stream_cache.dart';
import '../constants/app_colors.dart';

/// Admin review of one provider's verification documents. Each document is
/// approved or rejected individually; the provider can only be approved
/// (made bookable) once every mandatory document is uploaded and approved.
class AdminVerificationReviewDialog extends StatefulWidget {
  final String role;
  final String uid;
  final String providerName;
  final void Function(String title, String url) onViewFile;

  const AdminVerificationReviewDialog({
    super.key,
    required this.role,
    required this.uid,
    required this.providerName,
    required this.onViewFile,
  });

  @override
  State<AdminVerificationReviewDialog> createState() =>
      _AdminVerificationReviewDialogState();
}

class _AdminVerificationReviewDialogState
    extends State<AdminVerificationReviewDialog> {
  // Live data connections kept open across redraws
  final StreamCache _streams = StreamCache();

  VerificationRequirementSet? _reqs;
  bool _loadingReqs = true;
  String _reqKey = '';
  final Set<String> _busy = {};
  bool _approving = false;

  void _ensureRequirements(Map<String, dynamic> profile) {
    final key = '${profile['category']}|${profile['qualification']}';
    if (key == _reqKey) return;
    _reqKey = key;
    VerificationService.getRequirementsFor(widget.role, profile).then((r) {
      if (!mounted) return;
      setState(() {
        _reqs = r;
        _loadingReqs = false;
      });
    });
  }

  Future<void> _review(
      VerificationDocRequirement req, String url, bool approve) async {
    String? reason;
    if (!approve) {
      final controller = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Reject: ${req.label}'),
          content: TextField(
            controller: controller,
            maxLines: 2,
            decoration: const InputDecoration(
              hintText: 'Reason shown to the provider (e.g. image unclear)',
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Reject'),
            ),
          ],
        ),
      );
      if (ok != true) return;
      reason = controller.text;
    }

    setState(() => _busy.add(req.key));
    try {
      await VerificationService.reviewDocument(
        role: widget.role,
        uid: widget.uid,
        requirement: req,
        url: url,
        approve: approve,
        rejectReason: reason,
      );
    } finally {
      if (mounted) setState(() => _busy.remove(req.key));
    }
  }

  Future<void> _setProviderVerified(bool approve) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _approving = true);
    try {
      if (approve) {
        final blocking = await VerificationService.approveProvider(
            role: widget.role, uid: widget.uid);
        messenger.showSnackBar(SnackBar(
          content: Text(blocking.isEmpty
              ? '${widget.providerName} approved. Profile is now bookable.'
              : 'Cannot approve yet. Pending: ${blocking.join(', ')}'),
          backgroundColor:
              blocking.isEmpty ? AppColors.successDark : AppColors.orange,
        ));
      } else {
        await VerificationService.revokeProvider(
            role: widget.role, uid: widget.uid);
        messenger.showSnackBar(SnackBar(
          content: Text('${widget.providerName} is no longer bookable.'),
          backgroundColor: AppColors.orange,
        ));
      }
    } finally {
      if (mounted) setState(() => _approving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _streams.get('profile', () => AppDatabase.instance
            .collection(VerificationService.collectionForRole(widget.role))
            .doc(widget.uid)
            .snapshots()),
        builder: (context, snap) {
          final profile = snap.data?.data() ?? {};
          if (snap.hasData) _ensureRequirements(profile);
          final isVerified = profile['isVerified'] == true;
          final reqs = _reqs;
          final blocking = reqs == null
              ? <VerificationDocRequirement>[]
              : VerificationService.blockingDocuments(reqs, profile);

          return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Verification: ${widget.providerName}',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                if (reqs != null)
                  Text(
                    '${reqs.title} • ${isVerified ? 'VERIFIED (bookable)' : 'NOT BOOKABLE'}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isVerified
                          ? AppColors.successDeep
                          : AppColors.warningDeep,
                    ),
                  ),
                const SizedBox(height: 12),
                Flexible(
                  child: !snap.hasData || (_loadingReqs && reqs == null)
                      ? const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      : reqs == null
                          ? Text(
                              'No document requirements configured for "${widget.role}". '
                              'Add them in Firestore → ${VerificationService.requirementsCollection}.',
                              style: const TextStyle(color: AppColors.danger),
                            )
                          : ListView(
                              shrinkWrap: true,
                              children: reqs.documents
                                  .map((r) => _docTile(r, profile))
                                  .toList(),
                            ),
                ),
                const SizedBox(height: 12),
                if (!isVerified && reqs != null && blocking.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Approve each mandatory (*) document to enable approval. Pending: ${blocking.length}',
                      style: const TextStyle(
                          fontSize: 11, color: AppTheme.textMuted),
                    ),
                  ),
                ElevatedButton.icon(
                  onPressed: _approving ||
                          reqs == null ||
                          (!isVerified && blocking.isNotEmpty)
                      ? null
                      : () => _setProviderVerified(!isVerified),
                  icon: Icon(isVerified
                      ? Icons.block_rounded
                      : Icons.verified_rounded),
                  label: Text(isVerified
                      ? 'Revoke (make not bookable)'
                      : 'Approve provider (make bookable)'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        isVerified ? AppColors.danger : AppColors.successDark,
                    iconColor: Colors.white,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 46),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _docTile(VerificationDocRequirement req, Map<String, dynamic> profile) {
    final state = VerificationService.docState(profile, req);
    final busy = _busy.contains(req.key);

    final (String text, Color fg, Color bg) = switch (state.status) {
      DocReviewStatus.missing => (
          req.mandatory ? 'Missing' : 'Not uploaded',
          req.mandatory ? AppColors.danger : AppTheme.textMuted,
          req.mandatory ? AppColors.dangerSoft : AppColors.chip
        ),
      DocReviewStatus.pending => (
          'To review',
          AppColors.warningDeep,
          AppColors.orangeTint
        ),
      DocReviewStatus.approved => (
          'Approved ✔',
          AppColors.successDeep,
          AppColors.successTint
        ),
      DocReviewStatus.rejected => (
          'Rejected',
          AppColors.danger,
          AppColors.dangerSoft
        ),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.bgLight,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  req.mandatory ? '${req.label} *' : '${req.label} (optional)',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.darkNavy),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                    color: bg, borderRadius: BorderRadius.circular(10)),
                child: Text(text,
                    style: TextStyle(
                        fontSize: 10, fontWeight: FontWeight.bold, color: fg)),
              ),
            ],
          ),
          if (state.status == DocReviewStatus.rejected &&
              (state.rejectReason ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Reason: ${state.rejectReason}',
                  style:
                      const TextStyle(fontSize: 11, color: AppColors.danger)),
            ),
          if (state.url != null) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                OutlinedButton.icon(
                  onPressed: () => widget.onViewFile(req.label, state.url!),
                  icon: const Icon(Icons.visibility_rounded, size: 16),
                  label: const Text('View'),
                  style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 34),
                      padding: const EdgeInsets.symmetric(horizontal: 10)),
                ),
                if (state.status != DocReviewStatus.approved)
                  ElevatedButton(
                    onPressed:
                        busy ? null : () => _review(req, state.url!, true),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.successDark,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(0, 34),
                        padding: const EdgeInsets.symmetric(horizontal: 12)),
                    child: const Text('Approve'),
                  ),
                if (state.status != DocReviewStatus.rejected)
                  OutlinedButton(
                    onPressed:
                        busy ? null : () => _review(req, state.url!, false),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.danger,
                        minimumSize: const Size(0, 34),
                        padding: const EdgeInsets.symmetric(horizontal: 12)),
                    child: const Text('Reject'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
