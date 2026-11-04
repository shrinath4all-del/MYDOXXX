import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mydox/services/storage_service.dart';
import 'package:mydox/widgets/document_viewer_screen.dart';

Uint8List bytes(List<int> head) => Uint8List.fromList([...head, 0, 0, 0, 0, 0, 0, 0, 0]);

void main() {
  final pdf = bytes([0x25, 0x50, 0x44, 0x46, 0x2D]); // %PDF-
  final png = bytes([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A]);
  final jpg = bytes([0xFF, 0xD8, 0xFF, 0xE0]);
  final zip = bytes([0x50, 0x4B, 0x03, 0x04]);

  test('the viewer knows a file by its contents, not its name', () {
    expect(documentKindOf(pdf), DocumentKind.pdf);
    expect(documentKindOf(png), DocumentKind.image);
    expect(documentKindOf(jpg), DocumentKind.image);
    expect(documentKindOf(zip), DocumentKind.other);
  });

  test('uploads get their real extension, also without one in the name', () {
    expect(StorageService.documentExtension(pdf, 'govt_photo_id'), 'pdf');
    expect(StorageService.documentExtension(jpg, 'IMG_2041'), 'jpg');
    expect(StorageService.documentExtension(png, 'scan.jpeg'), 'png',
        reason: 'the contents win over a wrong name');
    expect(StorageService.documentExtension(zip, 'degree.docx'), 'docx');
    expect(StorageService.documentExtension(zip, 'degree'), 'docx');
    expect(StorageService.documentExtension(bytes([1, 2, 3]), 'x'), 'bin');
  });
}
