import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

/// Implementazione web del CSV export: crea un Blob e triggera il
/// download tramite anchor element. Standard pattern, supportato da
/// tutti i browser moderni.
Future<void> doExportCsv(String csv, String filename) async {
  await doDownloadString(csv, filename, 'text/csv;charset=utf-8');
}

/// Download generico di una stringa testuale come file (GPX, JSON,
/// XML, ecc.) — riusa il pattern Blob+anchor del CSV.
Future<void> doDownloadString(
  String content,
  String filename,
  String mime,
) async {
  final bytes = utf8.encode(content);
  final blob = html.Blob([bytes], mime);
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..click();
  html.Url.revokeObjectUrl(url);
}
