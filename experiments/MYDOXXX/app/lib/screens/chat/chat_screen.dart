import '../../services/app_database.dart';
import '../../services/lab_device.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import '../../widgets/test_suggestion_ui.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import 'dart:async';

import '../../services/chat_access_service.dart';
import '../../utils/chat_access.dart';
import '../../widgets/chat_recharge_ui.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/chat_cards.dart';
import '../../widgets/voice_note.dart';
import '../../services/presence_service.dart';
import '../../services/call_service.dart';
import 'video_call_screen.dart';
import '../../services/firestore_service.dart';
import '../../services/push_service.dart';
import '../../services/storage_service.dart';
import '../../services/test_suggestion_service.dart';
import '../../utils/test_shortcut.dart';
import '../../theme/app_theme.dart';
import '../../utils/error_messages.dart';
import '../../utils/stream_cache.dart';
import '../../utils/responsive.dart';
import '../../constants/app_colors.dart';
import '../../utils/ist_clock.dart';

class ChatScreen extends StatefulWidget {
  final String chatId;
  final String currentUserId;
  final String currentUserName;
  final String peerName;
  final String peerRole; // 'Doctor' or 'Patient'
  // Video attachments (off for therapist, nurse and technician logins)
  final bool allowVideo;
  // Doctors can suggest tests to the patient from the chat, and send
  // prescriptions
  final bool canSuggestTests;

  /// Ambulance chat: the SOS request the ambulance is on. Open only while
  /// the ambulance is on duty for the patient (also read from the chat).
  final String? ambulanceSosId;

  const ChatScreen({
    super.key,
    required this.chatId,
    required this.currentUserId,
    required this.currentUserName,
    required this.peerName,
    required this.peerRole,
    this.allowVideo = true,
    this.canSuggestTests = false,
    this.ambulanceSosId,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  // Live data connections kept open across redraws
  final StreamCache _streams = StreamCache();

  final TextEditingController _messageController = TextEditingController();
  bool _isUploading = false;

  // Chat rules: opens when the consultation ends, 24 h, 10 free patient messages
  late final ({String patientUid, String providerUid})? _who =
      ChatAccessService.parties(widget.chatId);
  bool get _isPatient => _who?.patientUid == widget.currentUserId;
  DateTime? _consultationEnd;
  bool _endLoaded = false;
  Map<String, dynamic>? _chat;
  StreamSubscription<Map<String, dynamic>?>? _chatSub;
  Timer? _tick;
  ChatAccessState? _promptedFor;

  // Doctor: "\" in the message box opens the tests list (see TestShortcut)
  List<String> _labTests = [];
  bool _labTestsLoaded = false;
  String? _testQuery; // null: the list is closed
  final Set<String> _testsPicked = {};
  bool _sendingTests = false;

  bool get _testShortcutOn => widget.canSuggestTests && _who != null;

  void _onTyping(String text) {
    if (!_testShortcutOn) return;
    final q = TestShortcut.query(text);
    if (q == _testQuery) return;
    setState(() => _testQuery = q);
    if (q != null && !_labTestsLoaded) _loadLabTests();
  }

  Future<void> _loadLabTests() async {
    _labTestsLoaded = true;
    try {
      final list = await FirestoreService.getLabTestsWithPrice();
      if (!mounted) return;
      setState(() => _labTests = [for (final t in list) t['name'] as String]);
    } catch (e) {
      _labTestsLoaded = false; // try again next time "\" is typed
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ErrorMessages.of(e, action: 'load the tests'))));
    }
  }

  void _closeTestShortcut() {
    final text = TestShortcut.strip(_messageController.text);
    _messageController.value = TextEditingValue(
        text: text, selection: TextSelection.collapsed(offset: text.length));
    setState(() {
      _testQuery = null;
      _testsPicked.clear();
    });
  }

  Future<void> _sendPickedTests() async {
    final who = _who;
    if (who == null || _testsPicked.isEmpty || _sendingTests) return;
    setState(() => _sendingTests = true);
    try {
      await TestSuggestionService.suggest(
        chatId: widget.chatId,
        patientUid: who.patientUid,
        patientName: widget.peerName,
        doctorUid: widget.currentUserId,
        doctorName: widget.currentUserName,
        tests: _testsPicked.toList(),
      );
      if (!mounted) return;
      _closeTestShortcut();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ErrorMessages.of(e, action: 'send the tests'))));
    } finally {
      if (mounted) setState(() => _sendingTests = false);
    }
  }

  // Ambulance chat: open while the ambulance is on duty for the patient
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sosSub;
  String? _sosWatched;
  bool _onDuty = false;
  bool _sosLoaded = false;
  String? get _ambulanceSosId {
    final fromChat = _chat?['ambulanceSosId'];
    return widget.ambulanceSosId ?? (fromChat is String ? fromChat : null);
  }

  bool get _isAmbulanceChat => _ambulanceSosId != null;

  void _watchSos() {
    final id = _ambulanceSosId;
    if (id == null || id == _sosWatched) return;
    _sosWatched = id;
    _sosSub?.cancel();
    _sosSub = AppDatabase.instance
        .collection('appointments')
        .doc(id)
        .snapshots()
        .listen((d) {
      if (!mounted) return;
      setState(() {
        _onDuty = ChatAccess.ambulanceOnDuty(d.data(), _who?.providerUid);
        _sosLoaded = true;
      });
    }, onError: (_) {
      if (mounted) setState(() => _sosLoaded = true);
    });
  }

  // Patient: the doctor's follow-up after the chat time was offered once
  String? _followUpPrompted;

  // Whether the chat has any messages yet (null: not loaded). A patient who
  // closes the recharge popup stays to read the history, or goes back home
  // when there is none.
  bool? _hasMessages;
  StreamSubscription<List<Map<String, dynamic>>>? _msgSub;

  // The send button turns into a microphone while the box is empty
  bool _inputEmpty = true;

  // Voice message being recorded
  final AudioRecorder _recorder = AudioRecorder();
  bool _recording = false;
  DateTime? _recStart;
  Duration _recLen = Duration.zero;
  Timer? _recTimer;
  static const Duration _maxVoice = Duration(minutes: 5);

  String get _peerUid => _who == null
      ? ''
      : _isPatient
          ? _who.providerUid
          : _who.patientUid;

  ChatAccess get _access => _isAmbulanceChat
      ? ChatAccess.ambulance(onDuty: _onDuty)
      : _endLoaded
          ? ChatAccess.compute(consultationEnd: _consultationEnd, chat: _chat)
          : const ChatAccess(ChatAccessState.open);

  /// Provider after the chat time: one follow-up message is allowed.
  bool get _followUpMode =>
      !_isPatient &&
      !_isAmbulanceChat &&
      _endLoaded &&
      _access.providerCanFollowUp;

  bool get _canWrite => _isAmbulanceChat || _isPatient
      ? _access.isOpen
      : _access.providerCanSend || _followUpMode;

  Future<void> _loadAccess() async {
    final who = _who;
    if (who == null) {
      setState(() => _endLoaded = true);
      return;
    }
    try {
      _consultationEnd = await ChatAccessService.consultationEnd(
          who.patientUid, who.providerUid);
    } catch (_) {}
    if (!mounted) return;
    setState(() => _endLoaded = true);
    _maybePrompt();
  }

  /// Patient: when the chat time ends or the messages run out, the recharge
  /// popup shows (once for each, not again until it changes).
  void _maybePrompt() {
    if (!mounted || !_isPatient || !_endLoaded || _isAmbulanceChat) return;
    final a = _access;
    if (!a.needsRecharge) {
      _promptedFor = null;
      return;
    }
    // the doctor wrote after the chat time: offer the single message
    final followUp = a.followUpAt;
    if (a.state == ChatAccessState.timeOver &&
        followUp != null &&
        (a.endsAt == null || !followUp.isBefore(a.endsAt!))) {
      final key = followUp.toIso8601String();
      if (_followUpPrompted != key) {
        _followUpPrompted = key;
        _promptedFor = a.state;
        showSingleMessageOffer(context,
                chatId: widget.chatId,
                peerName: widget.peerName,
                followUp: true)
            .then((_) => _leaveIfNothingToRead());
        return;
      }
    }
    if (_promptedFor == a.state) return;
    // wait for the messages, to know whether there is a history to read
    if (_hasMessages == null) return;
    _promptedFor = a.state;
    showChatClosedPopup(context,
            chatId: widget.chatId, reason: a.state, peerName: widget.peerName)
        .then((_) => _leaveIfNothingToRead());
  }

  /// "Not now" (or closing the plans without paying): the patient stays to
  /// read the chat history; with no history, back to the home screen.
  Future<void> _leaveIfNothingToRead() async {
    // a payment that just went through reaches the chat a moment later
    await Future<void>.delayed(const Duration(seconds: 2));
    if (!mounted || !_access.needsRecharge || _hasMessages != false) return;
    Navigator.of(context).maybePop();
  }

  /// False (and tells the user why) when this person cannot write now.
  bool _guardWrite() {
    if (_canWrite) return true;
    final a = _access;
    if (_isPatient && a.needsRecharge && !_isAmbulanceChat) {
      showChatClosedPopup(context,
          chatId: widget.chatId, reason: a.state, peerName: widget.peerName);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ChatClosedException(a.state).toString())));
    }
    return false;
  }

  /// Sends one message through the chat rules. A file with its description
  /// is one message.
  Future<void> _deliver({
    String type = 'text',
    String text = '',
    String? mediaUrl,
    String? fileName,
    Map<String, dynamic> extra = const {},
  }) async {
    try {
      await ChatAccessService.send(
        chatId: widget.chatId,
        senderUid: widget.currentUserId,
        senderName: widget.currentUserName,
        consultationEnd: _consultationEnd,
        type: type,
        text: text,
        mediaUrl: mediaUrl,
        fileName: fileName,
        ambulanceSosId: _ambulanceSosId,
        ambulanceOnDuty: _onDuty,
        extra: extra,
      );
    } on ChatClosedException catch (e) {
      if (!mounted) return;
      if (_isPatient &&
          (e.state == ChatAccessState.timeOver ||
              e.state == ChatAccessState.limitReached)) {
        showChatClosedPopup(context,
            chatId: widget.chatId, reason: e.state, peerName: widget.peerName);
      } else {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  /// Asks for a description to send together with a file (one message).
  Future<String?> _askCaption() async {
    final c = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Add a description'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: c,
              autofocus: true,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration:
                  const InputDecoration(hintText: 'Describe it (optional)'),
            ),
            if (_isPatient) ...[
              const SizedBox(height: 8),
              const Text(
                'A description sent with the file counts as 1 message. Sent separately, they count as 2.',
                style: TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, c.text.trim()),
              child: const Text('Send')),
        ],
      ),
    );
    c.dispose();
    return result;
  }

  @override
  void initState() {
    super.initState();
    // Update current user last seen timestamp
    FirestoreService.updateUserLastSeen(
        widget.currentUserId, widget.peerRole == 'Doctor' ? 'patient' : 'doctor');
    PushService.activeChatId = widget.chatId; // no banners for this chat
    _chatSub = ChatAccessService.chatDoc(widget.chatId).listen((d) {
      if (!mounted) return;
      setState(() => _chat = d);
      // reading the chat clears its unread count
      if (ChatAccessService.unreadOf(d, widget.currentUserId) > 0) {
        ChatAccessService.markRead(widget.chatId, widget.currentUserId);
      }
      _watchSos();
      _maybePrompt();
    });
    _watchSos();
    _msgSub = _streams
        .get('messages',
            () => FirestoreService.getChatMessagesStream(widget.chatId))
        .listen((m) {
      final first = _hasMessages == null;
      _hasMessages = m.isNotEmpty;
      if (first) _maybePrompt();
    }, onError: (_) {
      _hasMessages ??= true; // can't tell: never send the patient away
    });
    _messageController.addListener(() {
      final empty = _messageController.text.trim().isEmpty;
      if (empty != _inputEmpty && mounted) setState(() => _inputEmpty = empty);
    });
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) {
        setState(() {});
        _maybePrompt();
      }
    });
    _loadAccess();
    // Patient opening a doctor's chat: remind them of tests still to book
    if (_isPatient) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          TestSuggestionPrompt.checkAndShow(context,
              patientUid: widget.currentUserId);
        }
      });
    }
  }

  @override
  void dispose() {
    if (PushService.activeChatId == widget.chatId) PushService.activeChatId = null;
    _chatSub?.cancel();
    _sosSub?.cancel();
    _msgSub?.cancel();
    _tick?.cancel();
    _recTimer?.cancel();
    _recorder.dispose();
    _messageController.dispose();
    super.dispose();
  }

  void _sendMessage() {
    // the tests list is open: Send sends the ticked tests, never "\mri"
    if (_testQuery != null) {
      if (_testsPicked.isNotEmpty) {
        _sendPickedTests();
      } else {
        _closeTestShortcut();
      }
      return;
    }
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    if (!_guardWrite()) return;
    _messageController.clear();
    _deliver(text: text);
  }

  Future<void> _openAttachmentOptions() async {
    if (!_guardWrite()) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Share Attachment',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textDark,
                ),
              ),
              const SizedBox(height: 20),
              Wrap(
                alignment: WrapAlignment.spaceAround,
                spacing: 18,
                runSpacing: 16,
                children: [
                  // Doctor: share a prescription with the patient
                  if (widget.canSuggestTests)
                    _buildAttachmentOption(
                      icon: Icons.medication_rounded,
                      label: 'Prescription',
                      color: AppColors.primary,
                      onTap: () {
                        Navigator.pop(ctx);
                        _pickAndSendPrescription();
                      },
                    ),

                  // 1. Image
                  _buildAttachmentOption(
                    icon: Icons.image_rounded,
                    label: 'Image',
                    color: AppColors.blue,
                    onTap: () {
                      Navigator.pop(ctx);
                      _pickAndSendImage();
                    },
                  ),

                  // 2. PDF Document
                  _buildAttachmentOption(
                    icon: Icons.picture_as_pdf_rounded,
                    label: 'PDF Document',
                    color: AppColors.danger,
                    onTap: () {
                      Navigator.pop(ctx);
                      _pickAndSendPdf();
                    },
                  ),

                  // 3. Video
                  if (widget.allowVideo)
                    _buildAttachmentOption(
                      icon: Icons.videocam_rounded,
                      label: 'Video',
                      color: AppColors.purple,
                      onTap: () {
                        Navigator.pop(ctx);
                        _pickAndSendVideo();
                      },
                    ),

                  // 4. Audio file or voice note
                  _buildAttachmentOption(
                    icon: Icons.audiotrack_rounded,
                    label: 'Audio',
                    color: AppColors.primaryLight,
                    onTap: () {
                      Navigator.pop(ctx);
                      _pickAndSendAudio();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Files up to $_maxFileMb MB',
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAttachmentOption({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: AppTheme.textDark,
            ),
          ),
        ],
      ),
    );
  }

  static const int _maxFileMb = 25;

  /// Picks a file of the given kind, checks its size and type, uploads it
  /// and sends it as one message with its description.
  Future<void> _pickAndSendFile({
    required String type,
    required String what,
    required FileType fileType,
    List<String>? extensions,
    required String Function(String ext) contentType,
  }) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: fileType,
        allowedExtensions: extensions,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      final ext = (file.extension ?? '').toLowerCase();
      if (extensions != null && !extensions.contains(ext)) {
        _fileError('This file type is not supported. Please choose a '
            '${extensions.map((e) => e.toUpperCase()).join(', ')} file.');
        return;
      }
      if (file.bytes == null) {
        _fileError('The file could not be read. Please choose another one.');
        return;
      }
      if (file.size > _maxFileMb * 1024 * 1024) {
        _fileError('The file is too large. Please choose one under '
            '$_maxFileMb MB.');
        return;
      }
      final caption = await _askCaption();
      if (caption == null) return;
      setState(() => _isUploading = true);
      final url = await StorageService.uploadChatAttachmentBytes(
        chatId: widget.chatId,
        fileName: file.name,
        bytes: file.bytes!,
        contentType: contentType(ext),
      );
      await _deliver(
          type: type, text: caption, mediaUrl: url, fileName: file.name);
    } catch (e) {
      _fileError(ErrorMessages.of(e, action: 'upload the $what'));
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  void _fileError(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(text), backgroundColor: AppColors.danger));
  }

  /// Doctor: a prescription (PDF or photo), labelled as one in the chat.
  Future<void> _pickAndSendPrescription() => _pickAndSendFile(
        type: 'prescription',
        what: 'prescription',
        fileType: FileType.custom,
        extensions: const ['pdf', 'jpg', 'jpeg', 'png'],
        contentType: (ext) =>
            ext == 'pdf' ? 'application/pdf' : 'image/${ext == 'png' ? 'png' : 'jpeg'}',
      );

  /// An audio file or voice note.
  Future<void> _pickAndSendAudio() => _pickAndSendFile(
        type: 'audio',
        what: 'audio',
        fileType: FileType.custom,
        extensions: const ['mp3', 'm4a', 'aac', 'wav', 'ogg', 'opus', 'amr'],
        contentType: (ext) => switch (ext) {
          'mp3' => 'audio/mpeg',
          'm4a' || 'aac' => 'audio/aac',
          'wav' => 'audio/wav',
          'amr' => 'audio/amr',
          _ => 'audio/ogg',
        },
      );

  Future<void> _pickAndSendImage() async {
    final picker = ImagePicker();
    final picked =
        await picker.pickImage(source: ImageSource.gallery, imageQuality: 75);
    if (picked == null) return;
    final caption = await _askCaption();
    if (caption == null) return;

    setState(() => _isUploading = true);

    try {
      final bytes = await picked.readAsBytes();
      final url = await StorageService.uploadChatAttachmentBytes(
        chatId: widget.chatId,
        fileName: picked.name,
        bytes: bytes,
        contentType: 'image/jpeg',
      );

      await _deliver(
        type: 'image',
        text: caption,
        mediaUrl: url,
        fileName: picked.name,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ErrorMessages.of(e, action: 'upload the image')),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _pickAndSendPdf() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'doc', 'docx'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      if (file.bytes == null) return;
      final caption = await _askCaption();
      if (caption == null) return;

      setState(() => _isUploading = true);

      final url = await StorageService.uploadChatAttachmentBytes(
        chatId: widget.chatId,
        fileName: file.name,
        bytes: file.bytes!,
        contentType: 'application/pdf',
      );

      await _deliver(
        type: 'pdf',
        text: caption,
        mediaUrl: url,
        fileName: file.name,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ErrorMessages.of(e, action: 'upload the PDF')),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _pickAndSendVideo() async {
    final picker = ImagePicker();
    final picked = await picker.pickVideo(source: ImageSource.gallery);
    if (picked == null) return;
    final caption = await _askCaption();
    if (caption == null) return;

    setState(() => _isUploading = true);

    try {
      final bytes = await picked.readAsBytes();
      final url = await StorageService.uploadChatAttachmentBytes(
        chatId: widget.chatId,
        fileName: picked.name,
        bytes: bytes,
        contentType: 'video/mp4',
      );

      await _deliver(
        type: 'video',
        text: caption,
        mediaUrl: url,
        fileName: picked.name,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ErrorMessages.of(e, action: 'upload the video')),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  void _confirmDeleteMessage(String messageId) {
    showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Delete Message?'),
          content: const Text('This message will be removed from chat.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancel', style: TextStyle(color: AppColors.muted)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
              onPressed: () async {
                Navigator.pop(dialogCtx);
                await FirestoreService.deleteChatMessage(
                  chatId: widget.chatId,
                  messageId: messageId,
                );
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  /// Patient: asks the provider for an audio or video call (shown in chat).
  Future<void> _requestCall(bool video) async {
    if (!_access.timeOn) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Calls can be requested while the chat is open.')));
      return;
    }
    final kind = video ? 'video' : 'audio';
    final ok = await AppDialog.confirm(
      context,
      title: 'Request a $kind call?',
      message:
          '${widget.peerName} sees your request in the chat and starts the call. Calls last up to 15 minutes.',
      icon: video ? Icons.videocam_rounded : Icons.call_rounded,
      confirmLabel: 'Send request',
    );
    if (!ok || !mounted) return;
    try {
      await ChatAccessService.requestCall(
        chatId: widget.chatId,
        senderUid: widget.currentUserId,
        senderName: widget.currentUserName,
        video: video,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ErrorMessages.of(e, action: 'send the call request'))));
    }
  }

  /// Starts the call a request is about (either side can, once the doctor
  /// accepted it; 15 minutes at most).
  void _startRequestedCall(Map<String, dynamic> request) {
    final who = _who;
    final id = (request['messageId'] ?? '').toString();
    if (who == null || id.isEmpty) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => VideoCallScreen(
        callId: CallService.newCallId(widget.chatId),
        isCaller: true,
        currentUid: widget.currentUserId,
        callerName: widget.currentUserName,
        peerUid: _peerUid,
        peerName: widget.peerName,
        peerRole: widget.peerRole,
        audioOnly: request['callType'] != 'video',
        maxDuration: VideoCallScreen.chatCallLimit,
        chatId: widget.chatId,
        requestMessageId: id,
      ),
    ));
  }

  String _requestId(Map<String, dynamic> m) =>
      (m['messageId'] ?? '').toString();

  /// Doctor accepts the request: it is marked accepted and the patient rings.
  Future<void> _acceptCall(Map<String, dynamic> m) async {
    await ChatAccessService.setCallStatus(
        widget.chatId, _requestId(m), 'accepted');
    if (mounted) _startRequestedCall(m);
  }

  Future<void> _declineCall(Map<String, dynamic> m) async {
    final ok = await AppDialog.confirm(
      context,
      title: 'Decline the call request?',
      message: '${widget.peerName} will see that the call was declined.',
      icon: Icons.call_end_rounded,
      color: AppColors.danger,
      confirmLabel: 'Decline',
    );
    if (ok) {
      await ChatAccessService.setCallStatus(
          widget.chatId, _requestId(m), 'declined');
    }
  }

  Future<void> _cancelCall(Map<String, dynamic> m) =>
      ChatAccessService.setCallStatus(
          widget.chatId, _requestId(m), 'cancelled');

  /// Ends a call that is on (from the card in the chat).
  Future<void> _endCall(Map<String, dynamic> m) async {
    final callId = (m['callId'] ?? '').toString();
    if (callId.isNotEmpty) await CallService.setStatus(callId, 'ended');
    await ChatAccessService.setCallStatus(
        widget.chatId, _requestId(m), 'completed');
  }

  // ------------------------------------------------------- voice messages

  Future<void> _startRecording() async {
    if (!_guardWrite() || _recording) return;
    try {
      if (!await _recorder.hasPermission()) {
        _fileError('Allow the microphone to record a voice message.');
        return;
      }
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/voice_${IstClock.instant().millisecondsSinceEpoch}.m4a';
      await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc),
          path: path);
      final start = IstClock.now();
      setState(() {
        _recording = true;
        _recStart = start;
        _recLen = Duration.zero;
      });
      _recTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
        if (!mounted) return;
        setState(() => _recLen = IstClock.now().difference(start));
        if (_recLen >= _maxVoice) _stopRecording(send: true);
      });
    } catch (e) {
      _fileError(ErrorMessages.of(e, action: 'record a voice message'));
    }
  }

  /// Stops recording; [send] uploads it as one message (else it is thrown
  /// away). The message plays inside the chat.
  Future<void> _stopRecording({required bool send}) async {
    if (!_recording) return;
    _recTimer?.cancel();
    final len = _recStart == null
        ? Duration.zero
        : IstClock.now().difference(_recStart!);
    setState(() => _recording = false);
    if (!send) {
      await _recorder.cancel();
      return;
    }
    final path = await _recorder.stop();
    if (path == null) return;
    if (len < const Duration(seconds: 1)) {
      _fileError('The voice message is too short. Tap the mic and speak.');
      return;
    }
    setState(() => _isUploading = true);
    try {
      final bytes = await XFile(path).readAsBytes();
      final url = await StorageService.uploadChatAttachmentBytes(
        chatId: widget.chatId,
        fileName: 'voice_${IstClock.instant().millisecondsSinceEpoch}.m4a',
        bytes: bytes,
        contentType: 'audio/mp4',
      );
      await _deliver(
        type: 'audio',
        mediaUrl: url,
        fileName: 'Voice message',
        extra: {'voice': true, 'durationMs': len.inMilliseconds},
      );
    } catch (e) {
      _fileError(ErrorMessages.of(e, action: 'send the voice message'));
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Widget _recordingRow() => Row(children: [
        IconButton(
          tooltip: 'Delete',
          icon: const Icon(Icons.delete_outline_rounded,
              color: AppColors.danger),
          onPressed: () => _stopRecording(send: false),
        ),
        const Icon(Icons.fiber_manual_record_rounded,
            color: AppColors.danger, size: 14),
        const SizedBox(width: 6),
        Expanded(
          child: Text('Recording  ${voiceClock(_recLen)}',
              style: const TextStyle(
                  fontWeight: FontWeight.w600, color: AppColors.ink)),
        ),
        GestureDetector(
          onTap: () => _stopRecording(send: true),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
                color: AppTheme.primaryTeal, shape: BoxShape.circle),
            child: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
          ),
        ),
      ]);

  void _openUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await labCanLaunchUrl(uri)) {
        await labLaunchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
  }

  /// "18 messages left · chat open until 5:40 PM" above the input.
  Widget _counterStrip() {
    final a = _access;
    final end = a.endsAt;
    String until = '';
    if (end != null) {
      final h = end.hour % 12 == 0 ? 12 : end.hour % 12;
      final m = end.minute.toString().padLeft(2, '0');
      final day = end.difference(IstClock.now()).inHours >= 24
          ? '${end.day}/${end.month} '
          : '';
      until = ' · open until $day$h:$m ${end.hour < 12 ? 'AM' : 'PM'}';
    }
    final low = a.remaining <= 5;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: low ? AppColors.dangerSoft : AppColors.primaryTint,
      child: Text(
        '${a.remaining} of ${a.limit} messages left$until',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: low ? AppColors.danger : AppColors.primary,
        ),
      ),
    );
  }

  /// Shown instead of the input when this person cannot write now.
  Widget _closedBar() {
    final a = _access;
    final String text;
    if (_isAmbulanceChat) {
      text = _sosLoaded
          ? 'Chat is unavailable: the ambulance is off duty.'
          : 'Checking the chat…';
    } else if (!_endLoaded) {
      text = 'Checking the chat…';
    } else if (a.state == ChatAccessState.notStarted) {
      text = 'Chat opens when the consultation ends.';
    } else if (_isPatient) {
      text = a.state == ChatAccessState.limitReached
          ? 'You have used all your messages.'
          : 'The chat time is over.';
    } else if (a.state == ChatAccessState.timeOver) {
      text = 'The chat time is over and your follow-up message was sent. '
          'The patient can recharge or pay for a single message to reply.';
    } else {
      text = 'The chat time is over. The patient can recharge to continue.';
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          )
        ],
      ),
      child: Row(children: [
        const Icon(Icons.lock_outline_rounded,
            color: AppColors.muted, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text,
              style: const TextStyle(color: AppColors.muted, fontSize: 13.5)),
        ),
        if (_isPatient && a.needsRecharge && !_isAmbulanceChat)
          ElevatedButton(
            onPressed: () => showChatRechargeSheet(context,
                chatId: widget.chatId, reason: a.state),
            child: const Text('Recharge'),
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveCenter(child: Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        actions: [
          // Patient: ask the doctor for an audio / video call
          if (_isPatient && !_isAmbulanceChat && _who != null) ...[
            IconButton(
              tooltip: 'Request audio call',
              icon: const Icon(Icons.call_outlined),
              onPressed: () => _requestCall(false),
            ),
            IconButton(
              tooltip: 'Request video call',
              icon: const Icon(Icons.videocam_outlined),
              onPressed: () => _requestCall(true),
            ),
          ],
          // Doctor: tests are suggested only while the chat is open
          if (widget.canSuggestTests && _canWrite)
            IconButton(
              tooltip: 'Suggest a test',
              icon: const Icon(Icons.biotech_rounded),
              onPressed: () {
                final patientUid = widget.chatId
                    .split('_')
                    .firstWhere((p) => p != widget.currentUserId,
                        orElse: () => '');
                if (patientUid.isEmpty) return;
                showSuggestTestSheet(
                  context,
                  chatId: widget.chatId,
                  patientUid: patientUid,
                  patientName: widget.peerName,
                  doctorUid: widget.currentUserId,
                  doctorName: widget.currentUserName,
                );
              },
            ),
        ],
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: AppTheme.primaryTeal.withValues(alpha: 0.15),
              child: const Icon(Icons.person, color: AppTheme.primaryTeal, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.peerName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textDark,
                    ),
                  ),
                  // "Online" in green while the other person has the app open
                  StreamBuilder<Map<String, dynamic>?>(
                    stream: _streams.get('peer', () => PresenceService.user(_peerUid)),
                    builder: (context, snap) {
                      final online = PresenceService.isOnline(snap.data);
                      final seen = PresenceService.lastSeen(snap.data);
                      return Text(
                        online
                            ? '${widget.peerRole} • Online'
                            : seen.isEmpty
                                ? widget.peerRole
                                : '${widget.peerRole} • $seen',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11,
                            color: online ? AppColors.online : AppColors.muted,
                            fontWeight: FontWeight.bold),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_isUploading)
              Container(
                padding: const EdgeInsets.all(8),
                color: AppTheme.primaryTeal.withValues(alpha: 0.1),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppTheme.primaryTeal),
                    ),
                    SizedBox(width: 10),
                    Text(
                      'Uploading attachment to Firebase Storage...',
                      style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.primaryTeal,
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),

            // Chat Messages Stream
            Expanded(
              child: StreamBuilder<List<Map<String, dynamic>>>(
                stream: _streams.get('messages', () => FirestoreService.getChatMessagesStream(widget.chatId)),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return LoadErrorView(error: snapshot.error, what: 'messages');
                  }
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(color: AppTheme.primaryTeal),
                    );
                  }

                  final messages = snapshot.data ?? [];

                  if (messages.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.chat_bubble_outline_rounded,
                              size: 60, color: AppColors.lineStrong),
                          const SizedBox(height: 12),
                          Text(
                            'Start conversation with ${widget.peerName}',
                            style: const TextStyle(
                              fontSize: 14,
                              color: AppTheme.textMuted,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.all(16),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final msg = messages[index];
                      final messageId = msg['messageId'] ?? '';
                      final isMe = msg['senderUid'] == widget.currentUserId;
                      final type = msg['type'] ?? 'text';
                      if (type == 'test_suggestion') {
                        return TestSuggestionCard(
                          message: msg,
                          currentUserId: widget.currentUserId,
                          patientView: _isPatient,
                        );
                      }
                      if (type == 'call_request') {
                        return CallRequestCard(
                          message: msg,
                          providerView: !_isPatient,
                          canStart: _access.timeOn,
                          onAccept: () => _acceptCall(msg),
                          onDecline: () => _declineCall(msg),
                          onCancel: () => _cancelCall(msg),
                          onStart: () => _startRequestedCall(msg),
                          onEnd: () => _endCall(msg),
                        );
                      }
                      if (type == 'prescription') {
                        return GestureDetector(
                          onLongPress: () {
                            if (isMe && messageId.isNotEmpty) {
                              _confirmDeleteMessage(messageId);
                            }
                          },
                          child: PrescriptionCard(
                            message: msg,
                            isMe: isMe,
                            onOpen: () =>
                                _openUrl((msg['mediaUrl'] ?? '').toString()),
                          ),
                        );
                      }
                      final text = msg['text'] ?? '';
                      final mediaUrl = msg['mediaUrl'] ?? '';
                      final fileName = msg['fileName'] ?? 'file';

                      return GestureDetector(
                        onLongPress: () {
                          if (isMe && messageId.isNotEmpty) {
                            _confirmDeleteMessage(messageId);
                          }
                        },
                        child: Align(
                          alignment: isMe
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(12),
                            constraints: BoxConstraints(
                              maxWidth:
                                  MediaQuery.of(context).size.width * 0.75,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  isMe ? AppTheme.primaryTeal : Colors.white,
                              borderRadius: BorderRadius.only(
                                topLeft: const Radius.circular(20),
                                topRight: const Radius.circular(20),
                                bottomLeft: isMe
                                    ? const Radius.circular(20)
                                    : const Radius.circular(4),
                                bottomRight: isMe
                                    ? const Radius.circular(4)
                                    : const Radius.circular(20),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.04),
                                  blurRadius: 6,
                                )
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // 1. IMAGE ATTACHMENT
                                if (type == 'image' && mediaUrl.isNotEmpty) ...[
                                  InkWell(
                                    onTap: () => _openUrl(mediaUrl),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(14),
                                      child: Image(
image: CachedNetworkImageProvider(mediaUrl),
                                        fit: BoxFit.cover,
                                        width: double.infinity,
                                        height: 180,
                                        loadingBuilder: (ctx, child, progress) {
                                          if (progress == null) return child;
                                          return Container(
                                            height: 180,
                                            color: AppColors.line,
                                            child: const Center(
                                              child: CircularProgressIndicator(
                                                  color: AppTheme.primaryTeal),
                                            ),
                                          );
                                        },
                                        errorBuilder: (ctx, error, stackTrace) {
                                          return Container(
                                            padding: const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                              color: isMe
                                                  ? Colors.white.withValues(alpha: 0.2)
                                                  : AppTheme.bgLight,
                                              borderRadius: BorderRadius.circular(14),
                                            ),
                                            child: Row(
                                              children: [
                                                Icon(Icons.image_rounded,
                                                    color: isMe
                                                        ? Colors.white
                                                        : AppTheme.primaryTeal,
                                                    size: 28),
                                                const SizedBox(width: 10),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment.start,
                                                    children: [
                                                      Text(
                                                        fileName.isNotEmpty
                                                            ? fileName
                                                            : 'Image Attachment',
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
                                                        style: TextStyle(
                                                          fontWeight: FontWeight.bold,
                                                          fontSize: 13,
                                                          color: isMe
                                                              ? Colors.white
                                                              : AppTheme.textDark,
                                                        ),
                                                      ),
                                                      Text(
                                                        'Tap to view image',
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          color: isMe
                                                              ? Colors.white70
                                                              : AppTheme.textMuted,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                Icon(Icons.open_in_new_rounded,
                                                    color: isMe
                                                        ? Colors.white
                                                        : AppTheme.primaryTeal,
                                                    size: 18),
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                ]
                                // 2. PDF ATTACHMENT
                                else if (type == 'pdf' && mediaUrl.isNotEmpty) ...[
                                  InkWell(
                                    onTap: () => _openUrl(mediaUrl),
                                    child: Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: isMe
                                            ? Colors.white.withValues(alpha: 0.2)
                                            : AppTheme.bgLight,
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(Icons.picture_as_pdf_rounded,
                                              color: isMe
                                                  ? Colors.white
                                                  : AppColors.danger,
                                              size: 28),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  fileName,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 13,
                                                    color: isMe
                                                        ? Colors.white
                                                        : AppTheme.textDark,
                                                  ),
                                                ),
                                                Text(
                                                  'Tap to open PDF',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: isMe
                                                        ? Colors.white70
                                                        : AppTheme.textMuted,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Icon(Icons.open_in_new_rounded,
                                              color: isMe
                                                  ? Colors.white
                                                  : AppTheme.primaryTeal,
                                              size: 18),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                ]
                                // 3. VIDEO ATTACHMENT
                                else if (type == 'video' && mediaUrl.isNotEmpty) ...[
                                  InkWell(
                                    onTap: () => _openUrl(mediaUrl),
                                    child: Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: isMe
                                            ? Colors.white.withValues(alpha: 0.2)
                                            : AppTheme.bgLight,
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(Icons.play_circle_fill_rounded,
                                              color: isMe
                                                  ? Colors.white
                                                  : AppColors.purple,
                                              size: 32),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  fileName,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 13,
                                                    color: isMe
                                                        ? Colors.white
                                                        : AppTheme.textDark,
                                                  ),
                                                ),
                                                Text(
                                                  'Tap to play video',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: isMe
                                                        ? Colors.white70
                                                        : AppTheme.textMuted,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                ],

                                // 4. AUDIO ATTACHMENT
                                if (type == 'audio' && mediaUrl.isNotEmpty) ...[
                                  VoiceNotePlayer(
                                    url: mediaUrl,
                                    isMe: isMe,
                                    title: msg['voice'] == true
                                        ? 'Voice message'
                                        : fileName,
                                    length: msg['durationMs'] is num
                                        ? Duration(
                                            milliseconds:
                                                (msg['durationMs'] as num)
                                                    .toInt())
                                        : null,
                                  ),
                                  const SizedBox(height: 6),
                                ],

                                // Message text, or the description of a file
                                if (text.toString().trim().isNotEmpty &&
                                    !text.toString().startsWith('[Attachment:'))
                                Text(
                                  text,
                                  style: TextStyle(
                                    color: isMe
                                        ? Colors.white
                                        : AppTheme.textDark,
                                    fontSize: 14,
                                    height: 1.3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),

            // Doctor typed "\": tick tests and send them together
            if (_testShortcutOn && _canWrite && _testQuery != null)
              TestShortcutPanel(
                tests: TestShortcut.filter(_labTests, _testQuery!),
                loading: _labTestsLoaded && _labTests.isEmpty,
                picked: _testsPicked,
                sending: _sendingTests,
                onToggle: (t) => setState(() => _testsPicked.contains(t)
                    ? _testsPicked.remove(t)
                    : _testsPicked.add(t)),
                onSend: _sendPickedTests,
                onClose: _closeTestShortcut,
              ),

            // How many messages and how much time are left (patient)
            if (_isPatient && _endLoaded && _access.isOpen && !_isAmbulanceChat)
              _counterStrip(),

            // Provider after the chat time: one follow-up message
            if (_followUpMode)
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: AppColors.primaryTint,
                child: const Text(
                  'The chat time is over. You can send one follow-up message (for example, "How are you?"). The patient can reply with a single paid message.',
                  style: TextStyle(fontSize: 12, color: AppColors.primary),
                ),
              ),

            // Message Input Bar with Attachment Option (+), or why it is closed
            if (!_canWrite)
              _closedBar()
            else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  )
                ],
              ),
              child: _recording
                  ? _recordingRow()
                  : Row(
                children: [
                  IconButton(
                    tooltip: 'Attach',
                    icon: const Icon(Icons.attach_file_rounded,
                        color: AppTheme.primaryTeal),
                    onPressed: _openAttachmentOptions,
                  ),
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      textCapitalization: TextCapitalization.sentences,
                      onChanged: _onTyping,
                      decoration: InputDecoration(
                        hintText: _testShortcutOn
                            ? r'Type message, or \ for tests'
                            : 'Type message...',
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(26),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: AppTheme.bgLight,
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // empty box: record a voice message; else send the text
                  Tooltip(
                    message: _inputEmpty && !kIsWeb && _testQuery == null
                        ? 'Record a voice message'
                        : 'Send',
                    child: GestureDetector(
                      onTap: _inputEmpty && !kIsWeb && _testQuery == null
                          ? _startRecording
                          : _sendMessage,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: const BoxDecoration(
                          color: AppTheme.primaryTeal,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _inputEmpty && !kIsWeb && _testQuery == null
                              ? Icons.mic_rounded
                              : Icons.send_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ));
  }
}
