import '../config/test_lab_config.dart';
import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

class StorageService {
  static FirebaseStorage get _storage {
    if (TestLabConfig.enabled) {
      throw StateError('Test lab: document and media uploads are disabled.');
    }
    return FirebaseStorage.instance;
  }

  /// Upload Profile Picture to Firebase Storage
  static Future<String> uploadProfilePicture({
    required String uid,
    required XFile file,
  }) async {
    final ref = _storage.ref().child('profile_pics').child('$uid.jpg');
    final bytes = await file.readAsBytes();

    final uploadTask = await ref.putData(
      bytes,
      SettableMetadata(contentType: 'image/jpeg'),
    );

    // The file path stays the same for a new photo: a version in the link
    // makes cached images (CachedNetworkImageProvider) load the new one.
    final url = await uploadTask.ref.getDownloadURL();
    return '$url&v=${DateTime.now().millisecondsSinceEpoch}';
  }

  /// File extension of a document, read from its first bytes (some phones
  /// give picked files no extension), else from its name.
  static String documentExtension(Uint8List bytes, String name) {
    bool starts(List<int> sig) =>
        bytes.length >= sig.length &&
        List.generate(sig.length, (i) => bytes[i] == sig[i]).every((x) => x);
    if (starts([0x25, 0x50, 0x44, 0x46])) return 'pdf';
    if (starts([0x89, 0x50, 0x4E, 0x47])) return 'png';
    if (starts([0xFF, 0xD8, 0xFF])) return 'jpg';
    if (starts([0xD0, 0xCF, 0x11, 0xE0])) return 'doc';
    final dot = name.lastIndexOf('.');
    final ext = dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
    if (const {'jpg', 'jpeg', 'png', 'pdf', 'doc', 'docx'}.contains(ext)) {
      return ext == 'jpeg' ? 'jpg' : ext;
    }
    // a .docx is a zip file
    if (starts([0x50, 0x4B, 0x03, 0x04])) return 'docx';
    return 'bin';
  }

  static const Map<String, String> _documentTypes = {
    'jpg': 'image/jpeg',
    'png': 'image/png',
    'pdf': 'application/pdf',
    'doc': 'application/msword',
    'docx':
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  };

  /// Upload Verification Document (Degree, Aadhaar, PAN, Address, Registration)
  static Future<String> uploadVerificationDocument({
    required String uid,
    required String docType,
    required XFile file,
  }) async {
    final bytes = await file.readAsBytes();
    // the real type, so the file opens (not downloads) when viewed
    final extension = documentExtension(bytes, file.name);
    final contentType =
        _documentTypes[extension] ?? 'application/octet-stream';

    final ref = _storage.ref().child('verification_docs').child(uid).child('$docType.$extension');

    final uploadTask = await ref.putData(
      bytes,
      SettableMetadata(contentType: contentType),
    );

    return await uploadTask.ref.getDownloadURL();
  }

  /// Deletes a stored file by its download link (ignored if already gone).
  static Future<void> deleteByUrl(String url) async {
    try {
      await _storage.refFromURL(url).delete();
    } catch (_) {}
  }

  /// Upload Chat Attachment (PDF, Image, Video) to Firebase Storage
  static Future<String> uploadChatAttachmentBytes({
    required String chatId,
    required String fileName,
    required Uint8List bytes,
    required String contentType,
  }) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final ref = _storage
        .ref()
        .child('chat_attachments')
        .child(chatId)
        .child('${timestamp}_$fileName');

    final uploadTask = await ref.putData(
      bytes,
      SettableMetadata(contentType: contentType),
    );

    return await uploadTask.ref.getDownloadURL();
  }
}
