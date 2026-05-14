import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:typed_data';

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

/// Download bytes binari (PNG, PDF, ZIP, ecc.) via Blob+anchor.
/// I parametri shareSubject/shareText sono ignorati su web — niente
/// share sheet, l'utente fa download diretto. Per fare share sui
/// social l'utente usa il proprio sistema dopo aver scaricato.
Future<void> doDownloadBytes(
  Object bytes,
  String filename,
  String mime, {
  String? shareSubject,
  String? shareText,
}) async {
  final blob = html.Blob([bytes as Uint8List], mime);
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..click();
  html.Url.revokeObjectUrl(url);
}
