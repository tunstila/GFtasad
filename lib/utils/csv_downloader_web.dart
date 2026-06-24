// Web implementation.

import 'dart:convert';
import 'dart:html' as html;

Future<String?> downloadCsv({required String filename, required String csvUtf8}) async {
  final bytes = utf8.encode(csvUtf8);
  final blob = html.Blob([bytes], 'text/csv;charset=utf-8');
  final url = html.Url.createObjectUrlFromBlob(blob);

  try {
    final anchor = html.AnchorElement(href: url)
      ..download = filename
      ..style.display = 'none';
    html.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
  } finally {
    html.Url.revokeObjectUrl(url);
  }

  return null;
}
