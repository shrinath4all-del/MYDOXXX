import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

/// "0:42" for a duration.
String voiceClock(Duration d) =>
    '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

/// Plays an audio message inside the chat: play / pause, how far it got and
/// its length. Used for recorded voice messages and sent audio files.
class VoiceNotePlayer extends StatefulWidget {
  final String url;
  final bool isMe;

  /// Length saved with a recorded message (shown before it is played).
  final Duration? length;

  /// "Voice message" or the file's name.
  final String title;

  const VoiceNotePlayer({
    super.key,
    required this.url,
    required this.isMe,
    required this.title,
    this.length,
  });

  @override
  State<VoiceNotePlayer> createState() => _VoiceNotePlayerState();
}

class _VoiceNotePlayerState extends State<VoiceNotePlayer> {
  AudioPlayer? _player;
  final List<StreamSubscription> _subs = [];
  PlayerState _state = PlayerState.stopped;
  Duration _pos = Duration.zero;
  Duration? _len;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _len = widget.length;
  }

  AudioPlayer _ensurePlayer() {
    final existing = _player;
    if (existing != null) return existing;
    final p = AudioPlayer();
    _subs.addAll([
      p.onPlayerStateChanged.listen((s) {
        if (mounted) setState(() => _state = s);
      }),
      p.onPositionChanged.listen((d) {
        if (mounted) setState(() => _pos = d);
      }),
      p.onDurationChanged.listen((d) {
        if (mounted && d > Duration.zero) setState(() => _len = d);
      }),
      p.onPlayerComplete.listen((_) {
        if (mounted) setState(() => _pos = Duration.zero);
      }),
    ]);
    return _player = p;
  }

  Future<void> _toggle() async {
    final p = _ensurePlayer();
    try {
      if (_state == PlayerState.playing) {
        await p.pause();
      } else if (_state == PlayerState.paused) {
        await p.resume();
      } else {
        await p.play(UrlSource(widget.url));
      }
      if (_failed && mounted) setState(() => _failed = false);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fg = widget.isMe ? Colors.white : AppColors.primary;
    final sub = widget.isMe ? Colors.white70 : AppColors.muted;
    final len = _len;
    final progress = len == null || len.inMilliseconds == 0
        ? 0.0
        : (_pos.inMilliseconds / len.inMilliseconds).clamp(0.0, 1.0);
    final playing = _state == PlayerState.playing;
    return Container(
      width: 240,
      padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
      decoration: BoxDecoration(
        color: widget.isMe ? Colors.white.withValues(alpha: 0.2) : AppColors.page,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(children: [
        IconButton(
          tooltip: playing ? 'Pause' : 'Play',
          onPressed: _toggle,
          icon: Icon(
              playing ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded,
              color: fg,
              size: 36),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: widget.isMe ? Colors.white : AppColors.ink)),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 4,
                  color: fg,
                  backgroundColor: fg.withValues(alpha: 0.25),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _failed
                    ? 'Could not play. Check your internet.'
                    : playing || _pos > Duration.zero
                        ? voiceClock(_pos)
                        : len == null
                            ? 'Tap to play'
                            : voiceClock(len),
                style: TextStyle(fontSize: 11, color: _failed ? AppColors.danger : sub),
              ),
            ],
          ),
        ),
      ]),
    );
  }
}
