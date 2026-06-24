// IO implementation.

import 'dart:convert';
import 'dart:io';

Future<String?> downloadCsv({required String filename, required String csvUtf8}) async {
  final dir = Directory.systemTemp;
  final safeName = filename.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  final file = File('${dir.path}/$safeName');
  await file.writeAsBytes(utf8.encode(csvUtf8), flush: true);
  return file.path;
}
