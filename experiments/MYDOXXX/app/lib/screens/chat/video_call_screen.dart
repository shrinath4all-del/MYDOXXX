import '../../config/test_lab_config.dart';
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../services/call_service.dart';
import '../../services/chat_access_service.dart';
import '../../utils/appointment_rules.dart';
import '../../theme/app_theme.dart';
import '../../utils/error_messages.dart';
import '../../constants/app_colors.dart';
import '../../utils/ist_clock.dart';

/// Real peer-to-peer video or audio call (WebRTC, signalled through
/// Firestore). The caller creates the call and rings the other side; the
/// receiver joins from the incoming-call screen with [isCaller] = false and
/// the same [callId].
///
/// A call started from a patient's request in the chat ([chatId] and
/// [requestMessageId]) lasts at most [maxDuration] (15 minutes), and the
/// request in the chat shows whether it started, finished or was missed.
class VideoCallScreen extends StatefulWidget {
  final String callId;
  final bool isCaller;
  final String appointmentId;
  final String currentUid;
  final String callerName; // current user's display name
  final String peerUid;
  final String peerName;
  final String peerRole;

  /// The call ends by itself at this time (end of the booked slot).
  final DateTime? endsAt;

  /// Voice only: no camera.
  final bool audioOnly;

  /// The call ends by itself this long after it connects.
  final Duration? maxDuration;

  /// The chat request this call answers (its status is kept up to date).
  final String? chatId;
  final String? requestMessageId;

  /// Longest call started from a chat request.
  static const Duration chatCallLimit = Duration(minutes: 15);

  const VideoCallScreen({
    super.key,
    required this.callId,
    required this.isCaller,
    required this.currentUid,
    required this.callerName,
    required this.peerUid,
    required this.peerName,
    required this.peerRole,
    this.appointmentId = '',
    this.endsAt,
    this.audioOnly = false,
    this.maxDuration,
    this.chatId,
    this.requestMessageId,
  });

  @override
  State<VideoCallScreen> createState() => _VideoCallScreenState();
}

class _VideoCallScreenState extends State<VideoCallScreen> {
  final _localRenderer = RTCVideoRenderer();
  final _remoteRenderer = RTCVideoRenderer();
  RTCPeerConnection? _pc;
  MediaStream? _localStream;

  StreamSubscription? _callSub;
  StreamSubscription? _candidateSub;
  Timer? _callTimer;
  Timer? _ringTimer;
  Timer? _slotTimer;
  Timer? _limitTimer;
  DateTime? _endsAt;
  Duration? _maxDuration;
  bool _declined = false;

  bool _isMuted = false;
  bool _isVideoOff = false;
  bool _connected = false;
  bool _ending = false;
  bool _remoteDescSet = false;
  final List<RTCIceCandidate> _pendingCandidates = [];
  String _statusText = 'Starting camera…';
  int _secondsConnected = 0;

  @override
  void initState() {
    super.initState();
    _setEndsAt(widget.endsAt);
    _maxDuration = widget.maxDuration;
    _start();
  }

  /// Auto-end the call when the booked slot ends.
  void _setEndsAt(DateTime? t) {
    if (t == null || _endsAt != null) return;
    _endsAt = t;
    final left = t.difference(IstClock.now());
    _slotTimer?.cancel();
    _slotTimer = Timer(left.isNegative ? Duration.zero : left, () {
      if (_ending || !mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('The booked time slot has ended, so the call was ended.'),
      ));
      _endCall();
    });
  }

  Future<void> _start() async {
    try {
      if (TestLabConfig.enabled) {
        throw StateError('Test lab: camera and audio calls are disabled. Text chat is live.');
      }
      await _localRenderer.initialize();
      await _remoteRenderer.initialize();

      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': widget.audioOnly ? false : {'facingMode': 'user'},
      });
      _localRenderer.srcObject = _localStream;

      _pc = await createPeerConnection(CallService.rtcConfig);
      for (final track in _localStream!.getTracks()) {
        await _pc!.addTrack(track, _localStream!);
      }

      _pc!.onTrack = (event) {
        if (event.streams.isNotEmpty && mounted) {
          setState(() => _remoteRenderer.srcObject = event.streams[0]);
        }
      };
      _pc!.onIceCandidate = (c) {
        if (c.candidate == null) return;
        CallService.candidates(widget.callId, widget.isCaller).add(c.toMap());
      };
      _pc!.onConnectionState = (state) {
        if (!mounted) return;
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          _onConnected();
        } else if (state ==
                RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
            state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
          _endCall(remoteEnded: true);
        } else if (state ==
            RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
          setState(() => _statusText = 'Reconnecting…');
        }
      };

      if (widget.isCaller) {
        await _startAsCaller();
      } else {
        await _startAsCallee();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ErrorMessages.of(e, action: 'start the call')),
        backgroundColor: AppColors.danger,
      ));
      _endCall();
    }
  }

  Future<void> _startAsCaller() async {
    final offer = await _pc!.createOffer();
    await _pc!.setLocalDescription(offer);

    await CallService.callRef(widget.callId).set({
      'appointmentId': widget.appointmentId,
      'callerUid': widget.currentUid,
      'callerName': widget.callerName,
      'calleeUid': widget.peerUid,
      'calleeName': widget.peerName,
      'status': 'ringing',
      'offer': {'sdp': offer.sdp, 'type': offer.type},
      if (_endsAt != null) 'endsAt': _endsAt!.toIso8601String(),
      'audioOnly': widget.audioOnly,
      if (_maxDuration != null) 'maxMinutes': _maxDuration!.inMinutes,
      'createdAt': IstClock.now().toIso8601String(),
    });
    if (mounted) setState(() => _statusText = 'Calling ${widget.peerName}…');

    // Give up if nobody picks up.
    _ringTimer = Timer(CallService.ringTimeout, () async {
      if (!_connected && !_ending) {
        await CallService.setStatus(widget.callId, 'missed');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${widget.peerName} did not answer.'),
        ));
        _endCall();
      }
    });

    _callSub = CallService.callRef(widget.callId).snapshots().listen((snap) async {
      final data = snap.data();
      if (data == null) {
        _endCall(remoteEnded: true);
        return;
      }
      final status = data['status'];
      if (status == 'declined') {
        _declined = true;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('${widget.peerName} declined the call.')));
        }
        _endCall();
        return;
      }
      if (status == 'ended' || status == 'missed') {
        _endCall(remoteEnded: true);
        return;
      }
      final answer = data['answer'];
      if (answer != null && !_remoteDescSet) {
        _remoteDescSet = true;
        await _pc!.setRemoteDescription(
            RTCSessionDescription(answer['sdp'], answer['type']));
        await _flushPendingCandidates();
        if (mounted) setState(() => _statusText = 'Connecting…');
      }
    });

    _listenForCandidates(fromCaller: false);
  }

  Future<void> _startAsCallee() async {
    if (mounted) setState(() => _statusText = 'Connecting…');
    final snap = await CallService.callRef(widget.callId).get();
    final data = snap.data();
    final offer = data?['offer'];
    if (data == null || offer == null) {
      _endCall();
      return;
    }
    // the caller's booked slot end (or call limit) applies to this side too
    _setEndsAt(IstClock.tryParse((data['endsAt'] ?? '').toString()));
    final maxMinutes = data['maxMinutes'];
    if (_maxDuration == null && maxMinutes is num && maxMinutes > 0) {
      _maxDuration = Duration(minutes: maxMinutes.toInt());
    }
    await _pc!.setRemoteDescription(
        RTCSessionDescription(offer['sdp'], offer['type']));
    _remoteDescSet = true;

    final answer = await _pc!.createAnswer();
    await _pc!.setLocalDescription(answer);
    await CallService.callRef(widget.callId).update({
      'answer': {'sdp': answer.sdp, 'type': answer.type},
      'status': 'active',
    });

    _listenForCandidates(fromCaller: true);

    _callSub = CallService.callRef(widget.callId).snapshots().listen((s) {
      final d = s.data();
      if (d == null || d['status'] == 'ended') _endCall(remoteEnded: true);
    });
  }

  void _listenForCandidates({required bool fromCaller}) {
    _candidateSub =
        CallService.candidates(widget.callId, fromCaller).snapshots().listen((snap) {
      for (final change in snap.docChanges) {
        if (change.type != DocumentChangeType.added) continue;
        final d = change.doc.data();
        if (d == null) continue;
        final c = RTCIceCandidate(d['candidate'], d['sdpMid'], d['sdpMLineIndex']);
        if (_remoteDescSet) {
          _pc?.addCandidate(c);
        } else {
          _pendingCandidates.add(c);
        }
      }
    });
  }

  Future<void> _flushPendingCandidates() async {
    for (final c in _pendingCandidates) {
      await _pc?.addCandidate(c);
    }
    _pendingCandidates.clear();
  }

  void _onConnected() {
    if (_connected) return;
    _ringTimer?.cancel();
    _connected = true;
    _callTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _secondsConnected++);
    });
    final limit = _maxDuration;
    if (limit != null) {
      _limitTimer = Timer(limit, () {
        if (_ending || !mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'The ${limit.inMinutes}-minute call limit was reached, so the call was ended.'),
        ));
        _endCall();
      });
    }
    _requestStatus('started');
    if (mounted) setState(() => _statusText = 'Connected');
  }

  /// Keeps the chat request up to date (caller side only).
  void _requestStatus(String status, {int? seconds}) {
    final chatId = widget.chatId, msgId = widget.requestMessageId;
    if (!widget.isCaller || chatId == null || msgId == null) return;
    ChatAccessService.setCallStatus(chatId, msgId, status,
        seconds: seconds, callId: widget.callId);
  }

  void _toggleMute() {
    _isMuted = !_isMuted;
    for (final t in _localStream?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = !_isMuted;
    }
    setState(() {});
  }

  void _toggleVideo() {
    _isVideoOff = !_isVideoOff;
    for (final t in _localStream?.getVideoTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = !_isVideoOff;
    }
    setState(() {});
  }

  Future<void> _switchCamera() async {
    final tracks = _localStream?.getVideoTracks() ?? [];
    if (tracks.isNotEmpty) await Helper.switchCamera(tracks.first);
  }

  /// Ends the call for both sides. Whoever hangs up marks it ended; the call
  /// record and ICE candidates are then deleted so nothing is kept.
  Future<void> _endCall({bool remoteEnded = false}) async {
    if (_ending) return;
    _ending = true;
    _slotTimer?.cancel();
    _limitTimer?.cancel();
    _ringTimer?.cancel();
    _callTimer?.cancel();
    _requestStatus(
        _connected
            ? 'completed'
            : _declined
                ? 'declined'
                : 'missed',
        seconds: _connected ? _secondsConnected : null);
    await _callSub?.cancel();
    await _candidateSub?.cancel();
    if (!remoteEnded) {
      await CallService.setStatus(widget.callId, 'ended');
    }
    if (widget.isCaller) {
      // Give the other side a moment to see 'ended' before deleting.
      Future.delayed(const Duration(seconds: 3),
          () => CallService.cleanup(widget.callId));
    }
    for (final t in _localStream?.getTracks() ?? <MediaStreamTrack>[]) {
      await t.stop();
    }
    await _localStream?.dispose();
    await _pc?.close();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _slotTimer?.cancel();
    _limitTimer?.cancel();
    _ringTimer?.cancel();
    _callTimer?.cancel();
    _callSub?.cancel();
    _candidateSub?.cancel();
    if (!_ending) {
      CallService.setStatus(widget.callId, 'ended');
      for (final t in _localStream?.getTracks() ?? <MediaStreamTrack>[]) {
        t.stop();
      }
      _localStream?.dispose();
      _pc?.close();
    }
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  String _formatDuration(int seconds) {
    final mins = (seconds ~/ 60).toString().padLeft(2, '0');
    final secs = (seconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  @override
  Widget build(BuildContext context) {
    final hasRemoteVideo =
        !widget.audioOnly && _remoteRenderer.srcObject != null;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _endCall();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            children: [
              // Remote video (full screen) or avatar while connecting
              Positioned.fill(
                child: hasRemoteVideo
                    ? RTCVideoView(
                        _remoteRenderer,
                        objectFit:
                            RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                      )
                    : Container(
                        color: AppColors.inkSoft,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircleAvatar(
                              radius: 56,
                              backgroundColor:
                                  AppTheme.primaryTeal.withValues(alpha: 0.3),
                              child: Text(
                                widget.peerName.isNotEmpty
                                    ? widget.peerName[0].toUpperCase()
                                    : 'D',
                                style: const TextStyle(
                                  fontSize: 48,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              widget.peerName,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _connected
                                  ? '${widget.audioOnly ? 'Audio call' : 'Connected'} • ${_formatDuration(_secondsConnected)}'
                                  : _statusText,
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.white70,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (_maxDuration != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  'Calls last up to ${_maxDuration!.inMinutes} minutes',
                                  style: const TextStyle(
                                      fontSize: 12, color: Colors.white54),
                                ),
                              ),
                            if (_endsAt != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  'Call ends automatically at ${AppointmentRules.hm(_endsAt!)}',
                                  style: const TextStyle(
                                      fontSize: 12, color: Colors.white54),
                                ),
                              ),
                          ],
                        ),
                      ),
              ),

              // Name + timer over the remote video
              if (hasRemoteVideo)
                Positioned(
                  top: 16,
                  left: 16,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      '${widget.peerName} • ${_connected ? _formatDuration(_secondsConnected) : _statusText}${_endsAt != null ? ' • ends ${AppointmentRules.hm(_endsAt!)}' : ''}',
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),

              // Own camera preview
              if (!widget.audioOnly)
              Positioned(
                top: 20,
                right: 20,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    width: 110,
                    height: 150,
                    color: AppColors.ink,
                    child: _isVideoOff
                        ? const Center(
                            child: Icon(Icons.videocam_off_rounded,
                                color: Colors.white70, size: 32))
                        : RTCVideoView(
                            _localRenderer,
                            mirror: true,
                            objectFit: RTCVideoViewObjectFit
                                .RTCVideoViewObjectFitCover,
                          ),
                  ),
                ),
              ),

              // Controls
              Positioned(
                bottom: 30,
                left: 20,
                right: 20,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(36),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      IconButton(
                        icon: Icon(
                          _isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                          color: _isMuted ? AppColors.danger : Colors.white,
                          size: 28,
                        ),
                        onPressed: _toggleMute,
                      ),
                      if (!widget.audioOnly) ...[
                        IconButton(
                          icon: Icon(
                            _isVideoOff
                                ? Icons.videocam_off_rounded
                                : Icons.videocam_rounded,
                            color:
                                _isVideoOff ? AppColors.danger : Colors.white,
                            size: 28,
                          ),
                          onPressed: _toggleVideo,
                        ),
                        IconButton(
                          icon: const Icon(Icons.cameraswitch_rounded,
                              color: Colors.white, size: 28),
                          onPressed: _switchCamera,
                        ),
                      ],
                      GestureDetector(
                        onTap: _endCall,
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: const BoxDecoration(
                            color: AppColors.danger,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.call_end_rounded,
                              color: Colors.white, size: 28),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
