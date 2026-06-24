/// Platform-conditional CSV download helper.
///
/// - On web: triggers a browser download.
/// - On IO platforms: writes to a temp file and returns the path.
///
/// This stub is used when neither `dart:html` nor `dart:io` is available.

Future<String?> downloadCsv({required String filename, required String csvUtf8}) => throw UnsupportedError('CSV download is not supported on this platform.');
