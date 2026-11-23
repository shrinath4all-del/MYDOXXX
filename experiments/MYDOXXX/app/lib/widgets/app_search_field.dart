import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../constants/app_colors.dart';
import '../constants/app_strings.dart';

/// Search box used across the app: type or tap the mic and speak. The
/// spoken words fill the box and search like typed text.
class AppSearchField extends StatefulWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String hint;
  final bool dense;

  const AppSearchField({
    super.key,
    required this.controller,
    required this.onChanged,
    this.hint = AppStrings.search,
    this.dense = false,
  });

  @override
  State<AppSearchField> createState() => _AppSearchFieldState();
}

class _AppSearchFieldState extends State<AppSearchField> {
  // one recogniser for the whole app (it holds the phone's speech service)
  static final SpeechToText _speech = SpeechToText();
  static bool? _available;
  bool _listening = false;

  @override
  void dispose() {
    if (_listening) _speech.stop();
    super.dispose();
  }

  void _set(String text) {
    widget.controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    widget.onChanged(text);
  }

  Future<void> _toggleVoice() async {
    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    try {
      // a refused or failed start is tried again on the next tap
      if (_available != true) {
        _available = await _speech.initialize(
          onStatus: (s) {
            if ((s == 'done' || s == 'notListening') && mounted) {
              setState(() => _listening = false);
            }
          },
          onError: (e) {
            if (!mounted) return;
            setState(() => _listening = false);
            final blocked = e.errorMsg.contains('not-allowed') ||
                e.errorMsg.contains('permission');
            if (blocked || e.errorMsg.contains('audio')) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(blocked
                      ? 'Allow the microphone for this app (or this site in the browser), then tap the mic again.'
                      : 'No microphone was found.')));
            }
          },
        );
      }
    } catch (_) {
      _available = false;
    }
    if (!mounted) return;
    if (_available != true) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(AppStrings.voiceUnavailable)));
      return;
    }
    setState(() => _listening = true);
    await _speech.listen(
      onResult: (r) => _set(r.recognizedWords),
      listenOptions: SpeechListenOptions(
        // Indian English hears local names (Baner, Aundh, Wakad) better
        localeId: kIsWeb ? 'en-IN' : 'en_IN',
        partialResults: true,
        listenFor: const Duration(seconds: 20),
        pauseFor: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasText = widget.controller.text.isNotEmpty;
    return TextField(
      controller: widget.controller,
      onChanged: widget.onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        isDense: widget.dense,
        hintText: _listening ? AppStrings.listening : widget.hint,
        prefixIcon: const Icon(Icons.search_rounded, color: AppColors.muted),
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasText && !_listening)
              IconButton(
                tooltip: 'Clear',
                icon: const Icon(Icons.clear_rounded, color: AppColors.muted),
                onPressed: () => _set(''),
              ),
            IconButton(
              tooltip: _listening ? 'Stop' : 'Search by voice',
              icon: Icon(
                _listening ? Icons.mic_rounded : Icons.mic_none_rounded,
                color: _listening ? AppColors.danger : AppColors.primary,
              ),
              onPressed: _toggleVoice,
            ),
          ],
        ),
      ),
    );
  }
}
