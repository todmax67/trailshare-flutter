import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// Implementazione web del CSV export: crea un Blob e triggera il
/// download tramite anchor element. Standard pattern, supportato da
/// tutti i browser moderni.
Future<void> doExportCsv(String csv, String filename) async {
  final bytes = utf8.encode(csv);
  final blob = html.Blob([bytes], 'text/csv;charset=utf-8');
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..click();
  html.Url.revokeObjectUrl(url);
}
