import 'app_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/safe_cast.dart';
import 'package:image_picker/image_picker.dart';

import 'storage_service.dart';
import '../utils/ist_clock.dart';

/// One document a provider must (or may) upload for admin verification.
class VerificationDocRequirement {
  final String key;
  final String label;
  final String description;
  final bool mandatory;

  /// Older profile field this document used to be stored in (e.g.
  /// 'aadhaarUrl'), so documents uploaded before this system still count.
  final String? legacyField;

  const VerificationDocRequirement({
    required this.key,
    required this.label,
    required this.description,
    required this.mandatory,
    this.legacyField,
  });

  factory VerificationDocRequirement.fromMap(Map<String, dynamic> m) {
    return VerificationDocRequirement(
      key: (m['key'] ?? '').toString(),
      label: (m['label'] ?? '').toString(),
      description: (m['description'] ?? '').toString(),
      mandatory: m['mandatory'] == true,
      legacyField: m['legacyField']?.toString(),
    );
  }
}

/// Required documents for one provider type, e.g. "Specialist Doctor".
class VerificationRequirementSet {
  final String id;
  final String role;
  final String title;
  final List<VerificationDocRequirement> documents;

  const VerificationRequirementSet({
    required this.id,
    required this.role,
    required this.title,
    required this.documents,
  });

  List<VerificationDocRequirement> get mandatoryDocuments =>
      documents.where((d) => d.mandatory).toList();
}

/// Review state of one uploaded document.
enum DocReviewStatus { missing, pending, approved, rejected }

class UploadedDocState {
  final String? url;
  final DocReviewStatus status;
  final String? rejectReason;

  const UploadedDocState(this.url, this.status, [this.rejectReason]);
}

/// Provider verification (CareConnect policy): a provider may create a
/// profile, but stays non-bookable (`isVerified: false`) until every
/// mandatory role-specific document is uploaded and approved by the admin.
///
/// Requirements live in Firestore collection `verification_requirements`.
/// Each doc: `role`, `title`, optional `matchField` + `matchValues` (e.g.
/// category ∈ ['Dentist']), optional `isDefault`, and `documents`
/// (list of {key, label, description, mandatory, legacyField, order}).
///
/// Uploads are stored on the provider profile under
/// `verificationDocuments.{key}` = {url, status, uploadedAt, rejectReason}.
class VerificationService {
  static final FirebaseFirestore _db = AppDatabase.instance;

  static const String requirementsCollection = 'verification_requirements';

  static String collectionForRole(String role) {
    switch (role) {
      case 'doctor':
        return 'doctors';
      case 'technician':
        return 'technicians';
      case 'nurse':
        return 'nurses';
      case 'therapist':
        return 'therapists';
      case 'hospital':
        return 'hospitals';
      case 'ambulance':
        return 'ambulances';
      case 'care_physician':
        return 'care_physicians';
      default:
        return 'users';
    }
  }

  /// Pick the requirement set for this provider: the one whose `matchField`
  /// value matches the profile, otherwise the role's `isDefault` set.
  /// Returns null if nothing is configured for the role in Firestore.
  static Future<VerificationRequirementSet?> getRequirementsFor(
      String role, Map<String, dynamic> profile) async {
    try {
      final snap = await _db
          .collection(requirementsCollection)
          .where('role', isEqualTo: role)
          .get();
      if (snap.docs.isEmpty) return null;

      QueryDocumentSnapshot<Map<String, dynamic>>? chosen;
      QueryDocumentSnapshot<Map<String, dynamic>>? fallback;
      for (final doc in snap.docs) {
        final data = doc.data();
        if (data['isActive'] == false) continue;
        final field = data['matchField']?.toString();
        final values = (data['matchValues'] as List<dynamic>? ?? [])
            .map((e) => e.toString().trim().toLowerCase())
            .toList();
        final profileValue =
            (field == null ? '' : (profile[field] ?? '')).toString().trim().toLowerCase();
        if (field != null && values.isNotEmpty && values.contains(profileValue)) {
          chosen = doc;
          break;
        }
        if (data['isDefault'] == true) fallback ??= doc;
      }
      final picked = chosen ?? fallback;
      if (picked == null) return null;

      final data = picked.data();
      final docs = (data['documents'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList()
        ..sort((a, b) => (toNum(a['order']) ?? 0)
            .compareTo(toNum(b['order']) ?? 0));

      return VerificationRequirementSet(
        id: picked.id,
        role: role,
        title: (data['title'] ?? '').toString(),
        documents: docs
            .map(VerificationDocRequirement.fromMap)
            .where((d) => d.key.isNotEmpty)
            .toList(),
      );
    } catch (_) {
      return null;
    }
  }

  /// Current upload + review state of one required document.
  static UploadedDocState docState(
      Map<String, dynamic> profile, VerificationDocRequirement req) {
    final all = profile['verificationDocuments'] as Map<String, dynamic>? ?? {};
    final entry = all[req.key] as Map<String, dynamic>?;
    final url = (entry?['url'] ??
            (req.legacyField != null ? profile[req.legacyField] : null))
        ?.toString();
    if (url == null || url.isEmpty) {
      return const UploadedDocState(null, DocReviewStatus.missing);
    }
    switch (entry?['status']) {
      case 'approved':
        return UploadedDocState(url, DocReviewStatus.approved);
      case 'rejected':
        return UploadedDocState(
            url, DocReviewStatus.rejected, entry?['rejectReason']?.toString());
      default:
        // Includes documents uploaded before per-document review existed
        return UploadedDocState(url, DocReviewStatus.pending);
    }
  }

  /// Mandatory documents that block approval (missing, pending or rejected).
  static List<VerificationDocRequirement> blockingDocuments(
      VerificationRequirementSet reqs, Map<String, dynamic> profile) {
    return reqs.mandatoryDocuments
        .where((r) => docState(profile, r).status != DocReviewStatus.approved)
        .toList();
  }

  static Future<void> _writeProfile(
      String role, String uid, Map<String, dynamic> data) async {
    await _db
        .collection(collectionForRole(role))
        .doc(uid)
        .set(data, SetOptions(merge: true));
  }

  /// Provider uploads (or replaces) a document. It goes back to "pending";
  /// replacing a mandatory document makes the profile non-bookable until
  /// Largest document that can be uploaded.
  static const int maxDocumentMb = 10;

  /// "aadhaar" for "Aadhaar.PDF" / "aadhaar.jpg": the file name without its
  /// extension, so the same document saved as another type is recognised.
  static String fileBase(String fileName) {
    final name = fileName.trim().toLowerCase();
    final dot = name.lastIndexOf('.');
    return (dot > 0 ? name.substring(0, dot) : name).trim();
  }

  /// Why [bytes] can't be uploaded for [docKey], or null if it can: over
  /// [maxDocumentMb], or a file with the same name as another document's
  /// file, only with another extension (aadhaar.jpg for the Aadhaar card,
  /// aadhaar.pdf for the PAN card). [uploaded] is the profile's
  /// `verificationDocuments`, whose entries keep the file's name. (The IT
  /// team's version also refuses a copy of a document already uploaded, by
  /// file fingerprint; that part needs the `crypto` package and a new
  /// Firestore collection and is not enabled here yet.)
  static String? uploadProblem(List<int> bytes, String docKey,
      Map<String, dynamic>? uploaded,
      {Map<String, String>? labels, String? fileName}) {
    if (bytes.length > maxDocumentMb * 1024 * 1024) {
      return 'This file is larger than $maxDocumentMb MB. Please upload a '
          'smaller file (for example a compressed PDF or a photo).';
    }
    // the same document under another extension, for another document
    final base = fileName == null ? '' : fileBase(fileName);
    if (base.isNotEmpty) {
      for (final e in (uploaded ?? const {}).entries) {
        final entry = e.value;
        if (e.key == docKey || entry is! Map) continue;
        if ((entry['fileBase'] ?? '').toString() != base) continue;
        final label = (entry['label'] ?? labels?[e.key] ?? 'another document')
            .toString();
        return 'A file named "${fileName!.trim()}" is already uploaded as '
            '$label (only the file type is different). Please upload the '
            'correct document.';
      }
    }
    return null;
  }

  /// the admin reviews it again. Refused (DocumentUploadException) when the
  /// file is over 10 MB.
  static Future<void> uploadDocument({
    required String role,
    required String uid,
    required VerificationDocRequirement requirement,
    required XFile file,
  }) async {
    // the file this one replaces (its type, and so its name, may differ)
    final before = (await _db.collection(collectionForRole(role)).doc(uid).get())
        .data();
    final uploaded = (before?['verificationDocuments'] as Map?)
        ?.cast<String, dynamic>();
    final bytes = await file.readAsBytes();
    final problem =
        uploadProblem(bytes, requirement.key, uploaded, fileName: file.name);
    if (problem != null) throw DocumentUploadException(problem);
    final oldUrl = ((before?['verificationDocuments'] as Map?)?[requirement.key]
            as Map?)?['url']
        ?.toString();
    final url = await StorageService.uploadVerificationDocument(
      uid: uid,
      docType: requirement.key,
      file: file,
    );
    await _writeProfile(role, uid, {
      'verificationDocuments': {
        requirement.key: {
          'url': url,
          'label': requirement.label,
          'status': 'pending',
          'fileBase': fileBase(file.name),
          'sizeBytes': bytes.length,
          'uploadedAt': IstClock.now().toIso8601String(),
          'rejectReason': FieldValue.delete(),
        },
      },
      if (requirement.mandatory) 'isVerified': false,
    });
    // replaced by a file of another type: remove the old one from storage
    if (oldUrl != null &&
        oldUrl.contains('verification_docs') &&
        _storagePath(oldUrl) != _storagePath(url)) {
      await StorageService.deleteByUrl(oldUrl);
    }
  }

  /// "verification_docs/uid/key.pdf" from a download link.
  static String _storagePath(String url) =>
      Uri.decodeComponent(Uri.parse(url).path.split('/o/').last);

  /// Admin approves or rejects one document. Rejecting a mandatory document
  /// makes the profile non-bookable.
  static Future<void> reviewDocument({
    required String role,
    required String uid,
    required VerificationDocRequirement requirement,
    required String url,
    required bool approve,
    String? rejectReason,
  }) async {
    await _writeProfile(role, uid, {
      'verificationDocuments': {
        requirement.key: {
          'url': url,
          'label': requirement.label,
          'status': approve ? 'approved' : 'rejected',
          'reviewedAt': IstClock.now().toIso8601String(),
          'rejectReason': approve
              ? FieldValue.delete()
              : (rejectReason?.trim().isNotEmpty == true
                  ? rejectReason!.trim()
                  : 'Please upload a clearer / valid document'),
        },
      },
      if (!approve && requirement.mandatory) 'isVerified': false,
    });
  }

  /// Approve the provider (make bookable) only if every mandatory document
  /// is uploaded and approved. Re-reads Firestore so the check is current.
  /// Returns the labels of blocking documents (empty list = approved).
  static Future<List<String>> approveProvider({
    required String role,
    required String uid,
  }) async {
    final snap = await _db.collection(collectionForRole(role)).doc(uid).get();
    final profile = snap.data() ?? {};
    final reqs = await getRequirementsFor(role, profile);
    if (reqs == null) {
      return ['Verification documents are not configured for "$role" '
          '(Firestore: $requirementsCollection)'];
    }
    final blocking = blockingDocuments(reqs, profile);
    if (blocking.isNotEmpty) return blocking.map((d) => d.label).toList();

    await _writeProfile(role, uid, {
      'isVerified': true,
      'verifiedAt': IstClock.now().toIso8601String(),
      'verificationRequirementId': reqs.id,
    });
    return [];
  }

  /// Revoke approval (profile becomes non-bookable).
  static Future<void> revokeProvider({
    required String role,
    required String uid,
  }) async {
    await _writeProfile(role, uid, {
      'isVerified': false,
      'verifiedAt': IstClock.now().toIso8601String(),
    });
  }
}

/// A document that can't be uploaded (too large); the message is shown to the
/// user as it is.
class DocumentUploadException implements Exception {
  final String message;
  const DocumentUploadException(this.message);

  @override
  String toString() => message;
}
