import '../services/app_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/verification_service.dart';
import '../theme/app_theme.dart';
import 'document_viewer_screen.dart';
import '../utils/error_messages.dart';
import '../constants/app_colors.dart';

/// Provider-side "Verification Documents" card, used on every provider's
/// Edit Profile screen. The document list comes from Firestore
/// (`verification_requirements`) for the provider's role and sub-type, and
/// shows each document's upload + admin review status live.
class VerificationDocumentsSection extends StatefulWidget {
  final String role;
  final String uid;
  final Color accentColor;

  const VerificationDocumentsSection({
    super.key,
    required this.role,
    required this.uid,
    this.accentColor = AppTheme.primaryTeal,
  });

  @override
  State<VerificationDocumentsSection> createState() =>
      _VerificationDocumentsSectionState();
}

class _VerificationDocumentsSectionState
    extends State<VerificationDocumentsSection> {
  VerificationRequirementSet? _requirements;
  bool _loadingRequirements = true;
  String _requirementsKey = '';
  final Set<String> _uploading = {};

  Stream<DocumentSnapshot<Map<String, dynamic>>> get _profileStream =>
      AppDatabase.instance
          .collection(VerificationService.collectionForRole(widget.role))
          .doc(widget.uid)
          .snapshots();

  /// (Re)load requirements when the fields that pick the sub-type change,
  /// e.g. a doctor changing category from General Physician to Dentist.
  void _ensureRequirements(Map<String, dynamic> profile) {
    final key = '${profile['category']}|${profile['qualification']}';
    if (key == _requirementsKey) return;
    _requirementsKey = key;
    VerificationService.getRequirementsFor(widget.role, profile).then((r) {
      if (!mounted) return;
      setState(() {
        _requirements = r;
        _loadingRequirements = false;
      });
    });
  }

  Future<void> _pickAndUpload(VerificationDocRequirement req) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf', 'doc', 'docx'],
      withData: true,
    );
    if (!mounted || result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null && file.path == null) return;

    setState(() => _uploading.add(req.key));
    final messenger = ScaffoldMessenger.of(context);
    try {
      final xFile = file.bytes != null
          ? XFile.fromData(file.bytes!, name: file.name)
          : XFile(file.path!, name: file.name);
      await VerificationService.uploadDocument(
        role: widget.role,
        uid: widget.uid,
        requirement: req,
        file: xFile,
      );
      messenger.showSnackBar(SnackBar(
        content: Text('${req.label} uploaded. Waiting for admin review.'),
        backgroundColor: AppColors.successDark,
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text(ErrorMessages.of(e, action: 'upload the document')),
        backgroundColor: AppColors.danger,
      ));
    } finally {
      if (mounted) setState(() => _uploading.remove(req.key));
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accentColor;
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _profileStream,
      builder: (context, snap) {
        final profile = snap.data?.data() ?? {};
        if (snap.hasData) _ensureRequirements(profile);
        final isVerified = profile['isVerified'] == true;
        final reqs = _requirements;

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: accent.withValues(alpha: 0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.verified_user_rounded, color: accent, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Professional Verification Documents',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.darkNavy,
                      ),
                    ),
                  ),
                  _chip(
                    isVerified ? 'VERIFIED ✓' : 'Pending Admin Verification',
                    isVerified ? AppColors.successDeep : AppColors.warningDeep,
                    isVerified ? AppColors.successTint : AppColors.orangeTint,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              if (!snap.hasData || (_loadingRequirements && reqs == null))
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (reqs == null)
                const Text(
                  'Document requirements for your profile are not set up yet. '
                  'Please contact the admin team.',
                  style: TextStyle(fontSize: 12, color: AppColors.danger),
                )
              else ...[
                if (isVerified)
                  Text(
                    '${reqs.title}: all mandatory documents are verified. Patients can book you.',
                    style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                  )
                else ...[
                  const Text('Document Verification Required',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.darkNavy)),
                  const SizedBox(height: 2),
                  Text(
                    '${reqs.title} must upload all mandatory (*) documents. Your profile will become visible and bookable to patients once the admin approves the required documents.',
                    style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                  ),
                ],
                const SizedBox(height: 14),
                ...reqs.documents.map((r) => _docTile(r, profile)),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _docTile(VerificationDocRequirement req, Map<String, dynamic> profile) {
    final state = VerificationService.docState(profile, req);
    final uploading = _uploading.contains(req.key);
    final accent = widget.accentColor;

    late final String statusText;
    late final Color statusColor;
    late final Color statusBg;
    switch (state.status) {
      case DocReviewStatus.missing:
        statusText = req.mandatory ? 'Required' : 'Optional';
        statusColor = req.mandatory ? AppColors.danger : AppTheme.textMuted;
        statusBg = req.mandatory ? AppColors.dangerSoft : AppColors.chip;
        break;
      case DocReviewStatus.pending:
        statusText = 'Under review';
        statusColor = AppColors.warningDeep;
        statusBg = AppColors.orangeTint;
        break;
      case DocReviewStatus.approved:
        statusText = 'Verified ✓';
        statusColor = AppColors.successDeep;
        statusBg = AppColors.successTint;
        break;
      case DocReviewStatus.rejected:
        statusText = 'Rejected';
        statusColor = AppColors.danger;
        statusBg = AppColors.dangerSoft;
        break;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: state.status == DocReviewStatus.rejected
              ? AppColors.danger
              : state.status == DocReviewStatus.approved
                  ? AppColors.successLight
                  : AppColors.lineStrong,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  req.mandatory ? '${req.label} *' : req.label,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppTheme.darkNavy,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _chip(statusText, statusColor, statusBg),
            ],
          ),
          if (req.description.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(req.description,
                style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
          ],
          if (state.status == DocReviewStatus.rejected &&
              (state.rejectReason ?? '').isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('Admin: ${state.rejectReason}',
                style: const TextStyle(fontSize: 11, color: AppColors.danger)),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              if (state.url != null) ...[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => DocumentViewerScreen.open(context,
                        url: state.url!, title: req.label),
                    icon: Icon(Icons.visibility_rounded, size: 16, color: accent),
                    label: const _ButtonText('View Document'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: accent,
                      iconColor: accent,
                      side: BorderSide(color: accent),
                      minimumSize: const Size(0, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: uploading ? null : () => _pickAndUpload(req),
                  icon: uploading
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Icon(
                          state.url == null
                              ? Icons.upload_file_rounded
                              : Icons.sync_rounded,
                          size: 16,
                          color: Colors.white),
                  label: _ButtonText(state.url == null
                      ? 'Upload Document'
                      : 'Replace Document'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: Colors.white,
                    iconColor: Colors.white,
                    minimumSize: const Size(0, 40),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(String text, Color fg, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
      child: Text(text,
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: fg)),
    );
  }
}

/// Button text that shrinks to fit on narrow phones instead of wrapping.
class _ButtonText extends StatelessWidget {
  final String text;
  const _ButtonText(this.text);

  @override
  Widget build(BuildContext context) => FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(text,
            maxLines: 1,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      );
}
