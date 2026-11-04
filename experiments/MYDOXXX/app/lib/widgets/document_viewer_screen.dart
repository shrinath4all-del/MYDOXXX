import '../services/lab_device.dart';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:pdfrx/pdfrx.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/app_colors.dart';

/// Kind of an uploaded document, read from its first bytes (older uploads
/// were saved without a file extension, so the name cannot be trusted).
enum DocumentKind { pdf, image, other }

DocumentKind documentKindOf(Uint8List b) {
  bool starts(List<int> sig) =>
      b.length >= sig.length &&
      List.generate(sig.length, (i) => b[i] == sig[i]).every((x) => x);
  if (starts([0x25, 0x50, 0x44, 0x46])) return DocumentKind.pdf; // %PDF
  if (starts([0x89, 0x50, 0x4E, 0x47]) || // PNG
      starts([0xFF, 0xD8, 0xFF]) || // JPEG
      starts([0x47, 0x49, 0x46, 0x38]) || // GIF
      (starts([0x52, 0x49, 0x46, 0x46]) && // WEBP
          b.length > 11 &&
          String.fromCharCodes(b.sublist(8, 12)) == 'WEBP')) {
    return DocumentKind.image;
  }
  return DocumentKind.other;
}

/// Shows a verification document inside the app: images with pinch-zoom,
/// PDFs page by page. Other files (Word) can be opened in another app.
class DocumentViewerScreen extends StatefulWidget {
  final String url;
  final String title;

  const DocumentViewerScreen({super.key, required this.url, required this.title});

  /// Opens the viewer as a full screen page.
  static Future<void> open(BuildContext context,
          {required String url, required String title}) =>
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => DocumentViewerScreen(url: url, title: title)));

  @override
  State<DocumentViewerScreen> createState() => _DocumentViewerScreenState();
}

class _DocumentViewerScreenState extends State<DocumentViewerScreen> {
  late Future<Uint8List> _bytes = _load();

  Future<Uint8List> _load() async {
    final res = await http.get(Uri.parse(widget.url));
    if (res.statusCode != 200) {
      throw Exception('Could not load the document (${res.statusCode}).');
    }
    return res.bodyBytes;
  }

  Future<void> _openOutside() async {
    try {
      await labLaunchUrl(Uri.parse(widget.url),
          mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.ink,
      appBar: AppBar(
        backgroundColor: AppColors.ink,
        foregroundColor: Colors.white,
        title: Text(widget.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 16)),
        actions: [
          IconButton(
            tooltip: 'Open in another app',
            icon: const Icon(Icons.open_in_new_rounded),
            onPressed: _openOutside,
          ),
        ],
      ),
      body: FutureBuilder<Uint8List>(
        future: _bytes,
        builder: (context, snap) {
          if (snap.hasError) {
            return _message(
              Icons.error_outline_rounded,
              'This document could not be loaded here.',
              retry: true,
            );
          }
          if (!snap.hasData) {
            return const Center(
                child: CircularProgressIndicator(color: Colors.white));
          }
          final bytes = snap.data!;
          switch (documentKindOf(bytes)) {
            case DocumentKind.image:
              return InteractiveViewer(
                minScale: 1,
                maxScale: 5,
                child: Center(
                  child: Image.memory(bytes,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => _message(
                          Icons.broken_image_outlined,
                          'This image could not be shown.')),
                ),
              );
            case DocumentKind.pdf:
              return PdfViewer.data(bytes, sourceName: widget.url);
            case DocumentKind.other:
              return _message(Icons.description_outlined,
                  'This file type (for example a Word file) cannot be shown inside the app.');
          }
        },
      ),
    );
  }

  Widget _message(IconData icon, String text, {bool retry = false}) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white70, size: 48),
              const SizedBox(height: 12),
              Text(text,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 14)),
              const SizedBox(height: 16),
              Wrap(spacing: 10, runSpacing: 8, alignment: WrapAlignment.center, children: [
                if (retry)
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white54),
                        minimumSize: const Size(0, 42)),
                    onPressed: () => setState(() => _bytes = _load()),
                    child: const Text('Try again'),
                  ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brand,
                      iconColor: Colors.white,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 42)),
                  onPressed: _openOutside,
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: const Text('Open in another app'),
                ),
              ]),
            ],
          ),
        ),
      );
}
